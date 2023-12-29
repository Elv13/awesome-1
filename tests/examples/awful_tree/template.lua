local filepath, svgpath = ...
require("_common_template")(...)

local atree     = require("awful.tree")
local wibox     = require("wibox")
local gshape    = require("gears.shape")
local gcolor    = require("gears.color")
local gtable    = require("gears.table")
local beautiful = require("beautiful")
local surface   = require("gears.surface")
local proj      = require("_3d_projection")
local cairo     = require("lgi").cairo
local unpack    = unpack or table.unpack -- luacheck: globals unpack

local spacing        = 40
local column_margin  = 3
local line_width     = 1.5
local column_indent  = 10
local tree_spacing   = 10
local indicator_size = 10

local faded_bg = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.bg_normal, 0.3))
local faded_fg = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.fg_normal, 0.6))
local extra_lbl_arrow = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.bg_highlight, 0.5))

local trees = {}

local canvas = wibox.layout.manual()

local function get_surface(p)
    local img = cairo.SvgSurface.create(p, 288, 76)
    return cairo.Context(img)
end

-- To avoid curves intersection overlap, move the middle.
--
-- This avoid math.rand so the generation is the same each time.
local random_counter = 1

-- Have a global color for each client.
local client_highlight_colors = {}

local function get_curve_offset(random)
    return random and
        ((random_counter % 2 > 0 and -1 or 1) * 3 * (random_counter % 3)) or
        0
end

local function generate_bezier_cubics(cr, pt1, pt2, random, vertical, start, ending)
    pt1, pt2 = gtable.clone(pt1), gtable.clone(pt2)

    local start_shape_size, end_shape_size = start == "dot" and 2.5 or 0, ending == "dot" and 2.5 or 10

    if pt1.y > pt2.y and vertical then
        start_shape_size, end_shape_size = end_shape_size, start_shape_size
    end

    local straight_line_length = math.max(start_shape_size, end_shape_size)/2

    for _, comp in ipairs { "x", "y" } do
        pt1[comp], pt2[comp] = math.max(0, pt1[comp]), math.max(0, pt2[comp])
        local min, max = math.min(pt1[comp], pt2[comp]), math.max(pt1[comp], pt2[comp])
        local is_equal = (max - min) <= 4*line_width
        local median   = min + (max - min)/2
        if is_equal then
            pt1[comp], pt2[comp] = median, median
        end
    end

    -- Make sure the line goinf into the arrow if straight.
    if vertical then
        if start == "dot" then
            cr:arc(pt1.x, pt1.y, end_shape_size, 0, 2*math.pi)
            cr:fill()
        end

        cr:line_to(pt1.x, pt1.y + straight_line_length)
        pt1.y = pt1.y + straight_line_length
        pt2.y = pt2.y - straight_line_length
    else
        cr:line_to(pt1.x + straight_line_length, pt1.y)
        pt1.x = pt1.x + straight_line_length
        pt2.x = pt2.x - straight_line_length
    end


    -- Split the curve in half so the pseudo random x-offset can be applied.
    local middle = {
        x = (math.max(pt1.x, pt2.x) - math.min(pt1.x, pt2.x))/2 + get_curve_offset(random),
        y = (math.max(pt1.y, pt2.y) - math.min(pt1.y, pt2.y))/2,
    }

    if vertical then
        if pt1.x ~= pt2.x then
            cr:curve_to(
                --[[x1]] pt1.x,
                --[[y1]] middle.y,
                --[[x2]] middle.x,
                --[[y2]] middle.y,
                --[[x3]] middle.x,
                --[[y3]] middle.y
            )
            cr:curve_to(
                --[[x1]] middle.x,
                --[[y1]] middle.y,
                --[[x2]] pt2.x,
                --[[y2]] middle.y,
                --[[x3]] pt2.x,
                --[[y3]] pt2.y - end_shape_size
            )
        end
        pt2.y = pt2.y + straight_line_length
        cr:line_to(pt2.x, pt2.y - end_shape_size)
    else
        if pt1.y ~= pt2.y  then
            cr:curve_to(
                --[[x1]] middle.x,
                --[[y1]] pt1.y,
                --[[x2]] middle.x,
                --[[y2]] middle.y,
                --[[x3]] middle.x,
                --[[y3]] middle.y
            )
            cr:curve_to(
                --[[x1]] middle.x,
                --[[y1]] middle.y,
                --[[x2]] middle.x,
                --[[y2]] pt2.y,
                --[[x3]] pt2.x - end_shape_size,
                --[[y3]] pt2.y
            )
        end
        pt2.x = pt2.x + straight_line_length
        cr:line_to(pt2.x - end_shape_size, pt2.y)
    end

    cr:stroke()

    -- Make sure the line goinf into the arrow if straight.
    if ending == "dot" then
        cr:arc(pt2.x, pt2.y, end_shape_size, 0, 2*math.pi)
        cr:fill()
    elseif ending == "arrow" then
        if vertical then
            if pt2.y < pt1.y then
                cr:move_to(pt2.x - start_shape_size/2, pt2.y)
                cr:line_to(pt2.x + start_shape_size/2, pt2.y)
                cr:line_to(pt2.x, pt2.y - start_shape_size)
                cr:line_to(pt2.x - start_shape_size/2, pt2.y)
            else
                cr:move_to(pt2.x - end_shape_size/2, pt2.y - end_shape_size)
                cr:line_to(pt2.x + end_shape_size/2, pt2.y - end_shape_size)
                cr:line_to(pt2.x, pt2.y)
                cr:line_to(pt2.x - end_shape_size/2, pt2.y - end_shape_size)
                cr:close_path()
            end
        else
            cr:move_to(pt2.x - end_shape_size, pt2.y - end_shape_size/2)
            cr:line_to(pt2.x, pt2.y)
            cr:line_to(pt2.x - end_shape_size, pt2.y + end_shape_size/2)
            cr:line_to(pt2.x - end_shape_size, pt2.y - end_shape_size/2)
            cr:close_path()
        end

        cr:fill()
    end


    random_counter = random_counter + 1
end

local function line_widget_factory(args)
    return wibox.widget {
        fit = function()
            return math.max(args.width, line_width*1.5), math.max(args.height, line_width*1.5)
        end,
        draw = function(_,_, cr)
            local lw = args.line_width or line_width

            -- Avoid the complexity of `translate` for the line width and the negative
            -- arrow offset.
            cr:reset_clip()

            if args.dash then
                cr:set_dash(unpack(args.dash))
            end

            local pt1 = {
                x = args.left and args.width or 0,
                y = args.up and args.height or 0
            }

            local pt2 = {
                x = args.left and 0 or args.width,
                y = args.up and 0 or args.height,
            }

            cr:set_source(gcolor(args.color or beautiful.border_color))
            cr:set_line_width(lw)
            cr:move_to(pt1.x, pt1.y)

            generate_bezier_cubics(cr, pt1, pt2, args.random, args.vertical, args.start, args.ending)
        end,
    }
end

local function widget_factory(node)
    local lbl = node.parent and node.label or "root"
    local wdg = wibox.widget {
        {
            {
                markup = "<b>"..lbl.."</b>",
                widget = wibox.widget.textbox,
            },
            margins = {
                left   = 10,
                right  = 10,
                top    = 1,
                bottom = 1,
            },
            widget = wibox.container.margin,
        },
        border_width = 1.5,
        border_color = beautiful.border_color,
         border_strategy = "inner",
        --bg           = beautiful.bg_normal,
        fg           = beautiful.fg_normal,
        shape        = gshape.rounded_bar,
        widget       = wibox.container.background
    }

    return wdg
end

local function added_widget()
    return wibox.widget {
        {
            shape        = gshape.cross,
            color        = "green",
            forced_width = 10,
            widget       = wibox.widget.separator
        },
        wibox.widget {
            fit = function(_, _, w, h)
                return w, h
            end,
            draw = function(_,_, cr, w, h)
                cr:set_source(gcolor("green"))
                cr:set_line_width(line_width)
                cr:set_dash({4, 1}, 1)
                cr:move_to(2, h/2)
                cr:line_to(w, h/2)
                cr:stroke()
            end,
        },
        widget = wibox.layout.fixed.horizontal
    }
end

local function removed_widget()
    return wibox.widget {
        wibox.widget {
            fit = function(_, _, w, h)
                return w-10, h
            end,
            draw = function(_,_, cr, w, h)
                cr:set_source(gcolor(beautiful.bg_urgent))
                cr:set_line_width(line_width)
                cr:set_dash({4, 1}, 1)
                cr:move_to(2, h/2)
                cr:line_to(w, h/2)
                cr:stroke()
            end,
        },
        wibox.widget {
            fit = function(_, _, w, h)
                return 10, h
            end,
            draw = function(_,_, cr, w, h)
                cr:set_source(gcolor(beautiful.bg_urgent))
                cr:set_line_width(line_width)
                cr:move_to(0, 0)
                cr:line_to(w, h)
                cr:stroke()
                cr:move_to(0, h)
                cr:line_to(w, 0)
                cr:stroke()
            end,
        },
        widget = wibox.layout.fixed.horizontal,
    }
end

local get_size
get_size = function(node, columns_width, depth, metadatas)
    if not node then return depth end

    local max_depth = depth

    for sib_node in atree.iterate_next_sibling(node, true) do
        assert(node._private and (node._private.siblings or node._mapping))

        local wdg = widget_factory(sib_node)
        local w, h = wdg:fit({dpi=96}, 9999, 9999)

        columns_width[depth] = math.max(columns_width[depth] or 0, w)

        table.insert(metadatas, {
            previous     = sib_node.previous,
            next         = sib_node.next,
            has_children = sib_node.first_child,
            node         = sib_node,
            widget       = wdg,
            column       = depth,
            lines        = {},
            position     = {
                width  = w,
                height = h,
            },
        })

        if sib_node.first_child then
            local d =  get_size(sib_node.first_child, columns_width, depth + 1, metadatas)
            max_depth = math.max(max_depth, d)
        end
    end

    return max_depth
end

local function compute_line(color, target, pos1, pos2)
    local w = math.ceil((pos2.x+(pos2.width/2)) - (pos1.x+(pos1.width/2)))
    local h = pos2.y - pos1.y - pos1.height
    table.insert(target.lines, {
        widget = line_widget_factory {
            width    = w,
            height   = h,
            vertical = true,
            start    = "dot",
            ending   = "dot",
            color    = color,
        },
        x      = pos1.x+math.floor(pos1.width/2),
        y      = pos1.y+pos1.height,
    })
end

local add_lines
add_lines = function(color, node_to_metadata, node, parent)
    if not node then return end

    local prev = nil

    -- Diagonal between parent and first_child.
    if parent then
        local pos1, pos2 = node_to_metadata[parent].position, node_to_metadata[node].position
        compute_line(color, node_to_metadata[parent], pos1, pos2)
    end

    -- Vertical between siblings.
    for sib_node in atree.iterate_next_sibling(node, true) do
        if prev then
            local pos1, pos2 = node_to_metadata[prev].position, node_to_metadata[sib_node].position
            compute_line(color, node_to_metadata[prev], pos1, pos2)
        end

        if sib_node.first_child then
            add_lines(color, node_to_metadata, sib_node.first_child, sib_node)
        end

        prev = sib_node
    end

end

local function get_metadata(args)
    local columns_width, metadatas, column_position = {}, {}, {0}
    local max_x, max_y = 0, 0

    get_size(args.tree, columns_width, 1, metadatas)

    local node_to_metadata = {}

    for col, width in ipairs(columns_width) do
        column_position[col+1] = (column_position[col] or 0) + math.ceil(width/2) + column_indent
    end

    for idx, metadata in ipairs(metadatas) do
        metadata.position.y = (idx-1)*spacing
        metadata.position.x = column_position[metadata.column] + column_margin*(metadata.column - 1)
        max_x = math.max(max_x, metadata.position.x + metadata.position.width)
        max_y = math.max(max_y, metadata.position.y + metadata.position.height)
    end

    for _, metadata in ipairs(metadatas) do
        node_to_metadata[metadata.node] = metadata
    end

    add_lines(args.arrows and faded_bg or beautiful.border_color, node_to_metadata, args.tree)

    return metadatas, node_to_metadata, columns_width, max_x, max_y
end

local x0, y0, trees = 0, 40, {}

local function add_tree(args)
    local tree = args.tree
    local metadatas, map, columns_width, max_x, max_y = get_metadata(args)

    -- Add extra labels, if any.
    local label_max_width = 0
    local prod_offset     = 0

    -- Add an extra column section with some pango markup text.
    if args.node_labels then
        -- Use `awful.tree.next` to make the SVG order stable.
        for node in atree.iterate_next(tree, true) do
            if args.node_labels[node] then
                local metadata = nil

                for _, mt in ipairs(metadatas) do
                    if mt.node == node then
                        metadata = mt
                        break
                    end
                end

                if metadata then
                    metadata.label_widget = wibox.widget {
                        markup = '<span color="'..extra_lbl_arrow..'">➜  </span>'
                            .. args.node_labels[node],
                        widget = wibox.widget.textbox
                    }

                    local w = metadata.label_widget:fit({dpi=96},9999, 9999)
                    label_max_width = math.max(label_max_width, w)
                end
            end
        end
    end

    -- Align the nodes to the column center.
    for _, metadata in ipairs(metadatas) do
        local w = metadata.widget:fit({dpi=96},9999, 9999)
        local offset = math.floor((columns_width[metadata.column] - w) / 2)

        for _, line in ipairs(metadata.lines) do
            line.x = line.x + offset
        end

        metadata.position.x = metadata.position.x + offset
    end

    -- Add the 3D projection.
    if args.project then
        local projection = proj {
            show_table           = false,
            tree                 = args.tree,
            horizontal_grid_size = 12,
        }
        canvas:add_at(projection, {
            x = x0,
            y = y0,
        })

        prod_offset = select(2, projection:fit({dpi=96},9999, 9999))
        for c, col in pairs(projection.client_colors) do
            local r,g,b = math.ceil(col[1]*255), math.ceil(col[2]*255), math.ceil(col[3]*255)
            client_highlight_colors[c] = string.format("#%x%x%x", r, g, b)
        end
    end

    -- Add the nodes.
    for _, metadata in ipairs(metadatas) do
        for _, line in ipairs(metadata.lines) do
            canvas:add_at(line.widget, {
                x = x0 + line.x,
                y = y0 + prod_offset + line.y
            })
        end

        -- Make the iterator path easier to see.
        if args.arrows then
            metadata.widget.border_color = faded_bg
            metadata.widget.fg           = faded_fg
        end

        if client_highlight_colors[metadata.node.client] then
            metadata.widget.bg =
                client_highlight_colors[metadata.node.client] .. "22"
        end

        canvas:add_at(metadata.widget, {
            x = x0 + metadata.position.x,
            y = y0 + prod_offset + metadata.position.y
        })

        if metadata.label_widget then
            canvas:add_at(metadata.label_widget, {
                x = x0 + max_x + 3*column_margin,
                y = y0 + prod_offset + metadata.position.y
            })
        end
    end

    -- Add the overlay arrows.
    if args.arrows then
        for _, arrow in ipairs(args.arrows) do
            local from_mt, to_mt

            for _, mt in ipairs(metadatas) do
                if mt.node == arrow.from then
                    from_mt = mt
                end
                if mt.node == arrow.to then
                    to_mt = mt
                end
            end

            if from_mt and to_mt then
                local pos_from, pos_to = from_mt.position, to_mt.position

                from_mt.widget.border_color = beautiful.bg_urgent
                to_mt.widget.border_color   = beautiful.bg_urgent
                from_mt.widget.fg           = beautiful.fg_normal
                to_mt.widget.fg             = beautiful.fg_normal

                local pt1 = {
                    x = math.floor(pos_from.x + pos_from.width /2),
                    y = math.floor(pos_from.y + pos_from.height/2),
                }

                local pt2 = {
                    x = math.floor(pos_to.x + pos_to.width /2),
                    y = math.floor(pos_to.y + pos_to.height/2),
                }

                local wdg = line_widget_factory {
                    width      = math.max(pt2.x, pt1.x) - math.min(pt2.x, pt1.x),
                    height     = math.max(pt2.y, pt1.y) - math.min(pt2.y, pt1.y) - 20,
                    up         = pt2.y < pt1.y,
                    left       = pt2.x < pt1.x,
                    color      = beautiful.bg_urgent,
                    dash       = { {4, 2}, 1 },
                    vertical   = true,
                    line_width = 3,
                    ending     = "arrow",
                }

                canvas:add_at(wdg, {
                    x = x0 + math.min(pt2.x, pt1.x),
                    y = y0 + prod_offset + math.min(pt2.y, pt1.y) + 10,
                })
            elseif to_mt then
                to_mt.widget.border_color = beautiful.bg_urgent
                to_mt.widget.fg           = beautiful.fg_normal
            end
        end
    end

    max_x = max_x + label_max_width + 3*column_margin

    canvas.forced_width  = x0 + max_x + 2*line_width
    canvas.forced_height = math.max(
        y0 + prod_offset + max_y + 2*line_width + indicator_size,
        canvas.forced_height or 0
    )

    -- Store so we can compare the trees later.
    table.insert(trees, {
        x               = x0,
        y               = y0 + prod_offset,
        label_max_width = label_max_width,
        label           = args.label,
        mapping         = map,
        columns_width   = columns_width,
        width           = max_x,
        height          = max_y,
        metadatas       = metadatas,
    })
    x0 = x0 + max_x + tree_spacing
end

loadfile(filepath)(add_tree)

-- Add separators.
for i=2, #trees do
    canvas:add_at(wibox.widget.separator { opacity = 0.4 }, {
        x      = trees[i].x - tree_spacing,
        y      = tree_spacing/2,
        width  = tree_spacing,
        height = canvas.forced_height - tree_spacing
    })
end

-- Add the label.
for _, tree in ipairs(trees) do
    local wdg = wibox.widget {
        markup    = tree.label,
        wrap      = true,
        ellipsize = "none",
        widget    = wibox.widget.textbox
    }

    local h = wdg:get_height_for_width(tree.width)

    wdg.forced_width  = tree.width
    wdg.forced_height = h
    canvas:add_at(wdg, { x = tree.x, y = 0 })
end

-- Draw the position change indicators.
for i=2, #trees do
    -- Add the `+` in front of new nodes.
    for node, new_mt in pairs(trees[i].mapping) do
        if not trees[i-1].mapping[node] then
            new_mt.widget.border_color = "green"
            canvas:add_at(added_widget(), {
                x      = trees[i].x + new_mt.position.x - 20,
                y      = trees[i].y + new_mt.position.y + math.floor(new_mt.position.height/2) - 5,
                width  = 20,
                height = 10,
            })
        end
    end

    for node, old_mt in pairs(trees[i-1].mapping) do
        local new_mt = trees[i].mapping[node]

        if new_mt then
            local prev_changed = old_mt.previous ~= new_mt.previous
            local next_changed = old_mt.next ~= new_mt.next

            local changed = prev_changed

            if (not prev_changed) and (not old_mt.next) then
                -- If it had no `next` and now it has, then don't count as changed.
                changed = false
            elseif (not prev_changed) and (not old_mt.has_children) and new_mt.has_children then
                -- If it had no children and not it has, then don't count as changed
                changed = false
            end

            if changed then
                local x0  = trees[i-1].x + old_mt.position.x + old_mt.position.width
                local y0_ = trees[i-1].y + old_mt.position.y + math.floor(old_mt.position.height/2)
                local x1  = trees[i].x + new_mt.position.x
                local y1  = trees[i].y + new_mt.position.y + math.floor(new_mt.position.height/2)
                local width, height = x1 - x0, y1 < y0_ and y0_ - y1 or  y1 - y0_

                local color = client_highlight_colors[node.client] or beautiful.bg_highlight

                local wdg = line_widget_factory {
                    width  = width,
                    height = height,
                    up     = y1 < y0_,
                    left   = false,
                    color  = color,
                    dash   = { {4, 1}, 1 },
                    random = true,
                    ending = "arrow",
                }

                canvas:add_at(wdg, {
                    x = x0,
                    y = y1 < y0_ and y1 or y0_
                })
            end
        else
            canvas:add_at(removed_widget(), {
                x      = trees[i-1].x + old_mt.position.x + old_mt.position.width,
                y      = trees[i-1].y + old_mt.position.y + math.floor(old_mt.position.height/2) - 5,
                width  = math.max(20, trees[i].x - (trees[i-1].x + old_mt.position.x + old_mt.position.width) + 10),
                height = 10,
            })
        end
    end
end

-- Save to the output filecontainer
local img = surface.widget_to_svg(canvas, svgpath..".svg", canvas.forced_width, canvas.forced_height)
img:finish()

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
