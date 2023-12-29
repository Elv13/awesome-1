local tree         = require("awful.tree")
local aspawn       = require("awful.spawn")
local aplacement   = require("awful.placement")
local wibox        = require("wibox")
local rules        = require("ruled.client")
local gdebug       = require("gears.debug")
local runner       = require("_runner")
local test_client2 = require("_client2")

local steps = {}

local tree1

local clients, wiboxes = {}, {}
local size_hints = {}

-- Disable the rules (no titlebar, no placement, no honor_size_hints defaults).
local dep = gdebug.deprecate
gdebug.deprecate = function() end
rules.rules = {}
gdebug.deprecate = dep

local function compare_lists(t1, t2)
    assert(#t1 == #t2)

    for i=1, #t1 do
        assert(t1[i] == t2[i])
    end
end

-- Unload `awful.layout._stacking`.
table.insert(steps, function()
    require("awful.layout._stacking")._unload()

    for _= 1, 10 do
        collectgarbage("collect")
    end

    assert(_tree_node.instances() == 0)

    return true
end)

-- Make sure the lua superclass works.
table.insert(steps, function()
    tree1 = tree {}
    assert(tree1)

    assert(tree1.read_only == false)
    assert(tree1.type == "awful.tree")

    tree1.foo = "bar"
    assert(tree1.foo == "bar")

    for name, method in pairs(tree) do
        assert(tree1._root[name] == method)
    end

    local called = false

    tree1:connect_signal("property::label", function()
        called = true
    end)

    tree1.label = "baz"
    assert(called)

    return true
end)

-- Spawn some client and wibox.
table.insert(steps, function()
    size_hints.size_hints_max = test_client2()
    size_hints.size_hints_max:set_class { class = "size_hints_max" }
    size_hints.size_hints_max:set_default_size {
        width  = 200,
        height = 200,
    }
    size_hints.size_hints_max:set_maximum_size {
        width  = 50,
        height = 50,
    }
    size_hints.size_hints_max:show()

    size_hints.size_hints_min = test_client2()
    size_hints.size_hints_min:set_class { class = "size_hints_min" }
    size_hints.size_hints_min:set_default_size {
        width  = 25,
        height = 25,
    }
    size_hints.size_hints_min:set_minimum_size {
        width  = 125,
        height = 125,
    }
    size_hints.size_hints_min:show()

    size_hints.default = test_client2()
    size_hints.default:set_class { class = "default" }
    size_hints.default:set_default_size {
        width  = 75,
        height = 75,
    }
    size_hints.default:show()

    size_hints.increment = test_client2()
    size_hints.increment:set_class { class = "increment" }
    size_hints.increment:set_resize_increment {
        width_inc  = 50,
        height_inc = 50
    }
    size_hints.increment:set_default_size {
        width  = 75,
        height = 75,
    }
    size_hints.increment:show()

    size_hints.resized = test_client2()
    size_hints.resized:set_class { class = "resized" }
    size_hints.resized:set_minimum_size {
        width  = 200,
        height = 200,
    }
    size_hints.resized:show()

    for _=1, 5 do
        table.insert(wiboxes, wibox {
            visible = false,
            x       = 100,
            y       = 100,
            width   = 100,
            height  = 100,
            bg      = "#ff0000",
        })
    end

    return true
end)

-- Check the Lua node constructors.
table.insert(steps, function()
    if #client.get() ~= 5 then return end

    for _, c in ipairs(client.get()) do
        assert(size_hints[c.class])
        size_hints[c.class].client = c
        table.insert(clients, c)
    end

    -- Check if the size_hints are honored by default (they should be).
    assert(size_hints.size_hints_max.client:geometry().width  == 50 )
    assert(size_hints.size_hints_max.client:geometry().height == 50 )
    assert(size_hints.size_hints_min.client:geometry().width  == 125)
    assert(size_hints.size_hints_min.client:geometry().height == 125)
    assert(size_hints.default.client:geometry().width         == 75 )
    assert(size_hints.default.client:geometry().height        == 75 )
    assert(size_hints.increment.client:geometry().width       == 50 )
    assert(size_hints.increment.client:geometry().height      == 50 )
    assert(size_hints.resized.client:geometry().width         == 200)
    assert(size_hints.resized.client:geometry().height        == 200)

    -- Test `:append_new()`.
    local n1 = tree1:append_new {
        client = clients[1]
    }
    assert(tree1:find_client_node(clients[1]) == n1)
    assert(tree1:find_wibox_node(clients[1]) == nil)
    assert(tree1:find_client_node(nil) == nil)

    assert(n1)
    assert(n1.type == "client")
    assert(n1.parent == tree1)
    assert(tree1.first_child == n1)
    assert(tree1._client_mapping[clients[1]] == n1)

    -- Will fail because it cannot work on client and wibox nodes.
    local ret = pcall(function() n1:append_new {
        client = clients[3],
    } end)
    assert(not ret)

    -- Test `:push_new()`.
    local n2 = tree1:push_new {
        client = clients[2]
    }

    assert(n2)
    assert(n2.parent == tree1)
    assert(n2.next_sibling == n1)
    assert(tree1.first_child == n2)
    assert(tree1._client_mapping[clients[2]] == n2)

    -- Will fail because it cannot work on client and wibox nodes.
    ret = pcall(function() n2:push_new {
        client = clients[3],
    } end)
    assert(not ret)

    -- Test `:create_before()`.
    ret = pcall(function() tree1:create_before {
        client = clients[3],
    } end)

    -- Will fail because these cannot work on roots.
    assert(not ret)

    local n3 = n1:create_before {
        client = clients[3],
    }
    assert(n3)
    assert(n3.parent == tree1)
    assert(n3.next_sibling == n1)
    assert(n3.next == n1)
    assert(n3.previous == n2)
    assert(n3.previous_sibling == n2)
    assert(tree1._client_mapping[clients[3]] == n3)

    -- Test `:after_before()`.
    ret = pcall(function() tree1:create_after {
        client = clients[4],
    } end)
    assert(not ret)

    local n4 = n3:create_after {
        client = clients[4],
    }

    assert(n4)
    assert(n4.parent == tree1)
    assert(n4.previous == n3)
    assert(n3.next == n4)
    assert(tree1._client_mapping[clients[4]] == n4)

    return true
end)

-- Check the `node.effective_geometry`.
table.insert(steps, function()
    local n = nil

    for node in tree.iterate_next(tree1.first_child, true) do
        if node.client == size_hints.default.client then
            n = node
            break
        end
    end

    assert(n)

    local geo = {
        x      = 80,
        y      = 90,
        width  = 100,
        height = 110,
    }

    n.geometry = geo

    for k, v in pairs(geo) do
        assert(v == n.geometry[k])
    end

    local gaps = {
        left   = 1,
        right  = 2,
        top    = 3,
        bottom = 4,
    }

    n.gaps = gaps

    -- Make sure the gaps doesn't affect the geometry.
    for k, v in pairs(geo) do
        assert(v == n.geometry[k])
    end

    for _, side in ipairs { "left", "right", "top", "bottom" } do
        assert(gaps[side] == n.gaps[side])
    end

    local new_geo = n.effective_geometry
    assert(type(new_geo) == "table")

    assert(new_geo.x      == 80  + gaps.left             )
    assert(new_geo.y      == 90  + gaps.top              )
    assert(new_geo.width  == 100 - gaps.left - gaps.right)
    assert(new_geo.height == 110 - gaps.top - gaps.bottom)

    local was_called = false

    n.placement = function(obj, args)
        was_called = true
        return {
            x      = 1000,
            y      = 1001,
            width  = 1002,
            height = 1003,
        }
    end

    local new_geo = n.effective_geometry

    assert(was_called)
    assert(new_geo.x      == 1000)
    assert(new_geo.y      == 1001)
    assert(new_geo.width  == 1002)
    assert(new_geo.height == 1003)

    return true
end)

-- Check for memory leaks.
table.insert(steps, function()
    if _tree_node.instances() ~= 5 then return end

    local weak = setmetatable({tree1}, {__mode = "v"})

    tree1 = nil

    for _= 1, 10 do
        collectgarbage("collect")
    end

    assert(#weak == 0)
    assert(_tree_node.instances() == 0)

    return true
end)

-- Check `:wrap()` and wibox nodes.
table.insert(steps, function()
    tree1 = tree{}

    for i= 1, 5 do
        local n1 = tree1:append_new {
            client = clients[i]
        }
        assert(n1.root == tree1)

        local n2 = n1:wrap()
        assert(n2.root == tree1)
        assert(n2.type == "branch")
        assert(n2.first_child == n1)
        assert(n2.last_child == n1)
        assert(n2.parent == tree1)

        local n3 = n2:push_new {
            wibox = wiboxes[i]
        }

        assert(n2.first_child == n3)
        assert(n2.last_child == n1)
        assert(n3.root == tree1)
        assert(n3.type == "wibox")
        assert(n3.wibox == wiboxes[i])
        assert(n3.next.type == "client")
        assert(n3.next.client == clients[i])
    end

    assert(_tree_node.instances() == 16)
    assert(tree1.last_child.last_child.client   == clients[5])
    assert(tree1.last_child.first_child.wibox   == wiboxes[5])
    assert(tree1.first_child.last_child.client  == clients[1])
    assert(tree1.first_child.first_child.wibox  == wiboxes[1])

    assert(#tree1._clients == 5)

    return true
end)

-- Test the iterators.
table.insert(steps, function()
    local count = 0
    assert(tree1.first_child)

    for node in tree.iterate_children(tree1.first_child) do
        count = count + 1

        if count == 1 then
            assert(node.wibox == wiboxes[1])
        elseif count == 2 then
            assert(node.client == clients[1])
        end
    end

    assert(count == 2)
    count = 0

    for node in tree.iterate_next_sibling(tree1.first_child.first_child, true) do
        count = count + 1

        if count == 1 then
            assert(node.wibox == wiboxes[1])
        elseif count == 2 then
            assert(node.client == clients[1])
        end
    end

    assert(count == 2)
    count = 0

    for node in tree.iterate_next_sibling(tree1.first_child.first_child, false) do
        count = count + 1

        if count == 1 then
            assert(node.client == clients[1])
        end
    end

    assert(count == 1)
    count = 0

    for node in tree.iterate_previous_sibling(tree1.first_child.first_child, false) do
        --
    end

    assert(count == 0)

    for node in tree.iterate_previous_sibling(tree1.first_child.last_child, true) do
        count = count + 1

        if count == 1 then
            assert(node.client == clients[1])
        elseif count == 2 then
            assert(node.wibox == wiboxes[1])
        end
    end

    assert(count == 2)
    count = 0

    for node in tree.iterate_previous_sibling(tree1.first_child.last_child, false) do
        count = count + 1

        if count == 1 then
            assert(node.wibox == wiboxes[1])
        end
    end

    assert(count == 1)
    count = 0

    for node in tree.iterate_next(tree1, true) do
        if count == 0 then
            assert(node == tree1)
        elseif count % 3 == 1 then
            assert(node.type == "branch")
        elseif count % 3 == 2 then
            assert(node.wibox == wiboxes[math.floor(count/3)+1])
        elseif count % 3 == 0 then
            assert(node.client == clients[math.ceil(count/3)])
        end

        count = count + 1
    end

    assert(count == 16)
    count = 1

    for node in tree.iterate_next(tree1, false) do
        if count == 0 then
            assert(node == tree1)
        elseif count % 3 == 1 then
            assert(node.type == "branch")
        elseif count % 3 == 2 then
            assert(node.wibox == wiboxes[math.floor(count/3)+1])
        elseif count % 3 == 0 then
            assert(node.client == clients[math.ceil(count/3)])
        end

        count = count + 1
    end

    assert(count == 16)
    count = 0

    for node in tree.iterate_previous(tree1.last_child.last_child, true) do
        if node.type == "awful.tree" then
            assert(count == 15)
        elseif node == tree1.last_child.last_child then
            assert(count == 0)
        elseif count % 3 == 2 then
            assert(node.type == "branch")
        elseif count % 3 == 1 then
            assert(node.wibox == wiboxes[5 - math.floor(count/3)])
        elseif count % 3 == 0 then
            assert(node.client == clients[5 - math.ceil(count/3)])
        end

        count = count + 1
    end

    assert(count == 16)
    count = 1

    for node in tree.iterate_previous(tree1.last_child.last_child, false) do
        if node.type == "awful.tree" then
            assert(count == 15)
        elseif count % 3 == 2 then
            assert(node.type == "branch")
        elseif count % 3 == 1 then
            assert(node.wibox == wiboxes[5 - math.floor(count/3)])
        elseif count % 3 == 0 then
            assert(node.client == clients[5 - math.ceil(count/3)])
        end

        count = count + 1
    end

    assert(count == 16)

    return true
end)

-- Check for more types of node memory leaks.
table.insert(steps, function()
    assert(_tree_node.instances() == 16)

    tree1.last_child:detach()
    tree1.last_child:detach()

    local fs, ls = tree1.first_child, tree1.last_child

    -- Make sure it's possible to-add the client/wibox immediatly, then
    -- re-delete them.
    local n1 = tree1:append_new { client = clients[5] }
    local n2 = tree1:push_new   { wibox = wiboxes[5] }
    assert(tree1.last_child  == n1)
    assert(tree1.first_child == n2)
    n1:detach()
    n2:detach()
    assert(not n1.valid)
    assert(not n2.valid)
    assert(fs == tree1.first_child)
    assert(ls == tree1.last_child)
    n1, n2 = nil, nil

    for _= 1, 10 do
        collectgarbage("collect")
    end

    assert(_tree_node.instances() == 10)
    assert(ls.valid)
    assert(fs.valid)

    local weak = setmetatable({tree1}, {__mode = "v"})

    tree1 = nil

    for _= 1, 10 do
        collectgarbage("collect")
    end

    assert(#weak == 0)
    assert(_tree_node.instances() == 2)

    assert(not ls.valid)
    assert(not fs.valid)

    ls, fs = nil, nil

    for _= 1, 10 do
        collectgarbage("collect")
    end

    assert(_tree_node.instances() == 0)

    for i=5, 1, -1 do
        client.get()[i]:kill()
    end

    return true
end)

runner.run_steps(steps)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
