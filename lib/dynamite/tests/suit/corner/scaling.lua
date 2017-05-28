--DOC_HIDE_ALL --DOC_GEN_IMAGE
local template = ...

local corner = require("dynamite.suit.corner")

template.name = "dynamite::suit::corner::scaling"

template.layout_name = "corner"

template.test = {
    fill_space = true;
}

template.screens = {
    { width  = 64; height = 48; count  = 7; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 7; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 7; args = {workarea_sides=3} },
    { width  = 64; height = 48; count  = 7; args = {workarea_sides=3} },
}

template.tag_properties = {
    master_width_factor = 0.66
}

local layouts = {
    corner.nw;
    corner.sw;
    corner.ne;
    corner.se;
}

local layout_names = {
    "cornernw";
    "cornersw";
    "cornerne";
    "cornerse";
}

for i = 0, 3 do
    template.meta {
        mode         = "scaling";
        start_screen = (i*7) + 1,
        stop_screen  = (i+1) * 7,
        layout_name  = layout_names[i+1];
        layout       = layouts[i+1];
    }
end

template.arrange()

template.run()

return {hide_lines=true, radius=2}
