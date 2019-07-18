---------------------------------------------------------------------------
--- Rules for screens.
--
--@DOC_screen_rules_index_COMMON@
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2019 Emmanuel Lepage Vallee
-- @ruleslib ruled.screen
---------------------------------------------------------------------------

--TODO add a count property
--TODO add a dpi property
--TODO add a name property
--TODO add a width_mm, width_inch properties
--TODO add a primary property
--TODO add "names" (and the other) in case of overlapping
--TODO add minimum_dpi/maximum_dpi (and sizes) in case of overlapping
--TODO add a third paramater to the prop callbacks with the area content
--TODO add a scale factor for the DPI, wibox, titlebars and everything.
--TODO add a property to prevent auto-removal (volatile)
--TODO add a property to prevent auto-resizing
--TODO add a replace_timeout to replace a screen with another

--[[

awful.screen.rules.append_rule {
    rule_any = {
        name = "LVDS-1",
    },
    properties = {
        volatile = true,
        dpi = function(_, area) return area.preferred_dpi end,
    },
}

]]


--- The current number of (physical) monitor areas.
--
--
-- @rulematcher area_count
-- @param number

--- The name of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_name
-- @param string

--- The physical width of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_mm_width
-- @param numner

--- The physical height of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_mm_heihgt
-- @param string

--- The least dense DPI of the area.
-- @rulematcher minimum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher maximum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher preferred_dpi
-- @param number

local capi = {screen = screen, tag = tag}
local matcher = require("gears.matcher")
local gtable  = require("gears.table")
local gobject = require("gears.object")


local srules = matcher()

local module = {}



local function get_screen(s)
    return s and capi.screen[s]
end


--- The current number of (physical) monitor areas.
--
--
-- @rulematcher area_count
-- @param number

--- The name of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_name
-- @param string

--- The physical width of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_mm_width
-- @param numner

--- The physical height of the area.
--
-- Note that this only works in the `except_any` or `rule_any` section because
-- an area can have multiple outputs.
--
-- @rulematcher area_mm_heihgt
-- @param string

--- The least dense DPI of the area.
-- @rulematcher minimum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher maximum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher preferred_dpi
-- @param number

--- Remove a source.
-- @tparam string name The source name.
-- @treturn boolean If the source was removed,
function module.remove_rule_source(name)
    return trules:remove_matching_source(name)
end

--- Apply the tag rules to a client.
--
-- This is useful when it is necessary to apply rules after a tag has been
-- created. Many workflows can make use of "blank" tags which wont match any
-- rules until later.
--
-- @tparam client c The client.
function module.apply(c, args)
    local callbacks, props = {}, {}
    for _, v in ipairs(trules._matching_source) do
        v.callback(trules, c, props, callbacks)
    end

    trules:_execute(c, props, callbacks, args)
end

--- Add a new rule to the default set.
-- @param table rule A valid rule.
function module.append_rule(rule)
    trules:append_rule("awful.tag.rules", rule)
end

--- Add a new rules to the default set.
-- @param table rule A table with rules.
function module.append_rules(rules)
    trules:append_rules("awful.tag.rules", rules)
end

--- Remove a new rule to the default set.
-- @param table rule A valid rule.
function module.remove_rule(rule)
    trules:remove_rule("awful.tag.rules", rule)
    module.emit_signal("rule::removed", rule)
end

--- Return an existing dynamic tag or create one.
-- @treturn tag|nil A tag or nil if the name doesn't exist.
function module.get_or_create_by_name(name, screen, args)
    --
end

--- Add a new rule source.
--
-- A rule source is a provider called when a client initially request tags. It
-- allows to configure, select or create a tag (or many) to be attached to the
-- client.
--
-- @tparam string name The provider name. It must be unique.
-- @tparam function callback The callback that is called to produce properties.
-- @tparam client callback.c The client
-- @tparam table callback.properties The current properties. The callback should
--  add to and overwrite properties in this table
-- @tparam table callback.callbacks A table of all callbacks scheduled to be
--  executed after the main properties are applied.
-- @tparam[opt={}] table depends_on A list of names of sources this source depends on
--  (sources that must be executed *before* `name`.
-- @tparam[opt={}] table precede A list of names of sources this source have a
--  priority over.
-- @treturn boolean Returns false if a dependency conflict was found.
-- @function awful.tag.rules.add_rule_source

function module.add_rule_source(name, cb, ...)
    local function callback(_, ...)
        cb(...)
    end

    return trules:add_matching_function(name, callback, ...)
end

-- Add signals.
gobject._setup_class_signals(module)

return module
