--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local magnifier = require("dynamite.suit.magnifier")

template.name = "dynamite::suit::magnifier::mwfact"

template.layout_name = "magnifier"

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
    property = "master_width_factor";
    values   = {
        0.2, 0.4, 0.6, 0.8
    },
}

template.arrange()

template.run()
