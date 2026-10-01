sentinel.scoring = {}

local scores_by_player_name = {}
local thresholds = {}




local function rearm_thresholds_below_score(player_name, score)
    for _, threshold in ipairs(thresholds) do
        if score < threshold.value then
            threshold.triggered[player_name] = nil
        end
    end
end




function sentinel.scoring.get_score(player_name)
    return scores_by_player_name[player_name] or 0
end




function sentinel.scoring.add_score(player_name, amount)
    if sentinel.is_whitelisted(player_name) then
        return sentinel.scoring.get_score(player_name)
    end

    if sentinel.enforcement.actions.is_sanctioned(player_name) then
        return sentinel.scoring.get_score(player_name)
    end

    local new_score = sentinel.scoring.get_score(player_name) + amount
    scores_by_player_name[player_name] = new_score

    rearm_thresholds_below_score(player_name, new_score)

    sentinel.persistence.mark_scores_dirty()

    local highest_new_threshold = nil

    for _, threshold in ipairs(thresholds) do
        if new_score >= threshold.value and not threshold.triggered[player_name] then
            if not highest_new_threshold or threshold.value > highest_new_threshold.value then
                highest_new_threshold = threshold
            end
        end
    end

    local pending_threshold_callback = nil

    if highest_new_threshold then
        for _, threshold in ipairs(thresholds) do
            if threshold.value <= highest_new_threshold.value then
                threshold.triggered[player_name] = true
            end
        end

        pending_threshold_callback = function()
            highest_new_threshold.callback(player_name, new_score)
        end
    end

    return new_score, pending_threshold_callback
end




function sentinel.scoring.get_all_scores()
    return scores_by_player_name
end





function sentinel.scoring.set_score(player_name, score)
    scores_by_player_name[player_name] = score

    rearm_thresholds_below_score(player_name, score)

    sentinel.persistence.mark_scores_dirty()
end




function sentinel.scoring.reset_score(player_name)
    scores_by_player_name[player_name] = nil

    rearm_thresholds_below_score(player_name, 0)

    sentinel.persistence.mark_scores_dirty()
end




function sentinel.scoring.register_threshold(value, callback)
    table.insert(thresholds, {
        value = value,
        callback = callback,
        triggered = {},
    })
end