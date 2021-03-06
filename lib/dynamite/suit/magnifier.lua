---------------------------------------------------------------------------
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016 Emmanuel Lepage Vallee
-- @module dynamite

--- A client in front of a list of other clients.
--
--@DOC_dynamite_suit_magnifier_magnifier_EXAMPLE@
--
-- **Client count scaling**:
--
--@DOC_dynamite_suit_magnifier_scaling_EXAMPLE@
--
-- **nmaster effect**:
--
-- Unused
--
-- **ncol effect**:
--
-- Unused
--
-- **master\_width\_factor effect**:
--
-- @DOC_dynamite_suit_magnifier_mwfact_EXAMPLE@
--
-- **gap effect**:
--
-- The "useless" gap tag property will change the spacing between clients.
--@DOC_dynamite_suit_magnifier_gap_EXAMPLE@
--
-- **resize effect**:
--@DOC_dynamite_suit_magnifier_resize_EXAMPLE@
--
-- See `awful.tag.setgap`
-- See `awful.tag.getgap`
-- See `awful.tag.incgap`
--
-- **screen padding effect**:
--
--@DOC_dynamite_suit_magnifier_padding_EXAMPLE@
-- See `awful.screen.padding`
-- @clientlayout dynamite.magnifier

local dynamic = require( "dynamite.base"         )
local wibox   = require( "wibox"                 )
local l_ratio = require( "dynamite.layout.ratio" )
local stack   = require( "dynamite.layout.stack" )

local function raise_widget(self, widget)
    --TODO check if there is manual split applied, preserve them
    local front = self:get_children_by_id("front_layout")[1]

    local w = front:get_children()[1]

    if widget == w then return end

    self:swap_widgets(w, widget, true)
end

local function add(self, widget, ...)
    local front = self:get_children_by_id("front_layout")[1]

    local w = front:get_children()[1]

    if not w then
        front:set_widget(widget)
        return
    end

    local list = self:get_children_by_id("main_vertical")[1]
    list:add(widget, ...)

    self:raise_widget(widget)
end

local function before_draw_children(self, _, _, width, height)
    local m = self:get_children_by_id("front_layout")[1]
    local mwfact = self._client_layout_handler._tag.master_width_factor

    -- The /2 is because there is a margin on both sides
    m:set_margins(math.min(width, height)/2 * mwfact)
end

local function ctr(_)
    local main_layout = wibox.widget {
        {
            id     = "front_layout",
            left   = 0,
            right  = 0,
            top    = 0,
            bottom = 0,
            layout = wibox.container.margin,
        },
        {
            id     = "main_vertical",
            layout = l_ratio.vertical
        },
        display_top_only = false,
        before_draw_children = before_draw_children,
        layout = stack
    }

    main_layout.add = add
    main_layout.raise_widget = raise_widget

    main_layout:connect_signal("request::resize", function(origin, request)
        print("\n\nREQUEST RESIZE", origin, request)
    end)

    return main_layout
end

local module = dynamic("magnifier", ctr)

return module
-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
