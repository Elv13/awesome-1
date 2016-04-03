---------------------------------------------------------------------------
-- Based on https://github.com/RobSis/treesome
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016 Emmanuel Lepage Vallee
-- @module dynamite
---------------------------------------------------------------------------
local dynamic = require( "dynamite.base"         )
local tabbed  = require( "dynamite.layout.tabbed")
local wibox   = require( "wibox"                 )
local l_ratio = require( "dynamite.layout.ratio" )
local stack   = require( "dynamite.layout.stack" )
local gobject = require( "gears.object"          )
local capi    = {client = client, screen = screen}

--- Split the focused client area in two.
--
-- The split will be either vertical or horizontal to maximize the space.
--
-- By default, left untouched, it will form a spiral. This means this layout
-- is unsuited when initializing it with many existing clients. This, in turn,
-- makes it user-unfriendly when switching between multiple layouts:
--
--@DOC_dynamite_suit_treesome_simple_EXAMPLE@
--
-- Alternatively, it is possible to control this layout per-screen using the
-- "remote control" object returned by:
--
--    local api = dynamite.suit.treesome.api(mouse.screen)
--
-- This object has the following mutually exclusive properties:
--
-- * **horizontal_split**: Split along the horizontal axis (side by side)
-- * **vertical_split**: Split along the horizontal axis (top/bottom)
-- * **tabbed**: Add client on top of each other.
-- * **auto**: Pick `vertical` or `horizontal` depending on the maximum size
--  of the resulting clients (*default*)
--
-- It also has:
--
-- * *insert*:
--
-- Here's an example of the following steps:
--
--@DOC_dynamite_suit_treesome_complex_EXAMPLE@
--
-- Here's an example when `insert` is enabled:
--
--@DOC_dynamite_suit_treesome_insert_EXAMPLE@
--
-- It is useful to add keybindings to the `globalkeys` section of `rc.lua` to
-- manipulate this API:
--
--    awful.key({ modkey }, "g", function()
--        dynamite.suit.treesome.api(mouse.screen).auto = true
--    end, {description = "go back", group = "layout"}),
--    awful.key({ modkey, "Shift"}, "g", function()
--        dynamite.suit.treesome.api(mouse.screen).horizontal_split = true
--    end, {description = "go back", group = "layout"}),
--    awful.key({ modkey, "Control"}, "g", function()
--        dynamite.suit.treesome.api(mouse.screen).vertical_split = true
--    end, {description = "go back", group = "layout"}),
--    awful.key({ modkey, "Mod1"}, "g", function()
--        dynamite.suit.treesome.api(mouse.screen).tabbed = true
--    end, {description = "go back", group = "layout"}),
--    awful.key({ modkey, "Mod1", "Control"}, "g", function()
--        dynamite.suit.treesome.api(mouse.screen).insert =
--            not dynamite.suit.treesome.api(mouse.screen).insert
--    end, {description = "go back", group = "layout"}),
--
-- @clientlayout dynamite.treesome

local props = {"auto", "horizontal_split", "vertical_split", "tabbed"}
local apis  = setmetatable({}, {__mode="k"})

local prop_to_layout = {
    horizontal_split = "horizontal",
    vertical_split   = "vertical",
    tabbed           = "tabbed",
}

-- Create a per-screen "API" for this suit. It allows to manually set if the
-- layout should have v-split, h-split or tabs.
local function api_factory(s)
    local src = capi.screen[s]
    if apis[src] then return apis[src] end

    local ret = gobject {
        enable_properties   = true,
        enable_auto_signals = true,
    }

    rawset(ret, "_private", {})

    -- Generate mutually exclusive properties.
    for _, p in ipairs(props) do
        rawset(ret, "set_"..p, function(_, v)
            ret._private.state = v and p or nil
            for _, p2 in ipairs(props) do
                ret:emit_signal("property::"..p2, p2 == p)
            end
        end)
        rawset(ret, "get_"..p, function() return ret._private.state == p end)
    end

    rawset(ret, "get_current_state", function()
        return ret._private.state or "auto"
    end)

    -- There's also an implicit "insert" property to insert into the existing
    -- container if the state is "auto" or if the state match the current
    -- container type.
    ret.insert = false

    apis[src] = ret

    return ret
end

local function focus_changed(self, placeholder, c)
    self._private.previous = self._private.latest
    self._private.latest = c
end

-- Remove containers when they are empty or have only 1 client
local function garbage_empty(self, idx)
    local ret = self._private._remove(self, idx)

    local children = self.children
    if #children == 0 or (#children == 1 and children[1].auto_gc) then
        self._private.tree:remove_widgets(self, true)
    elseif #children == 1 then
        self._private.tree:replace_widget(self, children[1], true)
    end

    return ret
end

local function create_container(direction, parent)
    local ret = direction == "tabbed" and tabbed() or l_ratio[direction]()

    ret._private.split_type = direction
    ret._private.tree       = parent
    ret._private._remove    = ret.remove
    ret._private.auto_gc    = true
    rawset(ret, "remove", garbage_empty)

    return ret
end

-- Select the client to split in half.
local function find_current(self)
    local everything = self:get_all_children()
    local biggest, ret = 0

    -- Because the newly added client probably already has focus, keeping
    -- a short history of the last 2 focused clients is required
    local preferred, preferred2 = self._private.latest, self._private.previous

    -- Find the biggest client
    for _, w in ipairs(everything) do
        if w._client and w._client.valid then
            -- BUG this uses the **current** client size, but it can be already
            -- invalid.
            local geo = w._client:geometry()

            if preferred == w._client or w._client == capi.client.focus then
                return w
            end

            if preferred2 == w._client then
                biggest = math.huge
                ret = w
            end

            if geo.width*geo.height > biggest then
                assert(w._client.valid)
                biggest, ret = geo.width*geo.height, w
            end
        end
    end

    return ret
end

local function get_direction(api, c)
    if api and prop_to_layout[api._private.state] then
        return prop_to_layout[api._private.state]
    end

    local geo = c:geometry()

    return geo.width > geo.height and "horizontal" or "vertical"
end

-- When adding another tab or when `api.insert` is true, re-use an existing
-- layout/container instead of creating a new one.
local function get_container(self, api, target)
    local ins = api and (api.insert or api.tabbed)
    local l = ins and select(2, self:index(target, true)) or nil

    local split_match = l and (
        (not api._private.state) or
        api._private.state:match(l._private.split_type) or
        api._private.state == "auto"
    )

    return split_match and l or nil
end

local function add(self, w1, ...)
    if not w1 then return end

    -- Add the first element
    if #self:get_children() == 0 then
        self._private._add(self, w1)

        self:add(...)
        return true
    end

    if w1._client and w1._client == capi.client.focus then
        focus_changed(self, w1, w1._client)
    end

    local target = find_current(self)

    local api = (target and target._client and target._client.screen)
        and apis[target._client.screen] or nil

    local dir = get_direction(api, target._client)

    if target then
        local l = get_container(self, api, target)
        if l then
            l:add(w1)
        else
            l = wibox.layout {
                target,
                w1,
                layout = create_container(dir, self)
            }
            self:replace_widget(target, l, true)
        end
    else
        -- Someone messed with the layout
        assert(false)
    end

    self:add(...)
end

local function ctr()
    local main = stack()

    main._private._add = main.add
    rawset(main, "add", add)
    main:connect_signal("focused", focus_changed)

    return main
end

local module = dynamic("treesome", ctr)

module.api = api_factory

return module
-- kate: space-indent on; indent-width 4; replace-tabs on;
