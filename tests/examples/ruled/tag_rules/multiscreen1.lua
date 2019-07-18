--DOC_GEN_IMAGE --DOC_NO_USAGE
local module = ... --DOC_HIDE
local ruled = {tag = require("ruled.tag"), client = require("ruled.client")} --DOC_HIDE
local awful = require("awful") --DOC_HIDE
require("awful.ewmh") --DOC_HIDE
screen[1]:fake_resize(0, 0, 1280, 720) --DOC_HIDE
screen.fake_add(1300,0,1280,720) --DOC_HIDE
screen.fake_add(0,740,1280,720) --DOC_HIDE
screen.fake_add(1300,740,1280,720) --DOC_HIDE

function awful.spawn(name, args) --DOC_HIDE
    local c = client.gen_fake{class = name, name = name, x = 10, y=10, width = 60, height =50} --DOC_HIDE
end --DOC_HIDE

    client.connect_signal("request::rules", function()
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
            rule_any    = {
                class  = {"kcalc"},
                screen = {screen[2], screen[4]},
            },
            properties  = {
                name        = function(c) return c.class end,
                icon        = function(c) return c.icon  end,
                view_only   = true,
                multi_class = false,
                max_client  = 2,
                layout      = awful.layout.suit.fair,
                volatile    = true,
                exclusive   = true,
            }
        }
    end)

tag.emit_signal("request::rules") --DOC_HIDE
--DOC_NEWLINE

--DOC_NEWLINE

module.add_event("Spawn some apps", function() --DOC_HIDE
    -- Spawn some apps.
    awful.spawn("kcalc")
    awful.spawn("xterm")
    awful.spawn("kcalc")
    awful.spawn("xterm")
end) --DOC_HIDE

module.display_tags() --DOC_HIDE


module.execute { display_label = true } --DOC_HIDE
