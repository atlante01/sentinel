sentinel.priority = {}




function sentinel.priority.new()
    return {
        items = {},
        meta = {}, -- item -> { priority = ..., order = ... }
        next_order = 0,
    }
end




function sentinel.priority.insert(list, item, priority)
    list.next_order = list.next_order + 1

    list.meta[item] = {
        priority = priority or sentinel.config.priority.default_priority,
        order = list.next_order,
    }

    table.insert(list.items, item)

    table.sort(list.items, function(a, b)
        local meta_a, meta_b = list.meta[a], list.meta[b]

        if meta_a.priority ~= meta_b.priority then
            return meta_a.priority < meta_b.priority
        end

        return meta_a.order < meta_b.order
    end)
end




function sentinel.priority.remove(list, item)
    if not list.meta[item] then
        return false
    end

    list.meta[item] = nil

    for index, existing_item in ipairs(list.items) do
        if existing_item == item then
            table.remove(list.items, index)
            break
        end
    end

    return true
end




function sentinel.priority.get_priority(list, item)
    local meta = list.meta[item]
    return meta and meta.priority
end




function sentinel.priority.items(list)
    return list.items
end