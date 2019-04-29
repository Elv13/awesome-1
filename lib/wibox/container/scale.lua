---------------------------------------------------------------------------
--- Resize the content widget by a factor, offset or DPI differential.
--
-- This container can be used to shrink or grow its content.
--
--@DOC_wibox_container_defaults_scale_EXAMPLE@
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2019 Emmanuel Lepage Vallee
-- @classmod wibox.container.scale
---------------------------------------------------------------------------
local base = require("wibox.widget.base")
local matrix = require("gears.matrix")
local gtable = require("gears.table")

local scale = { mt = {} }

-- Convert the input into a factor.
local function get_factor(self, geo)
    local ret = {}
    for pos, orientation in ipairs {"horizontal", "vertical" } do
        if self._private["factor_"..orientation] then
            ret[pos] = self._private["factor_"..orientation]
        elseif self._private["points_"..orientation] then
            --TODO
        elseif self._private["percent_"..orientation] then
            --TODO
        else
            ret[pos] = 1
        end

    end

    return ret[1], ret[2]
end

-- Layout this layout
function scale:layout(_, width, height)
    if not self._private.widget then return end

    print("SCALE", width, height, get_factor(self, {width, height}))
    local m = matrix.identity:scale(get_factor(self, {width, height}))

    return { base.place_widget_via_matrix(self._private.widget, m, width, height) }
end

-- Fit this layout into the given area
function scale:fit(context, ...)
    if not self._private.widget then
        return 0, 0
    end
    return base.fit_widget(self, context, self._private.widget, ...)
end

--- The widget to be reflected.
-- @property widget
-- @tparam widget widget The widget

function scale:set_widget(widget)
    if widget then
        base.check_widget(widget)
    end
    self._private.widget = widget
    self:emit_signal("widget::layout_changed")
end

function scale:get_widget()
    return self._private.widget
end

--- Get the number of children element
-- @treturn table The children
function scale:get_children()
    return {self._private.widget}
end

--- Replace the layout children
-- This layout only accept one children, all others will be ignored
-- @tparam table children A table composed of valid widgets
function scale:set_children(children)
    self:set_widget(children[1])
end

--- Reset this layout. The widget will be removed and the axes reset.
function scale:reset()
    self._private = {}
    self:emit_signal("widget::layout_changed")
end

local function meta_setter_common(prefix)
    return function(self, value)
        local t = type(value)
        if t == "number" then
            t = {vertical = t, horizontal = t}
        elseif t ~= 'table' then
            error("Invalid type of factor for scale container: " ..
                t .. " (should be a table)")
        end
        for _, ref in ipairs({"horizontal", "vertical"}) do
            if value[ref] ~= nil then
                self._private[prefix.."_"..ref] = value[ref]
            end
        end
        self:emit_signal("widget::layout_changed")
    end
end

local function meta_getter_common(prefix)
    return function(self)
        -- Allows to do mywidget.reflection.vertical = true
        return setmetatable({}, {
            __index = {
                horizontal = self._private[prefix.."_horizontal"],
                vertical   = self._private[prefix.."_vertical"]
            },
            __newindex = function(_, k, v)
                assert(k == "vertical" or k == "horizontal")
                self._private[k] = v
                self:emit_signal("widget::layout_changed")
            end
        })
    end
end

--- Set the scaling factor of this scale container.
-- @property factor
-- @tparam table factor A table of booleans with the keys "horizontal", "vertical".
-- @tparam boolean factor.horizontal
-- @tparam boolean factor.vertical

--- Set the scaling of this scale container (by points/pixels).
-- @property factor
-- @tparam table factor A table of booleans with the keys "horizontal", "vertical".
-- @tparam boolean factor.horizontal
-- @tparam boolean factor.vertical

--- Set the scaling percentage of this scale container.
-- @property factor
-- @tparam table factor A table of booleans with the keys "horizontal", "vertical".
-- @tparam boolean factor.horizontal
-- @tparam boolean factor.vertical

for _, p in ipairs {"factor","points","percent"} do
    scale["get_"..p] = meta_getter_common(p)
    scale["set_"..p] = meta_setter_common(p)
end

--- Returns a new scale container.
--
-- horizontal and vertical are by default false which doesn't change anything.
-- @param[opt] widget The widget to display.
-- @param[opt] reflection A table describing the reflection to apply.
-- @treturn table A new scale container
-- @function wibox.container.scale
local function new(args)
    args = args or {}
    local ret = base.make_widget(nil, nil, {enable_properties = true})

    gtable.crush(ret, scale, true)
    gtable.crush(ret, args , false)

         print("\n\nRET")
    return ret
end

function scale.mt:__call(...)
    return new(...)
end

--@DOC_widget_COMMON@

--@DOC_object_COMMON@

return setmetatable(scale, scale.mt)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
