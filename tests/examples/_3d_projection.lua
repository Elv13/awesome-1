local capi       = {client = client, root = root}
local gtable     = require("gears.table")
local gcolor     = require("gears.color")
local gshape     = require("gears.shape")
local atree      = require("awful.tree")
local beautiful  = require("beautiful")
local base       = require("wibox.widget.base")
local lgi        = require('lgi')
local Pango      = lgi.Pango
local PangoCairo = lgi.PangoCairo
local unpack     = unpack or table.unpack -- luacheck: globals unpack (compatibility with Lua 5.1)

-- Define the 3D rotation angles and 2D translation
local angle_x, angle_y, angle_z = math.rad(40), math.rad(45), math.rad(50)
local translation_x, translation_y = 0, 0

-- How far appart the layers are.
local scale_factor         = 15
local horizontal_grid_size = 10
local table_offset         = 30

-- Theme related values.
local label_margin = 3
local arrow_size = 3
local axis_offset = 5
local table_border_width = 1
local client_border_width = 2
local client_titlebar_height = 7
local client_border_opacity = 0.3
local client_content_opacity = 0.4
local axis_color = beautiful.bg_urgent
local wallpaper_color = gcolor.change_opacity(beautiful.bg_normal, 0.15)
local shadow_color = gcolor.change_opacity(beautiful.bg_normal, 0.15)
local grid_color = gcolor.change_opacity(beautiful.fg_normal, 0.2)
local back_color = gcolor.change_opacity(beautiful.bg_normal, 0.02)
local table_border_color = gcolor.change_opacity(beautiful.bg_normal, 0.15)
local wallpaper_label_color = gcolor.change_opacity(beautiful.fg_normal, 0.5)
local layer_label_color = gcolor.change_opacity(beautiful.fg_normal, 0.6)

-- Globally assing a color to client and wiboxes.
local client_colors, client_color_memento, max_client_color = {
    {39 / 255, 190 / 255, 255 / 255},
    {182/ 255, 56  / 255, 255 / 255},
    {31 / 255, 184 / 255, 31  / 255},
    {254/ 255, 153 / 255, 29  / 255},
    {65 / 255, 38  / 255, 254 / 255},
    {245/ 255, 254 / 255, 73  / 255},
}, {}, 1

-- Create the Pango context for the text.
local pctx = PangoCairo.font_map_get_default():create_context()
local playout = Pango.Layout.new(pctx)
playout:set_font_description(Pango.FontDescription.from_string("sans 8"))
pctx:set_resolution(96)
playout:context_changed()

-- The main transformation matrix (initialized in `init_projection_matrix()`.
local transform = nil

local module = {}

-- Get the object color.
-- The memento is to ensure the color remain the same even if clients are
-- added/killed.
local function drawable_color(c)
    if client_color_memento[c] then return client_color_memento[c] end
    client_color_memento[c] = client_colors[max_client_color]
    max_client_color = max_client_color + 1
    return gtable.clone(client_color_memento[c])
end

-- Compute the size of the scene.
local function viewport_area(self)
    local grid_size = self._private.horizontal_grid_size or horizontal_grid_size
    local factor    = self._private.scale_factor or scale_factor
    local n_object  = #self._private.data.clients
    local s_geo     = self._private.data.size
    local area_x    = factor * grid_size
    local area_z    = factor * n_object
    local area_y    = (s_geo.height * area_x) / s_geo.width

    return area_x, area_z, area_y
end

-- Function to multiply two matrices
local function matrix_multiply(m1, m2)
    local ret = {}

    for i = 1, #m1 do
        ret[i] = {}
        for j = 1, #m2[1] do
            ret[i][j] = 0
            for k = 1, #m1[1] do
                ret[i][j] = ret[i][j] + m1[i][k] * m2[k][j]
            end
        end
    end

    return ret
end

-- Very basic 3D engine.
--
-- This takes a 2D point and project it in a 3D space with hardcoded rotation
-- and translations. From point, it's easy to extrapolate this to vectors. From
-- vector to polygons. In theory, polygon to faces, then faces to 3D models, etc,
-- but there's no use case for this here.
--
-- It's not well suited to project surfaces or do UV mapping/mipmapping. This
-- can be worked around by using shear matricies to approximate the surface
-- mapping when the surface is aligned to the x/y/z plane. Anything more
-- complicated isn't possible with this design.
local function init_projection_matrix()
    if transform then return transform end

    local rotate_x = {
        {1, 0                ,  0                , 0},
        {0, math.cos(angle_x), -math.sin(angle_x), 0},
        {0, math.sin(angle_x),  math.cos(angle_x), 0},
        {0, 0                ,  0                , 1},
    }

    local rotate_z = {
        { math.cos(angle_z), 0, math.sin(angle_z), 0},
        { 0                , 1, 0                , 0},
        {-math.sin(angle_z), 0, math.cos(angle_z), 0},
        { 0                , 0, 0                , 1},
    }

    local rotate_y = {
        {math.cos(angle_y), -math.sin(angle_y), 0, 0},
        {math.sin(angle_y),  math.cos(angle_y), 0, 0},
        {0                ,  0                , 1, 0},
        {0                ,  0                , 0, 1},
    }

    local translate = {
        {1, 0, 0, translation_x},
        {0, 1, 0, translation_y},
        {0, 0, 1, 0            },
        {0, 0, 0, 1            },
    }

    -- Multiply the matrices to get the final transformation matrix.
    transform = matrix_multiply(rotate_x , rotate_z )
    transform = matrix_multiply(transform, rotate_y )
    transform = matrix_multiply(transform, translate)

    return transform
end

-- Use the `angle_x/y/z` above to rotate the 2D input `point` into a 3D projection.
local function project_point(point)
    return matrix_multiply(
        {{point[1], point[2], point[3], 1}}, init_projection_matrix()
    )[1]
end

local function draw_line_common(cr, start_point, end_point)
    -- Translate the starting and ending points of the line
    start_point = project_point(start_point)
    end_point   = project_point(end_point  )
    cr:move_to(start_point[1], start_point[2])
    cr:line_to(end_point  [1], end_point  [2])
    cr:stroke()
end

local function draw_x_line(cr, z, y, x1, x2)
    draw_line_common(cr, {x1, z, y}, {x2, z, y})
end

local function draw_z_line(cr, x, y, z1, z2)
    draw_line_common(cr, {x, z1, y}, {x, z2, y})
end

local function draw_y_line(cr, x, z, y1, y2)
    draw_line_common(cr, {x, z, y1}, {x, z, y2})
end

-- Create the cairo path.
--
-- It does *not* call `:stroke()` or `:fill()`.
local function draw_polygon(cr, points)
    for idx, p in ipairs(points) do
        local pt = project_point(p)
        cr[idx ==  1 and "move_to" or "line_to"](cr, pt[1], pt[2])
    end
    cr:close_path()
end

-- Generate the header based on optional columns.
local function get_header_labels(self)
    local header_labels, indices = { "z-index" }, {}

    if self._private.show_previous_z_index then
        table.insert(header_labels, "Previous")
    end

    header_labels = gtable.join(header_labels, {"Client name", "Layer" })

    if self._private.show_modal then
        header_labels = gtable.join(header_labels, {"Transient for", "Modal" })
    end

    if self._private.show_geometry_table then
        header_labels = gtable.join(header_labels, { "x", "y", "width", "height"})
    end

    for k, v in ipairs(header_labels) do
        indices[v] = k
    end

    return header_labels, indices
end

-- Function to draw the grid.
local function draw_grid(self, cr)
    local area_x, area_z, area_y = viewport_area(self)
    local factor = self._private.scale_factor or scale_factor

    -- Draw the solid (ZY) back.
    local points = {
        --    X           Z          Y
        {(area_x/2), -(area_z/2), -area_y},
        {(area_x/2),  (area_z/2), -area_y},
        {(area_x/2),  (area_z/2), 0      },
        {(area_x/2), -(area_z/2), 0      },
    }

    draw_polygon(cr, points)

    cr:set_source(gcolor(back_color))
    cr:fill()

    -- Draw the solid (XZ) bottom.
    points = {
        --    X             Z      Y
        { (area_x/2),  (area_z/2), 0},
        { (area_x/2), -(area_z/2), 0},
        {-(area_x/2), -(area_z/2), 0},
        {-(area_x/2),  (area_z/2), 0},
    }

    draw_polygon(cr, points)

    cr:set_source(gcolor(back_color))
    cr:fill()

    -- Set the color for the grid lines to blue
    cr:set_source(gcolor(grid_color))

    -- Set the line width for the grid lines
    cr:set_line_width(1)

    -- Draw the (XZ) horizontal lines
    for y = -(area_z/2), (area_z/2), factor do
        draw_x_line(cr, y, 0, -(area_x/2), (area_x/2))
    end

    -- Draw the (XZ) vertical lines
    for x = -(area_x/2), (area_x/2), factor do
        draw_z_line(cr, x, 0, -(area_z/2), (area_z/2))
    end

    -- Draw the (ZY) vertical lines
    for z = -(area_z/2), (area_z/2), factor do
        draw_y_line(cr, (area_x/2), z, 0, -area_y)
    end

    -- Close off the (ZY) grid
    draw_z_line(cr, (area_x/2), -area_y, -(area_z/2), (area_z/2))
end

-- Function to draw the X axis
local function draw_axis(self, cr)
    local area_x, area_z, area_y = viewport_area(self)

    -- Make the axis longer than the cartesian plan to make the label readable.
    area_x, area_z, area_y = area_x + 2*axis_offset, area_z + 2*axis_offset, area_y + 2*axis_offset

    -- Set the line width and color
    cr:set_line_width(2)
    cr:set_font_size(12)

    local labels = { "-X", "Z", "Y" }

    for label_idx, axis in ipairs { {1, 0, 0}, {0, -1, 0}, {0, 0, 1} } do
        -- End of the axis line.
        local p1 = {
             (area_x/2) + -area_x * axis[1],
            -(area_z/2) -area_z * axis[2],
            -area_y * axis[3]
        }

        -- Origin.
        local p2 = {(area_x/2), -(area_z/2), 0}

        local start_pt = project_point(p1)
        local end_pt   = project_point(p2)

        -- Draw a red line for the axis.
        cr:move_to(unpack(start_pt))
        cr:line_to(unpack(end_pt  ))
        cr:set_source(gcolor(axis_color))
        cr:stroke()

        -- Draw the triangle at the end of the axis.
        -- y = m*x+b
        local m = (end_pt[2] - start_pt[2]) / (end_pt[1] - start_pt[1])
        local base_angle1, base_angle2 = math.atan(-1 / m), math.atan(m)

        local dx = arrow_size * math.cos(base_angle1) * math.sqrt(arrow_size/2)
        local dy = arrow_size * math.sin(base_angle1) * math.sqrt(arrow_size/2)

        local arrow_p1 = {start_pt[1] + dx, start_pt[2] + dy}
        local arrow_p2 = {start_pt[1] - dx, start_pt[2] - dy}

        local dir = (label_idx==2 and 1 or -1)

        cr:move_to(unpack(arrow_p1))
        cr:line_to(unpack(arrow_p2))
        cr:line_to(
            start_pt[1] + math.cos(base_angle2) * 2*arrow_size * dir,
            start_pt[2] + math.sin(base_angle2) * 2*arrow_size * dir
        )
        cr:close_path()
        cr:fill()

        -- Add a label.
        playout.attributes, playout.text = Pango.parse_markup(labels[label_idx], -1, 0)
        local _, logical = playout:get_pixel_extents()

        local center_x = (logical.width /2) + arrow_size
        local center_y = (logical.height/2) + arrow_size

        local lbl_distance = math.sqrt(center_x^2 + center_y^2)

        cr:move_to(
            (start_pt[1] + math.cos(base_angle2) * lbl_distance * dir) - logical.width/2,
            (start_pt[2] + math.sin(base_angle2) * lbl_distance * dir) - logical.height/2
        )

        cr:set_source(gcolor(beautiful.fg_normal))
        cr:show_layout(playout)
    end
end

local function draw_wallpaper(self, cr)
    local area_x, area_z, area_y = viewport_area(self)

    local wall_pts = {
        --     X           Z          Y
        {-(area_x/2), -(area_z/2), -area_y},
        { (area_x/2), -(area_z/2), -area_y},
        { (area_x/2), -(area_z/2), 0      },
        {-(area_x/2), -(area_z/2), 0      },
    }

    draw_polygon(cr, wall_pts)
    cr:set_source(gcolor(wallpaper_color))
    cr:fill()
end

-- Draw either a wibox or a client.
local function draw_drawables(self, cr)
    local ret = {}

    local s_geo = self._private.data.size
    local area_x, area_z, area_y = viewport_area(self)
    local factor = self._private.scale_factor or scale_factor

    for idx, c in ipairs(self._private.data.clients) do
        local c_geo = c.geometry

        -- This only works for screenstarting at 0x0 for now. This template
        -- doesn't support multiple screen (until its needed?)
        local proj_geo = {
            x1 = (c_geo.x * area_x) / s_geo.width,
            x2 = ((c_geo.x+c_geo.width) * area_x) / s_geo.width,
            y1 = (c_geo.y * area_y) / s_geo.height,
            y2 = ((c_geo.x+c_geo.height) * area_y) / s_geo.height,
        }

        -- 0x0 is the "top left" while 0x0x0 in 3D is the center of the plan.
        -- This map between them.
        local vertices = {
            --              X                         Z                      Y
            {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y1},
            {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y1},
            {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y2},
            {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y2},
        }

        -- Add a "shadow" directly on the wallpaper.
        -- There is no light source in this code, so it's just a Z translation.
        local shadow_vertices = {
            --            X                  Z             Y
            {-(area_x/2) + proj_geo.x1, -(area_z/2), -proj_geo.y1},
            {-(area_x/2) + proj_geo.x2, -(area_z/2), -proj_geo.y1},
            {-(area_x/2) + proj_geo.x2, -(area_z/2), -proj_geo.y2},
            {-(area_x/2) + proj_geo.x1, -(area_z/2), -proj_geo.y2},
        }

        -- Get the center of the projection.
        table.insert(ret, {
            index  = idx,
            client = c,
            center = project_point({
                -(area_x/2) + proj_geo.x1 + (proj_geo.x2 - proj_geo.x1)/2,
                -(area_z/2) + factor*idx,
                -(proj_geo.y1 + (proj_geo.y2 - proj_geo.y1)/2)
            }),
        })

        -- Draw the shadow on the wallpaper
        draw_polygon(cr, shadow_vertices)
        cr:set_source(shadow_color)
        cr:fill()

        draw_polygon(cr, vertices)

        local fc = c.fill_color
        cr:set_source_rgba(fc[1], fc[2], fc[3], fc[4])
        cr:fill()

        -- Decorate the client.
        if c.type == "client" then
            local tb, bw = client_titlebar_height, client_border_width
            local bwc = c.border_color
            cr:set_source_rgba(bwc[1], bwc[2], bwc[3], bwc[4])

            -- Draw the titelear.
            local titlebar = {
                --                X                        Z                    Y
                {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y2   },
                {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y2   },
                {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y2+tb},
                {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y2+tb},
            }
            draw_polygon(cr, titlebar)
            cr:fill()

            -- Left border.
            local left = {
                --                X                        Z                    Y
                {-(area_x/2) + proj_geo.x1+bw, -(area_z/2) + factor*idx, -proj_geo.y1-bw},
                {-(area_x/2) + proj_geo.x1   , -(area_z/2) + factor*idx, -proj_geo.y1-bw},
                {-(area_x/2) + proj_geo.x1   , -(area_z/2) + factor*idx, -proj_geo.y2+tb},
                {-(area_x/2) + proj_geo.x1+bw, -(area_z/2) + factor*idx, -proj_geo.y2+tb},
            }
            draw_polygon(cr, left)
            cr:fill()

            -- Right border.
            local right = {
                --                X                        Z                    Y
                {-(area_x/2) + proj_geo.x2-bw, -(area_z/2) + factor*idx, -proj_geo.y1-bw},
                {-(area_x/2) + proj_geo.x2   , -(area_z/2) + factor*idx, -proj_geo.y1-bw},
                {-(area_x/2) + proj_geo.x2   , -(area_z/2) + factor*idx, -proj_geo.y2+tb},
                {-(area_x/2) + proj_geo.x2-bw, -(area_z/2) + factor*idx, -proj_geo.y2+tb},
            }
            draw_polygon(cr, right)
            cr:fill()

            -- Bottom border.
            local bottom = {
                --                X                        Z                    Y
                {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y1   },
                {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y1   },
                {-(area_x/2) + proj_geo.x2, -(area_z/2) + factor*idx, -proj_geo.y1-bw},
                {-(area_x/2) + proj_geo.x1, -(area_z/2) + factor*idx, -proj_geo.y1-bw},
            }
            draw_polygon(cr, bottom)
            cr:fill()
        end

        -- Draw solid "shadow" lines on the grid.
        cr:set_line_width(3)

        cr:set_source_rgba(fc[1], fc[2], fc[3], fc[4])

        draw_x_line(cr, -(area_z/2) + factor*idx, 0, vertices[1][1], vertices[2][1])

        draw_y_line(cr, (area_x/2), -(area_z/2) + factor*idx, vertices[2][3], vertices[3][3])

        -- Draw dashed lines from the rectangle to the "shadow".
        cr:save()
        cr:set_dash({1,1},1)
        cr:set_line_width(1)
        cr:set_source_rgba(1, 0, 0, 0.2)
        draw_x_line(cr, -(area_z/2) + factor*idx, vertices[1][3], vertices[2][1], (area_x/2))
        draw_x_line(cr, -(area_z/2) + factor*idx, vertices[3][3], vertices[2][1], (area_x/2))

        draw_y_line(cr, vertices[2][1], -(area_z/2) + factor*idx, 0, vertices[2][3])
        draw_y_line(cr, vertices[1][1], -(area_z/2) + factor*idx, 0, vertices[2][3])

        draw_z_line(cr, vertices[1][1], vertices[1][3], -(area_z/2), -(area_z/2) + factor*idx)
        draw_z_line(cr, vertices[2][1], vertices[2][3], -(area_z/2), -(area_z/2) + factor*idx)
        draw_z_line(cr, vertices[1][1], vertices[3][3], -(area_z/2), -(area_z/2) + factor*idx)
        draw_z_line(cr, vertices[2][1], vertices[4][3], -(area_z/2), -(area_z/2) + factor*idx)

        -- Move back to the wallpaper.
        for _, v in ipairs(vertices) do
            v[2] = -(area_z/2)
        end
        draw_polygon(cr, vertices)

        cr:stroke()

        cr:restore()
    end

    return ret
end

-- Draw the hardcoded layers desktop / below / normal / above / ontop.
local function draw_layers(self, cr)
    local ranges = {desktop = {0,0}}

    for idx, c in ipairs(self._private.data.clients) do
        local layer = c.layer

        ranges[layer] = ranges[layer] or {math.huge, 0}

        ranges[layer][1] = math.min(ranges[layer][1], idx)
        ranges[layer][2] = math.max(ranges[layer][2], idx)
    end

    local area_x, area_z, _ = viewport_area(self)
    local factor = self._private.scale_factor or scale_factor

    cr:set_line_width(1)
    cr:set_source(gcolor(layer_label_color))

    for name, range in pairs(ranges) do
        --                      X                         Z                    Y
        local p1 = project_point({-area_x/2 - 5 , -area_z/2 + factor*range[1], 0})
        local p2 = project_point({-area_x/2 - 10, -area_z/2 + factor*range[1], 0})
        local p3 = project_point({-area_x/2 - 10, -area_z/2 + factor*range[2], 0})
        local p4 = project_point({-area_x/2 - 5 , -area_z/2 + factor*range[2], 0})

        -- Draw a |____| bracket between the deepest and frontmost entry in the layer.
        cr:move_to(p1[1], p1[2])
        cr:line_to(p2[1], p2[2])
        cr:line_to(p3[1], p3[2])
        cr:line_to(p4[1], p4[2])
        cr:stroke()

        -- Get the size of the layer name text
        local attr, parsed = Pango.parse_markup(name, -1, 0)
        local dz = factor*range[1] + (factor*range[2] - factor*range[1])/2
        local center_point = project_point({-area_x/2 - 15, -area_z/2 + dz, 0})
        playout.attributes, playout.text = attr, parsed
        local _, logical = playout:get_pixel_extents()

        -- Draw vertical text
        cr:save()
        cr:translate(center_point[1] + logical.height/2, center_point[2])
        cr:rotate(math.pi/2)
        cr:show_layout(playout)
        cr:restore()
    end
end

-- Compute the size of a bounding box for the 3D projection.
local function fit_projection(self)
    local area_x, area_z, area_y = viewport_area(self)

    local pts = {}

    -- Gather the vertex of the wallpaper and "screen" bounding rectangles.
    --
    -- This create 2 rectangles. One at Z0 and one at Zmax.
    for _, z in ipairs {-(area_z/2), (area_z/2) } do
        table.insert(pts, {-area_x/2, z, 0     })
        table.insert(pts, {-area_x/2, z, area_y})
        table.insert(pts, { area_x/2, z, area_y})
        table.insert(pts, { area_x/2, z, 0     })
    end

    local min, max = {math.huge, math.huge, math.huge}, {0,0,0}

    -- Find the max and min x/y values.
    for _, pt in ipairs(pts) do
        pt = project_point(pt)
        for axis=1, 2 do
            min[axis] = math.min(min[axis], pt[axis])
            max[axis] = math.max(max[axis], pt[axis])
        end
    end

    -- What is projected beyond 0x0 and thus needs to be translated later.
    local tr_x, tr_y = math.ceil(-math.min(0, min[1])), math.ceil(-math.min(0, min[2]))

    return math.ceil(max[1] - min[1]), math.ceil(max[2] - min[2]), tr_x, tr_y
end

local function fit_layer_labels()
    local max_w, max_h = 0, 0

    -- It's rotated 90 degree, so the width becomes the height.
    for _, lbl in ipairs { "desktop", "below", "normal", "above", "ontop" } do
        playout.attributes, playout.text = Pango.parse_markup(lbl, -1, 0)
        local _, logical = playout:get_pixel_extents()
        max_w = math.max(max_w, logical.width )
        max_h = math.max(max_h, logical.height)
    end

    -- `max_h/2` is the margin
    return max_w + max_h/2
end

-- Size of the client size table.
local function fit_geometry_table(self)
    -- The order of the rows is not important to get the size of the table, so
    -- it is ignored.

    local cols_max, rows_max, max_row_height = {}, {}, 0

    local has_geo = self._private.show_geometry_table

    local header_lbls, header_columns = get_header_labels(self)

    -- Geometry headers.
    for idx, prop in ipairs(header_lbls) do
        playout.attributes, playout.text = Pango.parse_markup("<b>"..prop.."</b>", -1, 0)
        local _, logical = playout:get_pixel_extents()
        cols_max[idx] = logical.width
        rows_max[ 1 ] = logical.height
    end

    -- Layer size.
    cols_max[header_columns["Layer"]] = fit_layer_labels() + 2*label_margin

    -- Client size
    for row, c in ipairs(self._private.data.clients) do
        -- Fit the geometry values.
        if has_geo then
            local geo = c.geometry
            for idx, prop in ipairs {"x", "y", "width", "height"} do
                local col = header_columns[prop]
                local value = math.floor(geo[prop])
                playout.attributes, playout.text = Pango.parse_markup(value, -1, 0)
                local _, logical = playout:get_pixel_extents()
                cols_max[col] = math.max(cols_max[col], logical.width )
                rows_max[row+1] = math.max(rows_max[row+1] or 0, logical.height)
            end
        end

        -- Fir the client name.
        playout.attributes, playout.text = Pango.parse_markup(c.name, -1, 0)
        local _, logical = playout:get_pixel_extents()
        local col = header_columns["Client name"]
        cols_max[col] = math.max(cols_max[col], logical.width ) --FIXME hardocded col id
        rows_max[row+1] = math.max(rows_max[row+1] or 0, logical.height)
    end

    local fit_w, fit_h, cols_x0 = 4*label_margin, 4*label_margin, {}

    -- +1 is for the border width
    for col=1, #cols_max do
        cols_max[col] = cols_max[col] + 2*label_margin + table_border_width
        cols_x0[col] = fit_w - 4*label_margin
        fit_w = fit_w + cols_max[col]
    end

    for row=1, #rows_max do
        rows_max[row] = rows_max[row] + 2*label_margin + table_border_width
        fit_h = fit_h + rows_max[row]
        max_row_height = math.max(max_row_height, rows_max[row])
    end

    max_row_height = math.ceil(max_row_height)

    cols_x0[#cols_x0+1] = fit_w - label_margin

    -- Add the wallpaper row.
    fit_h = fit_h + table_border_width + max_row_height

    return fit_w, fit_h, cols_x0, max_row_height, #rows_max
end

local function fit_axis_labels()
    playout.attributes, playout.text = Pango.parse_markup("-X", -1, 0)
    local _, logical = playout:get_pixel_extents()
    return math.ceil(logical.width + 2*arrow_size), math.ceil(logical.height*1.5 + 2*arrow_size)
end

local function fit_highlight_label(label)
    playout.attributes, playout.text = Pango.parse_markup("<b>"..label.."</b>", -1, 0)
    local _, logical = playout:get_pixel_extents()
    return logical.height + logical.width, logical.height
end

local function fit_highlight_labels(self)
    local max_w, max_h = 0, 0

    for idx, c in ipairs(self._private.data.clients) do
        if c.highlight_label then
            local w, h = fit_highlight_label(c.highlight_label)
            max_w, max_h = math.max(max_w, w), math.max(max_h, h)
        end
    end

    return max_w, max_h
end

local function draw_centered_label(cr, x0, y0, x1, y1, text)
    playout.attributes, playout.text = Pango.parse_markup("<b>"..text.."</b>", -1, 0)
    local _, logical = playout:get_pixel_extents()
    local x = x0 + math.ceil(((x1-x0) - logical.width)/2)
    cr:move_to(x, y0 + (y1-y0) - label_margin - logical.height)
    cr:show_layout(playout)
end

local function draw_highlight_label(self, cr, pos, label)
    local width, height = fit_highlight_label(label)

    pos.y = pos.y - height/2

    local border_color = gcolor.change_opacity(beautiful.bg_urgent, 1)
    local color = gcolor.change_opacity(beautiful.bg_urgent, 0.5)

    cr:save()
    cr:set_line_width(2)
    cr:set_dash(nil, nil)
    cr:translate(pos.x, pos.y)
    gshape.rectangular_tag(cr, width, height)
    cr:set_source(color)
    cr:fill_preserve()
    cr:set_source(border_color)
    cr:stroke()
    cr:restore()

    cr:set_source(gcolor(beautiful.fg_urgent))
    cr:move_to(pos.x + height/2 + label_margin, pos.y)
    cr:show_layout(playout)
end

local function draw_geometry_table(self, cr, positions, origin, x_offset, total_height)
    local _, _, cols_pos, row_height, row_count = fit_geometry_table(self)
    local x0 = x_offset + table_offset
    local y0 = -origin.y + math.ceil((total_height - row_height*row_count)/2)

    cr:set_line_width(1)

    -- Sort the points by Y axis (bottom-most at idx 1). This allows us to
    -- detect when the label would overwise overlap.
    table.sort(positions, function(a, b) return a.index > b.index end)

    -- Draw the background for the focused row.
    for idx, data in ipairs(positions) do
        if data.client.highlight_label then
            local y = y0 + idx*row_height
            cr:set_source(gcolor.change_opacity(beautiful.bg_urgent, 0.05))
            cr:rectangle(x0, y, cols_pos[#cols_pos], row_height)
            cr:fill()
            draw_highlight_label(self, cr, {
                x = x0 + cols_pos[#cols_pos] + 2*label_margin,
                y = y + math.ceil(row_height/2)
            }, data.client.highlight_label)
        end
    end

    -- Draw the wallpaper cell background.
    cr:rectangle(x0, y0 + row_count*row_height, cols_pos[#cols_pos], row_height)
    cr:set_source(gcolor.change_opacity(beautiful.bg_normal, 0.075))
    cr:fill()

    -- Header background.
    cr:set_source(gcolor.change_opacity(beautiful.bg_normal, 0.2))
    cr:rectangle(
        x0,
        y0,
        cols_pos[#cols_pos],
        row_height
    )
    cr:fill()

    cr:set_source(gcolor(table_border_color))

    -- Draw the table horizontal border.
    for i=0, row_count+1 do
        local y = y0 + i*row_height
        cr:move_to(x0, y)
        cr:line_to(x0 + cols_pos[#cols_pos], y)
        cr:close_path()
    end

    -- Draw the table vertical borders.
    for i=1, #cols_pos do
        cr:move_to(x0 + cols_pos[i], y0)
        cr:line_to(x0 + cols_pos[i], y0 + row_count*row_height)
        cr:close_path()
    end

    -- Add the wallpaper row vertical borders.
    cr:move_to(x0, y0 + row_count*row_height)
    cr:line_to(x0, y0 + row_count*row_height + row_height)
    cr:close_path()
    cr:move_to(x0 + cols_pos[#cols_pos], y0 + row_count*row_height)
    cr:line_to(x0 + cols_pos[#cols_pos], y0 + row_count*row_height + row_height)

    cr:stroke()

    cr:set_source(gcolor(beautiful.fg_normal))

    local header_lbls, header_columns = get_header_labels(self)

    -- Geometry headers.
    for i, lbl in ipairs(header_lbls) do
        draw_centered_label(cr, x0 + cols_pos[i], y0, x0 + cols_pos[i+1], y0 + row_height, lbl)
    end

    -- Get the width of the "z-index" column.
    playout.attributes, playout.text = Pango.parse_markup("<b>z-index</b>", -1, 0)
    local _, z_index_extents = playout:get_pixel_extents()



    -- Table content.
    for idx, data in ipairs(positions) do
        local y = y0 + (idx+1)*row_height - math.floor(row_height/2)
        local col = data.client.fill_color

        cr:set_source_rgba(col[1], col[2], col[3], 1)
        cr:arc(data.center[1], data.center[2], 3, 0, math.pi*2)
        cr:fill()

        -- Radius for the client index colored circle.
        playout.attributes, playout.text = Pango.parse_markup(data.index, -1, 0)
        local _, logical = playout:get_pixel_extents()
        local radius = math.max(logical.width, logical.height)/2 + label_margin/3

        -- Draw a line between the center of the client to the label start.
        cr:set_line_width(data.client.highlight_arrow and 2 or 1)
        cr:set_dash({3,1}, table_border_width)
        cr:move_to(data.center[1], data.center[2])
        cr:line_to(data.center[1], y)
        cr:line_to(x0+z_index_extents.width/2-radius, y)
        cr:stroke()

        -- Draw the z-index.
        cr:set_dash({1,2}, table_border_width)
        cr:set_line_width(1)
        cr:move_to(x0 + z_index_extents.width/2 + radius, y)
        cr:arc(x0 + z_index_extents.width/2, y, radius, 0, 2*math.pi)
        cr:close_path()
        cr:set_source_rgba(col[1], col[2], col[3], client_border_opacity*2)
        cr:stroke_preserve()
        cr:set_source_rgba(col[1], col[2], col[3], client_content_opacity/2)
        cr:fill()

        cr:set_source(gcolor(beautiful.fg_normal))
        cr:move_to(x0 + z_index_extents.width/2 - logical.width/2, y - logical.height/2)
        cr:show_layout(playout)

        -- Draw the previous z-index
        if self._private.show_previous_z_index then
            local column = header_columns["Previous"]
            playout.attributes, playout.text = Pango.parse_markup(data.client.previous_idx, -1, 0)
            _, logical = playout:get_pixel_extents()
            local offset = math.ceil(((cols_pos[column+1]-cols_pos[column]) - logical.width) / 2) - label_margin
            cr:move_to(x0 + cols_pos[column] + offset + label_margin, y - logical.height/2)
            cr:show_layout(playout)
        end

        -- Render the client name.
        local column = header_columns["Client name"]
        playout.attributes, playout.text = Pango.parse_markup(data.client.name , -1, 0)
        _, logical = playout:get_pixel_extents()
        cr:move_to(x0 + cols_pos[column] + label_margin, y - logical.height/2)
        cr:show_layout(playout)

        -- Draw the layer name.
        column = header_columns["Layer"]
        playout.attributes, playout.text = Pango.parse_markup(data.client.layer, -1, 0)
        _, logical = playout:get_pixel_extents()
        cr:move_to(x0 + cols_pos[column] + label_margin, y - logical.height/2)
        cr:show_layout(playout)

        -- Draw the geometry values.
        if self._private.show_geometry_table then
            local geo = data.client.geometry

            for i, prop in ipairs {"x", "y", "width", "height"} do
                column = header_columns[prop]
                local value = math.floor(geo[prop])
                playout.attributes, playout.text = Pango.parse_markup(value, -1, 0)
                _, logical = playout:get_pixel_extents()
                local offset = math.ceil(((cols_pos[column+1]-cols_pos[column]) - logical.width) / 2) - label_margin
                cr:move_to(x0 + cols_pos[column] + offset + label_margin, y - logical.height/2)
                cr:show_layout(playout)
            end
        end
    end

    -- Draw the "wallpaper" label.
    cr:set_source(wallpaper_label_color)
    playout.attributes, playout.text = Pango.parse_markup("<i>Wallpaper</i>", -1, 0)
    local _, logical = playout:get_pixel_extents()

    cr:move_to(
        math.ceil(x0 + cols_pos[#cols_pos]/2 - logical.width/2),
        math.ceil(y0 + row_count*row_height + row_height/2 - logical.height/2)
    )
    cr:show_layout(playout)
end

--- Get the required client data.
function module.get_client_data(args)
    local clients = args.clients
    local width, height = capi.root.size()
    local has_highlight = false

    if args.tree then
        clients = {}
        for node in atree.iterate_next(args.tree) do
            if node.type == "client" then
                print("ADD", node.client, node.client:geometry().x, node.client:geometry().y, node.client:geometry().width, node.client:geometry().height)
                table.insert(clients, 1, node.client)
            end
        end
    end

    local ret = {
        size = {
            x    = 0,
            y    = 0,
            width  = width,
            height = height,
        },
        clients = {},
    }

    for _, c in ipairs(clients) do
        has_highlight = has_highlight or rawget(c, "_3d_highlight")
    end
    clients = clients
        or rawget(root, "_current_stacking_order")
        or capi.client.get(nil, true)


    local prev, highlight_labels = {}, {}

    if args.previous_z_index then
        for idx, c in ipairs(args.previous_z_index() or {}) do
            prev[c] = idx
        end
    end

    for _, c in ipairs(clients) do
        local data = {}

        data.layer = c.type == "desktop" and "desktop" or "normal"

        for _, prop in ipairs { "below", "above", "ontop" } do
            if c[prop] then
                data.layer = prop
            end
        end

        local highlighted = rawget(c, "_3d_highlight")

        local fill_opacity = has_highlight
            and ((client_content_opacity/6) * (highlighted and 9 or 5))
            or client_content_opacity

        local border_opacity = has_highlight
            and ((client_border_opacity/6) * (highlighted and 9 or 5))
            or client_border_opacity

        local fill_color, border_color = drawable_color(c), drawable_color(c)
        table.insert(fill_color, fill_opacity)
        table.insert(border_color, border_opacity)

        data.layer           = data.layer or "normal"
        data.geometry        = gtable.clone(c:geometry())
        data.fill_color      = fill_color
        data.border_color    = border_color
        data.name            = c.name
        data.type            = "client"
        data.focus           = client.focus == c
        data.previous_idx    = prev[c] or "<i>--</i>"
        data.highlight_label = (args.highlight or {})[c.name]
        data.highlight_arrow = highlighted

        table.insert(ret.clients, data)
    end

    return ret
end

function module:fit(_, _, _)
    local proj_w, proj_h = fit_projection        (self)
    local tab_w, _       = fit_geometry_table    (self)
    local lbl_w, lbl_h   = fit_axis_labels       (    )
    local label_height   = fit_layer_labels      (    )
    local foc_w, _       = fit_highlight_labels  (self)

    -- No idea why +30, I can't find where that's going.
    if self._private.show_table then
        local width  = proj_w + tab_w + 30 + table_offset + foc_w + lbl_w/2
        local height = proj_h + label_height + lbl_h
        return width, height
    else
        local width  = proj_w + 30 + lbl_w/2
        local height = proj_h + label_height + lbl_h
        return width, height
    end
end

function module:draw(_, cr, _, height)
    local proj_w, proj_h, tr_x, tr_y = fit_projection(self)
    local axix_lbl_w, axix_lbl_h = fit_axis_labels()

    -- The main projection geo is `0, fit_axis_labels(),w,h`, but these
    -- projections can be negative for a lot of the angles and need to be
    -- compensated by `tr_x` and `tr_y`, which are the maximum negative offsets.
    local origin = {
        x = proj_w - tr_x + math.ceil(1.5*axix_lbl_w),
        y = proj_h - tr_y + axix_lbl_h + axis_offset
    }

    cr:translate(origin.x, origin.y)

    -- Draw each of the components.
    draw_grid     (self, cr)
    draw_wallpaper(self, cr)
    draw_axis     (self, cr)
    draw_layers   (self, cr)
    local projected_positions = draw_drawables(self, cr)

    if self._private.show_table then
        draw_geometry_table(self, cr, projected_positions, origin, proj_w - tr_x, height)
    end
end

function module:get_client_colors()
    return client_color_memento
end

local function new(_, args)
    args = args or {}

    local ret = base.make_widget(nil, nil, {
        enable_properties = true,
    })

    ret._private.show_geometry_table   = true
    ret._private.show_previous_z_index = false
    ret._private.show_modal            = false
    ret._private.show_table            = args.show_table ~= false
    ret._private.highlight_focus       = true
    ret._private.horizontal_grid_size  = args.horizontal_grid_size
    ret._private.scale_factor          = args.scale_factor

    ret._private.data = args.data or module.get_client_data(args)

    gtable.crush(ret, module, true)
    gtable.crush(ret._private, args or {})

    return ret
end

return setmetatable(module, { __call = new })
