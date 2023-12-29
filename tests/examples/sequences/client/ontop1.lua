 --DOC_GEN_IMAGE --DOC_NO_USAGE --DOC_HIDE_START --DOC_ASTERISK
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
  awful.spawn("client", {name = "client #1", ontop = false})
  awful.spawn("client", {name = "client #2", ontop = true })
  awful.spawn("client", {name = "client #3", ontop = true })
  awful.spawn("client", {name = "client #4", ontop = false})
  --DOC_HIDE_START
end)

module.display_stacking {
    highlight             = {
        ["client #1"] = "Before `:raise()`"
    }
}

module.add_event('Raise "client #1"', function()
  --DOC_HIDE_END
  --DOC_NEWLINE

  -- Raise "client #1"
  client.get()[1]:raise()

  --DOC_HIDE_START
end)

module.display_stacking {
    highlight             = {
        ["client #1"] = "After `:raise()`"
    }
}

module.add_event('Move "client #4" to the ontop layer and #3 to below', function()
  local c3, c2 = client.get()[3], client.get()[2]
  --DOC_HIDE_END
  --DOC_NEWLINE

  -- Move "client #1" to the ontop layer.
  client.get()[3].ontop = true -- now "client #4" due to the :raise() ontop
  client.get()[2].below = true -- now "client #3" due to the :raise() ontop

  --DOC_HIDE_START
  assert(c3.ontop)
  assert(c2.below)
end)

module.display_stacking {
    highlight             = {
        ["client #1"] = "After the layer change"
    }
}


module.execute { display_screen = false, display_clients     = true ,
                 display_label  = false, display_client_name = true }
