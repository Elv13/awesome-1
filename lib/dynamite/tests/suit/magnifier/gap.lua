--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local magnifier = require("dynamite.suit.magnifier")

template.name = "dynamite::suit::magnifier::gap"

template.layout_name = "magnifier"

local values = {
    2, 4, 6, 8
}

function template.display.column_label_callback(column)
    return "gap: " .. values[column]
end

template.test = {
    fill_space = true;
    no_overlap = false;
}

template.screens = {
    {
        width  = 128;
        height = 96;
        count  = 4;
    }
}

template.meta {
    layout   = magnifier;
    mode     = "tag",
    property = "gap";
    values   = values,
}

template.arrange()

template.run()
