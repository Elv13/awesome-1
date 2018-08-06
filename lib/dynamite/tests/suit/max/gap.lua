--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local max = require("dynamite.suit.max")

template.name = "dynamite::suit::max::gap"

template.layout_name = "max"

local values = {
    2, 4, 6, 8
}

function template.display.column_label_callback(column)
    return "gap: " .. values[column]
end

template.test = {
    fill_space   = true;
    full_overlap = true;
}

template.screens = {
    {
        width  = 128;
        height = 96;
        count  = 4;
    }
}

template.meta {
    layout   = max;
    mode     = "tag",
    property = "gap";
    count    = 1;
    values   = values,
}

template.arrange()

template.run()
