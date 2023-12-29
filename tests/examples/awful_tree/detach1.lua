--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START --DOC_ASTERISK
local add_tree = ...
local awful = { tree = require("awful.tree") }

for i=1, 5 do
    client.gen_fake{ name = "client #"..i }
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
   add_tree { tree = tree, label = ""} --DOC_HIDE

--DOC_HIDE_END

   -- Remove client4.
   tree.last_child.previous:detach()
   add_tree { tree = tree, label = "Remove 'client3'"} --DOC_HIDE

   --DOC_NEWLINE

   -- Remove 'branch'.
   tree.last_child.previous_sibling:detach()
   add_tree { tree = tree, label = "Remove 'branch'"} --DOC_HIDE
