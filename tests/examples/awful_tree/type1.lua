--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_ALL --DOC_ASTERISK
local add_tree = ...
local awful = { tree = require("awful.tree") }
local beautiful = require("beautiful")
local gcolor = require("gears.color")
local wibox = require("wibox")

local color = gcolor.to_rgba_string(gcolor.change_opacity(beautiful.fg_normal, 0.7))

for i=1, 5 do
    client.gen_fake { name = "client #"..i }
end

local wibox1, wibox2 = wibox {}, wibox {}

local tree = awful.tree {}

for _, c in ipairs(client.get()) do
    tree:append_new {
        client = c,
    }
end

tree:append_new {
    wibox = wibox1,
    label = "wibox1",
}

local second_node = tree.first_child.next_sibling
local new_branch = second_node:wrap { label = "branch" }
local client4_node = tree.last_child.previous_sibling
new_branch:push(client4_node)

new_branch:append_new {
    wibox = wibox2,
    label = "wibox2",
}

local labels = {}

for node in awful.tree.iterate_next(tree, true) do
    local type = node.type

    if node == node.root then
        type = "awful.tree"
    end

    labels[node] = "<i><span color='"..color.."'>type:</span></i> "..type
end

add_tree {
    tree        = tree,
    label       = "Move client4 to the new branch",
    node_labels = labels
}
