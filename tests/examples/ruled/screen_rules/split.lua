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
                x = 0, y = 0, width = 1920, height = 1080 --DOC_HIDE
            }, --DOC_HIDE
            outputs = {{ --DOC_HIDE
                name      = "LVDS1", --DOC_HIDE
                mm_width  = 400, --DOC_HIDE
                mm_height = 300, --DOC_HIDE
            }}, --DOC_HIDE
        },{ --DOC_HIDE
            id = 2, --DOC_HIDE
            geometry = { --DOC_HIDE
                x = 0, y = 1080, width = 2560, height = 1080 --DOC_HIDE
            }, --DOC_HIDE
            outputs = {{ --DOC_HIDE
                name      = "DVI1", --DOC_HIDE
                mm_width  = 400, --DOC_HIDE
                mm_height = 300, --DOC_HIDE
            }}, --DOC_HIDE
        } --DOC_HIDE
    } --DOC_HIDE
end --DOC_HIDE

module.add_event("Split ultrawide monitors into 3 screens", function() --DOC_HIDE

    -- Split ultrawide monitors into 3 screens.
    ruled.screen.append_rule {
        rule       = { aspect_ratio = 21/9 }, -- ultrawide
        properties = { split = { ratios = {1/5, 3/5, 1/5 } } },
    }

    screen.emit_signal("property::_viewports", screen._viewports()) --DOC_HIDE

    assert(screen.count() > 0) --DOC_HIDE

end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute {display_screen=true} --DOC_HIDE
