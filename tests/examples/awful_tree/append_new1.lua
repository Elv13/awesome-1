--DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local add_tree = ...
local awful = { tree = require("awful.tree") }

client.gen_fake{ name = "client #1"}
assert(client.get()[1].name ==  "client #1")

--DOC_HIDE_END

   -- Create a tree.
   local tree = awful.tree {}
   add_tree { tree = tree, label = ""} --DOC_HIDE

--DOC_NEWLINE

   -- Create a branch.
   local branch1 = tree:append_new {
       label = "branch1",
   }
   add_tree { tree = tree, label = "Create a branch"} --DOC_HIDE

--DOC_NEWLINE

   -- Create another branch after "branch1".
   tree:append_new {
       label = "branch2",
   }
   add_tree { tree = tree, label = "Create another branch after \"branch1\""} --DOC_HIDE

--DOC_NEWLINE

   -- Add a client to "branch1".
   local client_node = --DOC_HIDE
   branch1:append_new {
       client           = client.get()[1],
       honor_size_hints = false,
       geometry         = {
           x       = 100,
           y       = 100,
           width   = 100,
           height  = 100,
       },
   }

--DOC_HIDE_START

assert(client_node.type == "client")
assert(client_node.client == client.get()[1])

add_tree { tree = tree, label = "Add a client to \"branch1\""}
