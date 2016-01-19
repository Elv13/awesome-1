---------------------------------------------------------------------------
--- Reserve a spot for a client (or nothing) in the client layouts.
--
-- Clients are not "true" widgets. They are objects that are placed directly
-- on the screen with little control over their content. This widget doesn't
-- really embed clients. Rather, it simply create an empty widget and moves
-- the clients over the empty space.
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016 Emmanuel Lepage Vallee
-- @tilinglib dynamite.widget.placeholder
---------------------------------------------------------------------------
local object    = require( "gears.object"           )
local wbase     = require( "wibox.widget.base"      )
local resize    = require( "dynamite.resize"        )
local utils     = require( "dynamite.utils"         )
local l_ratio   = require( "dynamite.layout.ratio"  )
local stack_l   = require( "dynamite.layout.tabbed" )
local gtable    = require( "gears.table"            )
local aw_client = require( "awful.client"           )

local module = {}

-- All all placeholder/client_wrapper instances (to track focus)
local instances = setmetatable({}, {__mode = "k"})

-- Callback called when a split point is activated
local function split(wrapper, context, direction)
    if not context.client_widget or not context.source_root then return end
    local t = (direction == "left" or direction == "right")

    local l = t and l_ratio.horizontal() or l_ratio.vertical()

    local f = context.source_root._private.remove_widgets or context.source_root.remove_widgets
    f(context.source_root, context.client_widget, true)

    t = (direction == "left" or direction == "top")
    l:add(t and context.client_widget or wrapper)
    l:add(t and wrapper or context.client_widget)

    context.source_root:replace_widget(wrapper, l, true)

    context.source_root:raise_widget(context.client_widget)

    context.source_root:emit_signal("widget::redraw_needed")
end

-- Callback called when a stack point is activated
local function stack(wrapper, context)

    local f = context.source_root._remove_widgets or context.source_root.remove_widgets
    f(context.source_root, context.client_widget, true)

    local l = stack_l()

    l:add(context.client_widget)
    l:add(wrapper              )

    context.source_root:replace_widget(wrapper, l, true)

    context.source_root:emit_signal("widget::redraw_needed")

    l:raise_widget(context.client_widget)
end

local function get_name(self)
    return self._client and self._client.name or ""
end

--- Allow the wrapper to be splited in each of the 4 directions
-- @param self A wrapper
-- @param[opt] geometry A modified geometry preferred by the handler
--
-- This function can be overloaded to add new points
--
-- @return A table of potential split points
function module.splitting_points(self, geometry)
    geometry = geometry or (self._client and self._client:geometry())

    -- Add a group of split point for the UX handler
    local ret = {
        position      = "centered",
        bounding_rect = geometry,
        type          = "internal",
        client        = self._client,
        points        = {}
    }

    for _, v in ipairs {"left", "right", "top", "bottom", false} do
        table.insert(ret.points, {
            direction = v or "stack",
            callback  = function(_, ct) (v and split or stack)(self, ct, v) end
        })
    end

    return ret
end

local function fit(self, _, width, height)
    local c = self._client

    if (not c.valid) or (not self.visible) then return 0, 0 end

    if c.size_hints_honor then
        return c:apply_size_hints(width, height)
    end

    -- Let the flex or ratio layout decide the space it wants
    return 1, 1
end

-- Equivalent of wibox.widget.draw, simply move and resize the client
local function draw(self, _, cr, width, height)
    local c = self._client

    -- There is a few race condition where the client is invalidated during a
    -- pending redraw. This will cause a visual glitch, but the layouts should
    -- be repainted in the next iteration.
    if (not c.valid) or not self.visible or c.floating then return end

    local matrix = cr:get_matrix()
    local gap    = (not self._handler._tag and 0 or self._handler._tag.gap)/2

    -- If a mirror or rotate container was used, the size might be negative.
    local x2, y2, w2, h2 = matrix:transform_rectangle( 0, 0, width, height )

    -- Remove the border and gap from the final size
    w2 = math.max(1, w2 - 2*gap - 2*c.border_width)
    h2 = math.max(1, h2 - 2*gap - 2*c.border_width)

    -- Make sure the layout did not screw up
    assert(w2 <= width  or w2 == 1)
    assert(h2 <= height or h2 == 1)

    if c.size_hints_honor then
        w2, h2 = c:apply_size_hints(w2, h2)
    end

    c:geometry {
        x      = x2 + gap,
        y      = y2 + gap,
        width  = w2      ,
        height = h2      ,
    }
end

--- Callback when a new geometry is requested
local function on_geometry(wrapper, c, reasons, hints)
    if (not wrapper.visible) or c.floating then return end

    assert(wrapper._is_connected)

    if wrapper._handler.active  and reasons == "mouse.resize" then
        local gap = c.screen.selected_tag.gap/2

        hints = setmetatable({
            width  = (hints.width  or c.width ) + 2*c.border_width + 2*gap,
            height = (hints.height or c.height) + 2*c.border_width + 2*gap,
            x      = (hints.x      or c.x     ) - gap,
            y      = (hints.y      or c.y     ) - gap,
            gap    = gap,
        }, {__index = hints or {}})

        local delta = {}

        --FIXME use the hierarchy, the current geometry might be from another tag
        -- Convert the geometry change into delta.
        for _, side in ipairs {
            {"x", "left"}, {"y", "top"}, {"width", "right"}, {"height", "bottom"}
        } do
            delta[side[2]] = (hints[side[1]] or client[side[1]]) - (hints[side[1]] or 0)
        end

        resize(wrapper._handler, c, wrapper, hints)

        -- This will convert the request::geometry into a request::resize. This
        -- Is necessary because layouts have constraints floating rectangle
        -- lack.
        utils.resize_widget(nil, wrapper, delta)
    end
end

--- Callback when the client is raised
local function on_raise(wrapper, _)
    assert(wrapper._is_connected)
    if wrapper._handler.active and wrapper._handler.widget.raise then
        wrapper._handler.widget:raise_widget(wrapper, true)
        wrapper:emit_signal_recursive("raised", wrapper._client)
    end
end

--- Callback when two client indices are swapped
local function on_swap(wrapper, self, other_c, is_source)
    assert(wrapper._is_connected)
    if wrapper._handler.active and is_source then
        if wrapper._handler then
            wrapper._handler:swap_widgets(self, other_c, true)
            wrapper._handler.widget:emit_signal("widget::redraw_needed")
            wrapper:emit_signal_recursive("swapped", other_c)
        end
    end
end

local function on_name(wrapper)
    wrapper:emit_signal(
        "property::name", get_name(wrapper)
    )
end

-- Useful when the client is minimized, shaded or the decoration changed
local function redraw(wrapper, c)
    -- Let maximized and fullscreen clients (which also have `c.floating = true`
    -- use their normal space. But prevent explicitly floating or
    -- minimized clients from using up space. Removing them from the layout is
    -- not an option because toggling floating or minimization would cause them
    -- to lose their spot.
    wrapper.visible = (
        (not c.minimized) and (not aw_client.property.get(c, "floating"))
    )

    wrapper:emit_signal("widget::redraw_needed")
    wrapper:emit_signal("widget::layout_changed")
end

--- Avoid flickering by disconnecting signals when the wrapper is not in use
local function suspend(wrapper)
    if not wrapper._is_connected then return end

    for signal, callback in pairs(wrapper._private.callbacks) do
        wrapper._client:disconnect_signal(signal, callback)
    end

    wrapper._is_connected = false
end

--- Re-connect the signals when the wrapper is activated
local function wake_up(wrapper)
    if wrapper._is_connected then return end

    for signal, callback in pairs(wrapper._private.callbacks) do
        wrapper._client:connect_signal(signal, callback)
    end

    wrapper._is_connected = true
end

-- Create the wrapper
-- @param c_w A client or a wibox
local function wrap_client(_, c_w)
    local wrapper = wbase.make_widget(nil, nil, {
        enable_properties = true,
    })

    -- Keep track to be able to emit the focus related signals
    instances[c_w] = instances[c_w] or setmetatable({}, {__mode = "v"})
    table.insert(instances[c_w], wrapper)

    gtable.crush(wrapper, {
        _client          = c_w,
        draw             = draw,
        fit              = fit,
        suspend          = suspend,
        wake_up          = wake_up,
        splitting_points = module.splitting_points,
        get_name         = get_name,
    }, true)

    -- Hints as to where to place the new wrapper --FIXME can't work like that
    wrapper.slave, wrapper.master = c_w.slave, c_w.master

    -- Make sure the widget is notified when the client state changes
    wrapper._private.callbacks = {
        ["request::geometry"    ] = function(...) on_geometry(wrapper, ... ) end,
        ["swapped"              ] = function(...) on_swap    (wrapper, ... ) end,
        ["raised"               ] = function(...) on_raise   (wrapper, ... ) end,
        ["property::minimized"  ] = function(...) redraw     (wrapper, ... ) end,
        ["property::floating"   ] = function(...) redraw     (wrapper, ... ) end,
        ["property::name"       ] = function(...) on_name    (wrapper, ... ) end,
    }

    wake_up(wrapper)

    wrapper:connect_signal("widget::layout_changed", function()
        wrapper._private.widget_caches = {}
    end)

    return wrapper
end

-- Make sure the layout is notified when the focus changes
client.connect_signal("focus", function(c)
    for _, w in ipairs(instances[c] or {}) do
        if w._is_connected then
            w:emit_signal_recursive(
                c == client.focus and "focused" or "unfocused", w, c
            )
        end
    end
end)

--- Create a new placeholder.
-- @constructorfct dynamite.widget.placeholder

return setmetatable(module, {__call = wrap_client})
-- kate: space-indent on; indent-width 4; replace-tabs on;
