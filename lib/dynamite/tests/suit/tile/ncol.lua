--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local tile = require("dynamite.suit.tile")

template.name = "dynamite::suit::tile::gap"

template.layout_name = "tile"

local values = {
    2, 3, 4, 5
}

function template.display.column_label_callback(column)
    return "n. column: " .. values[column]
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

template.meta {
    layout   = tile;
    mode     = "tag",
    property = "column_count";
    count    = 8;
    values   = values,
}

template.arrange()

template.run()
