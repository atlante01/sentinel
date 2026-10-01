sentinel.enforcement.actions = {}

local sanctioned_player_names = {}




function sentinel.enforcement.actions.is_sanctioned(player_name)
    return sanctioned_player_names[player_name] == true
end




function sentinel.enforcement.actions.clear_sanction(player_name)
    sanctioned_player_names[player_name] = nil
end




local function apply_sanction(player_name, reason, log_message, webhook_message)
    sanctioned_player_names[player_name] = true

    core.disconnect_player(player_name, reason)

    sentinel.utils.log("action", log_message)
    sentinel.webhook_send(webhook_message)
end




function sentinel.enforcement.actions.kick_player(player_name, reason)
    apply_sanction(
        player_name,
        reason,
        string.format("Player '%s' was kicked by Sentinel", player_name),
        string.format(
            sentinel.config.messages.webhooks.kick,
            player_name, sentinel.scoring.get_score(player_name)
        )
    )
end




function sentinel.enforcement.actions.tempban_player(player_name, duration_seconds, reason)
    local duration_formatted = sentinel.utils.format_duration_hms(duration_seconds)

    apply_sanction(
        player_name,
        reason,
        string.format(
            "Player '%s' was tempbanned by Sentinel for %s (ban logic not yet implemented)",
            player_name, duration_formatted
        ),
        string.format(
            sentinel.config.messages.webhooks.tempban,
            player_name, duration_formatted, sentinel.scoring.get_score(player_name)
        )
    )
end




function sentinel.enforcement.actions.permaban_player(player_name, reason)
    apply_sanction(
        player_name,
        reason,
        string.format(
            "Player '%s' was permabanned by Sentinel (ban logic not yet implemented)",
            player_name
        ),
        string.format(
            sentinel.config.messages.webhooks.permaban,
            player_name, sentinel.scoring.get_score(player_name)
        )
    )
end




-- Tier action dispatch table: maps a tier's declarative 'action' name
-- (from config.enforcement.tiers) to the handler that builds the
-- player-facing reason from config.messages.sanctions and applies it via
-- the *_player functions above. Add a new entry here to support a new
-- action name in config.lua's tiers list.
local action_handlers = {
    kick = function(player_name, tier)
        sentinel.enforcement.actions.kick_player(
            player_name, sentinel.config.messages.sanctions.kick
        )
    end,

    tempban = function(player_name, tier)
        local duration_seconds = tier.duration or sentinel.config.enforcement.tempban_default_duration
        local duration_formatted = sentinel.utils.format_duration_hms(duration_seconds)
        local restore_date = sentinel.utils.compute_restore_date_utc_plus_one(duration_seconds)

        local reason = string.format(
            sentinel.config.messages.sanctions.tempban, duration_formatted, restore_date
        )

        sentinel.enforcement.actions.tempban_player(player_name, duration_seconds, reason)
    end,

    permaban = function(player_name, tier)
        sentinel.enforcement.actions.permaban_player(
            player_name, sentinel.config.messages.sanctions.permaban
        )
    end,
}




function sentinel.enforcement.actions.dispatch(action_name, player_name, tier)
    local handler = action_handlers[action_name]

    if not handler then
        sentinel.utils.log("error", string.format(
            "Sentinel enforcement tier references unknown action '%s' for player '%s'",
            tostring(action_name), player_name
        ))

        return false
    end

    handler(player_name, tier)

    return true
end