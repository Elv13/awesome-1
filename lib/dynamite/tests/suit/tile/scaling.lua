--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local tile = require("dynamite.suit.tile")

template.name = "dynamite::suit::tile::scaling"

template.layout_name = "tile"

template.test = {
    fill_space = true;
}

template.screens = {
    { width  = 64; height = 48; count  = 4; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 4; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 4; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 4; args = {workarea_sides=3} },
}

template.tag_properties = {
    master_width_factor = 0.66
}

template.display = {
    radius = 2;

}

function template.display.row_label_callback(row)
    return " hi! "..row.." bb bb bb "
end

function template.display.column_label_callback(column)
    return "hi!"..column
end

local layouts = {
    tile;
    tile.left;
    tile.top;
    tile.bottom;
}

local layout_names = {
    "tile";
    "tileleft";
    "tiletop";
    "tilebottom";
}

for i = 0, 3 do
    template.meta {
        mode         = "scaling";
        start_screen = (i*4) + 1,
        stop_screen  = (i+1) * 4,
        layout_name  = layout_names[i+1];
        layout       = layouts[i+1];
    }
end

template.arrange()

template.run()

return {hide_lines=true, radius=2}
