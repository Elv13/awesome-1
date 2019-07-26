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
                name      = "HDMI1", --DOC_HIDE
                mm_width  = 1328, --DOC_HIDE
                mm_height = 747 , --DOC_HIDE
            }}, --DOC_HIDE
        } --DOC_HIDE
    } --DOC_HIDE

end --DOC_HIDE

module.add_event("Use the least dense DPI when multiple outputs are cloned", function() --DOC_HIDE

    -- Use the least dense DPI when multiple outputs are cloned.
    ruled.screen.append_rule {
        rule_greater = { inch_size = 50 }, -- Force a low DPI for large screens.
        properties   = { dpi       = 72 },
    }

    screen.emit_signal("property::_viewports", screen._viewports()) --DOC_HIDE

    assert(screen.count() > 0) --DOC_HIDE

end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute {display_screen=true} --DOC_HIDE
