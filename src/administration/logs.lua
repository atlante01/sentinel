sentinel.logs = {}

local recent_violations_by_player_name = {}
local has_warned_about_missing_file_access = false

local ensured_directories = {}
local cached_day_key = nil




local function get_player_directory(player_name)
    return core.get_worldpath() .. "/" .. sentinel.config.logs.directory_name .. "/" .. player_name
end




local function get_day_directory(player_name, timestamp)
    local day_folder_name = os.date(sentinel.config.logs.date_format, timestamp)

    return get_player_directory(player_name) .. "/" .. day_folder_name
end




local function get_module_file_path(player_name, technical_name, timestamp)
    return get_day_directory(player_name, timestamp) .. "/" .. technical_name .. ".ndjson"
end




local function ensure_directory_exists(path)
    if core.mkdir then
        core.mkdir(path)
    end
end




local function ensure_directory_exists_cached(path)
    if ensured_directories[path] then
        return
    end

    ensure_directory_exists(path)
    ensured_directories[path] = true
end




local function purge_cache_if_new_day(timestamp)
    local day_key = os.date(sentinel.config.logs.date_format, timestamp)

    if day_key ~= cached_day_key then
        ensured_directories = {}
        cached_day_key = day_key
    end
end




local function warn_about_missing_file_access()
    if has_warned_about_missing_file_access then
        return
    end

    has_warned_about_missing_file_access = true

    sentinel.utils.log("warning",
        "Sentinel cannot append to violation logs: 'io' is unavailable. " ..
        "Add 'sentinel' to secure.trusted_mods in minetest.conf to enable disk logging."
    )
end




local function append_entry(file_path, entry)
    if not io or not io.open then
        warn_about_missing_file_access()

        return false
    end

    local file = io.open(file_path, "a")

    if not file then
        sentinel.utils.log("error", string.format("Sentinel could not open '%s' for appending", file_path))

        return false
    end

    file:write(core.write_json(entry) .. "\n")
    file:close()

    return true
end




local function get_or_create_ring_buffer(player_name)
    if not recent_violations_by_player_name[player_name] then
        recent_violations_by_player_name[player_name] = sentinel.ring_buffer.new(sentinel.config.logs.context_window_size)
    end

    return recent_violations_by_player_name[player_name]
end




local function build_recent_history(player_name)
    local ring_buffer = recent_violations_by_player_name[player_name]

    if not ring_buffer then
        return {}
    end

    local oldest_to_newest = sentinel.ring_buffer.to_array(ring_buffer)
    local newest_to_oldest = {}

    for _, snapshot in ipairs(oldest_to_newest) do
        table.insert(newest_to_oldest, 1, snapshot)
    end

    return newest_to_oldest
end




function sentinel.logs.record_violation(player_name, module, details)
    local logs_config = sentinel.config.logs

    if not logs_config or not logs_config.enabled then
        return
    end

    local timestamp = os.time()

    purge_cache_if_new_day(timestamp)

    local technical_name = module.identity.technical_name

    local entry = {
        timestamp = timestamp,
        date = os.date(logs_config.timestamp_format, timestamp),
        module = technical_name,
        module_name = module.identity.name,
        reason = details.reason,
        base_amount = details.base_amount,
        accumulator_multiplier = details.accumulator_multiplier,
        amount = details.amount,
        score_after = details.score,
        mode = sentinel.mode.get(),
        recent_history = build_recent_history(player_name),
    }

    local ring_buffer = get_or_create_ring_buffer(player_name)

    sentinel.ring_buffer.push(ring_buffer, {
        timestamp = timestamp,
        module = technical_name,
        amount = details.amount,
        score_after = details.score,
    })

    ensure_directory_exists_cached(core.get_worldpath() .. "/" .. sentinel.config.logs.directory_name)
    ensure_directory_exists_cached(get_player_directory(player_name))
    ensure_directory_exists_cached(get_day_directory(player_name, timestamp))

    local file_path = get_module_file_path(player_name, technical_name, timestamp)

    append_entry(file_path, entry)
end




function sentinel.logs.clear(player_name)
    recent_violations_by_player_name[player_name] = nil
end