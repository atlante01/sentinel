sentinel.friction = {}




-- The 'kick' tier's threshold is the reference point for friction (score
-- gains get progressively harder past it). Resolved once at load time from
-- config.enforcement.tiers, since tiers are static config data, not
-- runtime-mutable state.
local function resolve_kick_threshold()
    for _, tier in ipairs(sentinel.config.enforcement.tiers) do
        if tier.action == "kick" then
            return tier.threshold
        end
    end

    sentinel.utils.log("warning",
        "Sentinel friction could not find a 'kick' tier in enforcement.tiers, friction reduction will never apply"
    )

    return math.huge
end

local kick_threshold = resolve_kick_threshold()




local function is_enabled()
    local friction_config = sentinel.config.friction

    return friction_config ~= nil and friction_config.enabled
end




function sentinel.friction.apply_to_amount(amount, player_name)
    if not is_enabled() then
        return amount
    end

    local current_score = sentinel.scoring.get_score(player_name)
    local factor = sentinel.config.friction.reduction_factor

    if current_score >= kick_threshold then
        return amount * factor
    end

    local projected_score = current_score + amount

    if projected_score > kick_threshold then
        local amount_below_threshold = kick_threshold - current_score
        local amount_above_threshold = projected_score - kick_threshold

        return amount_below_threshold + (amount_above_threshold * factor)
    end

    return amount
end




sentinel.pipeline.register_weight_modifier(function(amount, player_name)
    local adjusted_amount = sentinel.friction.apply_to_amount(amount, player_name)

    if adjusted_amount ~= amount then
        sentinel.utils.log("action", string.format(
            "Player '%s' friction applied (amount %.2f => %.2f)",
            player_name, amount, adjusted_amount
        ))
    end

    return adjusted_amount
end, 1000)