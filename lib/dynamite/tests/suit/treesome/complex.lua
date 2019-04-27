--DOC_HIDE_ALL --DOC_GEN_IMAGE --DOC_GEN_OUTPUT
local template = ...

local treesome = require("dynamite.suit.treesome")

template.name = "dynamite::suit::treesome::gap"

template.layout_name = "treesome"

template.test = {
    fill_space = true;
    no_overlap = false;
    deterministic = false;
    --arrange_often = true; --TODO
}

template.view = {
    index_client = true;
    show_old     = false;
}

template.screens = {{
    width  = 320;
    height = 240;
}}

template.init_now()

template.set_layout {
    screen = screen[1];
    layout = treesome;
}

local steps = {
    {""                           , function() --[[no-op]]                                     end},
    {"api.horizontal_split = true", function() treesome.api(screen[1]).horizontal_split = true end},
    {"api.vertical_split   = true", function() treesome.api(screen[1]).vertical_split   = true end},
    {"api.tabbed           = true", function() treesome.api(screen[1]).tabbed           = true end},
    {""                           , function() --[[no-op]]                                     end},
}

print("local api = treesome.api(screen[1])")

for _, step in ipairs(steps) do

    if step[1] ~= "" then
        print(step[1])
    end

    step[2]()

    template.add_step(step[2])

    template.add_clients {
        count = 1;
    }

    template.arrange()
end

template.run()
