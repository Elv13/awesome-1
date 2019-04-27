-- The logic behind this template instead of calling things directly from the
-- tests is for this template to be able to reproduce the test multiple time
-- with multiple parameters without any boiler plate for the test itself.
--
-- Since this test framework has access to a nearly working shims backend, it
-- is much better placed to attempt to trigger the corner cases than busted.
-- The integration tests are also a bad place because they can't help the
-- documentation. While this feels like yet another fully fledged test framework
-- (and it is), it's the best way to test the layouts.

local file_path, image_path = ...
require("_common_template")(...)

local cairo      = require("lgi").cairo

local color     = require( "gears.color"    )
local shape     = require( "gears.shape"    )
local beautiful = require( "beautiful"      )
local wibox     = require( "wibox"          )
local titlebar  = require( "awful.titlebar" )
local hierarchy = require( "wibox.hierarchy")
local a_tag     = require( "awful.tag"      )
local a_screen  = require( "awful.screen"   )
local a_layout  = require( "awful.layout"   )
local g_geo     = require( "gears.geometry" )


-- This template is designed to also unit-test the layout in a rather precise
-- way. The tests can define the subset of asserts they expect to pass. This
-- avoid the massive code duplication of earlier versions. It also makes
-- this module mostly bullet proof regression wise.

-- PROPERTIES
-- screen_count  // the numbers of screen
-- row_count     // the number of rows in the screen grid
-- fill_space    // 100% of the workarea is taken
--   * enable_gap// Add the gap around the client when computing the used space
--   * enable_hints// TODO
-- no_overlap    // all client are in different places
-- full_overlap  // some client have the same geometry, but they must 100% overlap
-- is_symetric   // removing client restore the geo
-- test_removal  // automatically remove the clients one by one when quitting
-- allow_move    // the client can move when new are added (default: true)
-- deterministic // test everything twice, disallow "refresh" to change the geometry
-- swap_clients  // make sure swapping works
-- test_insertion_points //
-- test_maximization // toggle floating and ensure nothing moved
-- test_fullscreen // toggle floating and ensure nothing moved
-- test_minimize // toggle floating and ensure nothing moved
-- test_floating // toggle floating and ensure nothing moved
-- test_multi_state // toggle floating, then maximize, then fullscreen in
--   all possible order to make sure all combination work.
-- arrange_often // Add clients one by one and force `arrange` in between

--[[

template.describe {
    name = "foo";

    tests = {
        fill_space    = true; DONE
        enable_gap    = true;
        deterministic = true;
        no_overlap    = true; DONE
        full_overlap  = false; DONE
        is_symetric   = true;
        test_removal  = true;
        allow_move    = false;
        swap_clients  = true;
    };

    screens = {
        {count = 5, width = 42, height = 42}, -- row1
    };

    display = {
        focus          = false;
        client_name    = false;
        client_count   = true;
        show_insertion = false;
    };
}

template.add_client {
    name = foo;
}

]]

-- Monkey-patch the screen geometry to add more tests.
local get_bounding_geometry = a_screen.object.get_bounding_geometry
a_screen.object.get_bounding_geometry = function(self, args)
    local geo = get_bounding_geometry(self, args)

    -- If the tag has a geometry, assume it is right
    if args.tag then
        self = args.tag.screen
    end

    -- Extra validations to detect off-by-one
    if args.honor_workarea then
        local wa = self.workarea
        assert(wa)
        assert(wa.x <= geo.x)
        assert(wa.y <= geo.y)
        assert(wa.x+wa.width >= geo.x+geo.width)
        assert(wa.y+wa.height >= geo.y+geo.height)
    end

    return geo
end

-- Test if the number of clients wrapper is right and if they are there
-- only once.
local function test_wrapper_count(t)
    local l = t.layout

    local all_widget = l.widget:get_all_children()
    local cls, inv = {},{}
    for _, w in ipairs(all_widget) do
        if w._client then
            assert(not inv[w._client], "A client has multiple wrapper")
            inv[w._client] = w
            table.insert(cls, w._client)
        end
    end

    assert(
        #cls == #t:clients(),
        "The number of client wrapper does not match the number of clients"
    )
end

local function test_is_symetric()
    --TODO
    -- * make sure the snapshot is/are taken
    -- * force `arrange_often` to true
    -- * store all intermediate layouts disposition
    -- * kill the client in the opposite order of creation
    -- * compare the geometries in reverse order
end

local function test_maximize()
    --TODO maximize all clients in various order and make sure they are restored
end

local function test_minimize()
    --TODO minimize all clients in various order and make sure they are restored
end

-- Ensure that the dynamic layouts are instantiated correctly.
-- Also ensure the initialization takes into account the existing clients.
local function test_layout_creation(t, name)
    local l = t.layout

    -- Test if the right type of layout was created
    assert(l.name == name)

    -- Test is setlayout did create a stateful layout
    assert(l.is_dynamic)

    -- Test if the stateful layout track the right number of clients
    assert(#t:clients() == #l.wrappers)

    if #l.wrappers > 0 then
        local params = a_layout.parameters(
            t, #t:clients() > 0 and t:clients()[1].screen or nil
        )
    end

    -- Test if the tag state is correct
    assert(l.active)

    -- Test if the widget has been created
    assert(l.widget)
end

-- Test if the layout uses all the space. This helps with off-by-one rounding
-- errors.
local function test_fill_space(s, t)
    s = screen[s]
    local l, gap, pad, wa = t.layout, t.gap/2, s.padding, s.workarea

    -- Apply the padding
    wa.x, wa.y = wa.x + pad.left, wa.y + pad.top
    wa.width, wa.height = wa.width - pad.left - pad.right, wa.height - pad.top - pad.bottom

    local s_sum, c_sum = wa.width * wa.height, 0

    assert(l and gap and pad, "The shims are broken")

    --TODO check if all WA corners have a client edge

    for _, c in ipairs(t:clients()) do
        local geo, bw = c:geometry(), c.border_width

        -- Apply the decoration
        geo.width, geo.height = geo.width+2*gap+2*bw, geo.height+2*gap+2*bw

        -- Check the workarea boundaries
        if l.honor_workarea then
            assert(geo.x >= wa.x, "The layout `x` is out of bound ("..geo.x.." < "..wa.x..")")
            assert(geo.y >= wa.y, "The layout `y` is out of bound ("..geo.y.." < "..wa.y..")")
        else
            assert(false)--TODO
        end

        assert(geo.x+geo.width  <= wa.x+wa.width , "The layout is too large."..
            " Got "..(geo.x+geo.width)..", Expected at most "..(wa.x+wa.width)
        )

        assert(geo.y+geo.height <= wa.y+wa.height,
            "The layout is too tall. Got "..(geo.y+geo.height)..
            ", Expected at most "..(wa.y+wa.height)
        )

        c_sum = c_sum + ( geo.width * geo.height )
    end

--     assert(
--         s_sum == c_sum,
--         "The layouts declare it fills the space, yet it does not. "..
--         "Expected "..s_sum..", got "..c_sum
--     ) --FIXME There is left over space. Probably rounding issues or misapplied border_width
end

-- Ensure no client overlap another
local function test_overlap(s, t, allow_complete)
    local gap = t.gap/2

    local rects = {}

    -- First, make sure the screens don't overlap, because it is unsupported
    -- and will make the test below fail due to reasons unrelated to the code
    -- it attempt to test
    for _, s1 in ipairs(screen) do
        for _, s2 in ipairs(screen) do
            if s1 ~= s2 then
                local int = g_geo.rectangle.get_intersection(s1.geometry, s2.geometry)
                assert(int.width == 0 and int.height == 0)
            end
        end
    end

    for _, c in ipairs(t:clients()) do
        local geo, bw = c:geometry(), c.border_width

        -- Apply the decoration
        geo.width, geo.height = geo.width+2*gap+2*bw, geo.height+2*gap+2*bw

        for _, r in ipairs(rects) do
            local int = g_geo.rectangle.get_intersection(geo, r)

            -- Some stacked layouts like max and full screen allow "perfect" overlapping
            if allow_complete and (int.width > 0 or int.height > 0) then
                for _, v in ipairs {"x", "y", "width", "height" } do
                    assert(
                        r[v] == geo[v] and geo[v] == int[v],
                        "Only fully overlapping are accepted"
                    )
                end
            else
                assert(
                    int.width == 0 and int.height == 0,
                    "No overlap is enabled, but the client do overlap at "..int.x..", "..int.y
                )
            end
        end

        table.insert(rects, geo)
    end
end

local properties = {
    layout      = nil;
    name        = nil;
    layout_name = nil;
    test        = { };
    steps       = { };
    init_steps  = { };
    tags        = { };
    view        = { };
    has_init    = false;
}

function properties.screens(value)
    table.insert(properties.init_steps, function()
        local rows = {}

        for i=1, #value do
            table.insert(rows, value[i].count or 1)
        end

        local r = value[1] --TODO support multiple rows
        screen._setup_grid(r.width, r.height, rows, r.args)

        -- Create the tags
        for i=1, screen.count() do
            properties.tags[screen[i]] = a_tag.add("Test"..i, {
                screen   = screen[i],
                selected = true
            })
        end
    end)
end

function properties.tag_properties(value)
    table.insert(properties.init_steps, function()
        for i=1, screen.count() or 1 do
            local s = screen[i]
            local t = properties.tags[s]
            for k, v in pairs(value) do
                t[k] = v
            end
        end
    end)
end

-- Make the test syntax as simple and readable as possible.
-- Use some metatable magic
local function newindex(_, key, value)
    if type(properties[key]) == "function" then
        properties[key](value)
    else
        rawset(properties, key, value)
    end
end

local module = {
    display = { }
}

function module.add_step(f)
    table.insert(properties.steps, f)
end

function module.add_clients(args)
    module.add_step(function()
        local s    = screen[args.screen or 1]
        local x, y = s.geometry.x, s.geometry.y

        assert(x and y, "The shims are broken")

        for i=1, args.count or 1 do
            client.gen_fake {
                x      = x  + (args.x      or s.workarea.x),
                y      = y  + (args.y      or s.workarea.y),
                width  = 40 + (args.width  or 1           ),
                height = 30 + (args.height or 1           ),
                screen = s,
            }:_hide()
        end
    end)
end

function module.remove_client(c)
    assert(c)
    module.add_step(function()
        c:kill()
    end)
end

function module.set_tag_property(s, name, value)
    assert(s and name)
    module.add_step(function()
        local t = properties.tags[screen[s]]
        assert(t)
        t[name] = value
    end)
end

function module.resize(args)
    assert(args and args.client)
    assert(args.delta or args.geometry)
    --TODO
end

function module.set_layout(args)
    assert(args.screen, "Please set the `screen` argument when calling set_layout")
    assert(args.layout, "Please set the `layout` argument when calling set_layout")
    properties._layout = value
    module.add_step(function()
        local t = properties.tags[screen[args.screen]]
        assert(t, "The screen is invalid")

        t.layout = args.layout
        test_layout_creation(t, args.layout_name or properties.layout_name)
        test_wrapper_count(t)
    end)
end

function module.arrange(args)
    args = args or {}
    module.add_step(function()
        for i= args.screen or 1, args.screen or screen.count() do
            local s = screen[i]
            local t = properties.tags[s]
            assert(s and s.valid, "The screen is invalid")
            assert(t and t.screen == s and t.selected, "The tag is invalid")
            local params = a_layout.parameters(t, s)
            t.layout.arrange(params)

            -- This also has some delayed calls
            for _ = 1, 5 do
                require("gears.timer").run_delayed_calls_now()
            end

            if properties.test.fill_space ~= false then
                test_fill_space(i, t)
            end
            if properties.test.no_overlap ~= false then
                test_overlap(i, t, properties.test.full_overlap)
            end
        end

    end)
end

local function run_test(steps)
    for _, step in ipairs(steps) do
        step()
    end
end

function module.init_now()
    if not properties.has_init then

        for _, step in ipairs(properties.init_steps) do
            step()
        end

        properties.has_init = true
    end
end

-- The meta version of the default "here is what it looks like when property X
-- changes" to avoid copy pasting the same code everywhere.
function module.meta(args)
    module.init_now()

    assert(args.mode, "Use a mode (\"tag\", \"layouts\" or \"screen\")")

    assert(
        args.property or args.layouts or args.mode == "scaling",
        "Set a property like `gap` or `master_width_factor`)"
    )

    assert(
        (args.values and #args.values == screen.count()) or
            args.layouts or
            args.mode == "scaling"
    )

    assert(args.layout or (args.layouts and #args.layouts == screen.count()))

    local delta = 1
    for i= args.start_screen or 1, args.stop_screen or screen.count() do
        local s = screen[i]
        local t = properties.tags[s]

        module.set_layout {
            screen = i;
            layout = args.layout or args.layouts[i];
            layout_name = args.layout_name or
                args.layout_names and args.layout_names[i] or nil
        }

        if args.mode == "tag" then
            t[args.property] = args.values[i]
        elseif args.mode == "screen" then
            s[args.property] = args.values[i]
        end

        if not properties.test.arrange_often then
            module.add_clients {
                x      = 0;
                y      = 0;
                width  = 35;
                height = 35;
                count  = args.mode == "scaling" and delta or args.count or 4;
                screen = i,
            }
        end

        delta = delta + 1
    end
end

-- This will execute all steps as many time as required to check all corner cases

function module.run()
    assert(properties.name       , "Please set the name before calling run"       )
    assert(properties.layout_name, "Please set the layout_name before calling run")
    assert(next(properties.test) , "Please define the tests to be executed"       )
    assert(#properties.steps > 0 , "There is nothing to do"                       )

    -- Declaring some tests to be executed is mandatory, but apply the defaults
    -- anyway. this avoid having to modify all the file when a new set is added
    --TODO

    for i=1, screen.count() do
        local s = screen[i]
        local t = properties.tags[s]
        assert(s, "The shims are broken")
        assert(t, "The shims are broken")
    end

    run_test(properties.steps)

    test_minimize()
    test_maximize()

    if properties.test.is_symetric then
        test_is_symetric()
    end
end

module = setmetatable(module, {__newindex = newindex, __index = properties})

-- Run the test
local args = loadfile(file_path)(module) or {}

-- Emulate the event loop for 5 iterations
for _ = 1, 5 do
    require("gears.timer").run_delayed_calls_now()
end

-- Draw the result
local label_x_offset = module.display.row_label_callback and 0 or 0
local label_y_offset = module.display.column_label_callback and 20 or 0
local ext_w, ext_h = screen._get_extents()
ext_w, ext_h = ext_w + label_x_offset, ext_h + label_y_offset

local img = cairo.SvgSurface.create(image_path..".svg", ext_w, ext_h)
local cr  = cairo.Context(img)

local function wrap_titlebar(tb, width, height)
    return wibox.widget {
        tb.drawable.widget,
        bg            = tb.args.bg_normal,
        fg            = tb.args.fg_normal,
        forced_width  = width,
        forced_height = height,
        widget        = wibox.container.background
    }
end

local function client_widget(c, col, label)
    local geo = c:geometry()
    local bw = c.border_width or beautiful.border_width or 0

    local l = wibox.layout.align.vertical()
    l.fill_space = true

    local tbs = c._private and c._private.titlebars or {}

    local map = {
        top    = "set_first",
        left   = "set_first",
        bottom = "set_third",
        right  = "set_third",
    }

    for _, position in ipairs{"top", "bottom"} do
        local tb = tbs[position]
        if tb then
            l[map[position]](l, wrap_titlebar(tb, c:geometry().width, tb.args.height or 16))
        end
    end

    for _, position in ipairs{"left", "right"} do
        local tb = tbs[position]
        if tb then
            l[map[position]](l, wrap_titlebar(tb, tb.args.width or 16, c:geometry().height))
        end
    end

    local l2 = wibox.layout.align.horizontal()
    l2.fill_space = true
    l:set_second(l2)
    l.forced_width  = c.width
    l.forced_height = c.height

    return wibox.widget {
        {
            {
                l,
                margins = bw + 1, -- +1 because the the SVG AA
                layout  = wibox.container.margin
            },
            {
                text   = label or "",
                align  = "center",
                valign = "center",
                widget = wibox.widget.textbox
            },
            layout = wibox.layout.stack
        },
        shape_border_width = bw*2,
        shape_border_color = beautiful.border_color,
        shape_clip         = true,
        fg                 = beautiful.fg_normal or "#000000",
        bg                 = col,
        forced_width       = geo.width  + 2*bw,
        forced_height      = geo.height + 2*bw,
        shape              = function(cr2, w, h)
            return shape.rounded_rect(cr2, w, h, args.radius or module.display.radius or 5)
        end,

        widget = wibox.container.background,
    }
end

-- Remove duplicates
local function clean_old_geo(c)
    local ret, prev = {}, nil
    for _, geo in ipairs(c._old_geo) do
        if not prev then
            table.insert(ret, geo)
        elseif not (
        prev.x == geo.x and
        geo.y == prev.y and
        prev.width == geo.width and
        prev.height == geo.height) then
            table.insert(ret, geo)
        end
        prev = geo
    end

    c._old_geo = ret
end

function module.take_snapshot()
    -- Print an outline for the screens
    for _, s in ipairs(screen) do
        cr:save()
        -- Draw the screen outline
        cr:set_source(color("#00000044"))
        cr:set_line_width(1.5)
        cr:set_dash({10,4},1)
        cr:rectangle(
            s.geometry.x+0.75 + label_x_offset,
            s.geometry.y+0.75 + label_y_offset,
            s.geometry.width-1.5,
            s.geometry.height-1.5
        )
        cr:stroke()

        -- Draw the workarea outline
        cr:set_source(color("#00000033"))
        cr:rectangle(
            s.workarea.x + label_x_offset,
            s.workarea.y + label_y_offset,
            s.workarea.width,
            s.workarea.height
        )
        cr:stroke()

        -- Draw the padding outline
        --TODO
        cr:restore()
    end

    cr:set_line_width(beautiful.border_width)
    cr:set_source(color(beautiful.border_color))

    local rect = {x1 = 0 ,y1 = 0 , x2 = 0 , y2 = 0}

    -- Get the region with wiboxes
    for _, obj in ipairs {drawin, client} do
        for _, d in ipairs(obj.get()) do
            local w = d.get_wibox and d:get_wibox() or d
            if w and w.geometry then
                local geo = w:geometry()
                rect.x1 = math.min(rect.x1, geo.x                                       )
                rect.y1 = math.min(rect.y1, geo.y                                       )
                rect.x2 = math.max(rect.x2, geo.x + geo.width  + 2*(w.border_width or 0))
                rect.y2 = math.max(rect.y2, geo.y + geo.height + 2*(w.border_width or 0))
            end
        end
    end

    local total_area = wibox.layout {
        forced_width  = rect.x2 + label_x_offset,
        forced_height = rect.y2 + label_y_offset,
        layout        = wibox.layout.manual,
    }

    -- Add the labels
    if module.display.column_label_callback then
        for k, s in ipairs(screen) do
            local label = module.display.column_label_callback(k)
            local geo   = s.geometry

            local tb = wibox.widget {
                {
                    markup        = label;
                    align         = "center";
                    forced_width  = geo.width,
                    widget        = wibox.widget.textbox
                };
                fg     = "#4A4A4A",
                widget = wibox.container.background
            }

            total_area:add_at(
                tb,
                {x=geo.x, y=geo.y}
            )
        end
    end

    -- Add all wiboxes

    -- Fix the wibox geometries that have a dependency on their content
    for _, d in ipairs(drawin.get()) do
        local w = d.get_wibox and d:get_wibox() or nil
        if w then
            -- Force a full layout first as widgets with as the awful.popup have
            -- interdependencies between the content and the container
            if w._apply_size_now then
                w:_apply_size_now()
            end
        end
    end

    -- Emulate the event loop for another 5 iterations
    for _ = 1, 5 do
        require("gears.timer").run_delayed_calls_now()
    end

    for _, d in ipairs(drawin.get()) do
        local w = d.get_wibox and d:get_wibox() or nil
        if w then
            local geo = w:geometry()
            total_area:add_at(w:to_widget(), {x = geo.x, y = geo.y})
        end
    end

    local for_screen = {}

    -- Loop each clients geometry history and paint it
    for idx, c in ipairs(client.get()) do
        if not c.minimized then
            local pgeo = nil
            clean_old_geo(c)
            local geos = properties.view.show_old == false
                and c._old_geo[#c._old_geo] or c._old_geo

            for _, geo in ipairs(c._old_geo) do
                if not geo._hide then

                    if properties.view.index_client then
                        for_screen[c.screen] = for_screen[c.screen]
                            and (for_screen[c.screen] + 1) or 1
                        geo._label = for_screen[c.screen]
                    end

                    total_area:add_at(
                        client_widget(c, c.color or geo._color or beautiful.bg_normal, geo._label),
                        {x=geo.x + label_x_offset, y=geo.y + label_y_offset}
                    )
                end

                pgeo = geo
            end
        end
    end

    -- Draw the wiboxes/clients on top of the screen
    wibox.widget.draw_to_cairo_context(
        total_area, cr, screen._get_extents()
    )

    cr:set_source_rgba(1,0,0,1)
    cr:set_dash({1,1},1)

    -- Paint the mouse cursor position history
    for _, h in ipairs(mouse.old_histories) do
        local pos = nil
        for _, coords in ipairs(h) do
            cr:fill()

            if pos then
                cr:move_to(pos.x, pos.y)
                cr:line_to(coords.x, coords.y)
                cr:stroke()
            end

            pos = coords
        end
    end

    img:finish()
end
module.take_snapshot()

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
