sentinel.velocity_cap = {}

local caps_by_player_name = {}




local function get_or_create_player_state(player_name)
    if not caps_by_player_name[player_name] then
        caps_by_player_name[player_name] = {
            xz_extra = 0,
            y_up_extra = 0,
            last_update_seconds = sentinel.utils.get_precise_time(),
        }
    end

    return caps_by_player_name[player_name]
end




local function compute_decayed_extra(extra, elapsed_seconds, decay_rate)
    return math.max(0, extra - decay_rate * elapsed_seconds)
end




local function apply_decay(player_state)
    local current_time_seconds = sentinel.utils.get_precise_time()
    local elapsed_seconds = current_time_seconds - player_state.last_update_seconds

    if elapsed_seconds > 0 then
        local decay_rate = sentinel.config.velocity_caps.decay_rate

        player_state.xz_extra = compute_decayed_extra(player_state.xz_extra, elapsed_seconds, decay_rate)
        player_state.y_up_extra = compute_decayed_extra(player_state.y_up_extra, elapsed_seconds, decay_rate)
        player_state.last_update_seconds = current_time_seconds
    end
end




function sentinel.velocity_cap.register_impulse(player_name, velocity)
    local player_state = get_or_create_player_state(player_name)
    apply_decay(player_state)

    local horizontal_speed = math.sqrt((velocity.x or 0) ^ 2 + (velocity.z or 0) ^ 2)
    local vertical_speed = velocity.y or 0

    player_state.xz_extra = math.max(player_state.xz_extra, horizontal_speed)

    if vertical_speed > 0 then
        player_state.y_up_extra = math.max(player_state.y_up_extra, vertical_speed)
    end

    sentinel.utils.log("action", string.format(
        "Player '%s' velocity cap elevated by impulse [%.2f, %.2f, %.2f], xz_extra now %.2f, y_up_extra now %.2f",
        player_name, velocity.x or 0, velocity.y or 0, velocity.z or 0,
        player_state.xz_extra, player_state.y_up_extra
    ))
end




function sentinel.velocity_cap.get(player_name)
    local baseline = sentinel.config.velocity_caps
    local player_state = caps_by_player_name[player_name]

    if not player_state then
        return {
            xz = baseline.baseline_xz,
            y_up = baseline.baseline_y_up,
        }
    end

    apply_decay(player_state)

    return {
        xz = baseline.baseline_xz + player_state.xz_extra,
        y_up = baseline.baseline_y_up + player_state.y_up_extra,
    }
end




function sentinel.velocity_cap.cleanup(player_name)
    caps_by_player_name[player_name] = nil
end