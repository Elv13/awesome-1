
-- This template provides a timeline like display for tag changes.
-- Basically a taglist with some pretty dots on the side. Note that the way it
-- copy tags is fragile and probably not really supportable.

local file_path, image_path = ...
require("_common_template")(...)
local capi = {client = client, screen = screen}
local cairo = require("lgi").cairo
local Pango = require("lgi").Pango
local PangoCairo = require("lgi").PangoCairo
require("awful.screen")
require("awful.tag")
local floating_l = require("awful.layout.suit.floating")
local taglist = require("awful.widget.taglist")
local gtable = require("gears.table")
local shape = require("gears.shape")
local color = require("gears.color")
local wibox = require("wibox")
local beautiful = require("beautiful")

local bar_size, radius = 18, 2

local history = {}

local module = {}

-- Draw a mouse cursor at [x,y]
local function draw_mouse(cr, x, y)
    cr:set_source_rgb(1, 0, 0)
    cr:move_to(x, y)
    cr:rel_line_to( 0, 10)
    cr:rel_line_to( 3, -2)
    cr:rel_line_to( 3,  4)
    cr:rel_line_to( 2,  0)
    cr:rel_line_to(-3, -4)
    cr:rel_line_to( 4,  0)
    cr:close_path()
    cr:fill()
end

-- Imported from the Collision module.
local function draw_lines()
    local ret = wibox.widget.base.make_widget()

    function ret:fit(ctx, w, h)
        return w, self.widget_pos and #self.widget_pos*6 or 30
    end

    function ret:draw(ctx, cr, w, h)
        if (not self.widget_pos) or (not self.pager_pos) then return end

        cr:set_line_width(1)
        cr:set_source_rgba(0,0,0,0.3)

        local count = #self.widget_pos

        for k, t in ipairs(self.widget_pos) do
            local point1 = {x = t.widget_x, y = 0, width = t.widget_width, height = 1}
            local point2 = {x = t.pager_x, y = 0, width = t.pager_width, height = h}
            assert(point1.x and point1.width)
            assert(point2.x and point2.width)

            local dx = (point1.x == 0 and radius or 0) + (point1.width and point1.width/2 or 0)
            local dy = point1.y == 0 and radius or 0

            cr:move_to(bar_size+dx+point1.x, point1.y+2*radius)
            cr:line_to(bar_size+dx+point1.x, point2.y+(count-k)*((h-2*radius)/count)+2*radius)
            cr:line_to(point2.x+point2.width/2, point2.y+(count-k)*((h-2*radius)/count)+2*radius)
            cr:line_to(point2.x+point2.width/2, point2.y+point2.height)
            cr:stroke()

            cr:arc(bar_size+dx+point1.x, point1.y+2*radius, radius, 0, 2*math.pi)
            cr:fill()

            cr:arc(point2.x+point2.width/2, point2.y+point2.height-radius, radius, 0, 2*math.pi)
            cr:fill()
        end
    end

    return ret
end

local function gen_vertical_line(dot)
    local w = wibox.widget.base.make_widget()

    function w:draw(ctx, cr, w, h)
        cr:set_source_rgba(0,0,0,0.5)
        cr:rectangle(w/2-0.5, 0, 1, h)
        cr:fill()

        if dot then
            cr:arc(w/2,w/2,bar_size/4, 0, 2*math.pi)
            cr:set_source_rgb(1,1,1)
            cr:fill_preserve()
            cr:set_source_rgba(0,0,0,0.5)
            cr:stroke()
        end
    end

    function w:fit(ctx, w, h)
        return bar_size, bar_size
    end

    return w
end

local function gen_taglist_layout_proxy(tags, w2, name)
    local l = wibox.layout.fixed.horizontal()

    local layout = l.layout

    local pos = {}

    l.layout = function(self,context, width, height)
        local ret = layout(self,context, width, height)

        for k, v in ipairs(ret) do
            tags[k][name.."_x"    ] = v._matrix.x0
            tags[k][name.."_width"] = v._width
        end

        if w2 then
            w2[name.."_pos"] = tags

            if not w2[name.."_configured"] then
                rawset(w2, name.."_configured", true)
                w2:emit_signal("widget::redraw_needed")
                w2:emit_signal("widget::layout_changed")
            end
        end

        return ret
    end

    return l
end

local function gen_fake_taglist_wibar(tags, w2)
    local layout = gen_taglist_layout_proxy(tags, w2, "widget")
    local w = wibox.widget {
        {
            {
                forced_height = bar_size,
                image         = beautiful.awesome_icon,
                widget        = wibox.widget.imagebox,
            },
            taglist {
                forced_height = 14,
                forced_width  = 300,
                layout        = layout,
                screen        = screen[1],
                filter        = taglist.filter.all,
                source        = function() return tags end,
            },
            layout = wibox.layout.fixed.horizontal,
        },
        bg     = beautiful.bg_normal,
        widget = wibox.container.background
    }

    return w
end

local function gen_cls(c,results)
    local ret = setmetatable({},{__index = function(t,i)
            local ret2 = c[i]
            if type(ret2) == "function" then
                if i == "geometry" then
                    return function(self, val)
                        if val then
                            c:geometry(gtable.crush(c:geometry(), val))
                            -- Make a copy as the original will be changed
                            results[c] = gtable.clone(c:geometry())
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

local function fake_arrange(tag)
    local cls,results,flt = {},setmetatable({},{__mode="k"}),{}
    local s, l = tag.screen, tag.layout
    local focus, focus_wrap = capi.client.focus, nil
    for k,c in ipairs (tag:clients()) do
        -- Handle floating client separately
        if not c.minimized then
            local floating = c.floating
            if (not floating) and (l ~=  floating_l) then
                cls[#cls+1] = gen_cls(c,results)
                if c == focus then
                    focus_wrap = cls[#cls]
                end
            else
                flt[#flt+1] = gtable.clone(c:geometry())
                flt[#flt].c = c
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
        tag              = tag,
        screen           = 1,
        clients          = cls,
        focus            = focus_wrap,
        geometries       = setmetatable({}, {__mode = "k"}),
        workarea         = tag.screen.workarea,
        useless_gap      = tag.gaps or 4,
        apply_size_hints = false,
    }

    l.arrange(param)

    local ret = {}

    for _, geo_src in ipairs {param.geometries, flt } do
        for c, geo in pairs(geo_src) do
            geo.c = geo.c or c
            table.insert(ret, geo)
        end
    end

    return ret
end

local function gen_fake_clients(tag, args)
    local pager = wibox.widget.base.make_widget()

    function pager:fit()
        return 60, 48
    end

    if not tag then return end

    local sgeo = tag.screen.geometry

    local show_name = args.display_client_name or args.display_label

    function pager:draw(ctx, cr, w, h)
        if not tag.client_geo then return end

        for _, geom in ipairs(tag.client_geo) do
            local x      = (geom.x*w)/sgeo.width
            local y      = (geom.y*h)/sgeo.height
            local width  = (geom.width*w)/sgeo.width
            local height = (geom.height*h)/sgeo.height
            cr:set_source(color(geom.c.color or beautiful.bg_normal))
            cr:rectangle(x,y,width,height)
            cr:fill_preserve()
            cr:set_source(color(geom.c.border_color or beautiful.border_color))
            cr:stroke()

            if show_name and type(geom.c) == "table" and geom.c.name then
                cr:set_source_rgb(0, 0, 0)
                cr:move_to(x + 2, y + height - 2)
                cr:show_text(geom.c.name)
            end
        end

        -- Draw the screen outline.
        cr:set_source(color("#00000044"))
        cr:set_line_width(1.5)
        cr:set_dash({10,4},1)
        cr:rectangle(0, 0, w, h)
        cr:stroke()
    end

    return pager
end

local function gen_fake_pager_widget(tags, w2, args)
    local layout = gen_taglist_layout_proxy(tags, w2, "pager")
    layout.spacing = 10

    for _, t in ipairs(tags) do
        layout:add(wibox.widget {
            gen_fake_clients(t, args),
            widget        = wibox.container.background
        })
    end

    return layout
end

local function wrap_timeline(w, dot)
    return wibox.widget {
            gen_vertical_line(dot),
            {
                w,
                top     = dot and 5 or 0,
                bottom  = dot and 5 or 0,
                left    = 0,
                widget  = wibox.container.margin
            },
            layout = wibox.layout.fixed.horizontal
        }
end

local function gen_screen_widget(s)
    local ret = wibox.widget.base.make_widget()

    function ret:fit()
        -- Use a factor of 10.
        return s.geometry.width/10, x.geometry.height/10
    end

    function ret:draw(ctx, cr, w, h)
        -- Draw the screen outline
        cr:set_source(color("#00000044"))
        cr:set_line_width(1.5)
        cr:set_dash({10,4},1)
        cr:rectangle(s.geometry.x+0.75,s.geometry.y+0.75,s.geometry.width-1.5,s.geometry.height-1.5)
        cr:stroke()

        -- Draw the workarea outline
        cr:set_source(color("#00000033"))
        cr:rectangle(s.workarea.x,s.workarea.y,s.workarea.width,s.workarea.height)
        cr:stroke()
    end

    return ret
end

local function draw_info(s, cr, factor)
    cr:set_source_rgba(0, 0, 0, 0.4)

    local pctx    = PangoCairo.font_map_get_default():create_context()
    local playout = Pango.Layout.new(pctx)
    local pdesc   = Pango.FontDescription()
    pdesc:set_absolute_size(11 * Pango.SCALE)
    playout:set_font_description(pdesc)

    local rows = {
        "primary", "index", "geometry", "dpi", "dpi range", "outputs:"
    }

    local dpi_range = s.minimum_dpi and s.preferred_dpi and s.maximum_dpi
        and (s.minimum_dpi.."-"..s.preferred_dpi.."-"..s.maximum_dpi)
        or s.dpi.."-"..s.dpi

    local values = {
        s.primary and "true" or "false",
        s.index,
        s.x..":"..s.y.." "..s.width.."x"..s.height,
        s.dpi,
        dpi_range,
        "",
    }

    for n, o in pairs(s.outputs) do
        table.insert(rows, "  "..n)
        table.insert(values,
            math.ceil(o.mm_width).."mm x "..math.ceil(o.mm_height).."mm"
        )
    end

    local col1_width, col2_width, height = 0, 0, 0

    -- Get the extents of the longest label.
    for k, label in ipairs(rows) do
        local attr, parsed = Pango.parse_markup(label..":", -1, 0)
        playout.attributes, playout.text = attr, parsed
        local _, logical = playout:get_pixel_extents()
        col1_width = math.max(col1_width, logical.width+10)

        local attr, parsed = Pango.parse_markup(values[k], -1, 0)
        playout.attributes, playout.text = attr, parsed
        local _, logical = playout:get_pixel_extents()
        col2_width = math.max(col2_width, logical.width+10)

        height = math.max(height, logical.height)
    end

    local dx = (s.width*factor - col1_width - col2_width - 5)/2
    local dy = (s.height*factor - #values*height)/2 - height

    -- Draw everything.
    for k, label in ipairs(rows) do
        local attr, parsed = Pango.parse_markup(label..":", -1, 0)
        playout.attributes, playout.text = attr, parsed
        local _, logical = playout:get_pixel_extents()
        cr:move_to(dx, dy)
        cr:show_layout(playout)

        local attr, parsed = Pango.parse_markup(values[k], -1, 0)
        playout.attributes, playout.text = attr, parsed
        local _, logical = playout:get_pixel_extents()
        col2_width = math.max(col1_width, logical.width+10)
        cr:move_to( dx+col1_width+5, dy)
        cr:show_layout(playout)

        dy = dy + 5 + logical.height
    end
end

local function gen_ruler(h_or_v, factor, margins)
    local ret = wibox.widget.base.make_widget()

    function ret:fit(ctx, w, h)
        local rw, rh = root.size()
        rw, rh = rw*factor, rh*factor

        if h_or_v == "vertical" then
            w = 1
            h = rh + margins.top/2 + margins.bottom/2
        else
            w = rw + margins.left/2 + margins.right/2
            h = 1
        end

        return w, h
    end

    function ret:draw(ctx, cr, w, h)
        cr:set_source(color("#77000033"))
        cr:set_line_width(2)
        cr:set_dash({1,1},1)
        cr:move_to(0, 0)
        cr:line_to(w == 1 and 0 or w, h == 1 and 0 or h)
        cr:stroke()
    end

    return ret
end

-- When multiple tags are present, only show the selected tag(s) for each screen.
local function gen_screens(l, screens, args)
    local margins = {left=50, right=50, top=30, bottom=30}

    local ret = wibox.layout.manual()

    local sreen_copies = {}

    -- Keep a copy because it can change.
    local rw, rh = root.size()

    -- Find the current origin.
    local x0, y0 = math.huge, math.huge

    for s in screen do
        x0, y0 = math.min(x0, s.geometry.x), math.min(y0, s.geometry.y)
        local scr_cpy = gtable.clone(s.geometry, false)
        scr_cpy.outputs = gtable.clone(s.outputs, false)
        scr_cpy.primary = screen.primary == s

        for _, prop in ipairs {
          "dpi", "index", "maximum_dpi", "minimum_dpi", "preferred_dpi" } do
            scr_cpy[prop] = s[prop]
        end

        table.insert(sreen_copies, scr_cpy)
    end

    function ret:fit(ctx, w, h)
        w = margins.left+(x0+rw)/5 + 5 + margins.right
        h = margins.top +(y0+rh)/5 + 5 + margins.bottom
        return w, h
    end

    -- Add the rulers.
    for _, s in ipairs(sreen_copies) do
        ret:add_at(gen_ruler("vertical"  , 1/5, margins), {x=margins.left+s.x/5, y =margins.top/2})
        ret:add_at(gen_ruler("vertical"  , 1/5, margins), {x=margins.left+s.x/5+s.width/5, y =margins.top/2})
        ret:add_at(gen_ruler("horizontal", 1/5, margins), {y=margins.top+s.y/5, x =margins.left/2})
        ret:add_at(gen_ruler("horizontal", 1/5, margins), {y=margins.top+s.y/5+s.height/5, x =margins.left/2})
    end

    -- Print an outline for the screens
    for k, s in ipairs(sreen_copies) do
        s.widget = wibox.widget.base.make_widget()

        local wb = gen_fake_taglist_wibar(screens[k].tags, w2)
        wb.forced_width = s.width/5

        -- The clients have an absolute geometry, transform to relative.
        if screens[k].tags[1] then
            for _, geo in ipairs(screens[k].tags[1].client_geo) do
                geo.x = geo.x - s.x
                geo.y = geo.y - s.y
            end
        end

        local clients_w = gen_fake_clients(screens[k].tags[1], args)

        local content = wibox.widget {
            wb,
            clients_w,
            nil,
            layout       = wibox.layout.align.vertical,
            forced_width = s.width/5,
        }

        function s.widget:fit(ctx, w, h)
            return s.width/5, s.height/5
        end

        function s.widget:draw(ctx, cr, w, h)
            cr:set_source(color("#00000044"))
            cr:set_line_width(1.5)
            cr:set_dash({10,4},1)
            cr:rectangle(1,1,w-2,h-2)
            cr:stroke()

            if args.display_label ~= false then
                draw_info(s, cr, 1/5)
            end
        end

        function s.widget:after_draw_children(ctx, cr, w, h)
            if args.display_mouse and mouse.screen.index == s.index then
                local rel_x = mouse.coords().x - s.x
                local rel_y = mouse.coords().y - s.y
                draw_mouse(cr, rel_x/5+5, rel_y/5+5)
            end
        end

        function s.widget:layout(_, width, height)
            return { wibox.widget.base.place_widget_at(
                content, 0, 0, width, height
            ) }
        end

        ret:add_at(s.widget, {x=margins.left+s.x/5, y=margins.top+s.y/5})
    end

    l:add(wrap_timeline(wibox.widget {
        markup  = "<i>Current tags:</i>",
        opacity = 0.5,
        widget  = wibox.widget.textbox
    }, true))
    l:add(wrap_timeline(ret,false))
end

-- When a single screen is present, show all tags.
local function gen_noscreen(l, tags, args)
    local w2 = draw_lines()
    l:add(wrap_timeline(wibox.widget {
        markup  = "<i>Current screens:</i>",
        opacity = 0.5,
        widget  = wibox.widget.textbox
    }, true))

    local wrapped_wibar = wibox.widget {
        gen_fake_taglist_wibar(tags, w2),
        fill_space = false,
        layout = wibox.layout.fixed.horizontal
    }

    l:add(wrap_timeline(wrapped_wibar, false))

    if #capi.client.get() > 0 or args.show_empty then
        l:add(wrap_timeline(w2, false))
        l:add(wrap_timeline(gen_fake_pager_widget(tags, w2, args), false))
    end
end

local function gen_timeline(args)
    local l = wibox.layout.fixed.vertical()

    for _, event in ipairs(history) do
        local ret = event.callback()
        if event.event == "event" then
            l:add(wrap_timeline(wibox.widget {
                markup = "<u><b>"..event.description.."</b></u>",
                widget = wibox.widget.textbox
            }, true))
        elseif event.event == "tags" and #ret == 1 and not args.display_screen then
            gen_noscreen(l, ret[1].tags, args)
        elseif event.event == "tags" and (#ret > 1 or args.display_screen) then
            gen_screens(l, ret, args)
        end
    end

    return l
end

function module.display_tags()
    local function do_it()
        local ret = {}
        for s in screen do
            local st = {}
            for _, t in ipairs(s.tags) do
                -- Copy just enough for the taglist to work.
                table.insert(st, {
                    name                = t.name,
                    selected            = t.selected,
                    icon                = t.icon,
                    screen              = t.screen,
                    data                = t.data,
                    clients             = t.clients,
                    layout              = t.layout,
                    master_width_factor = t.master_width_factor,
                    client_geo          = fake_arrange(t),
                })
                assert(#st[#st].client_geo == #t:clients())
            end
            table.insert(ret, {tags=st})
        end
        return ret
    end

    table.insert(history, {event="tags", callback = do_it})
end

function module.add_event(description, callback)
    assert(description and callback)
    table.insert(history, {
        event       = "event",
        description = description,
        callback    = callback
    })
end

function module.execute(args)
    local widget = gen_timeline(args or {})
    require("gears.timer").run_delayed_calls_now()
    require("gears.timer").run_delayed_calls_now()
    require("gears.timer").run_delayed_calls_now()
    local w, h = widget:fit({dpi=96}, 9999,9999)
    wibox.widget.draw_to_svg_file(widget, image_path..".svg", w, h)
end

loadfile(file_path)(module)
