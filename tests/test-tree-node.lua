-- Test `capi._tree_node`, the building block of stacking, layers and layouts.

local runner = require("_runner")
local awful = require("awful")
local wibox = require("wibox")
local lgi = require('lgi')
local gsurface = require("gears.surface")
local cairo = lgi.cairo
local gdk = lgi.require('Gdk', '3.0')

local steps = {}

local clients, nodes

require("awful.layout._stacking")._unload()

for _= 1, 10 do
    collectgarbage("collect")
end

assert(_tree_node.instances() == 0)

local root1, wrapper = _tree_node { is_root = true }, nil

local request_cleanup_by_ctx = {}

-- Create a black "wallpaper"
local wallpaper = wibox {
    visible = true,
    bg      = "#000000",
    below   = true,
}
awful.placement.maximize(wallpaper)

local function get_pixel(x, y)
    local geo = screen[1].geometry
    local sur = gsurface(screen[1].content)
    local img = cairo.ImageSurface(cairo.Format.RGB24, geo.width, geo.height)
    local cr = cairo.Context(img)
    cr:set_source_surface(sur)
    cr:paint()
    img:flush()
    local bytes = gdk.pixbuf_get_from_surface(img, x, y, 1, 1):get_pixels()
    return "#" .. bytes:gsub('.', function(c) return ('%02x'):format(c:byte()) end)
end

local function geo_equal(geo1, geo2)
    return geo1.x == geo2.x
        and geo1.y == geo2.y
        and geo1.width == geo2.width
        and geo1.height == geo2.height
end

local function compare_lists(t1, t2)
    assert(#t1 == #t2)

    for i=1, #t1 do
        assert(t1[i] == t2[i])
    end
end

local function check_integrity()
    root1:_check_integrity()
end

local function count_request_cleanup(self, context, hints)
    request_cleanup_by_ctx[context] = (request_cleanup_by_ctx[context] or 0) + 1
end

root1:connect_signal("request::cleanup_node", count_request_cleanup)

-- Keep the clients in a known order
local function get_clients()
    clients, nodes = setmetatable({}, {__mode = "v"}), setmetatable({}, {__mode = "v"})

    for k, c in ipairs(client.get()) do
        clients[k] = c
    end

    -- Add a direct children of `root1`.
    for k, c in ipairs(clients) do
        local node = _tree_node{ client = c, parent = root1}
        assert(node.client == c)
        assert(node._clients[1] == c)
        assert(node.type == "client")
        assert(node._parent == root1)
        table.insert(nodes, node)
    end

    compare_lists(clients, root1._clients)
end

local function count_children(node)
    local count = 0

    local first = node.first_child

    -- Check for loopy chains.
    local seen = {}

    while first ~= nil do
        assert(not seen[first])
        seen[first] = true

        count = count + 1
        assert(first ~= first.next_sibling)
        first = first.next_sibling
    end

    return count
end

-- Create a flat list the tests can manipulate to check if the tree changes
-- are matching the spec.
local function flatten_tree(root, ignore_tree_nodes)
    local keys, values, count, node = {}, setmetatable({}, {__mode = "v"}), 1, root.first_child

    while node do
        if (not ignore_tree_nodes) or (node.type == "client" or node.type == "drawin")  then
            table.insert(values, node)
            keys[node] = #values
        end

        if node.type == "branch" then
            assert((not node.first_child) or node.next)
            assert(node.next == node.first_child)
        end

        if not node.next_sibling then
            assert(node._parent.last_child == node)
            assert((not node._parent.next_sibling) or node._parent.next_sibling == node.next)
        end

        node = node.next
        count = count + 1
    end

    return values, keys
end

-- Only works when the tree is a list.
local function check_chain()
    assert(#nodes > 0)
    assert(not nodes[1].previous_sibling)
    assert(not nodes[#nodes].next_sibling)
    assert(root1.first_child == nodes[1])
    assert(root1.last_child == nodes[#nodes])

    for k, node in ipairs(nodes) do
        assert(node.previous_sibling ~= node)
        assert(node.previous_sibling == nodes[k-1])
        assert(node.previous ~= node)
        assert(node.previous == nodes[k-1] or node.previous == root1)
        assert(node.next_sibling ~= node)
        assert(node.next_sibling == nodes[k+1])
        assert(node.next ~= node)
        assert(node.next == nodes[k+1])
        assert(node._parent == root1)
        assert(node.type ~= "branch")
        assert(node.type ~= "root")
    end

    assert(#nodes == count_children(root1))
    check_integrity()
end

-- Fatten the tree and compare it to a list.
-- @tparam table object_list A list of client or drawin tree nodes.
local function check_tree(root, object_list)
    root, object_list = root or root1, object_list or nodes

    local nodes = flatten_tree(root, true)
    assert(#nodes == #object_list, #nodes .."<->"..#object_list)

    for k, v in ipairs(nodes) do
        assert(v == object_list[k])
    end

    check_integrity()
end

-- Brute force what is the wibox order based on their color and screenshots.
local function get_visible_wiboxes(wiboxes, colors)
    local reverse_color = {}
    local wibox_above = {}

    for k, col in ipairs(colors) do
        reverse_color[col] = k
    end

    local default_geo = {
        x      = 0,
        y      = 0,
        width  = 50,
        height = 50,
    }

    local test_geo = {
        x      = 100,
        y      = 100,
        width  = 50,
        height = 50,
    }

    -- Move all to 0x0
    for _, w in ipairs(wiboxes) do
        w:geometry(default_geo)
    end

    for k1, w1 in ipairs(wiboxes) do
        local above, below = {}, {}

        for k2, w2 in ipairs(wiboxes) do
            if w1 ~= w2 then
                -- Move to the test area
                for _, w3 in ipairs { w1, w2 } do
                    w3:geometry(test_geo)
                end

                awesome.sync()

                -- Check which one is on top.
                local color = get_pixel(105, 105)
                assert(reverse_color[color])

                if color == colors[k2] then
                    -- w2 is above w1
                    table.insert(below, w2)
                elseif color == colors[k1] then
                    -- w1 is above w2
                    table.insert(above, w2)
                else
                    assert(false, "Invalid color")
                end

                -- Move to the storage area
                for _, w3 in ipairs { w1, w2 } do
                    w3:geometry(default_geo)
                end
            end
        end

        wibox_above[w1] = (#wiboxes - #above)
    end

    local order = {}

    for k, v in pairs(wibox_above) do
        order[v] = k
    end

    return order
end

local function get_wibox(x, y, wiboxes, colors)
    local color = get_pixel(x, y)

    for k, col in ipairs(colors) do
        if color == col then
            return wiboxes[k]
        end
    end

    return nil
end

local function order_equal(list1, list2)
    if #list1 ~= #list2 then return false end

    for k, v in ipairs(list1) do
        if list2[k] ~= v then return false end
    end

    return true
end

-- Spawn some clients.
table.insert(steps, function()
    for _=1, 5 do
        awful.spawn("xterm")
    end
    return true
end)

table.insert(steps, function()
    if #client.get() ~= 5 then return end
    get_clients()

    -- Test the horizontal linked list.
    check_chain()
    check_tree()

    for i=5, 1, -1 do
        client.get()[i]:kill()
    end

    return true
end)

-- Check for leaks.
table.insert(steps, function()
    if #client.get() ~= 0 then return end

    for _=1, 5 do
        collectgarbage("collect")
    end

    if #nodes > 0 then return end

    assert(not root1.first_child)
    assert(not root1.last_child)
    assert(count_children(root1) == 0)
    assert(request_cleanup_by_ctx.client_killed == 5)
    request_cleanup_by_ctx = {}

    for _=1, 5 do
        awful.spawn("xterm")
    end

    return true
end)

-- Poke holes in the chain.
table.insert(steps, function()
    if #client.get() ~= 5 then return end
    get_clients()
    assert(count_children(root1) == 5)
    check_chain()

    table.remove(nodes, 4)
    client.get()[4]:kill()

    table.remove(nodes, 2)
    client.get()[2]:kill()

    return true
end)

-- See if the chain adapted.
table.insert(steps, function()
    if #client.get() ~= 3 then return end

    assert(count_children(root1) == 3)
    check_chain()

    table.remove(nodes, 3)
    client.get()[3]:kill()

    table.remove(nodes, 1)
    client.get()[1]:kill()

    return true
end)

table.insert(steps, function()
    if #client.get() ~= 1 then return end
    assert(count_children(root1) == 1)
    check_chain()
    assert(root1.first_child == root1.last_child)

    table.remove(nodes, 1)
    client.get()[1]:kill()

    return true
end)

table.insert(steps, function()
    if #client.get() ~= 0 then return end

    assert(not root1.first_child)
    assert(not root1.last_child)

    for _=1, 5 do
        awful.spawn("xterm")
    end

    return true
end)

-- Try swapping some clients.
table.insert(steps, function()
    if #client.get() ~= 5 then return end

    get_clients()
    assert(count_children(root1) == 5)
    check_chain()

    local n1, n5 = nodes[1], nodes[5]

    -- Swap the ends of the list
    assert(root1.first_child == n1)
    assert(root1.last_child == n5)
    nodes[1]:swap(nodes[5])
    nodes[5], nodes[1] = nodes[1], nodes[5]
    check_chain()
    assert(root1.first_child == n5)
    assert(root1.last_child == n1)
    assert(count_children(root1) == 5)
    check_chain()

    -- Swap inner nodes
    nodes[4]:swap(nodes[2])
    nodes[4], nodes[2] = nodes[2], nodes[4]
    check_chain()

    -- Swap nodes next to each other
    nodes[3]:swap(nodes[2])
    nodes[3], nodes[2] = nodes[2], nodes[3]
    check_chain()

    -- Undo
    nodes[2]:swap(nodes[3])
    nodes[3], nodes[2] = nodes[2], nodes[3]
    check_chain()

    -- Middle with first
    nodes[3]:swap(nodes[1])
    nodes[3], nodes[1] = nodes[1], nodes[3]
    check_chain()

    -- First with middle
    nodes[1]:swap(nodes[3])
    nodes[3], nodes[1] = nodes[1], nodes[3]
    check_chain()

    -- Middle with last
    nodes[3]:swap(nodes[5])
    nodes[3], nodes[5] = nodes[5], nodes[3]
    check_chain()

    -- Last with middle
    nodes[5]:swap(nodes[3])
    nodes[3], nodes[5] = nodes[5], nodes[3]
    check_chain()

    return true
end)

-- Create a tree.
table.insert(steps, function()
    local old_last = root1.last_child
    local tree = _tree_node { parent = root1 }

    assert(tree._parent == root1)
    assert(root1.last_child == tree)
    assert(not tree.next_sibling)
    assert(not tree.next)
    assert(old_last.next_sibling == tree)
    assert(old_last.next == tree)
    assert(tree.previous_sibling == old_last)
    assert(tree.previous == old_last)
    check_tree()

    local n1, n2, n3 = nodes[1], nodes[3], nodes[2]
    table.remove(nodes, 1)
    table.insert(nodes, n1)
    tree:append(n1)
    assert(n1._parent == tree)
    assert(tree.first_child == n1)
    assert(tree.last_child == n1)
    check_tree()

    -- No-op
    tree:append(n1)
    assert(n1._parent == tree)
    assert(tree.first_child == n1)
    assert(tree.last_child == n1)
    check_tree()

    tree:append(n2)
    table.remove(nodes, 2)
    table.insert(nodes, n2)
    assert(tree.first_child == n1)
    assert(tree.last_child == n2)
    check_tree()

    -- No-op
    tree:append(n2)
    assert(tree.first_child == n1)
    assert(tree.last_child == n2)

    tree:append(n3)
    table.remove(nodes, 1)
    table.insert(nodes, n3)
    assert(tree.first_child == n1)
    assert(tree.last_child == n3)
    assert(n3.previous_sibling == n2)
    assert(n2.next_sibling == n3)
    check_tree()

    -- Swap the sub-tree from the back to the front.
    local new_last, old_first = nodes[2], nodes[1]
    assert(new_last ~= tree)
    assert(root1.last_child == tree)
    old_first:swap(tree)
    assert(root1.last_child == old_first)
    old_first:swap(tree)
    assert(root1.last_child == tree)
    check_tree()

    -- Swap the sub-tree from the back to the middle.
    new_last:swap(tree)
    assert(new_last.previous == tree.last_child)
    assert(root1.last_child == new_last)
    new_last:swap(tree)
    new_last:swap(tree)
    assert(new_last.previous == tree.last_child)
    assert(root1.last_child == new_last)
    table.remove(nodes, 2)
    table.insert(nodes, new_last)
    check_tree()

    -- Move the tree back to the front (using `push` instead of `swap`).
    assert(root1.first_child == nodes[1])
    root1:push(tree)
    assert(root1.first_child == tree)
    assert(tree.next_sibling == nodes[1])
    assert(n3.next == nodes[1])
    assert(nodes[1].previous_sibling == tree)
    assert(nodes[1].previous == tree.last_child)

    -- Move it back to the end (using `append` instead of `swap`).
    root1:append(tree)
    root1:append(new_last)
    assert(root1.first_child == nodes[1])
    check_tree()

    -- Move to the back and refresh `nodes`
    root1:append(tree)
    local function refresh_nodes()
        nodes = setmetatable({}, {__mode = "v"})
        local n = root1.first_child
        while n do
            if n.type ~= "branch" then
                table.insert(nodes, n)
            end
            n = n.next_sibling
        end
    end
    refresh_nodes()

    -- Move it to the middle using `insert_before`.
    assert(nodes[2].previous_sibling == nodes[1])
    tree:move_before(nodes[2])
    assert(nodes[2].previous_sibling == tree)
    assert(tree.next_sibling == nodes[2])
    assert(tree.last_child.next == nodes[2])
    assert(tree.previous_sibling == nodes[1])
    assert(nodes[1].next_sibling == tree)

    -- Move to the tree to the front by moving the current `first_child` to the
    -- middle.
    nodes[1]:move_before(nodes[2])
    assert(nodes[2].previous_sibling == nodes[1])
    assert(nodes[1].previous_sibling == tree)
    assert(tree.next_sibling == nodes[1])
    assert(root1.first_child == tree)

    -- Move the tree to the back using `insert_after`.
    refresh_nodes()
    assert(root1.last_child == nodes[2])
    tree:move_after(nodes[2])
    assert(root1.last_child == tree)
    assert(nodes[2].next_sibling == tree)
    assert(tree.previous_sibling == nodes[2])
    assert(nodes[1].next_sibling == nodes[2])
    assert(nodes[2].previous_sibling == nodes[1])

    -- Remove the tree first and last elements and move them around it.
    refresh_nodes()
    assert(nodes[1].next_sibling == nodes[2])
    local old_tree_first, old_tree_last = tree.first_child, tree.last_child
    local old_tree_middle = tree.first_child.next_sibling
    old_tree_first:move_before(tree)
    old_tree_last:move_after(tree)
    assert(tree.previous_sibling == old_tree_first)
    assert(tree.next_sibling == old_tree_last)
    assert(old_tree_first.next_sibling == tree)
    assert(old_tree_last.previous_sibling == tree)
    assert(nodes[2].next_sibling == old_tree_first)
    assert(root1.last_child == old_tree_last)
    assert(old_tree_first.previous_sibling == nodes[2])
    assert(old_tree_last.next_sibling == nil)

    -- Try wrap on the front.
    refresh_nodes()
    wrapper = _tree_node { wrap = nodes[1] }
    assert(wrapper.first_child == nodes[1])
    assert(wrapper.last_child == nodes[1])
    assert(nodes[1]._parent == wrapper)
    assert(wrapper.next_sibling == nodes[2])
    assert(nodes[2].previous_sibling == wrapper)
    assert(nodes[1].next == nodes[2])

    -- Multiple tree branches.
    refresh_nodes()
    local new_first = tree.first_child
    local old_tree_previous, old_tree_next = tree.previous_sibling, tree.next_sibling
    assert(tree == root1.last_child.previous_sibling)
    assert(root1.first_child._parent == root1)
    wrapper:swap(tree.first_child)
    assert(wrapper._parent == tree)
    assert(root1.first_child == new_first)
    assert(tree.first_child == wrapper)
    assert(tree.last_child == wrapper)
    assert(root1.first_child._parent == root1)
    assert(wrapper.first_child)
    assert(wrapper.first_child.next == old_tree_next)
    assert(old_tree_next.previous == wrapper.first_child)

    -- Join everything back.
    old_first = wrapper.first_child
    wrapper:join()
    tree:join()
    assert(old_tree_previous.next_sibling == old_first)
    assert(old_tree_next.previous_sibling == old_first)

    -- Make another tree.
    refresh_nodes()
    assert(#nodes == 5)
    wrapper = _tree_node { wrap = nodes[3] }
    nodes[2]:move_after(nodes[3])
    nodes[4]:move_before(nodes[3])
    assert(wrapper.first_child == nodes[4])
    assert(wrapper.last_child == nodes[2])
    assert(wrapper.first_child.next_sibling == nodes[3])
    assert(root1.first_child.next == wrapper)
    assert(root1.first_child.next.next == nodes[4])
    assert(root1.last_child.previous_sibling == wrapper)
    assert(root1.last_child.previous == nodes[2])
    local wrapper2 = _tree_node { wrap = nodes[2] }
    assert(wrapper2.first_child == nodes[2])
    assert(wrapper2.last_child == nodes[2])
    assert(root1.last_child.previous == nodes[2])
    assert(wrapper.last_child == wrapper2)
    assert(nodes[2].previous == wrapper2)
    wrapper:join()
    nodes[5]:move_before(root1.first_child)
    assert(nodes[2].previous == wrapper2)
    assert(root1.last_child == wrapper2)
    wrapper2:join()
    assert(root1.last_child == nodes[2])
    assert(nodes[2].next_sibling == nil)

    -- `:join()` edge cases.
    refresh_nodes()
    wrapper2 = _tree_node { wrap = nodes[1] }
    assert(root1.first_child == wrapper2)
    local wrapper3 = _tree_node { wrap = nodes[5] }
    assert(root1.last_child == wrapper3)
    wrapper2.first_child:move_before(nodes[3])
    wrapper3.first_child:move_before(nodes[3])
    assert(not wrapper2.first_child)
    assert(not wrapper2.last_child)
    assert(not wrapper3.first_child)
    assert(not wrapper3.last_child)
    wrapper2:join()
    wrapper3:join()
    assert(root1.first_child == nodes[2])
    assert(root1.last_child == nodes[4])

    -- Check what happens when killing clients.
    refresh_nodes()
    wrapper = _tree_node { wrap = nodes[1] }

    -- Add some extra nodes.
    for _, c in ipairs(client.get()) do
        for i=1, 5 do
            _tree_node{ client = c, parent = root1}
        end
    end

    for i=5, 1, -1 do
        client.get()[i]:kill()
    end

    return true
end)

-- Check that deleting all client didn't corrupt the _TREE nodes.
table.insert(steps, function()
    if #client.get() ~= 0 then return end

    assert(wrapper)
    assert(not wrapper.first_child)
    assert(not wrapper.last_child)
    assert(root1.first_child == wrapper)
    assert(root1.last_child == wrapper)

    wrapper:join()
    assert(not root1.first_child)
    assert(not root1.last_child)

    -- Test joining empty nodes.
    local node = _tree_node { parent = root1 }
    assert(root1.first_child == node)
    assert(root1.last_child == node)
    node:join()
    assert(not root1.first_child)
    assert(not root1.last_child)

    for _=1, 5 do
        awful.spawn("xterm")
    end

    return true
end)

-- Test geometry
table.insert(steps, function()
    if #client.get() ~= 5 then return end

    get_clients()

    assert(nodes[1].geometry.x == 0)
    nodes[1].geometry = { x = 100 }
    assert(nodes[1].geometry.x == 100)

    local old_w, old_h = nodes[2].client:geometry().width, nodes[2].client:geometry().height

    local args = nil
    nodes[2]:connect_signal("property::geometry", function(...)
        args = {...}
    end)

    local new_geo = {
        x      = 100,
        y      = 100,
        width  = old_w + 1,
        height = old_h + 1,
    }

    nodes[2].geometry = new_geo

    nodes[2].gaps = 2

    for _, side in ipairs { "left", "right", "top", "bottom" } do
        assert(nodes[2].gaps[side] == 2)
    end

    nodes[2].gaps = {
        left   = 41,
        right  = 42,
        top    = 43,
        bottom = 44,
    }

    for i, side in ipairs { "left", "right", "top", "bottom" } do
        assert(nodes[2].gaps[side] == 40+i)
    end

    assert(args)
    assert(args[1] == nodes[2])
    assert(geo_equal(new_geo, args[2]))

    assert(not geo_equal(nodes[2].client:geometry(), nodes[2].geometry))

    root1:_apply_geometry(true)

    -- Because it's xterm, it has size_hints.
    assert(nodes[2].client:geometry().x      == 100  )
    assert(nodes[2].client:geometry().y      == 100  )
    assert(nodes[2].client:geometry().width  == old_w)
    assert(nodes[2].client:geometry().height == old_h)

    -- Disable size hints.
    root1:_apply_geometry(false)
    assert(geo_equal(nodes[2].client:geometry(), nodes[2].geometry))

    -- Change the geo for each clients.
    for k, node in ipairs(nodes) do
        node.geometry = {
            x      = k*10,
            y      = k*10,
            width  = k*10,
            height = k*10,
        }
    end

    -- Create a tree.
    wrapper = _tree_node { wrap = nodes[4] }
    nodes[3]:move_after(nodes[4])
    assert(nodes[2].next == wrapper)
    assert(nodes[5].previous == nodes[3])
    check_integrity()

    root1:_apply_geometry(false)

    for k, node in ipairs(nodes) do
        assert(geo_equal(nodes[2].client:geometry(), nodes[2].geometry))
    end

    -- Test `_apply_geometry()` on a sub-tree.
    wrapper.first_child.geometry = {
        x      = 500,
        y      = 500,
        width  = 500,
        height = 500,
    }
    wrapper.last_child.geometry = {
        x      = 50,
        y      = 50,
        width  = 50,
        height = 50,
    }

    for _, node in ipairs { nodes[1], nodes[2], nodes[5] } do
        node.geometry = {
            x      = 1,
            y      = 1,
            width  = 1,
            height = 1,
        }
    end

    wrapper:_apply_geometry(false)
    assert(geo_equal(nodes[3].client:geometry(), nodes[3].geometry))
    assert(geo_equal(nodes[4].client:geometry(), nodes[4].geometry))
    for _, node in ipairs { nodes[1], nodes[2], nodes[5] } do
        assert(not geo_equal(node.client:geometry(), node.geometry))
    end

    for i=5, 1, -1 do
        client.get()[i]:kill()
    end

    return true
end)

local wiboxes = {}
local colors = {"#ff0000", "#ffff00", "#0000ff", "#00ff00", "#00ffff"}

-- Test the drawin/wibox and stacking.
table.insert(steps, function()
    if #client.get() ~= 0 then return end

    wrapper:join()

    assert(not root1.first_child)
    assert(not root1.last_child)

    local counter = 0

    local function prop_x_cb(self)
        counter = counter + 1
    end

    nodes = {}
    for _, color in ipairs(colors) do
        local w = wibox {
            visible = true,
            x       = 0,
            y       = 0,
            width   = 100,
            height  = 100,
            bg      = color,
        }
        assert(w.drawin)
        table.insert(wiboxes, w)
        if root1.first_child then
            table.insert(nodes, _tree_node {
                next    = root1.first_child,
                _drawin = w.drawin
            })
        else
            table.insert(nodes, _tree_node { parent = root1, _drawin = w.drawin })
        end
        assert(nodes[#nodes]._drawin)
        w:connect_signal("property::x", prop_x_cb)
    end

    for k, node in ipairs(nodes) do
        node.geometry = {
            x      = k*20,
            y      = k*20,
            width  = 200,
            height = 200,
        }
        assert(not geo_equal(node._drawin:geometry(), node.geometry))
    end

    root1:_apply_geometry(false)

    assert(counter == 5, "IS"..counter)

    for k, node in ipairs(nodes) do
        assert(geo_equal(node._drawin:geometry(), node.geometry))
    end

    return true
end)

-- Test tree operations and wibox stacking.
table.insert(steps, function()
    if get_pixel(25, 25) == "#000000" then return end

    local function reset_order()
        local new_order, node = {}, root1.first_child

        while node do
            table.insert(new_order, node)
            assert((not node.next_sibling) or node.next_sibling.previous_sibling == node)
            assert(node.next_sibling or node == root1.last_child)
            node = node.next_sibling
        end

        nodes = new_order
    end

    local original_order = get_visible_wiboxes(wiboxes, colors)
    root1:_apply_stacking()
    reset_order()
    check_chain()

    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))
    assert(get_wibox(42, 42, wiboxes, colors) == original_order[1])

    -- Append (move to front)
    table.insert(original_order, table.remove(original_order, 3))
    root1:append(nodes[3])
    reset_order()
    check_chain()
    root1:_apply_stacking()
    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))
    assert(get_wibox(42, 42, wiboxes, colors) == original_order[1])

    -- Append (move to back)
    local new_front = original_order[2]
    root1:push(nodes[5])
    root1:_apply_stacking()
    table.insert(original_order, 1, table.remove(original_order, 5))
    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))

    -- Wrap
    reset_order()
    original_order = get_visible_wiboxes(wiboxes, colors)
    local wrapper = _tree_node { wrap = nodes[3] }
    root1:_apply_stacking()
    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))

    -- Add to tree.
    nodes[4]:move_after(wrapper.first_child)
    root1:_apply_stacking()
    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))

    -- Swap.
    original_order[3], original_order[4] = original_order[4], original_order[3]
    assert(wrapper.first_child ~= wrapper.last_child)
    wrapper.first_child:swap(wrapper.last_child)
    root1:_apply_stacking()
    assert(order_equal(original_order, get_visible_wiboxes(wiboxes, colors)))
    assert(get_wibox(42, 42, wiboxes, colors) == original_order[1])

    -- Swap to front.
    root1.first_child:swap(wrapper)
    root1:_apply_stacking()
    assert(get_wibox(42, 42, wiboxes, colors) == wrapper.first_child._drawin:get_wibox())

    -- Get the wiboxes to be garbage collected.
    for _, w in ipairs(wiboxes) do
        w.visible = false
    end

    setmetatable(wiboxes, {__mode = "v" })
    nodes = {}
    while root1.first_child do
        root1.first_child:detach()
    end

    for _=1, 5 do
        collectgarbage("collect")
    end

    return true
end)

-- Try to force a drawin to be wiped.
--
-- As of the writing of this code, this is somewhat flaky with some Lua versions
-- (see `test-leaks-wibox.lua`). This test cannot make the drawin visible or it
-- will trigger the GC issue. The issue isn't "real" and doesn't actually happen
-- outside of testing as far as I can measure. However, for the sake of
-- non-flacky CI, no `visible = true` (aka, I wasted 5 hours already)...
table.insert(steps, function()
    wiboxes = {}

    assert(not root1.first_child)
    assert(not root1.last_child)

    for _, color in ipairs(colors) do
        local w = wibox {
            visible = false,
            x       = 0,
            y       = 0,
            width   = 100,
            height  = 100,
            bg      = color,
        }
        assert(w.drawin)
        table.insert(wiboxes, w)
        if root1.first_child then
            table.insert(nodes, _tree_node {
                next    = root1.last_child, -- this make no sense, on purpose
                _drawin = w.drawin
            })
        else
            table.insert(nodes, _tree_node { parent = root1, _drawin = w.drawin })
        end
    end

    request_cleanup_by_ctx.wibox_garbage_collected = 0

    assert(root1.first_child)
    assert(root1.last_child)

    -- Release the drawins
    wiboxes = {}

    return true
end)

-- Test wibox garbage collection.
table.insert(steps, function()
    for _=1, 5 do
        collectgarbage("collect")
    end

    if request_cleanup_by_ctx.wibox_garbage_collected < #colors then return end

    assert(not root1.first_child)
    assert(not root1.last_child)

    for _=1, 5 do
        awful.spawn("xterm")
    end

    return true
end)

-- Test cloning.
table.insert(steps, function()
    if #client.get() ~= 5 then return end

    nodes, wiboxes = {}, {}

    for i=1,5 do
        local parent = _tree_node { parent = root1 }
        table.insert(nodes, parent)

        local w = wibox {
            visible = true,
            x       = 0,
            y       = 0,
            width   = 100,
            height  = 100,
            bg      = colors[i],
        }

        local dnode = _tree_node { parent = parent, _drawin = w.drawin }
        local cnode = _tree_node { parent = parent, client  = client.get()[i] }
        table.insert(wiboxes, w)

        assert(dnode._wibox == w)
        assert(dnode._wiboxes [1] == w)
        assert(parent._wiboxes[1] == w)

        cnode.honor_size_hints = math.random() > 0.5

        dnode.geometry = {
            x      = 50*i,
            y      = 50*i,
            width  = 50*i,
            height = 50*i,
        }

        cnode.geometry = {
            x      = 20*i,
            y      = 20*i,
            width  = 20*i,
            height = 20*i,
        }

        assert(parent._parent == root1)
        assert(parent.first_child)
        assert(parent.last_child )
        assert(parent.last_child ~= parent.first_child)
    end

    compare_lists(wiboxes, root1._wiboxes)

    local fork = root1:fork()

    assert(root1 ~= fork)
    assert(fork.first_child)
    assert(fork.last_child )

    local n1, n2 = root1, fork

    while n1 do
        assert(n2)
        assert (n1 ~= n2)
        assert(n1.type == n2.type)

        if n1.type == "client" then
            assert(n1.client == n2.client)
            assert(type(n1.honor_size_hints) == "boolean")
            assert(n1.honor_size_hints == n2.honor_size_hints)
            assert(geo_equal(n1.geometry, n2.geometry))
        elseif n1.type == "wibox" then
            assert(n1._drawin == n2._drawin)
            assert(geo_equal(n1.geometry, n2.geometry))
        elseif n1.type == "type" then
            assert(n1.last_child.type == n2.last_child.type)
            assert(n1.first_child.type == n2.first_child.type)
        end

        assert(n2.next ~= n2)
        n1, n2 = n1.next, n2.next
    end

    return true
end)

-- Test the signals.
table.insert(steps, function()
    while root1.first_child do
        root1.first_child:detach()
    end

    for _, prop in ipairs { "protected", "_read_only" } do
        assert(not root1.last_child)
        assert(root1[prop] == false)

        local args = nil

        root1:connect_signal("property::"..prop, function(...)
            args = {...}
        end)

        root1[prop] = true
        assert(root1[prop] == true)
        assert(args)
        assert(args[1] == root1)
        assert(args[2] == true)
        assert(args[3] == false)

        root1[prop] = false
        assert(root1[prop] == false)
        assert(args)
        assert(args[1] == root1)
        assert(args[2] == false)
        assert(args[3] == true)
    end

    return true
end)

runner.run_steps(steps)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
