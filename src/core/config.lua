sentinel.config = {}




--------------------------------------------------------------------------
-- CORE
-- Global on/off switches, versioning, and the privilege set Sentinel
-- registers with the engine.
--------------------------------------------------------------------------

sentinel.config.enable = true
sentinel.config.debug = false

-- on / off / shadow
sentinel.config.default_mode = "on"

sentinel.config.version = {
    number = "1.1.014",
    release_date = "25/07/2026",
}

sentinel.config.privileges = {
    -- Basic execution privilege: safe commands moderators are allowed to run
    execute = {
        name = "sentinel_execute",
        description = "Allows executing basic Sentinel anti-cheat commands (moderators)",
        give_to_singleplayer = false,
        give_to_admin = true,
    },

    -- Sensitive execution privilege: commands reserved to trusted admins only
    execute_admin = {
        name = "sentinel_execute_admin",
        description = "Allows executing sensitive/administrative Sentinel commands",
        give_to_singleplayer = false,
        give_to_admin = true,
    },

    -- Privilege required to see Sentinel's internal messages/alerts (implemented later)
    view_messages = {
        name = "sentinel_view",
        description = "Allows viewing Sentinel anti-cheat alerts and messages",
        give_to_singleplayer = false,
        give_to_admin = true,
    },
}

sentinel.config.priority = {
    default_priority = 100
}




--------------------------------------------------------------------------
-- PLAYER STATE
-- Per-player runtime protections: teleport grace period and the extra
-- velocity headroom granted after an engine-driven knockback/impulse.
--------------------------------------------------------------------------

sentinel.config.hooks = {
    teleport_grace_seconds = 1.0,
}

sentinel.config.velocity_caps = {
    baseline_xz = tonumber(core.settings:get("movement_speed_walk")) or 4.0,
    baseline_y_up = tonumber(core.settings:get("movement_speed_jump")) or 6.5,
    decay_rate = tonumber(core.settings:get("movement_acceleration_default")) or 3.0,
}




--------------------------------------------------------------------------
-- SCORING
-- How raw violation weights turn into a suspicion score over time: burst
-- accumulation, natural decay, and friction as a player nears a sanction.
--------------------------------------------------------------------------

sentinel.config.decay = {
    enabled = true,
    tick_interval = 30,
    half_life_seconds = 1800,
    slow_half_life_seconds = 7200,
    protected_threshold = 16,
    offline_decay = true,
}

sentinel.config.accumulator = {
    enabled = true,
    initial_window_seconds = 15,
    extension_seconds = 10,
    growth_factor = 1.25,

    max_growth_multiplier = 4.0,

    min_multiplier = 0.5,
    leniency_half_life_seconds = 300,

    max_burst_multiplier = 1.5,
    burst_half_life_seconds = 1.8,
}

sentinel.config.friction = {
    enabled = true,
    -- Once a player's score reaches the 'kick' enforcement tier's
    -- threshold, every subsequent score gain is multiplied by this
    -- factor, making it progressively harder to climb from
    -- kick -> tempban -> permaban.
    reduction_factor = 0.90,
}




--------------------------------------------------------------------------
-- ENFORCEMENT
-- The score thresholds that trigger a sanction, and the sanction each
-- one dispatches once crossed.
--------------------------------------------------------------------------

sentinel.config.enforcement = {
    tempban_default_duration = 86400,

    -- Ordered list of enforcement tiers. Each tier is pure data: a
    -- score threshold and the name of the action to dispatch once a
    -- player's score crosses it. See enforcement/actions.lua's
    -- action_handlers table for the set of valid action names, and
    -- enforcement/sanctions.lua for how tiers are wired to scoring.
    -- Add, remove or reorder tiers here without touching any Lua logic.
    -- tempban tiers may set an optional 'duration' (seconds), falling
    -- back to tempban_default_duration above when omitted.
    tiers = {
        { threshold = 25.00, action = "kick" },
        { threshold = 35.00, action = "tempban", duration = 86400 },
        { threshold = 45.00, action = "permaban" },
    },
}




--------------------------------------------------------------------------
-- ADMINISTRATION
-- Everything that talks to the outside world or to disk: Discord
-- webhooks, the on-disk violation log, and mod-storage persistence.
--------------------------------------------------------------------------

sentinel.config.webhooks = {
    enabled = true,
    url = "",
}

-- On-disk audit trail of every violation, one JSON array file per
-- player/day/module, newest entry first. See logs.lua. Requires
-- 'sentinel' to be added to secure.trusted_mods in minetest.conf.
sentinel.config.logs = {
    enabled = true,

    -- Created directly under the world folder.
    directory_name = "sentinel_violations",

    -- Used to name each per-day folder (os.date format).
    date_format = "%d-%m-%Y",

    -- Used for the human-readable "date" field inside each entry.
    timestamp_format = "%d-%m-%Y %H:%M:%S",

    -- How many recent violations (across all modules) are kept in the
    -- rolling per-player buffer and attached to each new entry as
    -- "recent_history" context. Small on purpose: this is an in-memory
    -- ring buffer, not the persisted history, which keeps everything.
    context_window_size = 5,
}

sentinel.config.persistence = {
    save_interval_seconds = 30,
}




--------------------------------------------------------------------------
-- MESSAGES
-- Player-facing sanction reasons and internal notification templates,
-- centralized so wording/tone can be edited without touching any
-- enforcement logic.
--   messages.sanctions.*     -> shown to the disconnected player.
--                                tempban is formatted with
--                                (duration_formatted, restore_date).
--   messages.webhooks.*      -> Discord webhook notifications
--                                (Markdown formatting).
--   messages.announcements.* -> in-game chat sent to privileged players.
--------------------------------------------------------------------------

sentinel.config.messages = {
    sanctions = {
        kick =
            "Based on your recent actions, we have determined that your behavior " ..
            "is highly suspicious. We suspect you of using a modified client that " ..
            "gives you an unfair advantage over other players. If you believe this " ..
            "is a mistake, please contact us on discord",

        tempban =
            "Your account has been temporarily suspended for %s hour(s) " ..
            "Based on your recent actions, we have determined that you were using " ..
            "a modified client that gave you an unfair advantage " ..
            "Your account will be restored on: %s (UTC+1) " ..
            "If you believe this is a mistake, please contact us on discord",

        permaban =
            "Based on your recent actions and history, we have determined that you " ..
            "were using a modified client that gave you an unfair advantage. " ..
            "Your account has been permanently suspended. If you believe this is a mistake, " ..
            "please contact us on discord",
    },

    webhooks = {
        violation = "Player `%s` flagged by `%s` (+%.2f | score: %.2f)",
        kick = "Player `%s` was `kicked` (score: %.2f)",
        tempban = "Player `%s` was `tempbanned` for `%s` (score: %.2f)",
        permaban = "Player `%s` was `permabanned` (score: %.2f)",
    },

    announcements = {
        violation = "Player '%s' was flagged by %s (+%.2f | score: %.2f)",
    },
}




--------------------------------------------------------------------------
-- CHECKS
-- Per-module detection tuning. Each key is a module's technical_name; a
-- module without an entry here falls back to its own default_config
-- (see check_registry.lua's apply_default_config).
--------------------------------------------------------------------------

sentinel.config.checks = {
    fly = {
        check_interval = 0.5,
        weight = 2.5,
        -- How long the vertical velocity must stay "flat" (unchanged
        -- beyond velocity_epsilon) while airborne before the player is
        -- flagged as flying.
        flat_grace_seconds = tonumber(core.settings:get("sentinel_fly_detector_flat_grace_time")) or 0.15,
        -- How long the vertical velocity must behave normally again
        -- (falling or changing) before a flagged player is cleared.
        recovery_grace_seconds = tonumber(core.settings:get("sentinel_fly_detector_recovery_grace_time")) or 0.3,
        base_gravity_acceleration = tonumber(core.settings:get("movement_gravity")) or 9.81,

        -- How often on_tick's state-tracking work (ground/liquid/climbable
        -- scans, gravity-consistency sampling) actually runs, independent
        -- from check_interval (which throttles run_check/decision making).
        -- Kept below flat_grace_seconds/recovery_grace_seconds by default
        -- so detection resolution for brief anomalies stays effectively
        -- unchanged versus running on_tick every raw globalstep, while
        -- cutting call frequency (and the node-scan cost that comes with
        -- it) by roughly 3-6x on a typical 20 Hz server.
        tick_interval = tonumber(core.settings:get("sentinel_fly_detector_tick_interval")) or 0.15,
    },
}
