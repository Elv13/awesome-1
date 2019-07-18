--DOC_GEN_IMAGE --DOC_NO_USAGE
local module = ... --DOC_HIDE
local ruled = {tag = require("ruled.tag"), client = require("ruled.client")} --DOC_HIDE
local awful = {tag = require("awful.tag"), layout = require("awful.layout") } --DOC_HIDE
require("awful.ewmh") --DOC_HIDE
screen[1]._resize {x = 0, width = 128, height = 96} --DOC_HIDE

function awful.spawn(name, args) --DOC_HIDE
    local c = client.gen_fake{class = name, name = name, x = 10, y=10, width = 60, height =50} --DOC_HIDE
end --DOC_HIDE

    -- Try to group tags by name.
    local function group_tags(c, rule)
        local name = type(rule.name) == "function"
            and rule.name(c, rule) or rule.name or c.class

        for idx, t in ipairs(c.screen.tags) do
            if t.name == name then
                return idx + 1
            end
        end
    end

    --DOC_NEWLINE

    tag.connect_signal("request::rules", function()
        -- Create tags for each client class with a maximum of 2 clients per tag.
        ruled.tag.append_rule {
            rule        = {}, -- matches everything
            properties  = {
                name        = function(c) return c.class end,
                icon        = function(c) return c.icon  end,
                view_only   = true,
                multi_class = false,
                max_client  = 2,
                index       = group_tags,
                layout      = awful.layout.suit.fair,
                volatile    = true,
            }
        }
    end)

tag.emit_signal("request::rules") --DOC_HIDE
--DOC_NEWLINE

--DOC_NEWLINE

module.add_event("Spawn some apps", function() --DOC_HIDE
    -- Spawn some apps.
    awful.spawn("kcalc")
    assert(#screen[1].tags == 1) --DOC_HIDE
    awful.spawn("xterm")
    assert(#screen[1].tags == 2) --DOC_HIDE
    awful.spawn("kcalc")
    awful.spawn("xterm")
    assert(#screen[1].tags == 2) --DOC_HIDE
    assert(screen[1].selected_tag.name == "xterm") --DOC_HIDE
    assert(#screen[1].selected_tags == 1) --DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Spawn another kcalc", function() --DOC_HIDE
    -- Spawn another kcalc, it should create a tag next to the original.
    awful.spawn("kcalc")
    assert(screen[1].selected_tag.name == "kcalc") --DOC_HIDE
    assert(#screen[1].selected_tags == 1) --DOC_HIDE
    assert(#screen[1].tags == 3) --DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

--DOC_NEWLINE

module.add_event("Kill all clients", function() --DOC_HIDE
    -- Kill all clients. There is no non-volatile tags, so none should remains.
    for i = #client.get(), 1, -1 do
        client.get()[i]:kill()
    end
    assert(not screen[1].selected_tag) --DOC_HIDE
end) --DOC_HIDE

module.display_tags() --DOC_HIDE

module.execute { display_label = true } --DOC_HIDE
