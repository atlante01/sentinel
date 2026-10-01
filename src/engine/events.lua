core.register_on_mods_loaded(function()
    sentinel.persistence.load_mode()
    sentinel.whitelist_load()
    sentinel.persistence.load_scores()

    local version = sentinel.config.version

    sentinel.utils.log("action", string.format(
        "-!- Sentinel loaded, using version %s (%s)",
        version and version.number or "N/A",
        version and version.release_date or "N/A"
    ))
end)




core.register_on_joinplayer(function(player)
    sentinel.hooks.patch_player(player)

    local player_name = player:get_player_name()
    local version = sentinel.config.version

    core.chat_send_all(string.format(
        "-!- Sentinel loaded, using version %s (%s)",
        version and version.number or "N/A",
        version and version.release_date or "N/A"
    ))

    for _, module in ipairs(sentinel.get_modules_ordered()) do
        if module.behavior.enabled and module.execution_logic.on_join then
            local module_state = sentinel.pipeline.ensure_module_state(player_name, module.identity.technical_name)
            module.execution_logic.on_join(player, module_state.data)
        end
    end
end)




core.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()

    for _, module in ipairs(sentinel.get_modules_ordered()) do
        if module.behavior.enabled and module.execution_logic.on_leave then
            local module_state = sentinel.pipeline.ensure_module_state(player_name, module.identity.technical_name)
            module.execution_logic.on_leave(player, module_state.data)
        end
    end

    sentinel.grace.clear(player_name)
    sentinel.velocity_cap.cleanup(player_name)
    sentinel.accumulator.clear(player_name)
    sentinel.enforcement.actions.clear_sanction(player_name)
    sentinel.logs.clear(player_name)

    -- Must run last: on_leave callbacks above still need module_state.data,
    -- so the per-player module state can only be freed once they're done.
    sentinel.pipeline.remove_player_state(player_name)
end)




core.register_globalstep(function(dtime)
    sentinel.pipeline.step(dtime)
end)