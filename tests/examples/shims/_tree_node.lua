local gears_obj = require("gears.object")
local gtable = require("gears.table")
local unpack = unpack or table.unpack -- luacheck: globals unpack (compatibility with Lua 5.1)

local _tree_node, meta = awesome._shim_fake_class()

-- luacheck: globals _tree_node_weak_ref
_tree_node_weak_ref = function() end

local function node_factory()
    return {
        type   = "new",
        parent = nil,

        siblings = {
            next     = nil,
            previous = nil,
        },

        geometry = {
            x      = 0,
            y      = 0,
            width  = 0,
            height = 0,
        },

        client = nil,
        wibox  = nil,

        children  = {
            head = nil,
            tail = nil,
        },

        read_only        = false,
        protected        = false,
        honor_size_hints = true,
    }
end


local function init_pair(pair)
    pair.previous = nil
    pair.next     = nil
end

local function init_children(node)
    node._private.children.head = nil
    node._private.children.tail = nil
end

local function remove_node(previous, current, next)
    if next then
        next.previous = current.previous
    end

    if previous then
        previous.next = current.next
    end
end


local function unlink_node(node, detach, context)
    if node._private.type == "defunct" then
        return
    end

    if detach and context then
        local root = node.root

        if root and root ~= node and root._private.type ~= "defunct" then
            root:emit_signal("request::cleanup_node", context, {node = node})
        end

        node:emit_signal("request::cleanup", context, {node = node})
    end

    if detach and node._private.type == "branch" then
        while node._private.children.tail do
            unlink_node(node._private.children.tail, true, "parent_unlinked")
        end

        init_children(node)
    end

    if node._private.parent and node._private.parent._private.children.head == node then
        node._private.parent._private.children.head = node._private.siblings.next
    end

    if node._private.parent and node._private.parent._private.children.tail == node then
        node._private.parent._private.children.tail = node._private.siblings.previous
    end

    remove_node(
        node._private.siblings.previous and node._private.siblings.previous._private.siblings or nil,
        node._private.siblings,
        node._private.siblings.next and node._private.siblings.next._private.siblings or nil
    )

    init_pair(node._private.siblings)

    node._private.parent = nil

    if detach then
        node._private.type = "defunct"
    end
end

local function tree_node_append(node, parent)
    unlink_node(node, false, nil)

    local old_last = parent._private.children.tail

    parent._private.children.tail   = node
    node._private.parent            = parent
    node._private.siblings.previous = old_last
    node._private.siblings.next     = nil

    if not parent._private.children.head then
        parent._private.children.head = node
    end

    if old_last then
        old_last._private.siblings.next = node
    end
end

local function tree_node_push(node, parent)
    unlink_node(node, false, nil)

    local old_first = parent._private.children.head

    parent._private.children.head   = node
    node._private.parent            = parent
    node._private.siblings.next     = old_first
    node._private.siblings.previous = nil

    if not parent._private.children.tail then
        parent._private.children.tail = node
    end

    if old_first then
        old_first._private.siblings.previous = node
    end
end

local function tree_node_insert_before(to_insert, self)
    unlink_node(to_insert, false, nil)

    if self._private.parent and self._private.parent._private.children.head == self then
        self._private.parent._private.children.head = to_insert
    end

    to_insert._private.siblings.next     = self
    to_insert._private.siblings.previous = self._private.siblings.previous

    if self._private.siblings.previous then
        self._private.siblings.previous._private.siblings.next = to_insert
    end

    self._private.siblings.previous = to_insert
    to_insert._private.parent       = self._private.parent
end

local function tree_node_insert_after(to_insert, self)
    unlink_node(to_insert, false, nil)

    if self._private.parent and self._private.parent._private.children.tail == self then
        self._private.parent._private.children.tail = to_insert
    end

    to_insert._private.siblings.previous = self
    to_insert._private.siblings.next     = self._private.siblings.next

    if self._private.siblings.next then
        self._private.siblings.next._private.siblings.previous = to_insert
    end

    self._private.siblings.next = to_insert
    to_insert._private.parent   = self._private.parent
end

function _tree_node.get_geometry(self)
    return self._private.geometry
end

function _tree_node.set_geometry(self, value)
    self._private.geometry = value
end

function _tree_node.get__root(self)
    local par = self._private.parent

    while par._private.parent do
        par = self._private.parent
    end

    return par
end

function _tree_node.get_client(self)
    return self._private.client
end

function _tree_node.get__clients(self)
    local ret = {}
    local stop_at = self._private.siblings.next

    local node = self

    while node ~= stop_at do
        if node._private.type == "client" then
            table.insert(ret, self._private.client)
        end
        node = node.next
    end

    return ret
end

function _tree_node.get__drawin(self) -- luacheck: no unused
    return self._private.drawin
end

function _tree_node.get__wibox(self)
    return self._private.wibox
end

function _tree_node.get__wiboxes(self)
    local ret = {}
    local stop_at = self._private.siblings.next

    local node = self

    while node ~= stop_at do
        if node._private.type == "wibox" then
            table.insert(ret, self._private.wibox)
        end
        node = node.next
    end

    return ret
end

function _tree_node.get__parent(self)
    return self._private.parent
end

function _tree_node.get_previous_sibling(self)
    return self._private.siblings.previous
end

function _tree_node.get_next_sibling(self)
    return self._private.siblings.next
end

function _tree_node.get_previous(self)
    local prev = self._private.siblings.previous

    if prev and prev.type == "branch" then
        local candidate = prev._private.children.tail

        while candidate and candidate.type == "branch" and
          candidate._private.children.tail do
            candidate = candidate._private.children.tail
        end

        return candidate or self._private.siblings.previous
    end

    if prev then
        return prev
    elseif self._private.parent then
        return self._private.parent
    end

    return nil
end

function _tree_node.get_next(self)
    if self.type == "branch" and self._private.children.head then
        return self._private.children.head
    elseif self._private.siblings.next then
        return self._private.siblings.next
    end

    if self._private.parent then
        local candidate = self._private.parent

        while (not candidate._private.siblings.next) and candidate._private.parent do
            candidate = candidate._private.parent
        end

        return candidate._private.siblings.next
    end

    return nil
end

function _tree_node.get_first_child(self)
    return self._private.children.head
end

function _tree_node.get_last_child(self)
    return self._private.children.tail
end

function _tree_node.get_type(self)
    assert(self._private.type)
    return self._private.type
end

function _tree_node.get_protected(self)
    return self._private.protected
end

function _tree_node.get__read_only(self)
    return self._private.read_only
end

function _tree_node.get_read_only(self)
    return self._private.read_only
end

function _tree_node.get_mode(self) -- luacheck: no unused
    return "tree"
end

function _tree_node.get_honor_size_hints(self)
    return self._private.honor_size_hints
end

function _tree_node.swap(first, second)
    if first == second or not second then return end

    local first_previous  = first._private.siblings.previous
    local first_next      = first._private.siblings.next
    local second_previous = second._private.siblings.previous
    local second_next     = second._private.siblings.next
    local first_parent    = first._private.parent
    local second_parent   = second._private.parent

    if first._private.siblings.previous == second then
        if second_previous then
            second_previous._private.siblings.next = first
        end

        if first_next then
            first_next._private.siblings.previous = second
        end

        first._private.siblings.next      = second
        second._private.siblings.previous = first
        second._private.siblings.next     = first_next
        first._private.siblings.previous  = second_previous
    elseif first._private.siblings.next == second then
        if first_previous then
            first_previous._private.siblings.next = second
        end

        if second_next then
            second_next._private.siblings.previous = first
        end

        second._private.siblings.previous = first_previous
        first._private.siblings.next      = second_next
        first._private.siblings.previous  = second
        second._private.siblings.next     = first
    else
        first._private.siblings.next      = second_next
        first._private.siblings.previous  = second_previous
        second._private.siblings.next     = first_next
        second._private.siblings.previous = first_previous

        first._private.parent = second_parent
        second._private.parent = first_parent

        if first_previous then
            first_previous._private.siblings.next = second
        end

        if second_previous then
            second_previous._private.siblings.next = first
        end

        if first_next then
            first_next._private.siblings.previous = second
        end

        if second_next then
            second_next._private.siblings.previous = first
        end
    end

    local is_second_first = second_parent
        and second_parent._private.children.head == second
    local is_first_first  = first_parent
        and first_parent._private.children.head == first
    local is_second_last  = second_parent
        and second_parent._private.children.tail == second
    local is_first_last   = first_parent
        and first_parent._private.children.tail == first

    if is_second_first then
        second_parent._private.children.head = first
    end

    if is_first_first then
        first_parent._private.children.head = second
    end

    if is_second_last then
        second_parent._private.children.tail = first
    end

    if is_first_last then
        first_parent._private.children.tail = second
    end

end

function _tree_node.join(self)
    if self._private.read_only or self._private.protected then return end

    local parent           = self._private.parent
    local previous_sibling = self._private.siblings.previous
    local next_sibling     = self._private.siblings.next
    local first_child      = self._private.children.head
    local last_child       = self._private.children.tail

    init_children(self)
    unlink_node(self, true, "join")

    if not first_child then
        return true
    end

    if previous_sibling then
        previous_sibling._private.siblings.next = first_child
        first_child._private.siblings.previous  = previous_sibling
    else
        parent._private.children.head = first_child
        first_child._private.siblings.previous = nil
    end

    if next_sibling then
        next_sibling._private.siblings.previous = last_child
        last_child._private.siblings.next       = next_sibling
    else
        parent._private.children.tail = last_child
        last_child._private.siblings.next = nil
    end

    while first_child ~= next_sibling do
        first_child._private.parent = parent
        first_child = first_child._private.siblings.next
    end

    return true
end

function _tree_node.push(self, other)
    tree_node_push(other, self)
end

function _tree_node.append(self, other)
    tree_node_append(other, self)
end

function _tree_node.detach(self)
    unlink_node(self)
end

function _tree_node.fork(self) -- luacheck: no unused

end

function _tree_node.cleanup(self) -- luacheck: no unused

end

function _tree_node.move_before(self, other)
    tree_node_insert_before(self, other)
end

function _tree_node.move_after(self, other)
    tree_node_insert_after(self, other)
end

function _tree_node._apply_geometry(self)
    while self do
        if self._private.client then
            self._private.client:geometry(self._private.geometry)
        elseif self._private.wibox then
            self._private.wibox:geometry(self._private.geometry)
        end
        self = self.next
    end
end

function _tree_node._apply_stacking(self) -- luacheck: no unused
    local order = {}
    while self do
        if self._private.client then
            table.insert(order, 1, self._private.client)
        end
        self = self.next
    end

    --FIXME this assumes all clients are present.
    root._set_stacking_order(_, { content = order })
end


local function new_tree_node(_, args)
    local ret = gears_obj {
        enable_properties   = true,
        enable_auto_signals = true,
    }
    gtable.crush(ret, _tree_node, true)
    rawset(ret, "_private", node_factory())
    --ret._private.type = "awful.tree"
    --rawset(ret, "type", "awful.tree")

    if args.client then
        ret._private.type = "client"
        ret._private.client = args.client
        ret._private.honor_size_hints = args.honor_size_hints ~= false
    elseif args.wibox then
        ret._private.type   = "wibox"
        ret._private.wibox  = args.wibox
        ret._private.drawin = args.wibox.drawin
    elseif args._drawin then
        ret._private.type   = "wibox"
        ret._private.drawin = args._drawin
        ret._private.wibox  = args._drawin.get_wibox()
    else
        ret._private.type = "branch"
    end

    if args.previous then
        tree_node_insert_after(ret, args.previous)
    elseif args.next then
        tree_node_insert_before(ret, args.next)
    elseif args.parent then
        tree_node_append(ret, args.parent)
    elseif args.wrap then
        ret:swap(args.wrap)
        tree_node_append(args.wrap, ret)
    end

    local obj_mt = getmetatable(ret)

    local md = setmetatable(ret, {
        __index    = function(...)
            local ret = {obj_mt.__index(...)}
            if #ret > 0 then
                return unpack(ret)
            end
            return meta.__index(...)
        end,
        __newindex = function(...)
            return meta.__newindex(...)
        end
    })

    return md
end

return setmetatable(_tree_node, { __call = new_tree_node, })

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
