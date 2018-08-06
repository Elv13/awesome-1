--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local max = require("dynamite.suit.max")

template.name = "dynamite::suit::max::gap"

template.layout_name = "max"

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
    mode     = "scaling",
}

template.arrange()

template.run()
