local capi = { drawin = drawin, client = client, awesome = awesome, root = root }

local x11_layers_ordered, x11_layers_keys = {
    "WINDOW_LAYER_IGNORE",
    "WINDOW_LAYER_DESKTOP",
    "WINDOW_LAYER_BELOW",
    "WINDOW_LAYER_NORMAL",
    "WINDOW_LAYER_ABOVE",
    "WINDOW_LAYER_FULLSCREEN",
    "WINDOW_LAYER_ONTOP"
}, {}

for k, v in ipairs(x11_layers_ordered) do x11_layers_keys[v] = k end

local module = {}

-- Avoid restacking the clients and drawins too often.
local need_restack = true

local function client_to_layer(o)
    if o.type == "desktop" then
        return x11_layers_keys.WINDOW_LAYER_DESKTOP
    elseif o.ontop then
        -- first deal with user set attributes
        return x11_layers_keys.WINDOW_LAYER_ONTOP;
    elseif o.fullscreen and capi.client.focus == o then
        -- Fullscreen windows only get their own layer when they have the focus
        return x11_layers_keys.WINDOW_LAYER_FULLSCREEN;
    elseif o.above then
        return x11_layers_keys.WINDOW_LAYER_ABOVE;
    elseif o.below then
        return x11_layers_keys.WINDOW_LAYER_BELOW;
    elseif o.transient_for then
        -- check for transient attr
        return x11_layers_keys.WINDOW_LAYER_IGNORE;
    else
        return x11_layers_keys.WINDOW_LAYER_NORMAL
    end
end

-- [UNDOCUMENTED] Handler for `request::restack`.
--
-- @signalhandler awful.layout.move_handler
-- @tparam string context The context
-- @tparam table hints Additional hints
-- @tparam[opt=nil] client|nil hints.client The client
-- @tparam[opt=nil] drawin|nil hints.drawin Additional hints
function module._restack_handler(context, hints) -- luacheck: no unused args
    --TODO Support permissions
    need_restack = true
end

function module.restack()
    local layers = {}

    local function append(o)
        local layer = client_to_layer(o)
        layers[layer] = layers[layer] or {}
        table.insert(layers[layer], 1, o.drawin and o.drawin or o)
    end

    local drawins, clients = capi.drawin.get(), capi.client.get(nil, true)

    for _, c in ipairs(clients) do
        append(c)
    end

    for i=#drawins, 1, -1 do
        append(drawins[i].get_wibox and drawins[i].get_wibox() or drawins[i])
    end

    local result = {}

    for i = 1, #x11_layers_ordered do
        if layers[i] then
            for _, v in ipairs(layers[i] or {}) do
                table.insert(result, v)
            end
        end
    end

    capi.client.emit_signal("request::apply_stacking", "awful.layout", {
        content = result
    })

    capi.client.emit_signal("stacking", result)
end

-- Translate the `request::raise`, which will trigger a  `"request::restack"`.
capi.client.connect_signal("request::raise", function(c, context, hints) --luacheck: no unused args
    hints.client:raise()
end)

capi.client.connect_signal("request::restack", module._restack_handler)

-- Check if the type is `"desktop"`, which goes below everything.
for _, class in ipairs(capi.client, capi.drawin) do
    class.connect_signal("property::type", function(o)
        capi.client.emit_signal("request::restack", "type", {
            client = o.modal ~= nil and o or nil,
            drawin = o.modal == nil and o or nil,
        })
    end)
end


-- Place the clients and drawin on top of each other.
capi.awesome.connect_signal("refresh", function()
    if need_restack then
        module.restack()
        need_restack = false
    end
end)

return module
