 --DOC_GEN_IMAGE --DOC_NO_USAGE
local module = ... --DOC_HIDE
local ruled = {tag = require("ruled.tag"), client = require("ruled.client") } --DOC_HIDE
local awful = {tag = require("awful.tag"), layout = require("awful.layout")} --DOC_HIDE
require("awful.ewmh") --DOC_HIDE
screen[1]._resize {x = 0, width = 128, height = 96} --DOC_HIDE

function awful.spawn(name, args) --DOC_HIDE
    local c = client.gen_fake{class = name, name = name, x = 10, y=10, width = 60, height =50} --DOC_HIDE
end --DOC_HIDE

    -- Add some **tag** rules. Note that the `rule` and `rule_any` section
    -- actually match clients.
    tag.connect_signal("request::rules", function()
        -- Create 4 generic "workspace like" tags at startup.
        for k, name in ipairs { "one", "two", "three", "four" }  do
            ruled.tag.append_rule {
                rule        = {}, -- matches everything
                properties  = {
                    init             = true,
                    name             = name,
                    selected         = k == 3,
                    only_on_selected = true,
                    fallback         = true,
                    layout           = awful.layout.suit.floating,
                    view_only        = true,
                }
            }
        end

        assert(#screen[1].tags == 4) --DOC_HIDE
        assert(screen[1].selected_tag.name == "three") --DOC_HIDE

        --DOC_NEWLINE

        -- Create a "Calculator" only when a new calculator is spawned.
        ruled.tag.append_rule {
            rule_any    = {
                class = {"gnome-calculator", "kcalc", "wxmaxima"}
            },
            properties  = {
                init      = false,
                name      = "Calculator",
                index     = 4,
                view_only = true,
                exclusive = true,
                volatile  = true,
                layout    = awful.layout.suit.fair
            }
        }
    end)

tag.emit_signal("request::rules") --DOC_HIDE

--DOC_NEWLINE

    -- Add a **client** rule to allow `kcolorchooser` to be added to the
    -- selected tags regardless of their `exclusive` or `locked` properties.
    client.connect_signal("request::rules", function()
        ruled.client.append_rule {
            rule_any    = {
                class = {"kcolorchooser"}
            },
            properties = {
                intrusive = true,
            },
        }
    end)

client.emit_signal("request::rules") --DOC_HIDE

--DOC_NEWLINE

module.display_tags() --DOC_HIDE


--DOC_NEWLINE

module.add_event("Spawn kcalc", function() --DOC_HIDE
    assert(#screen[1].tags == 4) --DOC_HIDE

    -- Spawn a Calculator.
    awful.spawn("kcalc")

    assert(#screen[1].tags == 5) --DOC_HIDE
    assert(#screen[1].selected_tags == 1) --DOC_HIDE
    assert(screen[1].selected_tag.name == "Calculator") --DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE
--DOC_NEWLINE

module.add_event("Spawn kcolorchooser", function() --DOC_HIDE
    -- Spawn a kcolorchooser, which should enter the tag because it is intrusive.
    awful.spawn("kcolorchooser")

    assert(#screen[1].tags == 5) --DOC_HIDE
    assert(screen[1].selected_tag.name == "Calculator") --DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Spawn xterm", function() --DOC_HIDE
    -- Spawn xterm, it should pick another tag because it isn't allowed into
    -- the exclusive tag.
    awful.spawn("xterm")
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Kill kcalc and kcolorchooser", function() --DOC_HIDE
    -- Kill kcalc and kcolorchooser, the "Calculator" will be destroyed
    -- because it is volatile.
    for _, c in ipairs(client.get()) do
        if c.class == "kcalc" then
            c:kill()
        end
    end

    --DOC_NEWLINE

    for _, c in ipairs(client.get()) do
        if c.class == "kcolorchooser" then
            c:kill()
        end
    end
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute { display_label = true } --DOC_HIDE
