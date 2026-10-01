sentinel.accumulator = {}

local windows_by_player_name = {}




local function get_or_create_window(player_name)
    if not windows_by_player_name[player_name] then
        windows_by_player_name[player_name] = {
            window_until = 0,
            violation_count = 0,
            last_violation_time_seconds = nil,
        }
    end

    return windows_by_player_name[player_name]
end




local function compute_decay_factor(elapsed_seconds, half_life_seconds)
    return 0.5 ^ (elapsed_seconds / half_life_seconds)
end




local function compute_growth_multiplier(violation_count)
    local accumulator_config = sentinel.config.accumulator
    local raw_growth_multiplier = accumulator_config.growth_factor ^ math.max(0, violation_count - 1)

    return math.min(raw_growth_multiplier, accumulator_config.max_growth_multiplier)
end




local function compute_burst_multiplier(delta_since_last_violation_seconds)
    local accumulator_config = sentinel.config.accumulator

    if delta_since_last_violation_seconds <= 0 then
        return accumulator_config.max_burst_multiplier
    end

    local decay_factor = compute_decay_factor(
        delta_since_last_violation_seconds, accumulator_config.burst_half_life_seconds
    )

    return 1 + (accumulator_config.max_burst_multiplier - 1) * decay_factor
end




local function compute_lenience_multiplier(idle_excess_seconds)
    local accumulator_config = sentinel.config.accumulator

    if idle_excess_seconds <= 0 then
        return 1
    end

    local decay_factor = compute_decay_factor(idle_excess_seconds, accumulator_config.leniency_half_life_seconds)

    return accumulator_config.min_multiplier + (1 - accumulator_config.min_multiplier) * decay_factor
end




function sentinel.accumulator.register_violation(player_name)
    local accumulator_config = sentinel.config.accumulator

    if not accumulator_config.enabled then
        return 1
    end

    local now = sentinel.utils.get_precise_time()
    local window = get_or_create_window(player_name)
    local multiplier

    if window.window_until > now then
        local delta_since_last_violation_seconds = now - window.last_violation_time_seconds

        window.window_until = window.window_until + accumulator_config.extension_seconds
        window.violation_count = window.violation_count + 1

        local growth_multiplier = compute_growth_multiplier(window.violation_count)
        local burst_multiplier = compute_burst_multiplier(delta_since_last_violation_seconds)

        multiplier = growth_multiplier * burst_multiplier
    else
        local idle_seconds = window.last_violation_time_seconds and (now - window.last_violation_time_seconds) or 0
        local idle_excess_seconds = math.max(0, idle_seconds - accumulator_config.initial_window_seconds)

        window.window_until = now + accumulator_config.initial_window_seconds
        window.violation_count = 1
        multiplier = compute_lenience_multiplier(idle_excess_seconds)
    end

    window.last_violation_time_seconds = now

    sentinel.utils.log("action", string.format(
        "Player '%s' accumulator window holds %d violation(s), multiplier x%.2f, window extends for %.1fs more",
        player_name, window.violation_count, multiplier, window.window_until - now
    ))

    return multiplier
end




function sentinel.accumulator.get_multiplier(player_name)
    local window = windows_by_player_name[player_name]

    if not window then
        return 1
    end

    local now = sentinel.utils.get_precise_time()

    if window.window_until > now then
        return compute_growth_multiplier(window.violation_count)
    end

    if not window.last_violation_time_seconds then
        return 1
    end

    local idle_seconds = now - window.last_violation_time_seconds
    local idle_excess_seconds = math.max(0, idle_seconds - sentinel.config.accumulator.initial_window_seconds)

    return compute_lenience_multiplier(idle_excess_seconds)
end




function sentinel.accumulator.is_window_active(player_name)
    local window = windows_by_player_name[player_name]

    return window ~= nil and window.window_until > sentinel.utils.get_precise_time()
end




function sentinel.accumulator.clear(player_name)
    windows_by_player_name[player_name] = nil
end