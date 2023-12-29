--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local add_tree = ...
local awful = { tree = require("awful.tree") }
local beautiful = require("beautiful")
local gcolor = require("gears.color")

local color = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.fg_normal, 0.7))

for i=1, 5 do
    client.gen_fake { name = "client #"..i }
end

local tree = awful.tree {}

for _, c in ipairs(client.get()) do
    tree:append_new {
        client = c,
    }
end

local second_node = tree.first_child.next_sibling
local new_branch = second_node:wrap { label = "branch1" }
local client4_node = tree.last_child.previous_sibling
new_branch:push(client4_node)
local branch2 = client4_node:wrap { label = "branch2" }

local arrows, prev = {}, nil

--DOC_HIDE_END
   for node in awful.tree.iterate_previous(tree.last_child, true) do
       -- Do something.
       table.insert(arrows, { --DOC_HIDE
           from = prev, --DOC_HIDE
           to   = node, --DOC_HIDE
       }) --DOC_HIDE
       prev = node --DOC_HIDE
   end
--DOC_NEWLINE
--DOC_HIDE_START

add_tree {
    tree   = tree,
    label  = "origin: root\ninclusive: true",
    arrows = arrows,
}

arrows, prev = {}, nil

--DOC_HIDE_END
   for node in awful.tree.iterate_previous(tree.last_child, false) do
       -- Do something.
       table.insert(arrows, { --DOC_HIDE
           from = prev, --DOC_HIDE
           to   = node, --DOC_HIDE
       }) --DOC_HIDE
       prev = node --DOC_HIDE
   end
--DOC_NEWLINE
--DOC_HIDE_START

add_tree {
    tree   = tree,
    label  = "origin: root\ninclusive: false",
    arrows = arrows,
}

arrows, prev = {}, nil

--DOC_HIDE_END
   for node in awful.tree.iterate_previous(branch2, true) do
       -- Do something.
       table.insert(arrows, { --DOC_HIDE
           from = prev, --DOC_HIDE
           to   = node, --DOC_HIDE
       }) --DOC_HIDE
       prev = node --DOC_HIDE
   end
--DOC_NEWLINE
--DOC_HIDE_START

add_tree {
    tree   = tree,
    label  = "origin: branch2\ninclusive: true",
    arrows = arrows,
}

arrows, prev = {}, nil

--DOC_HIDE_END
   for node in awful.tree.iterate_previous(branch2, false) do
       -- Do something.
       table.insert(arrows, { --DOC_HIDE
           from = prev, --DOC_HIDE
           to   = node, --DOC_HIDE
       }) --DOC_HIDE
       prev = node --DOC_HIDE
   end
--DOC_HIDE_START

add_tree {
    tree   = tree,
    label  = "origin: branch2\ninclusive: false",
    arrows = arrows,
}
