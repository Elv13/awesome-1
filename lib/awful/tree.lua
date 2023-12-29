---------------------------------------------------------------------------
-- @classmod awful.tree
---------------------------------------------------------------------------
local capi    = { _tree_node = _tree_node, _tree_node_weak_ref = _tree_node_weak_ref }
local gobject    = require("gears.object")
local gtable     = require("gears.table")
local aplacement = require("awful.placement")

local module    = {}
local data      = setmetatable({}, { __mode = "k" })
local instances = setmetatable({}, { __mode = "v" })

local function copy_properties(source, protect)
    return {
        geometry         = source.geometry,
        client           = source.client,
        _drawin          = source._drawin,
        protect          = protect,
        honor_size_hints = source.honor_size_hints
    }
end

--- A name for this node.
-- @property label
-- @tparam[opt=nil] string|nil label
-- @propemits true true

--- An `awful.placement` function to use when the client has size hints.
--
-- The function must place the client within a larger geometry. It is not
-- allowed to set the width or height. The function called with the `pretend`
-- argument set to `true` and the `bounding_rect` set to the value of
-- `geometry`. The first `object` argument contains a `geometry` table
-- representing the size with the `gaps` added.
--
-- @property placement
-- @tparam[opt=awful.placement.top_left] nil|placement placement
-- @see awful.placement
-- @see awful.placement.top_left
-- @see honor_size_hints
-- @see gaps

--- Forwarded from the client `request::swap`.
--
-- Usually, the handler should do one of two things. If `:find_client_node()`
-- returns something for the swapped client, then the nodes should be swapped.
-- If there isn't, it is safe to call `.client = other` on the node.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::client_swap
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the client swapped.
-- @tparam table hints Other data.
-- @tparam client hints.client The client to replace.
-- @tparam awful.tree.node hints.node The node on which to replace the client.
-- @see client

--- Forwarded from the client or wibox `request::raise`.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::raise_node
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the object in need of being raised.
-- @tparam table hints Other data.
-- @tparam awful.tree.node hints.node The node on which to replace the client.
-- @see client

--- Forwarded from the client or wibox `request::lower`.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::lower_node
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the object in need of being lowered.
-- @tparam table hints Other data.
-- @tparam awful.tree.node hints.node The node on which to replace the client.
-- @see client

--- Forwarded from the client `request::resize`.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::resize_node
-- @see client

--- Forwarded from the client `property::size_hints_honor`.
-- @signal request::honor_size_hints
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the size hints chaning.
-- @tparam table hints Other data.
-- @tparam awful.tree.node hints.node The node on which to replace the client.

--- Sent when a client is added to one of the `tags`.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::add_client
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the client added.
-- @tparam table hints Other data.
-- @tparam client hints.client The client.
-- @see client

--- Sent when the client is no longer tagged in any of the tags.
--
-- This signal is only present on the `awful.tree` root object.
--
-- @signal request::remove_client
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the client removed.
-- @tparam table hints Other data.
-- @tparam client hints.client The client.
-- @see client

--- Hide object when none of the `tags` are the primary selection.
--
-- If there are, for example, `wibox`es to hide, do it here.
--
-- A tag "primary seletion" means when it is selected and its `layout` is used.
-- When multiple tags are selected, it usually means the one with the lowest
-- index.
--
-- @signal request::hide
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the tree being hidden.
-- @tparam table hints Other data (currently empty).

--- Show objects when one of the tag is the primary selection.
--
-- Note that it isn't required to implement this signal. Making the wibox
-- visible and other tasks like it can be done when `arrange` is called on the
-- layout.
--
-- A tag "primary seletion" means when it is selected and its `layout` is used.
-- When multiple tags are selected, it usually means the one with the lowest
-- index.
--
-- @signal request::show
-- @tparam awful.tree self The `awful.tree` object.
-- @tparam string context Why is the tree being hidden.
-- @tparam table hints Other data (currently empty).

-- Find the first common client or drawin between the tree.
--
-- It will be used as a seed to swap to nodes of the target tree to match the
-- order of the fist.
local function first_common(target, source)
    local left = {}

    while source do
        local left_obj  = target and (target.client or target._drawin) or nil
        local right_obj = source.client or source._drawin

        local candidate = left[right_obj]

        if candidate then  return candidate end

        left [left_obj] = target

        target, source = target and target.next or nil, source.next
    end
end

local function node_factory(args, parent)
    args._has_placement = args.placement and args.placement ~= aplacement.top_left

    local ret = capi._tree_node(args)

    data[ret] = {
        label          = args.label,
        _weak_root     = parent and data[parent]._weak_root,
        weak_wibox     = setmetatable({args.wibox}, {__mode = "v" }),
        placement      = args.placement,
    }

    return ret
end

local function client_added(self, c, node)
    local self_data = data[self]

    if not self_data then return end

    self_data._weak_root[1]._client_mapping[c] = node
end

local function cleanup_node(self, _, _)
    local obj = self.client or (self._drawin and self._drawin.get_wibox())

    if not obj then return end

    local self_data = data[self]

    if not self_data then return end

    local root = self_data._weak_root[1]

    if not root then return end

    root._client_mapping[obj] = nil
    root._drawin_mapping[obj] = nil
end

function module.get_wibox(self)
    return data[self].weak_wibox[1]
end

function module.get_root(self)
    return data[self]._weak_root[1]
end

function module.get_label(self)
    return data[self].label or (
        self.client and self.client.name
    ) or "N/A"
end

function module.set_label(self, value)
    local old = data[self].label

    if old == value then return end

    data[self].label = value

    self:emit_signal("property::label", value, old)
end

function module.get_placement(self)
    return data[self].placement
end

function module.set_placement(self, value)
    self._has_placement = value ~= aplacement.top_left

    local old = data[self].placement

    if old == value then return end

    data[self].placement = value

    self:emit_signal("property::placement", value, old)
end

--- Create a new tree.
-- @constructorfct awful.tree
-- @tparam[opt={}] table args
-- @treturn awful.tree The new tree.
function module.new(_, args) -- luacheck: no unused args
    local ret = node_factory({ mode = "tree" }, nil)

    -- Return a proxy object so it ca be garbage collected.
    -- `_weak_ref` will get GCed alongside with it and notify the C side.
    -- This is required to avoid a memory leak on Lua 5.1 and the official
    -- luajit release.
    local proxy = {
        _weak_ref = capi._tree_node_weak_ref { root_node = ret },
        _root     = ret,
        _client_mapping  = setmetatable({}, {__mode = "kv" }),
        _drawin_mapping  = setmetatable({}, {__mode = "kv" }),
    }

    proxy.root = proxy
    data[ret]._weak_root = setmetatable({proxy}, {__mode = "v"})

    -- Used by `.parent`.
    instances[ret] = proxy

    return setmetatable(proxy, {
        __index    = function(self, key)
            local upval = self._root[key]
            if type(upval) == "function" then
                local f = function(_, ...)
                    return upval(self._root, ...)
                end
                rawset(self, key, f)
                return f
            end
            return upval
        end,
        __newindex = function(self, key, value)
            self._root[key] = value
        end,
    })
end

--- Create a new list.
--
-- A list is a specialized tree where it isn't possible to insert sub-trees.
-- This is indented to be used alongside `:mirror_to()` to "flatten" trees into
-- tables.
--
-- @constructorfct awful.tree.list
-- @tparam[opt={}] table args
-- @treturn awful.tree The new list.
function module.list(args) -- luacheck: no unused args
    local ret = node_factory({ mode = "list" }, nil)

    data[ret]._client_mapping = setmetatable({}, {__mode = "kv" })
    data[ret]._drawin_mapping = setmetatable({}, {__mode = "kv" })

    return ret
end

-- FIXME Re-order the content of `other` to match `self`.
-- @method :mirror_to
-- @tparam awful.tree|awful.tree.node other The other tree.
-- @tparam[opt={}] table|nil args
-- @tparam[opt=true] boolean args.geometry
-- @tparam[opt=true] boolean args.order
-- @tparam[opt=true] boolean args.honor_size_hints
-- @tparam[opt=false] boolean args.protected
-- @tparam[opt=false] boolean args.hierarchy
-- @noreturn
function module.mirror_to(other, args)
    args = args or {}
    local last_other = other
    local target_node = first_common(self, other)

    for node in awful.tree.iterate_next(self) do
        local o = node.client or node._drawin

        local target = data[other]._client_mapping[o]

        if (not target) and args.insert then
            last_other:create_before(copy_properties(node, false))
        elseif target then
            if args.geometry ~= false then
                target.geometry = node.geometry
            end

            if args.order ~= false then
                --
            end

            if args.protected then
                target.protected = node.protected
            end

            if args.hierarchy then
                --TODO
            end
        end
    end
end

--- Wrap `self` with a new node.
--
-- @DOC_awful_tree_wrap1_EXAMPLE@
--
-- @method :wrap
-- @tparam[opt=nil] table args
-- @tparam[opt=nil] string args.label A name for the new wrapper node.
-- @tparam[opt=false] boolean args.protected If the new node is protected during
--  `:cleanup()`.
-- @treturn awful.tree.node The new wrapper node.
function module.wrap(self, args)
    args = gtable.crush({
        wrap = self,
    }, args or {})

    return node_factory(args, self._parent)
end

--- Create a new node and place it after `self`.
--
-- The node type depends on the arguments. If neither a client or a wibox is
-- specified, the new node will contain a branch.
--
-- @DOC_awful_tree_create_after1_EXAMPLE@
--
-- @method :create_after
-- @tparam[opt={}] table args
-- @tparam[opt=nil] client|nil args.client A client object.
-- @tparam[opt=nil] wibox|nil args.wibox A wibox object.
-- @tparam[opt=false] boolean args.protected If the new node is protected during
--  `:cleanup()`.
-- @tparam[opt=true] boolean args.honor_size_hints Honor the client size hints
--  when applying the client geometry.
-- @tparam[opt=nil] table|nil args.geometry The geometry.
-- @treturn awful.tree.node The new node.
-- @see create_before
-- @see push_new
-- @see append_new
function module.create_after(self, args)
    assert(
        self.type ~= "awful.tree",
        "`:create_after()` cannot be used on the root node"
    )

    local c, d = args.client, args.wibox and args.wibox.drawin

    if c or d then
        assert((not self._weak_root[1]._client_mapping[c])
          or not self._weak_root[1]._drawin_mapping[d],
            "`:create_after() cannot be completed because " .. tostring(c or d) ..
            " is already part of the tree")
    end

    args = gtable.crush({
        previous = self,
        _drawin  = d,
    }, args or {})

    return node_factory(args, self)
end

--- Create a new node and place it before `self`.
--
-- The node type depends on the arguments. If neither a client or a wibox is
-- specified, the new node will contain a branch.
--
-- @DOC_awful_tree_create_before1_EXAMPLE@
--
-- @method :create_before
-- @tparam[opt={}] table args
-- @tparam[opt=nil] client|nil args.client A client object.
-- @tparam[opt=nil] wibox|nil args.wibox A wibox object.
-- @tparam[opt=false] boolean args.protected If the new node is protected during
--  `:cleanup()`.
-- @tparam[opt=true] boolean args.honor_size_hints Honor the client size hints
--  when applying the client geometry.
-- @tparam[opt=nil] table|nil args.geometry The geometry.
-- @treturn awful.tree.node The new node.
-- @see create_after
-- @see push_new
-- @see append_new
function module.create_before(self, args)
    assert(
        self.type ~= "awful.tree",
        "`:create_before()` cannot be used on the root node"
    )

    local c, d = args.client, args.wibox and args.wibox.drawin

    if c or d then
        assert((not self._weak_root[1]._client_mapping[c])
          or not self._weak_root[1]._drawin_mapping[d],
            "`:create_before() cannot be completed because " .. tostring(c or d) ..
            " is already part of the tree")
    end

    args = gtable.crush({
        next    = self,
        _drawin = d,
    }, args or {})

    return node_factory(args, self)
end

--- Push a new node at the beginning of the branch.
--
-- The new node will become `self.first_child`.
--
-- The node type depends on the arguments. If neither a client or a wibox is
-- specified, the new node will contain a branch.
--
-- @DOC_awful_tree_push_new1_EXAMPLE@
--
-- @method :push_new
-- @tparam[opt={}] table args
-- @tparam[opt=nil] client|nil args.client A client object.
-- @tparam[opt=nil] wibox|nil args.wibox A wibox object.
-- @tparam[opt=false] boolean args.protected If the new node is protected during
--  `:cleanup()`.
-- @tparam[opt=true] boolean args.honor_size_hints Honor the client size hints
--  when applying the client geometry.
-- @tparam[opt=nil] table|nil args.geometry The geometry.
-- @treturn awful.tree.node The new node.
-- @see create_after
-- @see create_before
-- @see append_new
-- @see first_child
function module.push_new(self, args)
    local t = self.type
    assert(t == "branch" or t == "awful.tree","`:push_new()` only works on branch nodes")

    local c, d = args.client, args.wibox and args.wibox.drawin

    if c or d then
        assert((not self._weak_root[1]._client_mapping[c])
          or not self._weak_root[1]._drawin_mapping[d],
            "`:push_new() cannot be completed because " .. tostring(c or d) ..
            " is already part of the tree")
    end

    args = gtable.crush({
        next     = self.first_child,
        parent   = (not self.first_child) and self or nil,
        _drawin  = d,
    }, args or {})

    return node_factory(args, self)
end

--- Append a new node at the leaf end of this branch.
--
-- The new node will become `self.last_child`.
--
-- The node type depends on the arguments. If neither a client or a wibox is
-- specified, the new node will contain a branch.
--
-- @DOC_awful_tree_append_new1_EXAMPLE@
--
-- @method :append_new
-- @tparam[opt={}] table args
-- @tparam[opt=nil] client|nil args.client A client object.
-- @tparam[opt=nil] wibox|nil args.wibox A wibox object.
-- @tparam[opt=false] boolean args.protected If the new node is protected during
--  `:cleanup()`.
-- @tparam[opt=true] boolean args.honor_size_hints Honor the client size hints
--  when applying the client geometry.
-- @tparam[opt=nil] table|nil args.geometry The geometry.
-- @treturn awful.tree.node The new node.
-- @see create_after
-- @see create_before
-- @see push_new
-- @see last_child
function module.append_new(self, args)
    local t = self.type
    assert(t == "branch" or t == "awful.tree", "`:append_new()` only works on branch nodes")

    local c, d = args.client, args.wibox and args.wibox.drawin

    if c or d then
        assert((not self._weak_root[1]._client_mapping[c])
          or not self._weak_root[1]._drawin_mapping[d],
            "`:append_new() cannot be completed because " .. tostring(c or d) ..
            " is already part of the tree")
    end

    args = gtable.crush({
        parent   = self,
        _drawin  = d,
    }, args or {})

    return node_factory(args, self)
end

--- Locate the node which contain a client.
--
-- @DOC_awful_tree_find_client_node1_EXAMPLE@
--
-- @method :find_client_node
-- @tparam client client A client.
-- @treturn nil|awful.tree.node The node which contain the client or `nil`.
-- @see find_wibox_node
-- @see client
function module.find_client_node(self, client)
    if not client then
          return nil
    elseif self.client == client then
        return self
    elseif self.type == "awful.tree" then
        return data[self]._weak_root[1]._client_mapping[client]
    else
        for node in module.iterate_children(self) do
            if node.client == client then return node end
        end
    end
end

--- Locate the node which contain a wibox.
--
-- @DOC_awful_tree_find_wibox_node1_EXAMPLE@
--
-- @method :find_wibox_node
-- @tparam wibox wibox A wibox.
-- @treturn nil|awful.tree.node The node which contain the wibox or `nil`.
-- @see find_client_node
-- @see wibox
function module.find_wibox_node(self, wibox)
    local d = wibox.drawin

    if not d then return nil end

    if self._drawin == d then
        return self
    elseif self.type == "awful.tree" then
        return data[self]._weak_root[1]._drawin_mapping[d]
    else
        for node in module.iterate_children(self) do
            if node._drawin == d then return node end
        end
    end
end

function module.get_parent(self)
    local p = self._parent
    return instances[p] or p
end

--- Iterate from `self` to the furtest leaf of the tree.
--
-- @DOC_awful_tree_iterate_next1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_next
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @tparam[opt=false] boolean inclusive Also include `node` in th iterator.
-- @treturn function An iterator.
-- @see awful.tree.iterate_previous
-- @see awful.tree.iterate_next_sibling
-- @see next
function module.iterate_next(node, inclusive)
    if not node then return nil end

    if not inclusive then
        return function()
            node = node.next
            return node
        end
    else
        local current = node

        return function()
            current = node
            node = node and node.next or nil
            return current
        end
    end
end

--- Iterate from `self` to the root of the tree.
--
-- @DOC_awful_tree_iterate_previous1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_previous
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @tparam[opt=false] boolean inclusive Also include `node` in th iterator.
-- @treturn function An iterator.
-- @see awful.tree.iterate_next
-- @see awful.tree.iterate_previous_sibling
-- @see previous
function module.iterate_previous(node, inclusive)
    if not node then return nil end

    if not inclusive then
        return function()
            node = node.previous
            return node
        end
    else
        local current = node

        return function()
            current = node
            node = node and node.previous or nil
            return current
        end
    end
end

--- Iterate from `self` to the last sibling (node with same `parent`).
--
-- @DOC_awful_tree_iterate_next_sibling1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_next_sibling
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @tparam[opt=false] boolean inclusive Also include `node` in th iterator.
-- @treturn function An iterator.
-- @see awful.tree.iterate_previous_sibling
-- @see awful.tree.iterate_next
-- @see next_sibling
function module.iterate_next_sibling(node, inclusive)
    if not node then return nil end

    if not inclusive then
        return function()
            node = node.next_sibling
            return node
        end
    else
        local current = node

        return function()
            current = node
            node = node and node.next_sibling or nil
            return current
        end
    end
end

--- Iterate from `self` to the first sibling (node with same `parent`).
--
-- @DOC_awful_tree_iterate_previous_siblings1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_previous_sibling
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @tparam[opt=false] boolean inclusive Also include `node` in th iterator.
-- @treturn function An iterator.
-- @see awful.tree.iterate_next_sibling
-- @see awful.tree.iterate_next
-- @see previous_sibling
function module.iterate_previous_sibling(node, inclusive)
    if not node then return nil end

    if not inclusive then
        return function()
            node = node.previous_sibling
            return node
        end
    else
        local current = node

        return function()
            current = node
            node = node and node.previous_sibling or nil
            return current
        end
    end
end

--- Recursively iterate from `self` last child node.
--
-- @DOC_awful_tree_iterate_children1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_children
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @treturn function An iterator.
-- @see iterate_parent
function module.iterate_children(node)
    if not node then return nil end

    local stop_to = node.next_sibling
    return function()
        node =  node.next
        return node ~= stop_to and node or nil
    end
end

--- Iterate the parent nodes until the root node.
--
-- @DOC_awful_tree_iterate_parent1_EXAMPLE@
--
-- @staticfct awful.tree.iterate_parent
-- @tparam awful.tree|awful.tree.node node The initial node (or tree).
-- @tparam[opt=false] boolean inclusive Also include `node` in th iterator.
-- @treturn function An iterator.
-- @see iterate_children
function module.iterate_parent(node, inclusive)
    if not node then return nil end

    if not inclusive then
        return function()
            node = node.parent
            return node
        end
    else
        local current = node

        return function()
            current = node
            node = node and node.parent or nil
            return current
        end
    end
end

capi._tree_node.connect_signal("client::added", client_added)
capi._tree_node.connect_signal("request::cleanup", cleanup_node)

gobject.properties(capi._tree_node, {
    getter_class    = module,
    setter_class    = module,
    getter_fallback = function(self, key)
        return data[self][key]
    end,
    setter_fallback = function(self, key, value)
        local props = data[self]
        local old_v = props[key]
        props[key] = value
        self:emit_signal("property::"..key, value, old_v)
    end,
})

return setmetatable(module, { __call = module.new })
