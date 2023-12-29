--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_ALL --DOC_ASTERISK
local add_tree = ...
local awful = { tree = require("awful.tree") }
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

local tree = awful.tree {}

local ontop   = tree:append_new { label = "ontop"   }
local above   = tree:append_new { label = "above"   }
local normal  = tree:append_new { label = "normal"  }
local below   = tree:append_new { label = "below"   }
local desktop = tree:append_new { label = "desktop" }

ontop:append_new  { client = client.get()[4] }
local two = below:append_new  { client = client.get()[2] }
normal:append_new { client = client.get()[1] }
local three = normal:append_new { client = client.get()[3] }
normal:append_new { client = client.get()[5] }
normal:append_new { label = "awful.wibar" }


desktop:append_new { label = "desktop_icons"   }
desktop:append_new { label = "awful.wallpaper" }

add_tree {
    tree    = tree,
    label   = "",
    project = true,
}

normal:push(three)

add_tree {
    tree    = tree,
    label   = "<tt>client.get()[3]:raise()</tt>",
    project = true,
}

ontop:append(two)
client.get()[2].ontop = true

add_tree {
    tree    = tree,
    label   = "<tt>client.get()[2].ontop = true</tt>",
    project = true,
}
