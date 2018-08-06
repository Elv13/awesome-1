---------------------------------------------------------------------------
--- Draw a minimap of a tag in a widget.
--
-- This widget allows to keep track of the layout of a tag. It is limited to
-- a single tag and cannot represent multiple concurrently selected tags.
--
-- Alone, this widget is quite useless. To make it useful, it is usually
-- used as a `awful.widget.taglist` delegate:
--
-- TODO example as a taglist delegate
--
-- In a similar way, it can be used as a tag switcher popup:
--
-- TODO example as collision popup
--
-- Or a screen switcher:
--
-- TODO example as a screen switcher
--
-- Finally, it is also possible to use the `dynamite.widget.screenshot` widget
-- as the delegate. It is only reliable when compositing is enable. Otherwise
-- it will sometime work, sometime display garbage and sometime only black
-- rectangles.
--
-- TODO screenshot example
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2013-2018 Emmanuel Lepage Vallee
-- @module dynamite.widget.pager
---------------------------------------------------------------------------
local wbase  = require( "wibox.widget.base" )
local dbase  = require( "dynamite.base"     )
local gtable = require( "gears.table"       )
local gshape = require( "gears.shape"       )
local afloat = require( "awful.layout.suit.floating")
local capi         = { screen = screen, client=client }

local pager = { mt = {} }

-- The "legacy" way to have tiling layouts is still supported. While the
-- following code is a bit horrible, it once was the only way to generate
-- the pager. It works with all default Awesome layout and and the most
-- popular 3rd party ones.

-- Emulate a client using meta table magic
local function gen_cls(c, tiled)
    local ret = setmetatable({},{__index = function(t,i)
        local ret2 = c[i]
        if type(ret2) == "function" then
            if i == "geometry" then
                return function(self,...)
                    if #{...} > 0 then
                      local geom = ({...})[1]

                      -- Make a copy as the original will be changed
                      tiled[c] = awful.util.table.join(({...})[1],{})

                      return geom
                    end

                    return c:geometry()
                end
            else
                return function(self,...) return ret2(c,...) end
            end
        end
        return ret2
    end})
    return ret
end

function get_geometry(tag)
    local cls, tiled, floating = {},setmetatable({},{__mode="k"}),{}
    local s = tag.screen
    local l = tag.layout
    local focus,focus_wrap = capi.client.focus,nil
    for k,c in ipairs (tag:clients()) do
        if not c.minimized then
            -- Handle floating client separately
            if (not c.floating) and (l ~= afloat) then
                cls[#cls+1] = gen_cls(c, tiled)
                if c == focus then
                    focus_wrap = cls[#cls]
                end
            else
                table.insert(floating, c:geometry())
            end
        end
    end

    -- The magnifier layout require a focussed client
    -- there wont be any as that layout is not selected
    -- take one at random or (TODO) use stack data
    if not focus_wrap then
        focus_wrap = cls[1]
    end

    local param = {
        tag = tag,
        screen = 1,
        clients = cls,
        focus = focus_wrap,
        workarea = capi.screen[s or 1].workarea,
        geometries = setmetatable({}, {__mode = "k"})
    }

    l.arrange(param)

    return param.geometries, floating, tiled
end

--- The pager tag object.
--
-- Note that this unset `screen`.
--
-- @property tag
-- @param tag

function pager:set_tag(t)
    self._private.tag = t
    self._private.screen = nil

    self:emit_signal("widget::redraw_needed")
end

--- The pager screen object.
--
-- Note that this unset `tag`.
--
-- @property screen
-- @param screen

function pager:set_screen(s)
    if self._private.screen then
        self._private.screen:disconnect_signal("arrange", self._private.arrange_cb)
    end

    self._private.tag = nil
    self._private.screen = s

    if self._private.screen then
        self._private.screen:connect_signal("arrange", self._private.arrange_cb)
    end

    self:emit_signal("widget::redraw_needed")
end

--- Display the icon in the default delegate.
-- @property display icon
-- @param boolean

-- Return the width factor.
local function get_aspect_ratio(s)
    return s.geometry.width / s.geometry.height
end

function pager:fit(ctx, width, height)
    -- If there is only one screen, it could be implemented, but to keep it
    -- consistent, it's safer to ignore those widgets.
    if (not self._private.screen) and (not self._private.tag) then
        return 0, 0
    end

    local s = self._private.tag and
        self._private.tag.screen or self._private.screen

    -- In theory, a tag can have no screen, however bag things will happen.
    if not s then return 0, 0 end

    local factor = get_aspect_ratio(s)

    if factor >= 1 then
        if width > height*factor then
            return math.ceil(height*factor), height
        else
            return width, math.ceil(width/factor)
        end
    else
        if width*factor < height then
            assert(false) --TODO
        end
        assert(false) --TODO
    end

    -- Unreachable
    return 0, 0
end

function pager:draw(content, cr, width, height)
    local s = self._private.tag and
        self._private.tag.screen or self._private.screen

    if not s then return end

    local geo = s.geometry

    -- The widget size could have been forced, center the content
    local rw, rh = self:fit(context, width, height)
    local dx, dy = width-rw, height-rh

    -- The scaling factor compared to the native size, sw == sh 99& of the time
    local sw, sh = rw/geo.width, rh/geo.height

    -- Draw the background --TODO wallpaper?
    cr:set_source_rgba(1,0,0,1)
    cr:rectangle(dx, dy, rw, rh)
    cr:fill()

    local t = self._private.tag or self._private.screen.selected_tag

    if not t then return end

    --TODO use the hierarchy

    -- This is the fallback code path for stateless layouts. It emulate the
    -- client the get an approximation. Note that it misbehave in most corner
    -- cases and there is not much to do about it. It's a compatibility hack.
    local tiled, floating, legacy_tiled = get_geometry(t)

    cr:set_source_rgba(1, 0, 1, 1)
    cr:set_line_width(2)

    for _, c_geo in pairs(tiled) do
        cr:rectangle(
            dx+c_geo.x*sw, dy+c_geo.y*sh, c_geo.width*sw, dx+c_geo.height*sh
        )
    end
    cr:stroke()
end

--- Create a pager widget.
-- @function dynamite.widget.pager
local function new(format, refresh, tzid)
    local ret = wbase.make_widget(nil, nil, {
        enable_properties = true,
    })

    gtable.crush(ret, pager, true)

    function ret._private.arrange_cb()
        ret:emit_signal("widget::redraw_needed")
    end

    return ret
end

function pager.mt:__call(...)
    return new(...)
end

--@DOC_widget_COMMON@

--@DOC_object_COMMON@

return setmetatable(pager, pager.mt)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
