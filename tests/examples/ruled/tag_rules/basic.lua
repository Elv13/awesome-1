 --DOC_GEN_IMAGE --DOC_NO_USAGE
local module = ... --DOC_HIDE
local ruled = {tag = require("ruled.tag"), client = require("ruled.client")} --DOC_HIDE
local awful = {tag = require("awful.tag"), layout = require("awful.layout") } --DOC_HIDE
require("awful.ewmh") --DOC_HIDE
screen[1]._resize {x = 0, width = 128, height = 96} --DOC_HIDE

function awful.spawn(name, args) --DOC_HIDE
    local c = client.gen_fake{class = name, name = name, x = 10, y=10, width = 60, height =50} --DOC_HIDE
end --DOC_HIDE

    tag.connect_signal("request::rules", function()
        for i=1, 9 do
            ruled.tag.append_rule {
                rule        = {}, -- matches everything
                properties  = {
                    init             = true,
                    name             = i,
                    selected         = i == 3,
                    fallback         = true,
                    only_on_selected = true,
                }
            }
        end
        assert(#screen[1].tags == 9) --DOC_HIDE
    end)

tag.emit_signal("request::rules") --DOC_HIDE
--DOC_NEWLINE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Spawn kcalc", function() --DOC_HIDE
    -- The calculator will spawn into the currently selected tag.
    awful.spawn("kcalc")
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Spawn xterm", function() --DOC_HIDE
    -- Select tag 1 and tag 5.
    screen[1].tags[3].selected = false
    screen[1].tags[1].selected = true
    screen[1].tags[5].selected = true

    --DOC_NEWLINE

    -- The xterm will be tagged with the 2 selected tags.
    awful.spawn("xterm")
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute { display_label = true } --DOC_HIDE
