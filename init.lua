sentinel = {}

-- Add 'sentinel' to secure.http_mods in minetest.conf to enable webhooks
http = core.request_http_api()


local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)

local sentinel_modpath = modpath .. "/src"




local function secure_dofile(file_path)
    local is_success, error_message = pcall(dofile, file_path)

    if not is_success then
        core.log("error", string.format(
            "Sentinel failed to load '%s': %s", file_path, tostring(error_message)
        ))
    end

    return is_success
end




local function load_all_checks(checks_dir)
    local filenames = core.get_dir_list(checks_dir, false) or {}

    table.sort(filenames)

    for _, filename in ipairs(filenames) do
        if filename:match("%.lua$") then
            secure_dofile(checks_dir .. "/" .. filename)
        end
    end
end




secure_dofile(sentinel_modpath .. "/core/config.lua")
secure_dofile(sentinel_modpath .. "/core/utils.lua")
secure_dofile(sentinel_modpath .. "/core/priority.lua")
secure_dofile(sentinel_modpath .. "/core/ring_buffer.lua")

secure_dofile(sentinel_modpath .. "/engine/mode.lua")

secure_dofile(sentinel_modpath .. "/player_state/grace.lua")
secure_dofile(sentinel_modpath .. "/player_state/velocity_cap.lua")
secure_dofile(sentinel_modpath .. "/player_state/hooks.lua")

secure_dofile(sentinel_modpath .. "/engine/check_registry.lua")

secure_dofile(sentinel_modpath .. "/scoring/scoring.lua")
secure_dofile(sentinel_modpath .. "/scoring/accumulator.lua")

secure_dofile(sentinel_modpath .. "/engine/events.lua")
secure_dofile(sentinel_modpath .. "/engine/pipeline.lua")

secure_dofile(sentinel_modpath .. "/scoring/friction.lua")

secure_dofile(sentinel_modpath .. "/player_state/whitelist.lua")

secure_dofile(sentinel_modpath .. "/administration/webhooks.lua")
secure_dofile(sentinel_modpath .. "/administration/logs.lua")

secure_dofile(sentinel_modpath .. "/storage/persistence.lua")

secure_dofile(sentinel_modpath .. "/scoring/decay.lua")

secure_dofile(sentinel_modpath .. "/enforcement/sanctions.lua")
secure_dofile(sentinel_modpath .. "/enforcement/actions.lua")

secure_dofile(sentinel_modpath .. "/administration/commands.lua")

-- Detection modules are auto-discovered: drop a new file in checks/ and it
-- loads automatically, no line to add here. Each file is expected to call
-- sentinel.register_module(...) and be fully self-contained (identity,
-- behavior, optional default_config, execution_logic) -- see
-- check_registry.lua for the contract each file must respect.
load_all_checks(sentinel_modpath .. "/checks")