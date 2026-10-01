local storage = core.get_mod_storage()
local storage_key = "whitelist"

local whitelisted_player_names = {}




local function load_whitelist()
    local raw_data = storage:get_string(storage_key)

    if raw_data == "" then
        return {}
    end

    local parsed_whitelist = core.parse_json(raw_data)

    if type(parsed_whitelist) ~= "table" then
        sentinel.utils.log("warning", "Sentinel failed to parse persisted whitelist, resetting whitelist storage")

        storage:set_string(storage_key, core.write_json({}))

        return {}
    end

    return parsed_whitelist
end




local function save_whitelist()
    storage:set_string(storage_key, core.write_json(whitelisted_player_names))
end




function sentinel.is_whitelisted(player_name)
    return whitelisted_player_names[player_name] == true
end




function sentinel.whitelist_add(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return false, "player_name must be a non-empty string"
    end

    if sentinel.is_whitelisted(player_name) then
        return false, string.format("Player '%s' is already whitelisted.", player_name)
    end

    whitelisted_player_names[player_name] = true
    save_whitelist()

    if sentinel.scoring then
        sentinel.scoring.reset_score(player_name)
    end

    sentinel.utils.log("action", string.format(
        "Player '%s' was added to the Sentinel whitelist", player_name
    ))

    return true, string.format(
        "Player '%s' has been added to the Sentinel whitelist.", player_name
    )
end




function sentinel.whitelist_remove(player_name)
    if type(player_name) ~= "string" or player_name == "" then
        return false, "player_name must be a non-empty string"
    end

    if not sentinel.is_whitelisted(player_name) then
        return false, string.format("Player '%s' is not whitelisted.", player_name)
    end

    whitelisted_player_names[player_name] = nil
    save_whitelist()

    sentinel.utils.log("action", string.format(
        "Player '%s' was removed from the Sentinel whitelist", player_name
    ))

    return true, string.format(
        "Player '%s' has been removed from the Sentinel whitelist.", player_name
    )
end




function sentinel.whitelist_list()
    local names = {}

    for whitelisted_name, _ in pairs(whitelisted_player_names) do
        table.insert(names, whitelisted_name)
    end

    table.sort(names)

    return names
end




function sentinel.whitelist_load()
    whitelisted_player_names = load_whitelist()
end