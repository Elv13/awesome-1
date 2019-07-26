 --DOC_GEN_IMAGE
local module = ... --DOC_HIDE
local awful = {screen = require("awful.screen"), layout = require("awful.layout") } --DOC_HIDE
local ruled = {screen = require("ruled.screen") } --DOC_HIDE

screen.automatic_factory = false --DOC_HIDE

screen._clear() --DOC_HIDE

function screen._viewports() --DOC_HIDE
    return { --DOC_HIDE
        { --DOC_HIDE
            id = 1, --DOC_HIDE
            geometry = { --DOC_HIDE
                x = 0, y = 0, width = 1024, height = 768 --DOC_HIDE
            }, --DOC_HIDE
            outputs = {{ --DOC_HIDE
                name      = "LVDS1", --DOC_HIDE
                mm_width  = 400, --DOC_HIDE
                mm_height = 300, --DOC_HIDE
            }}, --DOC_HIDE
        },{ --DOC_HIDE
            id = 2, --DOC_HIDE
            geometry = { --DOC_HIDE
                x = 1024, y = 0, width = 1024, height = 768 --DOC_HIDE
            }, --DOC_HIDE
            outputs = {{ --DOC_HIDE
                name      = "LVDS1", --DOC_HIDE
                mm_width  = 400, --DOC_HIDE
                mm_height = 300, --DOC_HIDE
            }}, --DOC_HIDE
        },{ --DOC_HIDE
            id = 3, --DOC_HIDE
            geometry = { --DOC_HIDE
                x = 2028, y = 0, width = 1024, height = 768 --DOC_HIDE
            }, --DOC_HIDE
            outputs = {{ --DOC_HIDE
                name      = "LVDS1", --DOC_HIDE
                mm_width  = 400, --DOC_HIDE
                mm_height = 300, --DOC_HIDE
            }}, --DOC_HIDE
        }, --DOC_HIDE
    } --DOC_HIDE
end --DOC_HIDE

module.add_event("Add a rule to ignore the screen at `x == 1024`", function() --DOC_HIDE
    ruled.screen.append_rule {
        rule       = {x      = 1024 },
        properties = {ignore = true },
    }

    screen.emit_signal("property::_viewports", screen._viewports()) --DOC_HIDE

    assert(screen.count() > 0) --DOC_HIDE

end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute {display_screen=true} --DOC_HIDE
