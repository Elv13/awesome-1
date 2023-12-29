--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local add_tree = ...
local awful = { tree = require("awful.tree") }
require("awful.client")
local stacking = require("awful.layout._stacking")
local beautiful = require("beautiful")
local gcolor = require("gears.color")
screen[1]._resize {x = 0, width = 320, height = 180}

local color = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.fg_normal, 0.7))

for i=1, 5 do
    client.gen_fake {
        name   = "client #"..i ,
        x      = 20 + 15*i,
        y      = 10 + i*5,
        width  = 120,
        height = 80,
        below  = i == 2,
        ontop  = i == 4
    }
end

local tree = stacking._get_global_stacking()

add_tree {
    tree    = tree,
    label   = "",
    project = true,
}

--DOC_HIDE_END
   -- Raise the client (within the "normal" layer).
   client.get()[3]:raise()
--DOC_HIDE_START

add_tree {
    tree    = tree,
    label   = "<tt>client.get()[3]:raise()</tt>",
    project = true,
}

--DOC_HIDE_END
--DOC_NEWLINE

   -- Move the client from the "below" layer to the "ontop" layer.
   client.get()[2].ontop = true
--DOC_HIDE_START

add_tree {
    tree    = tree,
    label   = "<tt>client.get()[2].ontop = true</tt>",
    project = true,
}
