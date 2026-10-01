sentinel.decay = {}

local decay_floor = 0.5
local decay_accumulator_seconds = 0




local function resolve_half_life(current_score)
    local decay_config = sentinel.config.decay

    if current_score > decay_config.protected_threshold then
        return decay_config.slow_half_life_seconds
    end

    return decay_config.half_life_seconds
end




local function decay_player_score(player_name, elapsed_seconds)
    local current_score = sentinel.scoring.get_score(player_name)

    if current_score <= 0 then
        return false
    end

    local half_life_seconds = resolve_half_life(current_score)
    local decay_factor = 0.5 ^ (elapsed_seconds / half_life_seconds)
    local new_score = current_score * decay_factor

    if new_score < decay_floor then
        sentinel.scoring.reset_score(player_name)
    else
        sentinel.scoring.set_score(player_name, new_score)
    end

    return true
end




local function run_decay_tick(elapsed_seconds)
    local decay_config = sentinel.config.decay
    local decayed_player_count = 0

    if decay_config.offline_decay then
        for player_name, _ in pairs(sentinel.scoring.get_all_scores()) do
            if decay_player_score(player_name, elapsed_seconds) then
                decayed_player_count = decayed_player_count + 1
            end
        end
    else
        for _, player in ipairs(core.get_connected_players()) do
            if decay_player_score(player:get_player_name(), elapsed_seconds) then
                decayed_player_count = decayed_player_count + 1
            end
        end
    end

    sentinel.utils.log("action", string.format(
        "Sentinel decay tick: %d player(s) decayed over %.1fs",
        decayed_player_count, elapsed_seconds
    ))
end




sentinel.pipeline.register_infrastructure_handler(function(dtime)
    local decay_config = sentinel.config.decay

    if not decay_config.enabled then
        return
    end

    decay_accumulator_seconds = decay_accumulator_seconds + dtime

    if decay_accumulator_seconds < decay_config.tick_interval then
        return
    end

    local elapsed_seconds = decay_accumulator_seconds
    decay_accumulator_seconds = 0

    run_decay_tick(elapsed_seconds)
end)