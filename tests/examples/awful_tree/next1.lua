--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_ALL --DOC_ASTERISK
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
local new_branch = second_node:wrap { label = "branch" }
local client4_node = tree.last_child.previous_sibling
new_branch:push(client4_node)

local labels = {}

for node in awful.tree.iterate_next(tree, true) do
    local next_node = node.next
    local lbl = (not next_node)
        and "nil"
        or (next_node.label and '"'..next_node.label..'"')
        or "N/A"

    labels[node] = "<i><span color='"..color.."'>next:</span></i> "..lbl
end

add_tree {
    tree        = tree,
    label       = "Move client4 to the new branch",
    node_labels = labels
}
