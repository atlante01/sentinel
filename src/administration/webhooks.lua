local webhook_queue = {}
local is_sending = false
local max_queued_messages = 50




local function is_webhook_ready()
    local webhooks_config = sentinel.config.webhooks

    if not webhooks_config or not webhooks_config.enabled then
        sentinel.utils.log("action", "Sentinel webhook dispatch was skipped: webhooks disabled in config")

        return false
    end

    local webhook_url = webhooks_config.url

    if not webhook_url or webhook_url == "" then
        sentinel.utils.log("warning", "Sentinel webhook dispatch was skipped: webhook url is empty")

        return false
    end

    if not http then
        sentinel.utils.log("warning",
            "Sentinel webhook dispatch failed: http api unavailable, add 'sentinel' to secure.http_mods in minetest.conf"
        )

        return false
    end

    return true, webhook_url
end




local function process_queue()
    if is_sending then
        return
    end

    if #webhook_queue == 0 then
        return
    end

    local is_ready, webhook_url = is_webhook_ready()

    if not is_ready then
        return
    end

    local next_message = table.remove(webhook_queue, 1)

    is_sending = true

    sentinel.utils.log("action", string.format(
        "Sentinel is dispatching a webhook post to '%s'", webhook_url
    ))

    http.fetch({
        url = webhook_url,
        method = "POST",
        data = core.write_json({ content = next_message }),
        extra_headers = { "Content-Type: application/json" },
    },

    function(http_result)
        if not http_result.succeeded then
            sentinel.utils.log("warning", string.format(
                "Sentinel webhook delivery failed with http code %d", http_result.code or 0
            ))
        else
            sentinel.utils.log("action", string.format(
                "Sentinel webhook delivery succeeded with http code %d", http_result.code or 0
            ))
        end

        is_sending = false
        process_queue()
    end)
end




function sentinel.webhook_send(message)
    local is_ready = is_webhook_ready()

    if not is_ready then
        return false, "webhook is not ready"
    end

    table.insert(webhook_queue, message)

    if #webhook_queue > max_queued_messages then
        table.remove(webhook_queue, 1)

        sentinel.utils.log("warning",
            "Sentinel webhook queue exceeded its cap, oldest pending message was dropped"
        )
    end

    process_queue()

    return true
end