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

   -- Get some of the nodes into variables.
   local client1 = tree.first_child
   local branch  = tree.first_child.next_sibling
   local client5 = tree.last_child

   --DOC_NEWLINE

   -- Move 'client1' to become 'tree.last_child'.
   tree:append(client1)

   add_tree { tree = tree, label = "Move 'client1' to become 'tree.last_child'."} --DOC_HIDE


   --DOC_NEWLINE

   -- Move 'client5' to become 'branch.last_child'.
   branch:append(client5)
   add_tree { tree = tree, label = "Move 'client5' to become 'branch.last_child'."} --DOC_HIDE
