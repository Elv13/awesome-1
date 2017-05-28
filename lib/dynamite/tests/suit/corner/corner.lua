--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local corner = require("dynamite.suit.corner")

template.name = "dynamite::suit::corner::types"

template.layout_name = "corner"

local labels = {
    "corner.nw",
    "corner.sw",
    "corner.ne",
    "corner.se",
}

function template.display.column_label_callback(column)
    return labels[column]
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
    mode  = "layouts";
    count = 5;

    layouts = {
        corner.nw;
        corner.sw;
        corner.ne;
        corner.se;
    };

    layout_names = {
        "cornernw";
        "cornersw";
        "cornerne";
        "cornerse";
    }
}

template.arrange()

template.run()
