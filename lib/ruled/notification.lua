---------------------------------------------------------------------------
--- Rules for notifications.
--
--@DOC_wibox_nwidget_rules_urgency_EXAMPLE@
--
-- In this example, we setup a different widget template for some music
-- notifications:
--
--@DOC_wibox_nwidget_rules_widget_template_EXAMPLE@
--
-- In this example, we add action to a notification that originally lacked
-- them:
--
--@DOC_wibox_nwidget_rules_add_actions_EXAMPLE@
--
-- Here is a list of all properties available in the `properties` section of
-- a rule:
--
--@DOC_notification_rules_index_COMMON@
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2017-2019 Emmanuel Lepage Vallee
-- @ruleslib ruled.notifications
---------------------------------------------------------------------------

local capi = {screen = screen, client = client, awesome = awesome}
local matcher = require("gears.matcher")
local gtable  = require("gears.table")
local gobject = require("gears.object")
local naughty = require("naughty")

--- The notification is attached to the focused client.
--
-- This is useful, along with other matching properties and the `ignore`
-- notification property, to prevent focused application from spamming with
-- useless notifications.
--
-- @matchingproperty has_focus
-- @param boolean
-- @usage -- Note that the the message is matched as a pattern.
-- ruled.notification.append_rule {
--     rule       = { message = "I am SPAM", has_focus = true },
--     properties = { ignore  = true}
-- }

--- The notification is attached to a client with this class.
--
-- @matchingproperty has_class
-- @param string
-- @see has_instance
-- @usage
-- ruled.notification.append_rule {
--     rule       = { has_class = "amarok" },
--     properties = {
--         widget_template = my_music_widget_template,
--         actions         = get_mpris_actions(),
--     }
-- }

--- The notification is attached to a client with this instance name.
--
-- @matchingproperty has_instance
-- @param string
-- @see has_class

--- Append some actions to a notification.
--
-- Using `actions` directly is destructive since it will override existing
-- actions.
--
-- @clientruleproperty append_actions
-- @param table

local nrules = matcher()

local function client_match_common(n, prop, value)
    local clients = n.clients

    if #clients == 0 then return false end

    for _, c in ipairs(clients) do
        if c.class == value then
            return true
        end
    end

    return false
end

nrules:add_property_matcher("has_class", function(n, value)
    return client_match_common(n, "class", value)
end)

nrules:add_property_matcher("has_instance", function(n, value)
    return client_match_common(n, "instance", value)
end)

nrules:add_property_matcher("has_focus", function(n, value)
    local clients = n.clients

    if #clients == 0 then return false end

    for _, c in ipairs(clients) do
        if c == capi.client.focus then
            return true
        end
    end

    return false
end)

nrules:add_property_setter("append_actions", function(n, value)
    local new_actions = gtable.clone(n.actions or {}, false)
    n.actions = gtable.merge(new_actions, value)
end)

local module = {}

gobject._setup_class_signals(module)

--- Remove a source.
-- @tparam string name The source name.
-- @treturn boolean If the source was removed,
function module.remove_rule_source(name)
    return nrules:remove_matching_source(name)
end

--- Apply the tag rules to a client.
--
-- This is useful when it is necessary to apply rules after a tag has been
-- created. Many workflows can make use of "blank" tags which wont match any
-- rules until later.
--
-- @tparam naughty.notification n The notification.
function module.apply(n)
    local callbacks, props = {}, {}
    for _, v in ipairs(nrules._matching_source) do
        v.callback(nrules, n, props, callbacks)
    end

    nrules:_execute(n, props, callbacks)
end

--- Add a new rule to the default set.
-- @param table rule A valid rule.
function module.append_rule(rule)
    nrules:append_rule("ruled.notifications", rule)
end

--- Add a new rules to the default set.
-- @param table rule A table with rules.
function module.append_rules(rules)
    nrules:append_rules("ruled.notifications", rules)
end

--- Remove a new rule to the default set.
-- @param table rule A valid rule.
function module.remove_rule(rule)
    nrules:remove_rule("ruled.notifications", rule)
    module.emit_signal("rule::removed", rule)
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
-- @function ruled.notifications.add_rule_source

function module.add_rule_source(name, cb, ...)
    return nrules:add_matching_function(name, function(_, ...) cb() end, ...)
end

-- Add signals.
local conns = gobject._setup_class_signals(module)

-- First time getting a notification? Request some rules.
capi.awesome.connect_signal("startup", function()
    if conns["request::rules"] and #conns["request::rules"] > 0 then
        module.emit_signal("request::rules")

        -- This will disable the legacy preset support.
        naughty.connect_signal("request::preset", function(n)
            module.apply(n)
        end)
    end
end)

--@DOC_rule_COMMON@

return module
