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
local unsorted_stacking2 = atree {}

-- Mark if the client is eligible to be restored in its previous position or
-- if it should be added at the front/back of the layer.]
local restorable = setmetatable({}, {__mode = "k"})

-- Keep track of where the clients are currently located in the tree and which
-- other clients are in that layer. It avoids the `O(N)` foreach of the layer
-- when trying to find the ideal position to insert the client.
local layer_clients, clients_layer = {}, setmetatable({}, {__mode = "k"})

local x11_layers_to_nodes, nodes_to_x11_layers = {
    WINDOW_LAYER_ONTOP      = global_stacking:append_new { label = "ontop"      },
--     WINDOW_LAYER_FULLSCREEN = global_stacking:append_new { label = "fullscreen" },
    WINDOW_LAYER_ABOVE      = global_stacking:append_new { label = "above"      },
    WINDOW_LAYER_NORMAL     = global_stacking:append_new { label = "normal"     },
    WINDOW_LAYER_BELOW      = global_stacking:append_new { label = "below"      },
    WINDOW_LAYER_DESKTOP    = global_stacking:append_new { label = "desktop"    },
}, {}

for k, v in pairs(x11_layers_to_nodes) do
    nodes_to_x11_layers[v] = k
    layer_clients[v.label] = setmetatable({}, {__mode = "k"})
end

-- If a client is transient **TO** another client (so `self == other.transient_for`),
-- then create branch where `self` is the last_child and and other branch is
-- `first_child`. Calling `raise/lower` move the client within this second
-- sub-branch and also moves the whole group.
local transient_groups = setmetatable({}, {__mode = "kv"})
local transient_to     = setmetatable({}, {__mode = "k"})
local transient_for    = setmetatable({}, {__mode = "kv"})
local modal            = setmetatable({}, {__mode = "k"})
local placeholders     = setmetatable({}, {__mode = "kv"})

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
        return x11_layers_to_nodes.WINDOW_LAYER_DESKTOP
    elseif o.ontop then
        -- first deal with user set attributes
        return x11_layers_to_nodes.WINDOW_LAYER_ONTOP
--     elseif o.fullscreen then
--         return x11_layers_to_nodes.WINDOW_LAYER_FULLSCREEN
    elseif o.above then
        return x11_layers_to_nodes.WINDOW_LAYER_ABOVE
    elseif o.below then
        return x11_layers_to_nodes.WINDOW_LAYER_BELOW
    elseif o.transient_for then
        -- check for transient attr
        return x11_layers_to_nodes.WINDOW_LAYER_IGNORE
    else
        return x11_layers_to_nodes.WINDOW_LAYER_NORMAL
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

-- Return either the client client node or the group.
local function get_node(c)
    return transient_groups[c] or global_stacking:find_client_node(c)
end

-- local function get_unsorted_node(c)
--     return unsorted_stacking:find_client_node(c)
-- end

-- Get the global unsorted Z-index for a set of clients.
local function get_unsorted_indices(object_set, size)
    local index, found, ret = 1, 0, {}

    print("\nSTACK START")
    for node in atree.iterate_children(unsorted_stacking) do
        print(node.label)
        local o = node.client or (node.wibox and node.wibox.drawin)

        if o and object_set[o] then
            ret[o] = index
            found = found + 1

            if found == size then
                print("FOUND", node.label, ret, index)
                return ret
            end
        end
        index = index + 1
    end
    print("STACK STOP\n")

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


local function find_neighbor(object, layer)
    local applicable = layer_clients[layer.label]
    local unsorted_node = unsorted_stacking2:find_client_node(object)

    if not unsorted_node then
        print("\nNOT FOUND", node.label, layer.label, object)
        return nil, nil
    end

    local unsorted_node_prev = unsorted_node.previous_sibling
    local unsorted_node_next = unsorted_node.next_sibling

    -- Find the next and previous client.
    while unsorted_node_prev do
        print("CHECK PREV", unsorted_node_prev.client, applicable[unsorted_node_prev.client], layer.label, global_stacking:find_client_node(unsorted_node_prev.client))
        if applicable[unsorted_node_prev.client] then break end
        unsorted_node_prev = unsorted_node_prev.previous_sibling
    end

    while unsorted_node_next do
        print("CHECK NEXT", unsorted_node_next.client, applicable[unsorted_node_next.client], layer.label, global_stacking:find_client_node(unsorted_node_next.client))
        if applicable[unsorted_node_next.client] then break end
        unsorted_node_next = unsorted_node_next.next_sibling
    end

    print("\nRRRR", unsorted_node_prev, unsorted_node_next)

    -- Map this back to the layered tree.
    local prev_node = unsorted_node_prev
        and global_stacking:find_client_node(unsorted_node_prev.client) or nil
    local next_node = unsorted_node_next
        and global_stacking:find_client_node(unsorted_node_next.client) or nil

    -- Unwind the modal groups.
    if prev_node then
        while not nodes_to_x11_layers[prev_node.parent] do
            prev_node = prev_node.parent
        end
    end

    if next_node then
        while not nodes_to_x11_layers[next_node.parent] do
            next_node = next_node.parent
        end
    end

    return prev_node, next_node
end

-- Insert `object` into `layer` in a reproducible position.
--
-- It's slow, but only happens on layer changes, which are rare.
local function insert_into_layer(node, object, layer)
--     local map, size  = get_layer_object_map(layer)
--     map[object] = true

    local prev_neighbor, next_neighbor = find_neighbor(object, layer)

    while not nodes_to_x11_layers[node.parent] do
        node = node.parent
    end

    -- Maintain the map of which client is currently in each layer to speed-up
    -- finding where to insert them.
    print("\n\n\nDDDD", object, layer.label)
    local old_layer = clients_layer[object]

    if old_layer and old_layer ~= layer.label then
        layer_clients[old_layer][object] = nil
    end

    clients_layer[object] = layer.label
    print("\n\nADD", object, layer.label)
    layer_clients[layer.label][object] = true

--     local indices = get_unsorted_indices(map, size)

    local prev_idx, next_idx, prev_obj, next_obj = math.huge, 0, nil, nil
--     local target_idx = indices[object]

--     print("\nIDX", prev_idx, target_idx)

--     if not target_idx then
--         layer:push(node)
--         return
--     end

    -- Find the future siblings of `node`.
--     for obj, idx in pairs(indices) do
--         if idx < target_idx and idx > prev_idx then
--             prev_obj, prev_idx = obj, idx
--         end
--         if idx > target_idx and idx < next_idx then
--             next_obj, next_idx = obj, idx
--         end
--     end
--     print("\nIDX2", prev_idx, target_idx)
    print("\nIDX", prev_neighbor, prev_neighbor and prev_neighbor.label, "next", next_neighbor, next_neighbor and next_neighbor.label)
    if prev_neighbor then
        node:move_after(prev_neighbor)
    elseif next_neighbor then
        node:move_before(next_neighbor)
    else
        layer:push(node)

        -- Make sure the `push` is reflected in the unsorted list too.
        local unsorted_node = unsorted_stacking2:find_client_node(c)
        if unsorted_node then
            unsorted_stacking2:push(unsorted_node)
        end
    end
end

-- Keep the current and previous `transient_for` value.
local function update_transience(c)
    local node = get_node(c)
    print("update_transience", c, c.name, c.transient_for, node)

--     local unsorted = get_unsorted_node(c)
--     if unsorted then
--         unsorted_stacking:push(unsorted)
--     else
--         unsorted_stacking:push_new { client = c }
--     end

    -- Race condition when opening a popup.
    if not node then
        manage_client(c)
        node = get_node(c)
    end

    assert(node, "Can't find the tree node for `" .. c.name .."`")

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

local function unsorted_to_lower(c)
    restorable[c] = false

    local node = unsorted_stacking2:find_client_node(c)

    if not node then
        unsorted_stacking2:append_new { client = c }
    else
        unsorted_stacking2:append(node)
    end
end

local function unsorted_to_upper(c)
    restorable[c] = false

    local node = unsorted_stacking2:find_client_node(c)

    if not node then
        unsorted_stacking2:push_new { client = c }
    else
        unsorted_stacking2:push(node)
    end
end

-- local function fold_placeholder(c)
--     if placeholders[c] then
--         placeholders[c]:join()
--         placeholders[c] = nil
--     end
-- end
--
-- -- Placeholder nodes are to ensure you can undo operation
-- -- (like fullscreen->unfullscreen) and the client goes back in its original
-- -- Z-index slot. They are dismissed as soon as they are raised/lowered.
-- local function create_placeholder(c)
--     local node = global_stacking:find_client_node(c)
--
--     -- Get the topmost group in case of deep modal trees.
--     while not nodes_to_x11_layers[node.parent] do
--         node = node.parent
--     end
--
--     assert(node, "Can't find the tree node for `" .. c.name .."`" .. debug.traceback())
--
--     fold_placeholder(c)
--
--     local placeholder = node:wrap { label = "placeholder" }
--     placeholders[c] = placeholder
--
--     return node
-- end
--
-- local function apply_placeholder(c)
--     if placeholders[c] then
--         placeholders[c]:swap(node)
--     end
--     fold_placeholder(c)
-- end
--
-- local function placeholder_layer(c)
--     local ph = placeholders[c]
--     if not ph then return nil end
--
--     while ph and not nodes_to_x11_layers[ph] do
--         ph = ph.parent
--     end
--
--     return ph
-- end

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

    fold_placeholder(c)
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
    unsorted_stacking2:push_new { client = c }
    layer_clients[layer.label][c] = true

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

-- Make or delete a placeholder node to be able to restore
-- the previous position if un-fullscreenned without ever
-- raising or lowering the client.
local function handle_fullscreen(c)
    local node = get_node(c)
    -- Race condition between async signals.
    if not node then return end
    assert(node, "Can't find the tree node for `" .. c.name .."`")

--     if c.fullscreen then
--         create_placeholder(c)
--     else
--         if placeholders[c] then
--             placeholders[c]:swap(node)
--         end
--         fold_placeholder(c)
--     end
end

function module.raise_handler(c, context, hints)
    local node = get_node(c)
    local restack_needed = false

--     fold_placeholder(c)
    unsorted_to_upper(c)

--     local unsorted = get_unsorted_node(c)
--     if unsorted then
--         unsorted_stacking:push(unsorted)
--     else
--         unsorted_stacking:push_new { client = c } --FIXME impossible?
--     end

    print("RAISE!", node.parent.first_child ~= node, restack_needed, c.name)
    -- Raise the client within its own group.
    if node.parent.first_child ~= node then
        node.parent:push(node)
        restack_needed = true
    end

    print("BEFORE")
    -- Raise all groups all the way to the root.
    restack_needed = apply_recursive(node.parent, "push", "previous_sibling")
        or restack_needed
    print("AFTER", restack_needed)

    if restack_needed then
        module.restack()
    end
end

function module.lower_handler(c, context, hints)
    local node = get_node(c)
    local restack_needed = false
    local layer = client_to_layer(c)

    unsorted_to_lower(c)

    -- Dismiss the placeholder. They exist only to ensure `mod4+f` + `mod4+f`
    -- place the client back in its original Z slot.
--     if placeholders[c] then
--         placeholders[c]:join()
--         placeholders[c] = nil
--     end

    if node.parent.last_child ~= node then
        layer:append(node)
        restack_needed = true
    end

--     local unsorted = get_unsorted_node(c)
--     if unsorted then
--         unsorted_stacking:append(unsorted)
--     else
--         unsorted_stacking:append_new { client = c }
--     end

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

    -- The idea here is to be able to "undo" operations like layer change or
    -- fullscreen change and restore the client in its previous position.
    local is_restorable = restorable[c]
    restorable[c] = true

    local node = get_node(c)

    if not node then return end

    local current_layer, curent_group = node, node

    while not nodes_to_x11_layers[current_layer] do
        curent_group  = current_layer
        current_layer = current_layer.parent
    end

    local new_layer = client_to_layer(c)

--     local pl_layer = placeholder_layer(c)

--     print("APPLY!============", new_layer and new_layer == pl_layer, pl_layer and pl_layer.label or nil)
--     if new_layer and new_layer == placeholder_layer then
--         apply_placeholder(c)
--     end

    -- Make sure, if undone, the client go back to it's previous position.
--     node = create_placeholder(c)

    if new_layer ~= current_layer then
        print("LAYER CHANGE!", current_layer.label, "->", new_layer.label)
        insert_into_layer(node, c, new_layer)
        module.restack()
    end
end

function module.restack()
    if need_restack then return end

    need_restack = true
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
        print("END RESTACK")
        print("START UNORDER")
        for node in atree.iterate_next(unsorted_stacking2) do
            print(" * ", node.client)
        end
        print("END UNORDER") --END DEBUG
        global_stacking:_apply_stacking()
        need_restack = false
    end)
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
for _, class in ipairs { capi.client, capi.drawin } do
    class.connect_signal("property::type", function(o) --FIXME move fullscreen to C
        capi.client.emit_signal("request::restack", "type", {
            client = o.modal ~= nil and o or nil,
            drawin = o.modal == nil and o or nil,
        })
    end)
end

capi.client.connect_signal("property::fullscreen", handle_fullscreen)

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

    x11_layers_to_nodes  = nil
    global_stacking   = nil
    unsorted_stacking = nil
end

return module
