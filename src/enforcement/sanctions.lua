sentinel.enforcement = {}
sentinel.enforcement.sanctions = {}




-- Enforcement tiers are pure data (see config.lua: enforcement.tiers).
-- Each tier declares a score threshold and which action to dispatch once
-- that threshold is crossed; the concrete "how" of every action (player
-- message, disconnect, webhook) lives in enforcement/actions.lua, not here.
for _, tier in ipairs(sentinel.config.enforcement.tiers) do
    sentinel.scoring.register_threshold(tier.threshold, function(player_name, score)
        sentinel.utils.log("action", string.format(
            "Player '%s' reached the '%s' enforcement tier (score: %.2f, threshold: %.2f)",
            player_name, tier.action, score, tier.threshold
        ))

        sentinel.enforcement.actions.dispatch(tier.action, player_name, tier)
    end)
end