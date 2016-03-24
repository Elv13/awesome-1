--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local tile = require("dynamite.suit.tile")

template.name = "dynamite::suit::tile::padding"

template.layout_name = "tile"

local values = {
    2, 4, 6, 8
}

function template.display.column_label_callback(column)
    return "padding: " .. values[column]
end

template.test = {
    fill_space = true;
}

template.screens = {
    {
        width  = 128;
        height = 96;
        count  = 4;
    }
}

template.tag_properties = {
    master_width_factor = 0.66
}

template.meta {
    layout   = tile;
    mode     = "screen",
    property = "padding";
    count    = 4;
    values   = values,
}

template.arrange()

template.run()
