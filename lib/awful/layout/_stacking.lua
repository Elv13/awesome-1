local capi = { drawin = drawin, client = client, awesome = awesome, root = root }

-- Those tables are the Z-index source of truth.
local global_stack, global_stack_inverted = {}, {}
local client_stack, client_stack_inverted = {}, {}
local drawin_stack, drawin_stack_inverted = setmetatable({}, {__mode = "v"}), setmetatable({}, {__mode = "k"})

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
        return x11_layers_keys.WINDOW_LAYER_ONTOP
    elseif o.fullscreen and capi.client.focus == o then
        -- Fullscreen windows only get their own layer when they have the focus
        return x11_layers_keys.WINDOW_LAYER_FULLSCREEN
    elseif o.above then
        return x11_layers_keys.WINDOW_LAYER_ABOVE
    elseif o.below then
        return x11_layers_keys.WINDOW_LAYER_BELOW
    elseif o.transient_for then
        -- check for transient attr
        return x11_layers_keys.WINDOW_LAYER_IGNORE
    else
        return x11_layers_keys.WINDOW_LAYER_NORMAL
    end
end

-- Keep the current and previous `transient_for` value.
local function update_transience(c)
    if c.transient_for then
        local priv = c.transient_for._private
        priv.transient_to = priv.transient_to or {}
        c._private.previous_transient_for = c.transient_for
    elseif c._private.previous_transient_for and c._private.previous_transient_for.valid then
        local prev = c._private.previous_transient_for
        prev._private.transient_to[c] = nil
    end
end

-- Update the inverted mapping.
local function refresh_indices()
    local to_refresh = {
        [global_stack] = global_stack_inverted,
        [client_stack] = client_stack_inverted,
        [drawin_stack] = drawin_stack_inverted,
    }

    for raw, inverted in pairs(to_refresh) do
        for k, v in ipairs(raw) do
            inverted[v] = k
        end
    end
end

local function get_new_clients()
    if capi.client._get_count() == #client_stack then return {} end

    local new = {}

    for _, c in ipairs(capi.client.get()) do
        if not client_stack_inverted[c] then
            table.insert(new, c)
        end
    end

    return new
end

-- [UNDOCUMENTED] Handler for `request::restack`.
--
-- @signalhandler awful.layout.move_handler
-- @tparam string context The context
-- @tparam table hints Additional hints
-- @tparam[opt=nil] client|nil hints.client The client
-- @tparam[opt=nil] drawin|nil hints.drawin Additional hints
function module._restack_handler(context, context, hints)
    --TODO Support permissions
    hints = hints or {}

    -- Now is needed by the backend when either x-properties are added or when
    -- a new client is added.
    if hints.now then
        module.restack()
        need_restack = false
    else
        need_restack = true
    end
end

-- Remove a client from the stacking source of truth.
function module._unmanage_client_handler(c, context, hints)
    if not global_stack_inverted[c] then return end

    table.remove(global_stack, global_stack_inverted[c])
    table.remove(client_stack, client_stack_inverted[c])
    global_stack_inverted[c] = nil
    client_stack_inverted[c] = nil

    refresh_indices()
end

function module._unmanage_drawin_handler(d, context, hints)
    -- Those are weak tables, there is a GC race.
    if drawin_stack[drawin_stack_inverted[d]] == d then
        table.remove(drawin_stack, drawin_stack_inverted[d])
        drawin_stack_inverted[d] = nil
    end

    refresh_indices()
end

function module.raise_handler(c, context, hints)
    -- New client, it can't have reversed `transient_for` just yet.
    if not global_stack_inverted[c] then
        table.insert(global_stack, c)
        global_stack_inverted[c] = #global_stack
        table.insert(client_stack, c)
        client_stack_inverted[c] = #client_stack
        module.restack()
        return
    end

    -- Gather the transient_for/modal chain in front of `c` and raise them too.
    local keep_in_front = {c}

    local gather_transient = nil
    gather_transient = function(c, keep_in_front)
        keep_in_front = keep_in_front or {c}
        for tc in pairs(c._private.transient_to or {}) do
          table.insert(keep_in_front, tc)
          gather_transient(tc, keep_in_front)
        end

        return keep_in_front
    end

    local to_raise = gather_transient(c)

    -- Preserve the existing order.
    if #to_raise > 1 then
        table.sort(to_raise, function(a, b) return global_stack_inverted[a] < global_stack_inverted[b] end)
    end

    for _, c2 in ipairs(to_raise) do
        assert(global_stack[global_stack_inverted[c2]] == c)
        table.remove(global_stack, global_stack_inverted[c2])
        table.remove(client_stack, client_stack_inverted[c2])
    end

    for _, c2 in ipairs(to_raise) do
        table.insert(global_stack, 1, c2)
        table.insert(client_stack, 1, c2)
    end

    refresh_indices()

    module.restack()
end

function module.lower_handler(c, context, hints)

    -- Get every (grand-)parent in the transient chain and lower them too.
    -- Note that if there are multiple `transient_for` for the same parent,
    -- this will be a bit wierd. However, 1) calling `:lower()` is rare and
    -- 2), clients with multiple `transient_for` window in parallel is also
    -- getting very rare. Someone will probably eventually complain that there
    -- is not way to customize this behavior, but this is so niche it's not
    -- worth adding the complexity just yet.
    local chain = {c}

    local tc = c.transient_for

    while tc do
        table.insert(chain, 1, tc)
        tc = tc.transient_for
    end

    for _, c2 in ipairs(chain) do
        table.remove(global_stack, global_stack_inverted[c2])
        table.remove(client_stack, client_stack_inverted[c2])
    end

    for _, c2 in ipairs(chain) do
        table.insert(global_stack, 1, c2)
        table.insert(client_stack, 1, c2)
    end

    module.restack()
end

function module.restack()
    local layers = {}

    local function append(o, back)
        local layer = client_to_layer(o)
        layers[layer] = layers[layer] or {}
        if back then
            table.insert(layers[layer], o.drawin and o.drawin or o)
        else
            table.insert(layers[layer], 1, o.drawin and o.drawin or o)
        end
    end

    local drawins = capi.drawin.get() --FIXME use `request::manage`.

    -- Don't rely on `type()`, some backends don't support it.
    local types = { client = {}, drawin = {}}

    local new_c = {}

    for _, c in ipairs(client_stack) do
        append(c)
        types.client[c] = true
    end

    -- Assume `:lower()` by default for new clients.
    -- The default `rc.lua` rule will call `request::raise`, so this should be
    -- mostly fallback code in case the rules are deleted.
    for _, c in ipairs(get_new_clients()) do
        append(c, true)
    end

    for i=#drawins, 1, -1 do
        local d = drawins[i]
        append(d.get_wibox and d.get_wibox() or d)
        types.drawin[d] = true
    end

    local new_global_stack, new_global_stack_inverted = {}, {}
    local new_client_stack, new_client_stack_inverted = {}, {}
    local new_drawin_stack, new_drawin_stack_inverted = setmetatable({}, {__mode = "v"}), setmetatable({}, {__mode = "k"})

    -- Generate the new order.
    for i = 1, #x11_layers_ordered do
        if layers[i] then
            for _, v in ipairs(layers[i] or {}) do
                table.insert(new_global_stack, v)
                new_global_stack_inverted[v] = #new_global_stack
                if types.client[v] then
                    table.insert(new_client_stack, v)
                    new_client_stack_inverted[v] = #new_client_stack
                else
                    table.insert(new_drawin_stack, v)
                    new_drawin_stack_inverted[v] = #new_drawin_stack
                end
            end
        end
    end

    -- Update the source of truth.
    global_stack, global_stack_inverted = new_global_stack, new_global_stack_inverted
    client_stack, client_stack_inverted = new_client_stack, new_client_stack_inverted
    drawin_stack, drawin_stack_inverted = new_drawin_stack, new_drawin_stack_inverted

    capi.client.emit_signal("request::apply_stacking", "awful.layout", {
        content = new_global_stack
    })

    capi.client.emit_signal("stacking", new_global_stack)
end

-- Handle all the requests which affect the stack and ordering.
capi.client.connect_signal("request::raise", module.raise_handler)
capi.client.connect_signal("request::lower", module.lower_handler)
capi.client.connect_signal("request::restack", module._restack_handler)
capi.client.connect_signal("request::unmanage", module._unmanage_client_handler)
capi.drawin.connect_signal("request::unmanage", module._unmanage_drawin_handler)

-- Update the internal `update_transience` map.
capi.client.connect_signal("property::transient_for", update_transience)
capi.client.connect_signal("property::modal", update_transience)

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
