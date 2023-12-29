 --DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START
local module = ...
local awful = {tag = require("awful.tag"), layout = require("awful.layout")}
local beautiful = require("beautiful")
require("awful.ewmh")
screen[1]._resize {x = 0, width = 160, height = 90}
awful.tag({ "one", "two", "three" }, screen[1], awful.layout.suit.tile)
require("_stacking_validation")

local x, y = 10, 10

function awful.spawn(name, properties)
    local props = {
        class    = properties.name,
        floating = true,
        x        = x,
        y        = y,
        width    = 60,
        height   = 50,
    }
    for k, v in pairs(properties) do props[k] = v end
    client.gen_fake(props)
    x, y = x + 10, y + 10
end

module.add_event("Spawn some apps", function()
   --DOC_HIDE_END
   -- Spawn some clients.
   awful.spawn("client", {name = "client #1"})
   awful.spawn("client", {name = "client #2"})
   awful.spawn("client", {name = "client #3"})
   awful.spawn("client", {name = "client #4"})
   --DOC_HIDE_START
end)

module.display_stacking()

module.add_event('Lower "client #4"', function()
   --DOC_HIDE_END
   --DOC_NEWLINE

   -- Raise "client #1"
   client.get()[4]:lower()

   --DOC_HIDE_START
end)

module.display_stacking()


module.execute { display_screen = false, display_clients     = true ,
                 display_label  = false, display_client_name = true }
