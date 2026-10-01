for _, priv in pairs(sentinel.config.privileges) do
    if not core.registered_privileges[priv.name] then
        core.register_privilege(priv.name, {
            description = priv.description,
            give_to_singleplayer = priv.give_to_singleplayer,
            give_to_admin = priv.give_to_admin,
        })
    end
end




core.register_chatcommand("sentinel_whitelist", {
    params = "<add|remove|list> [player_name]",
    description = "Manage the Sentinel anti-cheat whitelist",
    privs = { [sentinel.config.privileges.execute.name] = true },

    func = function(caller_name, param)
        local action, player_name = param:match("^(%S*)%s*(%S*)$")
        action = action or ""
        player_name = player_name or ""

        if action == "add" then
            if player_name == "" then
                return false, "Usage: /sentinel_whitelist add <player_name>"
            end

            return sentinel.whitelist_add(player_name)

        elseif action == "remove" then
            if player_name == "" then
                return false, "Usage: /sentinel_whitelist remove <player_name>"
            end

            return sentinel.whitelist_remove(player_name)

        elseif action == "list" then
            local names = sentinel.whitelist_list()

            if #names == 0 then
                return true, "Sentinel whitelist is currently empty."
            end

            return true, string.format(
                "Sentinel whitelist (%d): %s", #names, table.concat(names, ", ")
            )

        else
            return false, "Usage: /sentinel_whitelist <add|remove|list> <player_name>"
        end
    end,
})




core.register_chatcommand("sentinel", {
    params = "<on|off|shadow>",
    description = "Hot-swap the Sentinel anti-cheat mode (on/off/shadow), or display the current status",
    privs = { [sentinel.config.privileges.execute_admin.name] = true },

    func = function(caller_name, param)
        local mode = param:match("^%s*(%S*)%s*$") or ""

        if not sentinel.mode.is_valid(mode) then
            return false, string.format(
                "Usage: /sentinel <on|off|shadow>. Current mode: '%s' (%s).",
                sentinel.mode.get(), sentinel.mode.get_description()
            )
        end

        if sentinel.mode.get() == mode then
            return true, string.format(
                "Sentinel mode is already '%s' (%s).", mode, sentinel.mode.get_description(mode)
            )
        end

        local is_success, previous_mode = sentinel.mode.set(mode, caller_name)

        if not is_success then
            return false, previous_mode
        end

        sentinel.utils.announce_to_privileged(string.format(
            "Sentinel mode changed from '%s' to '%s' (%s) by '%s'.",
            previous_mode, mode, sentinel.mode.get_description(mode), caller_name
        ))

        return true
    end,
})





core.register_chatcommand("pardon", {
    params = "<player_name>",
    description = "Reset a player's Sentinel score to zero",
    privs = { [sentinel.config.privileges.execute.name] = true },

    func = function(caller_name, param)
        local player_name = param:match("^%s*(%S*)%s*$") or ""

        if player_name == "" then
            return false, "Usage: /pardon <player_name>"
        end

        sentinel.scoring.reset_score(player_name)

        sentinel.utils.log("action", string.format(
            "Player '%s' score was reset to zero by '%s' via pardon", player_name, caller_name
        ))

        return true, string.format(
            "Player '%s' has been pardoned, their Sentinel score is now zero.", player_name
        )
    end,
})




local function build_suspicion_score_list()
    local suspicion_score_list = {}

    for player_name, score in pairs(sentinel.scoring.get_all_scores()) do
        if score > 0 then
            table.insert(suspicion_score_list, { name = player_name, score = score })
        end
    end

    table.sort(suspicion_score_list, function(a, b)
        return a.score > b.score
    end)

    return suspicion_score_list
end




core.register_chatcommand("sentinel_list", {
    params = "",
    description = "List all players with a Sentinel suspicion score above zero, online and offline",
    privs = { [sentinel.config.privileges.view_messages.name] = true },

    func = function(caller_name, param)
        local suspicion_score_list = build_suspicion_score_list()

        sentinel.utils.log("action", string.format(
            "Player '%s' requested the Sentinel suspicion score list (%d entries)",
            caller_name, #suspicion_score_list
        ))

        if #suspicion_score_list == 0 then
            return true, "No player currently has a Sentinel suspicion score above zero."
        end

        local score_lines = {}

        for list_index, entry in ipairs(suspicion_score_list) do
            local online_tag = sentinel.is_player_online(entry.name) and "[online]" or "[offline]"
            local whitelist_tag = sentinel.is_whitelisted(entry.name) and " [wl]" or ""

            score_lines[list_index] = string.format(
                "%d. %s %s %.2f%s", list_index, entry.name, online_tag, entry.score, whitelist_tag
            )
        end

        return true, string.format(
            "Players with a Sentinel suspicion score above 0 (%d total):\n%s",
            #suspicion_score_list, table.concat(score_lines, "\n")
        )
    end,
})





local function build_module_status_lines()
    local technical_names = {}

    for technical_name, _ in pairs(sentinel.get_all_modules()) do
        table.insert(technical_names, technical_name)
    end

    table.sort(technical_names)

    local lines = {}

    for _, technical_name in ipairs(technical_names) do
        local module_def = sentinel.get_module(technical_name)
        local state = module_def.behavior.enabled and "on" or "off"

        lines[#lines + 1] = string.format(
            "%s (%s): %s", module_def.identity.name, technical_name, state
        )
    end

    return lines
end




core.register_chatcommand("sentinel_modules", {
    params = "<module_name> [<on> | <off>]",
    description = "Gets or sets the enabled state of a Sentinel detection module. No args lists all modules.",
    privs = { [sentinel.config.privileges.execute_admin.name] = true },

    func = function(caller_name, param)
        local module_name, new_state = param:match("^%s*(%S+)%s+(%S+)%s*$")

        if not module_name then
            module_name = param:match("^%s*(%S+)%s*$")
        end

        if not module_name or module_name == "" then
            local lines = build_module_status_lines()

            return true, string.format(
                "Registered modules and their runtime states:\n%s",
                table.concat(lines, "\n")
            )
        end

        local module_def = sentinel.get_module(module_name)

        if not module_def then
            return false, string.format(
                "Unknown module '%s'. Use /sentinel_modules without arguments to list all modules.",
                module_name
            )
        end

        if not new_state or new_state == "" then
            return true, string.format(
                "Module '%s' is currently '%s'.",
                module_name, module_def.behavior.enabled and "on" or "off"
            )
        end

        if new_state ~= "on" and new_state ~= "off" then
            return false, "Usage: /sentinel_modules <module_name> [on | off]"
        end

        local requested_enabled = (new_state == "on")

        local is_success, previous_enabled = sentinel.set_module_state(module_name, requested_enabled)

        if not is_success then
            return false, string.format("Could not update module '%s'.", module_name)
        end

        if previous_enabled == requested_enabled then
            return true, string.format("Module '%s' is already '%s'.", module_name, new_state)
        end

        local previous_state = previous_enabled and "on" or "off"

        local chat_message = string.format(
            "Module '%s' state changed from '%s' to '%s' by '%s'.",
            module_name, previous_state, new_state, caller_name
        )

        sentinel.utils.log("action", chat_message)
        sentinel.utils.announce_to_privileged(chat_message)

        return true, chat_message
    end,
})