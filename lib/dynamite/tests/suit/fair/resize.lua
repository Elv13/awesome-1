--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local fair = require("dynamite.suit.fair")

template.name = "dynamite::suit::fair::types"

template.layout_name = "fair"

template.test = {
    fill_space = true;
}

template.screens = {
    {
        width  = 128;
        height = 96;
        count  = 2;
    }
}

template.meta {
    mode  = "layouts";
    count = 5;

    layouts = {
        fair;
        fair.horizontal;
    };

    layout_names = {
        "fair";
        "fairh";
    }
}

template.arrange()

template.run()
