--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local add_tree = ...
local awful = { tree = require("awful.tree") }

for i=1, 5 do
    client.gen_fake{ name = "client #"..i }
end

--DOC_HIDE_END

   -- Create a tree.
   local tree = awful.tree {}

--DOC_NEWLINE

   -- Add a bunch of clients.
   for _, c in ipairs(client.get()) do
       tree:append_new {
           client = c,
       }
   end
   add_tree { tree = tree, label = ""} --DOC_HIDE

--DOC_NEWLINE

   -- Wrap client2.
   local second_node = tree.first_child.next_sibling
   local new_branch  = second_node:wrap { label = "new_branch" }
   assert(new_branch.parent == tree) --DOC_HIDE
   assert(new_branch.first_child == second_node) --DOC_HIDE
   add_tree { tree = tree, label = "Wrap client2"} --DOC_HIDE

--DOC_NEWLINE

   -- Move client4 to the new branch.
   local client4_node = tree.last_child.previous_sibling
   new_branch:push(client4_node)
   add_tree { tree = tree, label = "Move client4 to the new branch"} --DOC_HIDE

