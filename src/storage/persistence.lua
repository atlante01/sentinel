sentinel.persistence = {}


local storage = core.get_mod_storage()
local scores_storage_key = "scores"
local mode_storage_key = "mode"

local save_interval_seconds = sentinel.config.persistence.save_interval_seconds
local is_scores_dirty = false
local seconds_since_last_flush = 0




function sentinel.persistence.load_scores()
    local raw_data = storage:get_string(scores_storage_key)

    if raw_data == "" then
        return
    end

    local scores = core.parse_json(raw_data)

    if type(scores) ~= "table" then
        sentinel.utils.log("warning", "Sentinel failed to parse persisted scores, resetting scores storage")

        sentinel.persistence.save_scores()

        return
    end

    for player_name, score in pairs(scores) do
        sentinel.scoring.set_score(player_name, score)
        sentinel.scoring.add_score(player_name, 0)
    end

    sentinel.utils.log("action", "Sentinel scores loaded from mod storage")
end




function sentinel.persistence.save_scores()
    local scores = sentinel.scoring.get_all_scores()
    local raw_data = core.write_json(scores)

    storage:set_string(scores_storage_key, raw_data)

    is_scores_dirty = false
    seconds_since_last_flush = 0
end




function sentinel.persistence.mark_scores_dirty()
    is_scores_dirty = true
end




sentinel.pipeline.register_infrastructure_handler(function(dtime)
    if not is_scores_dirty then
        return
    end

    seconds_since_last_flush = seconds_since_last_flush + dtime

    if seconds_since_last_flush < save_interval_seconds then
        return
    end

    sentinel.persistence.save_scores()
end)




core.register_on_shutdown(function()
    if is_scores_dirty then
        sentinel.persistence.save_scores()
    end
end)




function sentinel.persistence.load_mode()
    local raw_data = storage:get_string(mode_storage_key)

    if raw_data == "" then
        return
    end

    if not sentinel.mode.is_valid(raw_data) then
        sentinel.utils.log("warning", string.format(
            "Sentinel ignored invalid persisted mode '%s', resetting mode storage to '%s'",
            tostring(raw_data), sentinel.mode.get()
        ))

        sentinel.persistence.save_mode()

        return
    end

    sentinel.mode.set_silent(raw_data)

    sentinel.utils.log("action", string.format(
        "Sentinel mode restored from mod storage: '%s'", raw_data
    ))
end




function sentinel.persistence.save_mode()
    storage:set_string(mode_storage_key, sentinel.mode.get())
end