--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local magnifier = require("dynamite.suit.magnifier")

template.name = "dynamite::suit::magnifier::gap"

template.layout_name = "magnifier"

template.test = {
    fill_space = true;
    no_overlap = false;
}

template.screens = {
    {
        width  = 320;
        height = 240;
        count  = 1;
    }
}

template.meta {
    layout   = magnifier;
    property = "master_width_factor";
    values   = {0.5};
    count    = 5;
    mode     = "layouts";
}

template.arrange()

template.run()
