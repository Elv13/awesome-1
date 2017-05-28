--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local corner = require("dynamite.suit.corner")

template.name = "dynamite::suit::corner::gap"

template.layout_name = "corner"

local values = {
    2, 4, 6, 8
}

function template.display.column_label_callback(column)
    return "gap: " .. values[column]
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
    layout   = corner;
    mode     = "tag",
    property = "gap";
    values   = values,
}

template.arrange()

template.run()
