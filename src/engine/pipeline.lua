sentinel.pipeline = {}

local player_states = {}
local infrastructure_handlers = {}
local weight_modifiers = sentinel.priority.new()




local function make_modules_state()
    local modules_state = {}

    for _, module in ipairs(sentinel.get_modules_ordered()) do
        modules_state[module.identity.technical_name] = {
            data = sentinel.utils.deep_copy(module.execution_logic.state_init),
            elapsed_time = 0,
            tick_elapsed_time = 0,
        }
    end

    return modules_state
end




local function dispatch_module_callback(player_name, module, callback_name, callback, ...)
    local is_success, error_message = pcall(callback, ...)

    if not is_success then
        sentinel.utils.log("error", string.format(
            "Module '%s' %s callback failed for player '%s': %s",
            module.identity.name, callback_name, player_name, tostring(error_message)
        ))
    end

    return is_success
end




local function dispatch_module_on_tick(player_name, player, module, delta_time, module_state)
    local tick_interval = module.behavior.tick_interval or 0

    if tick_interval <= 0 then
        dispatch_module_callback(
            player_name, module, "on_tick", module.execution_logic.on_tick, player, delta_time, module_state.data
        )

        return
    end

    module_state.tick_elapsed_time = module_state.tick_elapsed_time + delta_time

    if module_state.tick_elapsed_time < tick_interval then
        return
    end

    local accumulated_delta_time = module_state.tick_elapsed_time
    module_state.tick_elapsed_time = 0

    dispatch_module_callback(
        player_name, module, "on_tick", module.execution_logic.on_tick, player, accumulated_delta_time, module_state.data
    )
end




local function apply_weight_modifiers(amount, player_name, module, reason)
    for _, modifier in ipairs(sentinel.priority.items(weight_modifiers)) do
        amount = modifier(amount, player_name, module, reason)
    end

    return amount
end




local function fire_violation(player_name, player, module, violation_amount, reason, module_data)
    local base_amount = violation_amount or module.behavior.weight
    local accumulator_multiplier = 1

    if not module.behavior.accumulator_exempt then
        accumulator_multiplier = sentinel.accumulator.register_violation(player_name)
    end

    local amount = base_amount * accumulator_multiplier

    amount = apply_weight_modifiers(amount, player_name, module, reason)

    local new_score, pending_threshold_callback = sentinel.scoring.add_score(player_name, amount)

    if module.execution_logic.on_violation then
        dispatch_module_callback(
            player_name, module, "on_violation", module.execution_logic.on_violation,
            player, amount, reason, module_data
        )
    end

    sentinel.utils.log("action", string.format(
        "Player '%s' was flagged by detection module '%s' (base weight %.2f, accumulator x%.2f, final amount +%.2f, total: %.2f)",
        player_name, module.identity.technical_name, base_amount, accumulator_multiplier, amount, new_score
    ))

    local is_log_success, log_error_message = pcall(sentinel.logs.record_violation, player_name, module, {
        base_amount = base_amount,
        accumulator_multiplier = accumulator_multiplier,
        amount = amount,
        reason = reason,
        score = new_score,
    })

    if not is_log_success then
        sentinel.utils.log("error", string.format(
            "Sentinel failed to persist violation log for player '%s': %s",
            player_name, tostring(log_error_message)
        ))
    end

    sentinel.webhook_send(string.format(
        sentinel.config.messages.webhooks.violation,
        player_name, module.identity.technical_name, amount, new_score
    ))

    sentinel.utils.announce_to_privileged(string.format(
        sentinel.config.messages.announcements.violation,
        player_name, module.identity.technical_name, amount, new_score
    ))

    if pending_threshold_callback then
        pending_threshold_callback()
    end
end




local function dispatch_module_check(player_name, player, module, delta_time, module_state)
    module_state.elapsed_time = module_state.elapsed_time + delta_time

    if module_state.elapsed_time < module.behavior.check_interval then
        return
    end

    module_state.elapsed_time = 0

    local is_success, is_violation, violation_amount, reason = pcall(
        module.execution_logic.run_check, player, module_state.data
    )

    if not is_success then
        sentinel.utils.log("error", string.format(
            "Module '%s' run_check callback failed for player '%s': %s",
            module.identity.name, player_name, tostring(is_violation)
        ))

        return
    end

    if is_violation then
        fire_violation(player_name, player, module, violation_amount, reason, module_state.data)
    end
end




local function process_player(player, delta_time)
    local player_name = player:get_player_name()
    local is_dead = player:get_hp() <= 0

    local exempt = sentinel.utils.is_player_exempt(player_name, player)
        or sentinel.enforcement.actions.is_sanctioned(player_name)

    for _, module in ipairs(sentinel.get_enabled_modules_ordered()) do
        local skip_because_dead = is_dead and not module.behavior.check_when_dead

        local wants_on_tick = module.execution_logic.on_tick ~= nil and not exempt

        local wants_check = not exempt and not skip_because_dead
            and not module.behavior.uses_events
            and module.execution_logic.run_check ~= nil

        local module_state = nil

        if wants_on_tick or wants_check then
            module_state = sentinel.pipeline.ensure_module_state(player_name, module.identity.technical_name)
        end

        if wants_on_tick then
            dispatch_module_on_tick(player_name, player, module, delta_time, module_state)
        end

        if wants_check then
            dispatch_module_check(player_name, player, module, delta_time, module_state)
        end
    end
end




local function dispatch_infrastructure_handlers(delta_time)
    for _, handler in ipairs(infrastructure_handlers) do
        local is_success, error_message = pcall(handler, delta_time)

        if not is_success then
            sentinel.utils.log("error", string.format(
                "Sentinel infrastructure handler crashed: %s", tostring(error_message)
            ))
        end
    end
end




function sentinel.pipeline.ensure_module_state(player_name, technical_name)
    if not player_states[player_name] then
        player_states[player_name] = make_modules_state()
    end

    return player_states[player_name][technical_name]
end




function sentinel.pipeline.remove_player_state(player_name)
    player_states[player_name] = nil
end




function sentinel.pipeline.reset_module_states(player_name)
    player_states[player_name] = make_modules_state()
end




function sentinel.pipeline.register_infrastructure_handler(callback)
    table.insert(infrastructure_handlers, callback)
end




function sentinel.pipeline.register_weight_modifier(callback, priority)
    sentinel.priority.insert(weight_modifiers, callback, priority)
end




function sentinel.pipeline.report_violation(player, technical_name, violation_amount, reason)
    local module = sentinel.get_module(technical_name)

    if not module or not module.behavior.enabled then
        return false, "unknown or disabled module"
    end

    local player_name = player:get_player_name()

    local exempt = sentinel.utils.is_player_exempt(player_name, player)
        or sentinel.enforcement.actions.is_sanctioned(player_name)

    if exempt then
        return false, "player is exempt or sanctioned"
    end

    local module_state = sentinel.pipeline.ensure_module_state(player_name, technical_name)

    fire_violation(player_name, player, module, violation_amount, reason, module_state.data)

    return true
end




function sentinel.pipeline.step(delta_time)
    for _, player in ipairs(core.get_connected_players()) do
        process_player(player, delta_time)
    end

    dispatch_infrastructure_handlers(delta_time)
end




sentinel.hooks.on_player_teleport(function(player_name)
    sentinel.pipeline.reset_module_states(player_name)
end, 0)




sentinel.hooks.on_player_knockback(function(player_name)
    sentinel.pipeline.reset_module_states(player_name)
end, 0)