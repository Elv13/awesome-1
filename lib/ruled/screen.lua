---------------------------------------------------------------------------
--- Rules for screens.
--
-- This is why you might want to have screen rules:
--
-- * Attach useful names to screens so they can be easily matched by client or
--   tag rules.
-- * Control the various HiDPI knobs.
-- * Define how removing viewports should affect the screens.
-- * Easily handle clone mode like when a projector is connected.
-- * Attach various custom properties to screen objects.
-- * Detect and configure various "modes" like work, office or portable with
--   different workflows.
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
--ruled.screen:
--
--TODO * add a way to select the smallest or biggest viewport when they
--   are embedded into each other
--TODO * add "has_smaller_embdedded" and "has_larger_embdedded" rule props
--
--TODO preserve strategies:
-- * replace: Replace existing non-preserved screens
-- * relocate: Relocate if a new viewport is added
-- * destroy: Do not preserve



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

local capi = {screen = screen, tag = tag}
local matcher = require("gears.matcher")
local gtable  = require("gears.table")
local gobject = require("gears.object")
local gtimer  = require("gears.timer")
local ascreen = require("awful.screen")


local srules = matcher()

local module = {}

local function get_screen(s)
    return s and capi.screen[s]
end

local function get_value(input, vp)
    if type(intput) == "function" then
        return input(vp)
    end

    return input
end

local function find_in_outputs(vp, prop, value)
    local name = get_value(value, vp)

    for _, o in ipairs(vp.outputs) do
        if o[prop] == name then
            return true
        end
    end

    return false
end

--- The current number of (physical) monitor viewports.
--
-- Note that a viewport can have multiple outputs.
--
-- @rulematcher viewport_count
-- @param number

srules:add_property_matcher("viewport_count", function(vp, value)
    return #ascreen._get_viewports() == get_value(value, vp)
end)

--- The number of output attached to the viewport.
--
-- It is normally one, but if, for example, a projector is in "clone mode" with
-- a laptop screen, there will be 2.
--
-- @rulematcher output_count
-- @param number
-- @see is_cloned

srules:add_property_matcher("output_count", function(vp, value)
    return #vp.outputs == get_value(value, vp)
end)

--- True if the viewport has multiple overlapping outputs.
--
-- @DOC_ruled_screen_rules_cloned_EXAMPLE@
--
-- @rulematcher is_cloned
-- @param boolean
-- @see output_count

srules:add_property_matcher("is_cloned", function(vp, value)
    return (#vp.outputs > 1) == get_value(value, vp)
end)

--- The screen aspect ratio.
--
-- The value is obtained by dividing the width (in pixels) with the height
-- (in pixels).
--
-- Note that the matching is permissive up to the second digit for
-- convinience. Some advertized ratios are not accurate and/or are periodic.
--
-- This property is useful to detect ultrawide monitors and vertical monitors.
--
-- @DOC_ruled_screen_rules_split_EXAMPLE@
--
-- @rulematcher aspect_ratio
-- @param number

srules:add_property_matcher("aspect_ratio", function(vp, value)
    value = get_value(value, vp)

    local ratio = vp.geometry.width/vp.geometry.height

    -- 1280x720 (old HDTVs) and 1280x700 (old Apple PowerBooks) and 1280x800
    -- (old Dells and Toshibas) all exist and advertize 16/9 on the boxes. This
    -- gap between the advertized ratio and the factual ratio is too great for
    -- this check, but at least the user don't have to enter 1.7777777 in the
    -- rule.
    return math.abs(ratio - value) < 0.1
end)

--- Check if one of the output is named as such.
--
-- @rulematcher has_name
-- @param string

--- Check if one of the output has this width (in millimeters).
--
-- @rulematcher has_mm_width
-- @param number

--- Check if one of the output has this height (in millimeters).
--
-- @rulematcher has_mm_height
-- @param number

--- Check if one of the output has this diagonal (in millimeters).
--
-- @rulematcher has_mm_size
-- @param number

--- Check if one of the output has this diagonal (in inches).
--
-- @rulematcher has_inch_size
-- @param number

--- Check if one of the output has this dpi (dots per inch).
--
-- @rulematcher has_dpi
-- @param number

for rule_prop, out_prop in pairs {
    has_name      = "name",
    has_mm_width  = "mm_width",
    has_mm_height = "mm_height",
    has_mm_size   = "mm_size",
    has_inch_size = "inch_size",
    has_dpi       = "dpi"
} do
    srules:add_property_matcher(rule_prop, function(vp, value)
        return find_in_outputs(cp, out_prop, value)
    end)
end

--- The viewport horizontal position (in pixels).
-- @rulematcher x
-- @param number

--- The viewport vertical position (in pixels).
-- @rulematcher y
-- @param number

--- The viewport width (in pixels).
-- @rulematcher width
-- @param number

--- The viewport height (in pixels).
-- @rulematcher height
-- @param number

for _, p in ipairs {"x", "y", "width", "height" } do
    srules:add_property_matcher(p, function(vp, value)
        return vp.geometry[p] == get_value(value, vp)
    end)
end

--- The least dense DPI of the area.
-- @rulematcher minimum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher maximum_dpi
-- @param number

--- The least dense DPI of the area.
-- @rulematcher preferred_dpi
-- @param number

--- The smallest diagonal size (in millimeters).
--
-- @rulematcher minimum_mm_size
-- @param number

--- The smallest diagonal size (in inches).
--
-- @DOC_ruled_screen_rules_max_dpi_EXAMPLE@
--
-- @rulematcher minimum_inch_size
-- @param number

--- The largest diagonal size (in millimeters).
--
-- @rulematcher maximum_mm_size
-- @param number

--- The largest diagonal size (in inches).
--
-- @rulematcher maximum_inch_size
-- @param number

--- Remove a source.
-- @tparam string name The source name.
-- @treturn boolean If the source was removed,
-- @staticfct ruled.screen.remove_rule_source
function module.remove_rule_source(name)
    return srules:remove_matching_source(name)
end

-- Apply the tag rules to a client.
--
-- This is useful when it is necessary to apply rules after a tag has been
-- created. Many workflows can make use of "blank" tags which wont match any
-- rules until later.
--
-- @tparam table viewport The client.
-- @staticfct ruled.screen.apply
function module._apply(viewport, args)
    local callbacks, props = {}, {}
    for _, v in ipairs(srules._matching_source) do
        v.callback(srules, viewport, props, callbacks)
    end

    local geo = {}

    -- This viewport will be ignored.
    if props.ignore then
        viewport.ignored = true
        return
    end

    local s = props.screen and get_screen(props.screen)

    -- If this is to use an existing screen, take care of it.
    if s then

        -- Prevent empty viewports.
        if s.data.viewport then
            --TODO? Maybe add a ID queue and merge all delayed calls into 1?
            -- This probably wont work well with split screens.
            gtimer.delayed_call(
                function() recycle_viewport(s.data.viewport.id) end
            )
        end

        s.geometry = viewport.geometry

        viewport.screen, props.screen = s, nil

        -- There could be other relevant properties.
        srules:_execute(s, props, callbacks, args)

        return
    end

    for _, p in ipairs {"x", "y", "width", "height" } do
        geo[p] = props[p] or viewport.geometry[p]
    end

    local s = capi.screen.fake_add(
        geo.x,
        geo.y,
        geo.width,
        geo.height,
        {_managed = true}
    )

    viewport.screen = s

    srules:_execute(s, props, callbacks, args)
end

--- Add a new rule to the default set.
-- @param table rule A valid rule.
-- @staticfct ruled.screen.append_rule
function module.append_rule(rule)
    srules:append_rule("awful.tag.rules", rule)
end

--- Add a new rules to the default set.
-- @param table rule A table with rules.
-- @staticfct ruled.screen.append_rules
function module.append_rules(rules)
    srules:append_rules("awful.tag.rules", rules)
end

--- Remove a new rule to the default set.
-- @param table rule A valid rule.
-- @staticfct ruled.screen.remove_rule
function module.remove_rule(rule)
    srules:remove_rule("awful.tag.rules", rule)
    module.emit_signal("rule::removed", rule)
end

--- The strategy to use when the viewport is removed.
--
-- The possible values are:
--
-- * **replace**: Replace existing non-preserved screens with this screen. If no
--  other non-replaceable screen exist, it will split the remaining screen to
--  make room for this one.
-- * **destroy**: Do not preserve and destroy the screen.
-- * **relocate**: Relocate if a new viewport is added at the same time. This
--  is better then viewports are simply moved
--  *(default)*.
-- * **keep**: Never destroy the screen even if it gets out of sight. It is good
--  when temporarily removing a viewport only to add it back (like moving from
--  work to home when both have an identical external screen).
--
-- Note that sometime it is easier to relocate the tags than to relocate the
-- screens.
--
-- @clientruleproperty persistence_strategy
-- @param string
-- @see timeout

--- A screen object (or function to pick one) to move to this viewport.
--
-- Instead of creating a new screen object, reuse an existing one. Note that
-- that if the `screen` had a viewport that still exists, it once it is moved,
-- the rules will be applied on that viewport.
--
-- @clientruleproperty screen

srules:add_property_setter("screen", function(s, value)
    value.screen = get_value(value, s)
end)

--- The geometry for this screen.
--
-- If none are provided, the viewport geometry will be used.
--
-- @clientruleproperty geometry
-- @tparam table geometry
-- @tparam number geometry.x
-- @tparam number geometry.y
-- @tparam number geometry.width
-- @tparam number geometry.height

--- The screen DPI.
-- @clientruleproperty dpi
-- @param number

--- If this screen is the primary screen.
--
-- @clientruleproperty primary
-- @param boolean

--- A timeout before destroying the screen once its viewport is gone.
--
-- Sometime, changing the screen layout can be done with multiple steps. In that
-- case, there will be a window of time where the viewports will be in the
-- "wrong" state. A timeout (in seconds) longer than this window of invalidity
-- will help avoid unnecessary screen creation and destruction.
--
-- @clientruleproperty timeout
-- @param number

--- When set to true, the screen wont be created.
--
-- This way the viewport can be ignored. This doesn't prevent from moving
-- floating clients to this area or having some static fullscreen clients there
-- like Kodi. When set, there will be no screen object, so no wallpaper, wibar
-- or tiled client area for that viewport.
--
-- @DOC_ruled_screen_rules_ignore_EXAMPLE@
--
-- @clientruleproperty ignore
-- @param boolean

-- The screen padding.
-- @clientruleproperty padding
-- @tparam table|number padding
-- @see screen.padding

--- The screen name.
--
-- This is useful to access the screen from `ruled.client` or `ruled.tag`
-- without having to write screen detection code.
--
-- Note that "primary" and any output names are reserved and should not be used.
--
-- @clientruleproperty name
-- @param string

--- Split the viewport into multiple screens.
--
-- When using ultrawide monitors or rotating a secondary screen vertically, it
-- is sometime helpful to split them into virtual screens with their own tags
-- and tiled layouts.
--
-- @DOC_ruled_screen_rules_split_EXAMPL
--
-- @clientruleproperty split
-- @see screen.split

srules:add_property_setter("split", function(s, value)
    local args = get_value(value, s)

    assert(type(args) == "table" and args.ratios,
        "The `split` property needs to be a table containing a `ratios` table"
    )

    local orientation = args.orientation or nil

    --FIXME
    s:split(args.ratios, orientation) --TODO get the viewport, somehow
end)

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
-- @staticfct awful.tag.rules.add_rule_source

function module.add_rule_source(name, cb, ...)
    local function callback(_, ...)
        cb(...)
    end

    return srules:add_matching_function(name, callback, ...)
end

-- Add signals.
gobject._setup_class_signals(module)

-- Auto create some extra "magic" properties based on existing output names.
local magic_properties = {}

capi.screen.connect_signal("request::_rules_create", function(viewport, args)

    -- Very useful with the "rule_every" section of the rule to match an exact
    -- setup.
    if viewport.outputs and #viewport.outputs > 0 then
        for _, o in ipairs(viewport.outputs) do
            if o.name and not magic_properties[o.name] then

                srules:add_property_matcher("is_"..o.name.."_connected", function(vp, value)
                    local vps  = ascreen._get_viewports()
                    local name = get_value(value, vp)

                    -- The extra loop is required because the outputs<->viewport
                    -- assassination can change over time. Given the purpose of
                    -- this rule property, the odds are rather high it will
                    -- happen in this context.
                    for _, vp2 in ipairs(vps) do
                        for _, o2 in ipairs(vp2.outputs) do
                            if o.name == name then
                                return true
                            end
                        end
                    end

                    return false
                end)

                srules:add_property_matcher(o.name.."_geometry", function(vp, value)
                    local vps = ascreen._get_viewports()
                    local geo = get_value(value, vp)

                    for _, vp2 in ipairs(vps) do
                        for _, o2 in ipairs(vp2.outputs) do
                            if o.name == name then
                                -- Allow partially defined geometries.
                                for _, p in ipairs {"x", "y", "width", "height" } do
                                    if geo[p] and geo[p] ~= vp2.geometry[p] then
                                        return false
                                    end
                                end
                                return true
                            end
                        end
                    end

                    return false
                end)

                magic_properties[o.name] = true
            end
        end
    end

    module._apply(viewport, args)
end)

--@DOC_rule_COMMON@

return module
