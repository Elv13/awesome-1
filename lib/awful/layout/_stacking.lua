local capi = { drawin = drawin, client = client, awesome = awesome, root = root }

local atree  = require("awful.tree")
local wibox  = require("wibox")
local gtimer = require("gears.timer")

local module = {}

-- This tree keeps all elements in X11 layers.
local global_stacking = atree {}

-- This stack puts all elements in the same layer. It is used for backward
-- compatibility with the old `stack.c` business logic. It also ensure changing
-- the layer twice (for instance, `ontop` to `below` to `ontop`) restores the
-- client to the same position.
local unsorted_stacking = atree {}

local x11_layers_nodes = {
    WINDOW_LAYER_ONTOP      = global_stacking:append_new { label = "ontop"      },
    WINDOW_LAYER_FULLSCREEN = global_stacking:append_new { label = "fullscreen" },
    WINDOW_LAYER_ABOVE      = global_stacking:append_new { label = "above"      },
    WINDOW_LAYER_NORMAL     = global_stacking:append_new { label = "normal"     },
    WINDOW_LAYER_BELOW      = global_stacking:append_new { label = "below"      },
    WINDOW_LAYER_DESKTOP    = global_stacking:append_new { label = "desktop"    },
}

-- If a client is transient **TO** another client (so `self == other.transient_for`),
-- then create branch where `self` is the last_child and and other branch is
-- `first_child`. Calling `raise/lower` move the client within this second
-- sub-branch and also moves the whole group.
local transient_groups = setmetatable({}, {__mode = "kv"})
local transient_to     = setmetatable({}, {__mode = "k"})
local transient_for    = setmetatable({}, {__mode = "kv"})
local modal            = setmetatable({}, {__mode = "k"})

-- Avoid restacking the clients and drawins too often.
local need_restack = false

-- Note on the internal behavior:
--
-- The modal and transient_for properties are often set before `request::manage`
-- and have their signal. Modality can also predate transience.
--
-- Only modal clients need to use special stacking. Because if this, a little
-- reverse engineeing is required during startup. `manage_client` can be called
-- by any client for any other client
local manage_client

local function client_to_layer(o)
    -- Unwind the chain and find the "real" layer.
    while o.transient_for do
        o = o.transient_for
    end

    if o.type == "desktop" then
        return x11_layers_nodes.WINDOW_LAYER_DESKTOP
    elseif o.ontop then
        -- first deal with user set attributes
        return x11_layers_nodes.WINDOW_LAYER_ONTOP
    elseif o.fullscreen and capi.client.focus == o then
        -- Fullscreen windows only get their own layer when they have the focus
        return x11_layers_nodes.WINDOW_LAYER_FULLSCREEN
    elseif o.above then
        return x11_layers_nodes.WINDOW_LAYER_ABOVE
    elseif o.below then
        return x11_layers_nodes.WINDOW_LAYER_BELOW
    elseif o.transient_for then
        -- check for transient attr
        return x11_layers_nodes.WINDOW_LAYER_IGNORE
    else
        return x11_layers_nodes.WINDOW_LAYER_NORMAL
    end
end

local function register_transient_for(c)
    local tr = c.transient_for

    if not tr then
        if transient_for[c] then
            transient_to[transient_for[c]][c] = nil
        end
        transient_for[c] = nil
        return
    end

    transient_to[tr] = transient_to[tr] or setmetatable({}, { __mode = "k" })

    transient_to[tr][c] = true
    transient_for[c] = tr
end

-- Return either the client client node or the a group.
local function get_node(c)
    return transient_groups[c] or global_stacking:find_client_node(c)
end

local function get_unsorted_node(c)
    return unsorted_stacking:find_client_node(c)
end

-- Get the global unsorted Z-index for a set of clients.
local function get_unsorted_indices(object_set, size)
    local index, found, ret = 1, 0, {}

    for node in atree.iterate_children(unsorted_stacking) do
        local o = node.client or (node.wibox and node.wibox.drawin)

        if o and object_set[o] then
            ret[o] = index
            found = found + 1

            if found == size then return ret end
        end
        index = index + 1
    end

    return ret
end

-- Get all `layer` drawins or clients into a set.
local function get_layer_object_map(layer)
    local set, size = {}, 0

    for node in atree.iterate_children(layer) do
        local o = node.client or (node.wibox and node.wibox.drawin)
        if o then
            set[o] = true
            size = size + 1
        end
    end

    return set, size
end

-- Insert `object` into `layer` in a reproducible position.
--
-- It's slow, but only happens on layer changes, which are rare.
local function insert_into_layer(object, layer)
    local node       = get_node(object)
    local map, size  = get_layer_object_map(layer)
    map[object] = true

    local indices = get_unsorted_indices(map, size)

    local prev_idx, next_idx, prev_obj, next_obj = math.huge, 0, nil, nil
    local target_idx = indices[object]

    if not target_idx then
        layer:push(node)
        return
    end

    -- Find the future siblings of `node`.
    for obj, idx in pairs(indices) do
        if idx < target_idx and idx > prev_idx then
            prev_obj, prev_idx = obj, idx
        end
        if idx > target_idx and idx < next_idx then
            next_obj, next_idx = obj, idx
        end
    end

    if prev_obj then
        node:move_after(prev_obj)
    elseif next_obj then
        node:move_before(next_obj)
    else
        layer:push(node)
    end
end

-- Keep the current and previous `transient_for` value.
local function update_transience(c)
    local node = get_node(c)
    print("update_transience", c, c.name, c.transient_for, node)

    local unsorted = get_unsorted_node(c)
    if unsorted then
        unsorted_stacking:push(unsorted)
    else
        unsorted_stacking:push_new { client = c }
    end

    -- Race condition when opening a popup.
    if not node then
        manage_client(c)
        node = get_node(c)
    end

    local parent = c.transient_for

    -- Cleanup.
    if (not parent) and transient_for[c] then
        local group = transient_groups[parent].first_child
        if group.first_child == node and group.last_child == node then
            group.parent:join()
            group:join()
            transient_groups[parent] = nil
        end
    end

    -- Update the known transient chains.
    register_transient_for(c)

    if not parent then return end
    -- if (not parent) or (not c.modal) then return end

    local parent_node = global_stacking:find_client_node(parent)

    -- Startup race condition, request::manage has not been sent on the parent
    -- yet. It isn't ideal, but do it now.
    if not parent_node then
        manage_client(parent)
        parent_node = global_stacking:find_client_node(parent)
    end

    local group = transient_groups[parent]

    -- Create a new transient group.
    if not group then
        group = parent_node:wrap { label = "transient_group" }
        transient_groups[parent] = group

        local t = group:push_new { label = "transient_to" }

        assert(t == group.first_child)
        assert(parent_node == group.last_child)
        module.restack()
    end

    -- Push the client to the group.
    if group.first_child.first_child ~= node then
        local old_parent = node.parent

        if old_parent.label == "transient_to" and not old_parent.first_child then
            old_parent.parent:join()
            old_parent:detach()
        end

        group.first_child:push(node)
        module.restack()
    end
end

local function modal_changed(c)
    -- Cleanup.
    if (not c.modal) and modal[c] then
        update_transience(c)
        modal[c] = nil
        return
    end

    update_transience(c)
end

local function unmanage_client(c)
    local group = transient_groups[c]

    if not group then
        local node = global_stacking:find_client_node(c)

        if node then
            node:detach()
        end

        return
    end

    group.first_child:join()
    group.last_child:detach()
    group:join()
    transient_groups[c] = nil
    module.restack()
end

manage_client = function(c)
    -- Race condition, the client has been added already because one popup
    -- needed it.
    local node = global_stacking:find_client_node(c)
    if node then return end

    local layer = client_to_layer(c)

    -- It might get moved immediatly after, but create the node anyway.
    -- Since restacking is delayed, this doesn't cause any performance issues
    -- or flickering.
    layer:push_new { client = c }

    update_transience(c)
    module.restack()
end

local function add_wibox(w)
    local layer = client_to_layer(w)
    layer:push_new {
        wibox = w
    }
end

local function apply_recursive(node, method, check)
    local restack_needed = false

    for parent in atree.iterate_parent(node.parent, true) do
        local lbl = parent.label
        local grandparent = parent.parent
        if lbl == "transient_group" and grandparent then
            if parent[check] then
                grandparent[method](grandparent, parent)
                restack_needed = true
            end
        elseif lbl == "transient_to" and grandparent then
            if parent[check] then
                grandparent[method](grandparent, parent)
                restack_needed = true
            end
        end
    end

    return restack_needed
end

function module.raise_handler(c, context, hints)
    local node = get_node(c)
    local restack_needed = false

    local unsorted = get_unsorted_node(c)
    if unsorted then
        unsorted_stacking:push(unsorted)
    else
        unsorted_stacking:push_new { client = c }
    end

    print("RAISE!", node.parent.first_child ~= node)
    -- Raise the client within its own group.
    if node.parent.first_child ~= node then
        node.parent:push(node)
        restack_needed = true
    end

    -- Raise all groups all the way to the root.
    restack_needed = apply_recursive(node.parent, "push", "previous_sibling")
        or restack_needed

    if restack_needed then
        module.restack()
    end
end

function module.lower_handler(c, context, hints)
    local node = get_node(c)
    local restack_needed = false

    if node.parent.last_child ~= node then
        layer:append(node)
        restack_needed = true
    end

    local unsorted = get_unsorted_node(c)
    if unsorted then
        unsorted_stacking:append(unsorted)
    else
        unsorted_stacking:append_new { client = c }
    end

    -- Raise all groups all the way to the root.
    restack_needed = apply_recursive(node.parent, "append", "next_sibling")
        or restack_needed

    if restack_needed then
        module.restack()
    end
end

function module.restack_handler(c, hints)
    local c = hints.client

    if not c then return end --FIXME

    local node = get_node(c)

    if not node then return end

    print("\n\nNODE", node, c.name)

    local current_layer = node and node.parent or nil

    local new_layer = client_to_layer(c)

    if new_layer ~= current_layer then
        print("LAYER CHANGE!", current_layer.label, "->", new_layer.label)
        insert_into_layer(c, new_layer)
        module.restack()
    end

    print("\n\n\nMOO", c, hints.client)
end

function module.restack()
    if not need_restack then
        gtimer.delayed_call(function()
            print("START RESTACK") --BEGIN DEBUG
            for node in atree.iterate_children(global_stacking) do
                    local depth = ""
                    local parent = node.parent
                    while parent do
                        parent = parent.parent
                        depth = depth .. "  "
                    end

                    print(depth.."--> " .. node.label)
            end
            print("END RESTACK") --END DEBUG
            global_stacking:_apply_stacking()
            need_restack = false
        end)
    end

    need_restack = true
end

-- For integration tests only.
function module._get_global_stacking()
    return global_stacking
end

-- Handle all the requests which affect the stack and ordering.
capi.client.connect_signal("request::raise"  , module.raise_handler  )
capi.client.connect_signal("request::lower"  , module.lower_handler  )
capi.client.connect_signal("request::restack", module.restack_handler)


-- Update the internal `update_transience` map.
capi.client.connect_signal("property::transient_for", update_transience)
capi.client.connect_signal("property::modal"        , modal_changed    )
capi.client.connect_signal("request::manage"        , manage_client    )
capi.client.connect_signal("request::unmanage"      , unmanage_client  )

wibox.connect_signal("request::manage", add_wibox)

-- Check if the type is `"desktop"`, which goes below everything.
for _, class in ipairs(capi.client, capi.drawin) do
    class.connect_signal("property::type", function(o)
        capi.client.emit_signal("request::restack", "type", {
            client = o.modal ~= nil and o or nil,
            drawin = o.modal == nil and o or nil,
        })
    end)
end

-- Disable this so we can intergration-test `awful.tree` without fighting with
-- the global stacking.
function module._unload()
    capi.client.disconnect_signal("request::raise"         , module.raise_handler  )
    capi.client.disconnect_signal("request::lower"         , module.lower_handler  )
    capi.client.disconnect_signal("request::restack"       , module.restack_handler)
    capi.client.disconnect_signal("property::transient_for", update_transience     )
    capi.client.disconnect_signal("property::modal"        , modal_changed         )
    capi.client.disconnect_signal("request::manage"        , manage_client         )
    capi.client.disconnect_signal("request::unmanage"      , unmanage_client       )
    wibox.disconnect_signal      ("request::manage"        , add_wibox             )

    x11_layers_nodes  = nil
    global_stacking   = nil
    unsorted_stacking = nil
end

return module
