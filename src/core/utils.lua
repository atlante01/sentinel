sentinel.utils = {}


function sentinel.utils.compute_restore_date_utc_plus_one(duration_seconds)
    local restore_timestamp = os.time() + duration_seconds
    return os.date("!%d/%m/%Y at %H:%M:%S", restore_timestamp + 3600)
end




function sentinel.utils.deep_copy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, sub_value in pairs(value) do
        copy[key] = sentinel.utils.deep_copy(sub_value)
    end

    return copy
end




function sentinel.utils.is_player_exempt(player_name, player)
    if sentinel.is_whitelisted(player_name) then
        return true
    end

    if sentinel.grace.is_active(player_name) then
        return true
    end

    player = player or core.get_player_by_name(player_name)

    if player and player:get_attach() ~= nil then
        return true
    end

    return false
end




function sentinel.utils.get_precise_time()
    return core.get_us_time() / 1000000.0
end




function sentinel.utils.is_in_future(timestamp)
    return timestamp > os.time()
end




function sentinel.utils.log(level, message)
    core.log(level, message)
end




function sentinel.utils.module_debug_enabled(module)
    if sentinel.config and sentinel.config.debug then
        return true
    end

    return module ~= nil and module.behavior ~= nil and module.behavior.debug == true
end




function sentinel.is_player_online(player_name)
    return core.get_player_by_name(player_name) ~= nil
end




function sentinel.utils.format_duration_hms(duration_seconds)
    local hours = math.floor(duration_seconds / 3600)
    local minutes = math.floor((duration_seconds % 3600) / 60)
    local remaining_seconds = math.floor(duration_seconds % 60)

    return string.format("%02d:%02d:%02d", hours, minutes, remaining_seconds)
end




function sentinel.utils.announce_to_privileged(message)
    local view_priv = sentinel.config.privileges.view_messages.name
    local admin_priv = sentinel.config.privileges.execute_admin.name

    for _, player in ipairs(core.get_connected_players()) do
        local player_name = player:get_player_name()
        local player_privs = core.get_player_privs(player_name)

        if player_privs[view_priv] or player_privs[admin_priv] then
            core.chat_send_player(player_name, message)
        end
    end
end