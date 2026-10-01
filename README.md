# Sentinel

Modular anti-cheat for Luanti (Minetest). Each detection is an independent module that reports violations. Sentinel turns those violations into a suspicion score, then applies a sanction when the score crosses a threshold.

Current version: 1.1.014

## How it works

1. On every server step, Sentinel goes through the connected players and runs the enabled modules in priority order (lowest value first).
2. A module tracks player state in `on_tick` and makes its decision in `run_check`, called every `check_interval` seconds.
3. When a violation is reported, its weight goes through several stages:
   - the module's base weight (or the value returned by `run_check`)
   - the accumulator multiplier (violations in quick succession weigh more)
   - weight modifiers (friction is one of them)
4. The result is added to the player's score. The score decays over time.
5. When the score reaches a tier threshold, the matching sanction is applied.

A player is skipped if they are whitelisted, under a grace period, attached to an entity (vehicle, mount) or already sanctioned. Dead players are skipped unless the module sets `check_when_dead = true`.

## Installation

1. Place the `sentinel` folder in `mods/` or in the world folder.
2. Enable the mod in the world.
3. Add the following to `minetest.conf`:

```
secure.trusted_mods = sentinel
secure.http_mods = sentinel
```

- `secure.trusted_mods` allows writing violation logs to disk.
- `secure.http_mods` allows sending Discord notifications.

Without these two lines Sentinel still runs, but it writes a warning to the server log and disables the affected feature.

## Configuration

Everything is set in `config.lua`.

| Section | Purpose |
|---|---|
| `default_mode` | Mode on first start: `on`, `off` or `shadow` |
| `privileges` | Privileges registered by Sentinel |
| `hooks` | Grace duration after a teleport |
| `velocity_caps` | Reference speeds, read from engine settings |
| `decay` | Score decay (half-life, protected threshold, offline decay) |
| `accumulator` | Burst window, growth, leniency after inactivity |
| `friction` | Reduction of score gains past the `kick` tier |
| `enforcement.tiers` | Sanction tiers |
| `webhooks` | Discord webhook toggle and URL |
| `logs` | On-disk violation log |
| `messages` | Texts for sanctions, webhooks and announcements |
| `checks` | Per-module settings, keyed by technical name |

### Sanction tiers

Tiers are pure data. You can add, remove or reorder them without touching the code.

```lua
sentinel.config.enforcement.tiers = {
    { threshold = 25.00, action = "kick" },
    { threshold = 35.00, action = "tempban", duration = 86400 },
    { threshold = 45.00, action = "permaban" },
}
```

Available actions: `kick`, `tempban` (duration in seconds, defaults to `tempban_default_duration`), `permaban`. To add an action, add an entry to the `action_handlers` table in `enforcement/actions.lua`.

### Decay

The score is halved every 1800 seconds. Above `protected_threshold` (16), the half-life becomes 7200 seconds. Below 0.5, the score is reset to zero.

### Friction

From the `kick` tier onward, every score gain is multiplied by `reduction_factor` (0.90). Reaching tempban, then permaban, therefore gets progressively harder.

## Commands

| Command | Privilege | Description |
|---|---|---|
| `/sentinel <on\|off\|shadow>` | `sentinel_execute_admin` | Changes the mode. Without a valid argument, shows the current mode |
| `/sentinel_modules [module] [on\|off]` | `sentinel_execute_admin` | Lists modules, or reads/changes the state of one module |
| `/sentinel_whitelist <add\|remove\|list> [player]` | `sentinel_execute` | Manages the whitelist |
| `/pardon <player>` | `sentinel_execute` | Resets a player's score to zero |
| `/sentinel_list` | `sentinel_view` | Lists players with a score above zero |

The `sentinel_view` privilege also gives access to the chat alerts sent on every violation.

## Modes

| Mode | Intended effect |
|---|---|
| `on` | Detection active, violations scored, logged and sanctioned |
| `shadow` | Detection active, violations scored and logged, sanctions muted |
| `off` | Detection suspended: ticks, scoring and sanctions disabled |

The mode is kept across restarts.

## Writing a module

A module is registered with `sentinel.register_module(technical_name, definition)`. Missing fields take the defaults from `check_registry.lua`.

### Polling module

The pipeline calls `run_check` every `check_interval` seconds. The function returns `is_violation, amount, reason`. With `amount = nil`, the module's weight is used.

```lua
sentinel.register_module("speed", {
    identity = {
        name = "Speed",
        description = "Detects horizontal speed above the allowed cap",
    },

    behavior = {
        weight = 1.5,
        check_interval = 0.5,
    },

    -- Merged into sentinel.config.checks.speed if missing from config.lua
    default_config = {
        tolerance = 1.25,
    },

    execution_logic = {
        run_check = function(player, data)
            if core.check_player_privs(player, { fast = true }) then
                return false
            end

            local velocity = player:get_velocity()
            local horizontal = math.sqrt(velocity.x ^ 2 + velocity.z ^ 2)

            -- Accounts for legitimate impulses (knockback)
            local cap = sentinel.velocity_cap.get(player:get_player_name())
            local limit = cap.xz * sentinel.config.checks.speed.tolerance

            if horizontal > limit then
                return true, nil, string.format("speed %.2f > %.2f", horizontal, limit)
            end

            return false
        end,
    },
})
```

### Event-driven module

With `uses_events = true`, the pipeline never calls `run_check`. The module reports its own violations from an engine callback, using `sentinel.pipeline.report_violation(player, technical_name, amount, reason)`.

```lua
sentinel.register_module("nuker", {
    identity = {
        name = "Nuker",
        description = "Detects too many nodes dug in a short time",
    },

    behavior = {
        weight = 3,
        uses_events = true,
    },

    execution_logic = {
        state_init = { count = 0, window_start = 0 },
    },
})

core.register_on_dignode(function(pos, oldnode, digger)
    if not digger or not digger:is_player() then
        return
    end

    local state = sentinel.pipeline.ensure_module_state(digger:get_player_name(), "nuker")
    local data = state.data
    local now = sentinel.utils.get_precise_time()

    if now - data.window_start > 1 then
        data.window_start = now
        data.count = 0
    end

    data.count = data.count + 1

    if data.count > 12 then
        sentinel.pipeline.report_violation(digger, "nuker", nil, "dug " .. data.count .. " nodes in 1s")
        data.count = 0
    end
end)
```

`report_violation` returns `false` if the module is unknown or disabled, or if the player is exempt or sanctioned.

### Available callbacks

All callbacks are optional and run under `pcall`: an error in one module is logged and does not block the others.

| Callback | Signature |
|---|---|
| `run_check` | `(player, data)` returns `is_violation, amount, reason` |
| `on_tick` | `(player, delta_time, data)` |
| `on_join` | `(player, data)` |
| `on_leave` | `(player, data)` |
| `on_violation` | `(player, amount, reason, data)` |
| `on_enable` | `()` |

`data` is the per-player state, copied from `state_init`. It is reset after a teleport or a knockback.

### `behavior` options

| Option | Default | Description |
|---|---|---|
| `enabled` | `true` | Module is active |
| `weight` | `1` | Weight of one violation |
| `priority` | `100` | Execution order, lowest first |
| `check_interval` | `1.0` | Interval of `run_check` in seconds |
| `tick_interval` | `0` | Interval of `on_tick`, 0 = every server step |
| `uses_events` | `false` | Disables `run_check` polling |
| `accumulator_exempt` | `false` | Ignores the accumulator multiplier |
| `check_when_dead` | `false` | Also checks dead players |
| `debug` | `false` | Verbose logs for this module |

## API

### Grace

Suspends detection for a player, for example after a server action that moves or pushes them.

```lua
sentinel.grace.grant("alice", 3)      -- 3 seconds for one player
sentinel.grace.grant_all(5)           -- 5 seconds for everyone
sentinel.grace.is_active("alice")     -- true / false
sentinel.grace.remaining("alice")     -- seconds left
sentinel.grace.revoke("alice")
sentinel.grace.revoke_all()
```

Grace is counted to the second (`os.time`).

### Teleport and knockback hooks

Sentinel intercepts `set_pos` and `add_velocity` on players. A teleport grants a grace period (`teleport_grace_seconds`). An impulse temporarily raises the allowed maximum speeds. In both cases, module state is reset.

```lua
sentinel.hooks.on_player_teleport(function(player_name, new_position)
    -- react to a teleport
end, 50)

sentinel.hooks.on_player_knockback(function(player_name, velocity)
    -- react to an impulse
end, 50)
```

The second argument is the (optional) priority. Only calls made through the Lua API are intercepted.

### Allowed speeds

```lua
local cap = sentinel.velocity_cap.get("alice")
-- cap.xz   : maximum horizontal speed
-- cap.y_up : maximum upward vertical speed
```

Base values come from `movement_speed_walk` and `movement_speed_jump`. They increase after an impulse, then fall back gradually.

### Score

```lua
sentinel.scoring.get_score("alice")
sentinel.scoring.set_score("alice", 12.5)
sentinel.scoring.reset_score("alice")

-- Runs a callback when a score crosses a value
sentinel.scoring.register_threshold(30, function(player_name, score)
    core.chat_send_all(player_name .. " is very suspicious")
end)
```

A threshold fires again only if the score drops below its value and then crosses it again. If a single gain crosses several thresholds, only the highest one runs.

### Weight modifiers

A modifier receives the final amount of a violation and returns the amount to apply. Friction is implemented this way, with priority 1000.

```lua
sentinel.pipeline.register_weight_modifier(function(amount, player_name, module, reason)
    if module.identity.technical_name == "fly" then
        return amount * 0.8
    end

    return amount
end, 500)
```

### Periodic tasks

```lua
sentinel.pipeline.register_infrastructure_handler(function(dtime)
    -- runs on every server step, independent of players
end)
```

### Whitelist

```lua
sentinel.whitelist_add("alice")       -- also resets their score to zero
sentinel.whitelist_remove("alice")
sentinel.is_whitelisted("alice")
sentinel.whitelist_list()
```

### Discord webhook

```lua
sentinel.webhook_send("Markdown message")
```

Messages are queued and sent one at a time. The queue is capped at 50 messages: beyond that, the oldest one is dropped.

## Logs

Each violation is appended to a file in NDJSON format (one JSON object per line):

```
<world>/sentinel_violations/<player>/<dd-mm-yyyy>/<module>.ndjson
```

Example entry:

```json
{
  "timestamp": 1785000000,
  "date": "25-07-2026 14:03:12",
  "module": "fly",
  "module_name": "Fly",
  "reason": "flat vertical velocity",
  "base_amount": 2.5,
  "accumulator_multiplier": 1.25,
  "amount": 3.125,
  "score_after": 8.4,
  "mode": "on",
  "recent_history": []
}
```

`recent_history` holds the player's last 5 violations across all modules, newest first (`logs.context_window_size`).

## Persistence

Scores, the whitelist and the mode are stored in mod storage. Scores are written at most every 30 seconds when they have changed, and on server shutdown.

## Layout

| File | Role |
|---|---|
| `config.lua` | Configuration |
| `check_registry.lua` | Module registration and state |
| `pipeline.lua` | Main loop, violations, modifiers |
| `scoring.lua` | Scores and thresholds |
| `accumulator.lua` | Burst multiplier |
| `decay.lua` | Score decay |
| `friction.lua` | Gain reduction past the `kick` tier |
| `enforcement/sanctions.lua` | Links tiers to actions |
| `enforcement/actions.lua` | Kick, tempban, permaban |
| `hooks.lua` | Interception of `set_pos` and `add_velocity` |
| `grace.lua` | Grace periods |
| `velocity_cap.lua` | Allowed maximum speeds |
| `whitelist.lua` | Whitelist |
| `mode.lua` | on / off / shadow modes |
| `persistence.lua` | Saving scores and mode |
| `logs.lua`, `ring_buffer.lua` | Violation log |
| `webhooks.lua` | Discord notifications |
| `commands.lua` | Commands and privileges |
| `events.lua` | Engine callbacks |
| `priority.lua`, `utils.lua` | Utilities |

## Known limitations

- The `tempban` and `permaban` actions disconnect the player and send the notification, but do not yet block reconnection.
