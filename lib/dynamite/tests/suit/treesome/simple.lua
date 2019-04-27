--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local treesome = require("dynamite.suit.treesome")

template.name = "dynamite::suit::treesome::gap"

template.layout_name = "treesome"

template.test = {
    fill_space    = true;
    full_overlap  = false;
    deterministic = false;
    --arrange_often = true; --TODO
}

template.view = {
    index_client  = true;
}

template.screens = {
    {
        width  = 128;
        height = 96;
        count  = 4;
    }
}

template.meta {
    layout   = treesome;
    mode     = "scaling",
}

template.arrange()

template.run()
