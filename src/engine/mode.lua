sentinel.mode = {}

local valid_modes = {
    on = true,
    off = true,
    shadow = true,
}

local mode_descriptions = {
    on = "Full detection active, violations are scored, logged and enforced",
    off = "Detection fully suspended: module ticks, scoring and enforcement are all disabled",
    shadow = "Detection active, violations are scored and logged, but enforcement is muted",
}




local function resolve_default_mode()
    local configured_default = sentinel.config.default_mode

    if valid_modes[configured_default] then
        return configured_default
    end

    sentinel.utils.log("warning", string.format(
        "Sentinel config.default_mode ('%s') is invalid, falling back to 'off'",
        tostring(configured_default)
    ))

    return "off"
end

local current_mode = resolve_default_mode()




function sentinel.mode.is_valid(mode)
    return valid_modes[mode] == true
end




function sentinel.mode.get()
    return current_mode
end




function sentinel.mode.get_description(mode)
    return mode_descriptions[mode or current_mode]
end




function sentinel.mode.is_active()
    return current_mode == "on" or current_mode == "shadow"
end




function sentinel.mode.is_shadow()
    return current_mode == "shadow"
end




local function fire_all_module_on_enable()
    for _, module in ipairs(sentinel.get_modules_ordered()) do
        if module.behavior.enabled then
            sentinel.fire_module_on_enable(module)
        end
    end
end




function sentinel.mode.set_silent(mode)
    if not valid_modes[mode] then
        return false
    end

    current_mode = mode

    return true
end




function sentinel.mode.set(mode, caller_name)
    if not valid_modes[mode] then
        return false, "mode must be one of: on, off, shadow"
    end

    local previous_mode = current_mode
    current_mode = mode

    if mode == "on" and previous_mode == "off" then
        sentinel.utils.log("action", "Sentinel mode switched from 'off' to 'on', firing module on_enable hooks")
        fire_all_module_on_enable()
    end

    sentinel.persistence.save_mode()

    sentinel.utils.log("action", string.format(
        "Sentinel mode changed from '%s' to '%s' by '%s'",
        previous_mode, mode, caller_name or "server"
    ))

    return true, previous_mode
end