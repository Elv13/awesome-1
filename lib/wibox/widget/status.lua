--[[
iconified progressbar


a signal gradient with "n" rounded_bar steps growing horizontally

a wifi things

a battery widget (both with bars and like mine)

a LTE tower with full radiant circles

a volume widget with "n" (def: 3) bars

HAVE BOTH A CONTINOUS AND A STEPPED MODE!]]

---------------------------------------------------------------------------
-- Several preconfigured status widget for common devices.
--
-- * A WIFI widget
-- * A sound widget
-- * A battery widget
-- * A mobile data widget
--
-- All widgets have a continuous mode and a step mode
--
--@DOC_wibox_widget_defaults_status_EXAMPLE@
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2014, 2017 Emmanuel Lepage Vallee
-- @classmod wibox.widget.status
---------------------------------------------------------------------------
local beautiful = require( "beautiful"         )
local base      = require( "wibox.widget.base" )
local color     = require( "gears.color"       )
local gtable    = require( "gears.table"       )
local shape     = require( "gears.shape"       )

local status = {}


local function draw(self, _, cr, width, height)
    -- In case there is a specialized.
    local draw_custom = self._private.draw or beautiful.status_draw

    local border_width = self._private.border_width or 1
    local mode = "continuous"
    local border_color = "#ff0000"

    shape.right_triangle(cr, width, height)
    if border_width > 0 and border_color then
        cr:stroke_preserve()
    else
        cr:stroke()
    end
end

local function fit(_, _, width, height)
    return width, height
end

--[[
for _, prop in ipairs {"orientation", "color", "thickness", "span_ratio",
                       "border_width", "border_color", "shape" } do
    status["set_"..prop] = function(self, value)
        self._private[prop] = value
        self:emit_signal("property::"..prop)
        self:emit_signal("widget::redraw_needed")
    end
    status["get_"..prop] = function(self)
        return self._private[prop] or beautiful["status_"..prop]
    end
end]]

local function new(args)
    local ret = base.make_widget(nil, nil, {
        enable_properties = true,
    })
    gtable.crush(ret, status, true)
    gtable.crush(ret, args or {})
    ret._private.orientation = ret._private.orientation or "auto"
    rawset(ret, "fit" , fit )
    rawset(ret, "draw", draw)
    return ret
end

--@DOC_widget_COMMON@

--@DOC_object_COMMON@

return setmetatable(status, { __call = function(_, ...) return new(...) end })
-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
