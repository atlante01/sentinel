sentinel.grace = {}

local grace_until_by_player_name = {}
local global_grace_until = 0




local function get_player_grace_until(player_name)
    return grace_until_by_player_name[player_name] or 0
end




function sentinel.grace.grant(player_name, duration_seconds)
    if type(player_name) ~= "string" or player_name == "" then
        return false, "player_name must be a non-empty string"
    end

    if type(duration_seconds) ~= "number" or duration_seconds <= 0 then
        return false, "duration_seconds must be a positive number"
    end

    grace_until_by_player_name[player_name] = os.time() + duration_seconds

    sentinel.utils.log("action", string.format(
        "Player '%s' was granted %d second(s) of Sentinel grace",
        player_name, duration_seconds
    ))

    return true
end




function sentinel.grace.grant_all(duration_seconds)
    if type(duration_seconds) ~= "number" or duration_seconds <= 0 then
        return false, "duration_seconds must be a positive number"
    end

    global_grace_until = os.time() + duration_seconds

    sentinel.utils.log("action", string.format(
        "All connected players were granted %d second(s) of Sentinel grace",
        duration_seconds
    ))

    return true
end




function sentinel.grace.clear(player_name)
    grace_until_by_player_name[player_name] = nil
end




function sentinel.grace.revoke(player_name)
    sentinel.grace.clear(player_name)
end




function sentinel.grace.revoke_all()
    global_grace_until = 0
end




function sentinel.grace.is_active(player_name)
    local now = os.time()

    if global_grace_until > now then
        return true
    end

    local player_grace_until = get_player_grace_until(player_name)

    if player_grace_until > now then
        return true
    end

    if grace_until_by_player_name[player_name] ~= nil then
        grace_until_by_player_name[player_name] = nil
    end

    return false
end




function sentinel.grace.remaining(player_name)
    local now = os.time()
    local remaining_global = 0
    local remaining_player = 0

    if sentinel.utils.is_in_future(global_grace_until) then
        remaining_global = global_grace_until - now
    end

    local player_grace_until = get_player_grace_until(player_name)

    if sentinel.utils.is_in_future(player_grace_until) then
        remaining_player = player_grace_until - now
    end

    return math.max(remaining_global, remaining_player)
end