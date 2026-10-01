sentinel.hooks = {}

local teleport_callback_list = sentinel.priority.new()
local knockback_callback_list = sentinel.priority.new()

local is_playerref_patched = false




local function dispatch_teleport(player_name, new_position)
    if sentinel.config.debug then
        sentinel.utils.log("action", string.format(
            "Player '%s' was teleported to (%.2f, %.2f, %.2f), notifying %d callback(s)",
            player_name, new_position.x, new_position.y, new_position.z,
            #sentinel.priority.items(teleport_callback_list)
        ))
    end

    sentinel.grace.grant(player_name, sentinel.config.hooks.teleport_grace_seconds)

    for _, callback in ipairs(sentinel.priority.items(teleport_callback_list)) do
        local is_success, error_message = pcall(callback, player_name, new_position)

        if not is_success then
            sentinel.utils.log("error", string.format(
                "Player '%s' teleport hook callback crashed: %s",
                player_name, tostring(error_message)
            ))
        end
    end
end




local function dispatch_knockback(player_name, velocity)
    if sentinel.config.debug then
        sentinel.utils.log("action", string.format(
            "Player '%s' received a knockback impulse [%.2f, %.2f, %.2f], notifying %d callback(s)",
            player_name, velocity.x or 0, velocity.y or 0, velocity.z or 0,
            #sentinel.priority.items(knockback_callback_list)
        ))
    end

    sentinel.velocity_cap.register_impulse(player_name, velocity)

    for _, callback in ipairs(sentinel.priority.items(knockback_callback_list)) do
        local is_success, error_message = pcall(callback, player_name, velocity)

        if not is_success then
            sentinel.utils.log("error", string.format(
                "Player '%s' knockback hook callback crashed: %s",
                player_name, tostring(error_message)
            ))
        end
    end
end




local function insert_callback(list, callback, priority)
    sentinel.priority.insert(list, callback, priority)
end




function sentinel.hooks.on_player_teleport(callback, priority)
    insert_callback(teleport_callback_list, callback, priority)
end




function sentinel.hooks.on_player_knockback(callback, priority)
    insert_callback(knockback_callback_list, callback, priority)
end




function sentinel.hooks.patch_player(player)
    if is_playerref_patched then
        return
    end

    local player_metatable = getmetatable(player)
    if not player_metatable then
        return
    end

    local original_set_pos = player_metatable.set_pos
    local original_add_velocity = player_metatable.add_velocity


    player_metatable.set_pos = function(self, new_position)
        if self:is_valid() and self:is_player() then
            local player_name = self:get_player_name()

            if player_name then
                dispatch_teleport(player_name, new_position)
            end
        end

        return original_set_pos(self, new_position)
    end


    player_metatable.add_velocity = function(self, velocity)
        if self:is_valid() and self:is_player() then
            local player_name = self:get_player_name()

            if player_name then
                dispatch_knockback(player_name, velocity)
            end
        end

        return original_add_velocity(self, velocity)
    end

    is_playerref_patched = true
end