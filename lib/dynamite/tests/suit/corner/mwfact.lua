--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local corner = require("dynamite.suit.corner")

template.name = "dynamite::suit::corner::mwfact"

template.layout_name = "corner"

local values = {
    0.2, 0.4, 0.6, 0.8
}

function template.display.column_label_callback(column)
    return "m. w. fact: " .. values[column]
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
    layout   = corner;
    mode     = "tag",
    property = "master_width_factor";
    values   = values,
}

template.arrange()

template.run()
