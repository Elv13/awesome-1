--DOC_GEN_IMAGE --DOC_NO_USAGE
local module = ... --DOC_HIDE
local ruled = {tag = require("ruled.tag"), client = require("ruled.client")} --DOC_HIDE
local awful = require("awful") --DOC_HIDE
client._autotags = false --DOC_HIDE
require("awful.ewmh") --DOC_HIDE
screen[1]:fake_resize(0, 0, 1280, 720) --DOC_HIDE
screen.fake_add(1300,0,1280,720) --DOC_HIDE

function awful.spawn(name, args) --DOC_HIDE
    return client.gen_fake{class = name, name = name, x = 10, y=10, width = 60, height =50} --DOC_HIDE
end --DOC_HIDE

    ruled.client.connect_signal("request::rules", function()
        -- These are a subset of the default `rc.lua` client rules. If you already
        -- have them, don't add this.
        ruled.client.append_rule {
            rule = {},
            properties = {
                focus     = awful.client.focus.filter,
                raise     = true,
                screen    = awful.screen.preferred,
                placement = awful.placement.no_overlap+awful.placement.no_offscreen
            },
        }
    end)

    --DOC_NEWLINE

    tag.connect_signal("request::rules", function()
        -- Allow tags named "kcalc" to be created on screen 2 and 4, but not
        -- 1 and 3.
        ruled.tag.append_rule {
            rule_every    = {
                class  = {"kcalc"},
                screen = {screen[1]},
            },
            properties  = {
                name        = function(c) return c.class .. " for s1/s3" end,
                icon        = function(c) return c.icon  end,
                view_only   = true,
                multi_class = false,
                max_client  = 2,
                layout      = awful.layout.suit.fair,
                volatile    = true,
                exclusive   = true,
            }
        }

        --DOC_NEWLINE

        -- Different layout if on screen 1 or 3.
        ruled.tag.append_rule {
            rule_any    = {
                class  = {"xterm"},
            },
            properties  = {
                name        = "Terminals",
                icon        = function(c) return c.icon  end,
                view_only   = true,
                multi_class = false,
                layout      = awful.layout.suit.max,
                volatile    = true,
                exclusive   = true,
            }
        }

        --DOC_NEWLINE

        ruled.tag.append_rule {
            rule_every    = {
                class  = {"kcalc"},
                screen = {screen[2]},
            },
            properties  = {
                name        = function(c) return c.class .. " for s2/s4" end,
                icon        = function(c) return c.icon  end,
                view_only   = true,
                multi_class = false,
                max_client  = 2,
                layout      = awful.layout.suit.max,
                volatile    = true,
                exclusive   = true,
            }
        }


    end)

tag.emit_signal("request::rules") --DOC_HIDE
--DOC_NEWLINE

--DOC_NEWLINE

module.add_event("Move the cursor to screen 1 pawn some apps", function() --DOC_HIDE
    -- Move the mouse to screen 1, where it cannot create the tag.
    mouse.coords {
        x = screen[1].geometry.x + 10,
        y = screen[1].geometry.y + 10,
    }

    --DOC_NEWLINE

    -- Spawn some apps.
    local c1 = --DOC_HIDE
    awful.spawn("kcalc")
    local c2 = --DOC_HIDE
    awful.spawn("xterm")

    assert(#c1:tags() == 1) --DOC_HIDE
    assert(c1:tags()[1].name == "kcalc for s1/s3") --DOC_HIDE
    assert(#c2:tags() == 1) --DOC_HIDE
    assert(c2:tags()[1].name == "Terminals") --DOC_HIDE
    assert(c1.screen == screen[1])--DOC_HIDE
    assert(c2.screen == screen[1])--DOC_HIDE

    --DOC_NEWLINE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.add_event("Move to mouse to screen 2 and spawn some more apps", function() --DOC_HIDE
    -- Move the mouse to screen 2, where it can create the tag.
    mouse.coords {
        x = screen[2].geometry.x + 10,
        y = screen[2].geometry.y + 10,
    }

    --DOC_NEWLINE
    local c1 = --DOC_HIDE
    awful.spawn("xterm")
    local c2 = --DOC_HIDE
    awful.spawn("kcalc")

    assert(#c1:tags() == 1, "Get ".. #c1:tags() .." expected 1 "..c1.name) --DOC_HIDE
    assert(c2:tags()[1].name == "kcalc for s2/s4", "\n\nGOT ".. c1:tags()[1].name) --DOC_HIDE
    assert(#c1:tags() == 1, #c2:tags() .." expected 1 "..c2.name) --DOC_HIDE
    assert(c1:tags()[1].name == "Terminals",  "\n\nGOT ".. c2:tags()[1].name) --DOC_HIDE
    assert(c1.screen == screen[2])--DOC_HIDE
    assert(c2.screen == screen[2])--DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE


module.execute { display_label = true, display_mouse = true } --DOC_HIDE
