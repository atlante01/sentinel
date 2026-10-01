local module_template = {
    identity = {
        name = "",
        description = "",
        technical_name = "",
    },

    behavior = {
        enabled = true,
        entropy_exempt = false,
        accumulator_exempt = false,

        weight = 1,

        -- Lower value = runs earlier.
        priority = sentinel.config.priority.default_priority, -- Default

        check_interval = 1.0,

        -- When true, the pipeline never polls this module's run_check on
        -- check_interval; the module is expected to call
        -- sentinel.pipeline.report_violation(...) itself from its own
        -- engine callback (on_dignode, on_punchplayer, etc). on_tick still
        -- runs as usual either way, since it's commonly used for state
        -- tracking independent of how violations get fired.
        uses_events = false,

        -- Per-module verbose logging switch, independent from the global
        -- sentinel.config.debug. See sentinel.utils.module_debug_enabled.
        debug = false,

        check_when_dead = false,

        -- Throttle for on_tick (state tracking only), independent from
        -- check_interval (which throttles run_check/decision making).
        -- 0 = run on_tick on every server step. This is the historical
        -- behavior and is the default for any module that doesn't set it
        -- explicitly, so existing modules are unaffected.
        tick_interval = 0,
    },

    execution_logic = {
        run_check = nil,
        state_init = {},
        on_join = nil,
        on_leave = nil,
        on_tick = nil,
        on_violation = nil,
        on_enable = nil,
    },
}


local modules_by_technical_name = {}
local modules_ordered = sentinel.priority.new()

local enabled_modules_cache = nil




local function invalidate_enabled_modules_cache()
    enabled_modules_cache = nil
end




local function merge_with_defaults(value, defaults)
    if type(defaults) ~= "table" then
        if value == nil then
            return defaults
        end

        return value
    end

    local merged = {}

    value = (type(value) == "table") and value or {}

    for key, default_value in pairs(defaults) do
        merged[key] = merge_with_defaults(value[key], default_value)
    end

    for key, raw_value in pairs(value) do
        if merged[key] == nil then
            merged[key] = raw_value
        end
    end

    return merged
end




local function ensure_module_definition_is_valid(technical_name, definition)
    if type(technical_name) ~= "string" or technical_name == "" then
        return false, "module technical_name must be a non-empty string"
    end

    if modules_by_technical_name[technical_name] ~= nil then
        return false, string.format("module '%s' is already registered", technical_name)
    end

    if type(definition) ~= "table" then
        return false, "module definition must be a table"
    end

    local identity = definition.identity
    if type(identity) ~= "table" or type(identity.name) ~= "string" or identity.name == "" then
        return false, "module identity.name must be a non-empty string"
    end

    if type(identity.description) ~= "string" or identity.description == "" then
        return false, "module identity.description must be a non-empty string"
    end

    local behavior = definition.behavior or {}
    if behavior.weight ~= nil and type(behavior.weight) ~= "number" then
        return false, "module behavior.weight must be a number"
    end

    if behavior.check_interval ~= nil and type(behavior.check_interval) ~= "number" then
        return false, "module behavior.check_interval must be a number expressed in seconds"
    end

    if behavior.tick_interval ~= nil and type(behavior.tick_interval) ~= "number" then
        return false, "module behavior.tick_interval must be a number expressed in seconds"
    end

    if behavior.priority ~= nil and type(behavior.priority) ~= "number" then
        return false, "module behavior.priority must be a number (lower runs earlier)"
    end

    if definition.default_config ~= nil and type(definition.default_config) ~= "table" then
        return false, "module default_config must be a table"
    end

    local execution_logic = definition.execution_logic or {}
    local non_callback_execution_logic_fields = {
        state_init = true,
    }

    for field_name, field_value in pairs(execution_logic) do
        if not non_callback_execution_logic_fields[field_name] then
            if field_value ~= nil and type(field_value) ~= "function" then
                return false, string.format(
                    "module execution_logic.%s must be a function", field_name
                )
            end
        end
    end

    if execution_logic.state_init ~= nil and type(execution_logic.state_init) ~= "table" then
        return false, "module execution_logic.state_init must be a table"
    end

    return true, nil
end




local function build_detection_module_from_definition(technical_name, definition)
    local detection_module = merge_with_defaults(definition, module_template)

    detection_module.identity.technical_name = technical_name

    return detection_module
end




local function insert_module_ordered(detection_module)
    sentinel.priority.insert(modules_ordered, detection_module, detection_module.behavior.priority)
end




local function apply_default_config(technical_name, default_config)
    if type(default_config) ~= "table" then
        return
    end

    sentinel.config.checks = sentinel.config.checks or {}

    if not sentinel.config.checks[technical_name] then
        sentinel.config.checks[technical_name] = sentinel.utils.deep_copy(default_config)

        return
    end


    for key, value in pairs(default_config) do
        if sentinel.config.checks[technical_name][key] == nil then
            sentinel.config.checks[technical_name][key] = value
        end
    end
end




function sentinel.register_module(technical_name, definition)
    local is_success, error_message = ensure_module_definition_is_valid(technical_name, definition)

    if not is_success then
        sentinel.utils.log("warning", string.format(
            "Sentinel rejected registration of detection module '%s': %s",
            tostring(technical_name), error_message
        ))

        return false, error_message
    end

    local detection_module = build_detection_module_from_definition(technical_name, definition)
    modules_by_technical_name[technical_name] = detection_module

    insert_module_ordered(detection_module)
    apply_default_config(technical_name, definition.default_config)
    invalidate_enabled_modules_cache()

    sentinel.utils.log("action", string.format(
        "Detection module '%s' registered successfully (priority %d)",
        technical_name, detection_module.behavior.priority
    ))

    return true, detection_module
end




function sentinel.get_module(technical_name)
    return modules_by_technical_name[technical_name]
end




function sentinel.get_all_modules()
    return modules_by_technical_name
end




function sentinel.get_modules_ordered()
    return sentinel.priority.items(modules_ordered)
end




function sentinel.get_enabled_modules_ordered()
    if enabled_modules_cache then
        return enabled_modules_cache
    end

    local ordered = sentinel.priority.items(modules_ordered)
    local filtered = {}

    for _, detection_module in ipairs(ordered) do
        if detection_module.behavior.enabled then
            filtered[#filtered + 1] = detection_module
        end
    end

    enabled_modules_cache = filtered

    return enabled_modules_cache
end




function sentinel.fire_module_on_enable(detection_module)
    if not detection_module.execution_logic.on_enable then
        return
    end

    local is_success, error_message = pcall(detection_module.execution_logic.on_enable)

    if not is_success then
        sentinel.utils.log("error", string.format(
            "Module '%s' on_enable callback failed: %s",
            detection_module.identity.name, tostring(error_message)
        ))
    end
end




function sentinel.set_module_state(technical_name, enabled)
    local detection_module = modules_by_technical_name[technical_name]

    if not detection_module then
        return false, "unknown module"
    end

    local previous_enabled = detection_module.behavior.enabled

    if previous_enabled == enabled then
        return true, previous_enabled
    end

    detection_module.behavior.enabled = enabled

    invalidate_enabled_modules_cache()

    if enabled then
        sentinel.fire_module_on_enable(detection_module)
    end

    return true, previous_enabled
end