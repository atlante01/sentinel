sentinel.ring_buffer = {}




function sentinel.ring_buffer.new(capacity)
    if type(capacity) ~= "number" or capacity < 1 then
        capacity = 1
    end

    return {
        capacity = math.floor(capacity),
        items = {},
        write_index = 0,
        count = 0,
    }
end




function sentinel.ring_buffer.push(buffer, item)
    buffer.write_index = (buffer.write_index % buffer.capacity) + 1
    buffer.items[buffer.write_index] = item
    buffer.count = math.min(buffer.count + 1, buffer.capacity)
end




function sentinel.ring_buffer.to_array(buffer)
    local ordered_items = {}

    if buffer.count == 0 then
        return ordered_items
    end

    local oldest_index = (buffer.count < buffer.capacity)
        and 1
        or (buffer.write_index % buffer.capacity) + 1

    for offset = 0, buffer.count - 1 do
        local index = ((oldest_index - 1 + offset) % buffer.capacity) + 1
        table.insert(ordered_items, buffer.items[index])
    end

    return ordered_items
end




function sentinel.ring_buffer.is_empty(buffer)
    return buffer.count == 0
end




function sentinel.ring_buffer.clear(buffer)
    buffer.items = {}
    buffer.write_index = 0
    buffer.count = 0
end