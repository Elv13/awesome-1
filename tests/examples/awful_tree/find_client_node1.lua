--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local add_tree = ...
local awful = { tree = require("awful.tree") }
local wibox = require("wibox")

for i=1, 5 do
    client.gen_fake{ name = "client #"..i }
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
   local branch = second_node:wrap { label = "branch" }
   local client4_node = tree.last_child.previous_sibling
   branch:push(client4_node)

   branch:append_new {
       wibox = wibox2,
       label = "wibox2",
   }

   add_tree { tree = tree, label = ""} --DOC_HIDE

--DOC_HIDE_END

   -- Remove 'client1'.
   tree:find_client_node(client.get()[1]):detach()
   add_tree { tree = tree, label = "Remove 'client1'"} --DOC_HIDE

   --DOC_NEWLINE

   -- Remove 'client5'.
   branch:find_client_node(client.get()[5]):detach()
   add_tree { tree = tree, label = "Remove 'client5'"} --DOC_HIDE
