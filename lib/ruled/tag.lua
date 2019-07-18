---------------------------------------------------------------------------
--- Rules for tags.
--
-- In this first example, we create 9 tags which are automatically initialized
-- even when there is no clients:
--
-- @DOC_ruled_tag_rules_basic_EXAMPLE@
--
-- In this second example, we create a tag called "calculator" which is only
-- created when wither `kcalc`, `gnome-calculator` or `wxmaxima` is started.
-- The tag is also volatile so it will get destroyed when the last client
-- gets closed.
--
-- @DOC_ruled_tag_rules_exclusive_EXAMPLE@
--
-- In this example, the rules are configured to create new tags for each client
-- class and assign at most 2 clients per tag, after which a new tag will be
-- created. It also demonstrate how to use a function on the `index` property
-- to place tags with the same name next to each other.
--
-- @DOC_ruled_tag_rules_groups_EXAMPLE@
--
-- This example shows how to use tag rules to send clients to a specific screen.
--
-- @DOC_ruled_tag_rules_multiscreen1_EXAMPLE@
--
-- Properties available in the rules
-- =================================
--
--@DOC_tag_rules_index_COMMON@
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2011-2019 Emmanuel Lepage Vallee
-- @ruleslib ruled.tag
---------------------------------------------------------------------------

local capi = {screen = screen, tag = tag}
local matcher = require("gears.matcher")
local gtable  = require("gears.table")
local gobject = require("gears.object")
local ascreen = require("awful.screen")

local class_manager, extra_properties, delayed_properties = {}, {}, {}

-- Keep a map of all tags created using the tag rules.
local instances, screen_init = setmetatable({}, {__mode="k"}), false

--[[

 * TODO have a `default` rule when a new tag is needed (ei. when there is none)
 * TODO support having zero tags
 * TODO support eminent style, create_on_next
 * TODO request::position (screen, args)
 * TODO shared_tags examples

awful.tag.rules.add_rule {
    rule = {
        screens  = "all", -- {screen[1]}, "primary", "LVDS-1", {1, 2, 3}
        --screen = "primary",
        classes  = "all", -- {"foo", "bar"}
        --class  = "urxvt",
        -- init  = true,
    },
    properties = {
        name = "lol",
        selected = true,
    },
}
]]

--- Create the tag when the rules are executed or only when clients are tagged.
--
-- They will be created in all matching screens.
--
-- @clientruleproperty init
-- @param[opt=false] boolean
-- @see tag.selected

--- Unselect the current tags and select this client tags when a client is tagged.
--
-- @clientruleproperty switch_to_tags
-- @param[opt=false] boolean
-- @see tag.selected

--- Deselect all tags and select the tag when a client is tagged.
--
-- @clientruleproperty view_only
-- @param[opt=false] boolean
-- @see tag:view_only()

--- Allow multiple classes in the tag.
--
-- When set to false, only clients from the same class will be tagged to this
-- tag.
--
-- @clientruleproperty multi_class
-- @param[opt=true] boolean
-- @see max_client

--- Only tag clients to this tag if it is currently selected.
--
-- If no tag is selected, this is ignored and one will be selected.
--
-- @clientruleproperty only_on_selected
-- @param[opt=true] boolean

-- Keep track of all "static" tag name which can be created by the rules.
local from_name, names = {}, {}

local atag
do
    atag = setmetatable({}, {
        __index = function(_, k)
            atag = require("awful.tag")
            return atag[k]
        end,
        __newindex = error -- Just to be sure in case anything ever does this
    })
end

-- Create a gears.matcher and abuse of the private API to make "awful.tag.rules"
-- look like a rule source when it is in fact a special function.
local trules = matcher()
trules._matching_rules["awful.tag.rules"] = {}

local function get_screen(s)
    return s and capi.screen[s]
end

-- Keep track of the existing tags while allowing them to be GCed
local function register_tag(rule, t)
    instances[rule] = instances[rule] or setmetatable({}, {__mode = "v"})
    table.insert(instances[rule], t)
    t._rule = rule
end

-- Get a tag for the rule.
--
-- Return nil when:
--
-- * There is none
-- * The screen(s) are incompatible
-- * There is too many clients
-- * The tag state is "locked"
--
local function get_tags(rule, args)
    args = args or {}
    local ins = instances[rule]

    -- There is none
    if (not ins) or #ins == 0 then return nil end

    local ret = {}

    for _, t in ipairs(ins) do
        local src_ok = (not args.screen) or t.screen == get_screen(args.screen)

        if src_ok then
            table.insert(ret, t)
        end
    end

    return #ret > 0 and ret or nil
end

-- Prevent clients from different classes to be mixed.
local function check_multiclass(t, class)
    if t.multi_class ~= false then return true end

    for _, c in ipairs(t:clients()) do
        if c.class ~= class then return false end
    end

    return true
end

-- Check the max_client.
local function check_maxclient(t, c)
    if (not t.max_client) or (not c) or #c:tags() == 0 then
        return (not t.max_client) or t.max_client > #t:clients()
    end

    local count = 0

    -- It will happen if the client is already tagged, which happens.
    for _, c2 in ipairs(t:clients()) do
        if c ~= c2 then
            count = count + 1
        end
    end

    return count < t.max_client
end

-- Remove "invalid" existing tags.
local function filter_existing(rule, tags, c)
    local preferred = {}
    local first_only_on_selected, allow_dup = nil, false

    for _, t in ipairs(tags or {}) do

        -- Check the various constraints.
        local select_ok = (not rule.properties.only_on_selected) or t.selected
        local locked_ok = not t.locked
        local max_ok    = check_maxclient(t, c)
        local multi_ok  = check_multiclass(t, c.class)

        -- Some contraints leave the door open to create more instances of the
        -- rule, some don't.
        allow_dup = allow_dup or (not max_ok) or not (multi_ok)

        if select_ok and locked_ok and max_ok and multi_ok then
            table.insert(preferred, t)
--             table.insert(rule.properties.fallback and fallbacks or preferred, t)
        elseif locked_ok and not select_ok then
            first_only_on_selected = first_only_on_selected or t
        end
    end

--     local ret = #preferred > 0 and preferred or fallbacks
    local ret = preferred --TODO deadcode

    return #ret > 0  and ret or nil, first_only_on_selected, allow_dup
end

-- Auto-detect the preferred `args` based on the context.
local function wrap_args(rule, args, c)
    -- Do not modify the original table.
    local nargs = setmetatable({}, {__index = args})

    if not args.screen then
        local scr1, src2 = nil
        if rule.rule and rule.rule.screen then
            scr1 = get_screen(rule.rule.screen)
        elseif rule.rule_any and rule.rule_any.screen then
            for _, s in ipairs(rule.rule_any.screen) do
                src2 = src2 or s
                src1 = s == ascreen.focused() and s
                if src1 then break end
            end
        elseif rule.rule_except and rule.rule_except.screen then
            --TODO
        end

        nargs = scr1 or src2 or (c and c.screen) or ascreen.focused()
    end

    return nargs
end

-- Create a tag for a dynamic rule.
local function create_tag(rule, args, c)
    args = wrap_args(rule, args, c)

    -- Copy the original rule before adding the additional data contained in
    -- `args`. A passthrough metatable cannot be used because `pairs()` has to
    -- work. Also because the properties can be functions.
    local real_rules = {}
    assert(rule.properties)

    for k, v in pairs(rule.properties) do
        local nv = v
        if type(v) == "function" then
            nv = v(c, rule)
        end

        if extra_properties[k] then
            extra_properties[k](nil, c, real_rules, nv)
        elseif not delayed_properties[k] then
            real_rules[k] = nv
        end
    end

    if args.screen and get_screen(args.screen) ~= get_screen(rule.properties.screen) then
        real_rules.screen = args.screen
    end

    -- Make sure the screen is always set.
    --TODO support multi-screen choice
    real_rules.screen = real_rules.screen or (c and c.screen or mouse.screen)

    local name = type(rule.properties.name) == "function" and rule.properties.name(c, rule)
        or rule.properties.name or (c and c.class) or "N/A"

    local t = atag.add(tostring(name), real_rules)

--     for k, v in pairs(rule.properties) do
--         if delayed_properties[k] then
--             delayed_properties[k](t, c, real_rules, v)
--         end
--     end

    register_tag(rule, t)

    return t
end

-- Apply some of the properties again after each client is tagged.
-- This allow to switch_to_tags and viwe_only to work.
local function apply_extra_properties(c, rules)
    for _, rule_pair in ipairs(rules) do
        for prop, value in pairs(rule_pair.rule.properties or {}) do
            if delayed_properties[prop] then
                for _, t in ipairs(rule_pair.tags) do
                    delayed_properties[prop](t, c, value)
                end
            end
        end
    end
end

trules:add_matching_function("awful.tag.rules", function(_, c, props, callbacks)
    -- The difference between this and the "normal" callback is that this one
    -- preserve each matching rules while the "normal" one crushes the
    -- properties into a table. This would make it impossible to multi-tag.
    for _, entry in ipairs(trules:matching_rules(c, rules)) do
        if entry.properties then
            table.insert(props, entry)
        end

        if entry.callback then
            table.insert(callbacks, entry.callback)
        end
    end
end)

-- The tag rules are triggered by client events, so the default implementation
-- isn't what we are looking for.
function trules:_execute(c, matching_rules, callbacks, args)
    -- All tags to set to the client
    local tags, tags_by_screen = {}, {}

    -- First, check for existing tags.
    --
    --FIXME wont work for screens.

    local confirmed_rules, last_resort = {}, nil

    for v, rule in pairs(matching_rules) do
        assert(rule.properties)
        -- Get existing (if any)
        local tgs = get_tags(rule, args)

        local ftgs, fallback, allow_dup = filter_existing(rule, tgs, c)

        last_resort = last_resort or fallback

        if ftgs then
            tgs = ftgs
            table.insert(confirmed_rules, {rule=rule, tags=tgs})
        elseif (not tgs) or #tgs == 0 or allow_dup then
            tgs =  {create_tag(rule, args, c)}

            if #tgs then
                table.insert(confirmed_rules, {rule=rule, tags=tgs})
            end
        else
            tgs = {}
        end

        gtable.merge(tags, tgs)

    end

    if #tags == 0 and last_resort then
        tags = {last_resort}
    end

    -- Make sure only 1 screen is selected.
    for _, t in ipairs(tags) do
        assert(t.screen)
        tags_by_screen[t.screen] = tags_by_screen[t.screen] or {}
        table.insert(tags_by_screen[t.screen], t)
    end

    if c and #tags > 0 then
        c:tags(tags_by_screen[c.screen] or next(tags_by_screen))

        apply_extra_properties(c, confirmed_rules)
    end
end

local module = {_object = {}}

function module._object.find_for_class(class, screen)
    local ret, t = {}, class_manager[class]
    if not t then return ret end

    for k, v in ipairs(t) do
        if (not screen) or v.screen == screen then
            table.insert(ret, v)
        end
    end

    return ret
end

-- For for the client desktop file category.
--
-- Some client provide a path to their matadata file. Some other tend to match
-- the name of the desktop file to their class. Some other, when a client
-- database is loaded, provide ways to match the client within the .desktop
-- metadata.
--
-- function tag.find_for_category(category, screen)
--     --TODO
-- end

function module._object.set_allowed_classes(t, classes)
    assert(type(classes) == "table")
    tag.setproperty(t, "allowed_classes"    , classes)
    tag.setproperty(t, "_allowed_classes_mt", nil)
end

function module._object.get_allowed_classes(t, classes)
    local proxy = tag.getproperty(t, "allowed_classes_mt")

    if not proxy then
        local src  = tag.getproperty(t, "allowed_classes")

        if not src then
            src = {}
            tag.setproperty(t, "allowed_classes" , src )
        end

        proxy = gtable.proxy(src, {
            insert_callback = function(k, v)
                assert(type(v) == "boolean" and type(k) == "string",
                    "The key needs to be a string and the value either true or false"
                )
            end,
            modify_callback = function(_, v)
                assert(type(v) == "boolean" and type(k) == "string",
                    "The key needs to be a string and the value either true or false"
                )
                --
            end,
            remove_callback = function(_, v)
                --
            end
        })
        tag.setproperty(t, "allowed_classes_mt", proxy)
    end

    return proxy
end

function module._object.add_allowed_class(self, class)
    local t = class_manager[class]
    class_manager[class] = t or {}

    table.insert(t, self)
end

local function create_init_tags(rule, new_screen)
    local scrs = {}
    if rule.rule_any and type(rule.rule_any.screen) == "function" then
        scrs = rule.rule_any.screen(nil, rule)
    elseif rule.rule and type(rule.rule.screen) == "function" then
        scrs = {rule.rule.screen(nil, rule)}
    elseif rule.rule_any and rule.rule_any.screen then
        scrs = rule.rule_any.screen
    elseif rule.rule.screen then
        scrs = {rule.rule.screen}
    else
        for s in screen do
            table.insert(scrs, s)
        end
    end

    if #scrs == 0 then return end

    -- Nothing to do.
    if new_screen and not gtable.hasitem(scrs, get_screen(new_screen)) then
        return
    end

    for _, s in ipairs(scrs) do
        create_tag(rule, {screen = s}, nil)
    end
end

function module._object.remove_allowed_class(self, class)
    local t = class_manager[class]
    class_manager[class] = t or {}

    for k, v in ipairs(t) do
        if v == self then
            table.remove(t, k)
            return
        end
    end
end

-- Detect when new tag rules are added.
--
-- When the `init` property is set to true, a tag must be created now.
trules:connect_signal("rule::appended", function(_, rule)
    local nt = type(rule.properties.name)
    -- For `get_or_create_by_name()`.
    if rule.properties and (nt == "string" or nt == "number") then
        if not from_name[rule.properties.name] then
            table.insert(names, rule.properties.name)
        end

        from_name[rule.properties.name] = from_name[rule.properties.name]
            or setmetatable({}, {__mode = "v"})

        table.insert(from_name[rule.properties.name], rule)

        module.emit_signal("name::added", rule.properties.name, rule)
    end

    -- Initialize the tags for all screen
    if rule.properties and rule.properties.init and screen_init then
        create_init_tags(rule, nil)
    end

    module.emit_signal("rule::appended", rule)
end)

-- Help the GC a bit
capi.tag.connect_signal("activated", function(t)
    if (not t.activated) and t._rule and instances[t._rule] then
        for k, t in pairs(instances[t._rule]) do
            table.remove(instances[t._rule], k)
            return
        end
    end
end)

-- Create the `init` tags on new screens.
ascreen.connect_for_each_screen(function(s)
    for _, rule in ipairs(trules._matching_rules["awful.tag.rules"]) do
        if rule.properties and rule.properties.init then
            create_init_tags(rule, s)
        end

        if screen_init and rule.properties and rule.properties.relocator then
            for _, t in ipairs(get_tags(rule) or {}) do
                local new_s, idx = rule.properties.relocator(t, s)

                if new_s then
                    t.screen = new_s
                    if idx then
                        t.index = idx
                    end
                end
            end
        end
    end

    screen_init = true
end)

-- function tag.object.set_allowed_categories(t, classes)
--     assert(type(classes) == "table")
--     tag.setproperty(t, "allowed_categories", classes)
-- end
--
-- function tag.object.get_allowed_categories(t, classes)
--     return tag.getproperty(t, "allowed_categories")
-- end

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
    -- The `intrusive` has already been applied, abides to it.
    if c.intrusive and #c:tags() > 0 then return end

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

--- Return a list of static names for dynamic tags.
--
-- Do *not* modify this list. If a copy is needed, use:
--
--    local names = gears.table.clone(awful.tag.rules.get_names())
--
function module.get_names()
    return names
end

function module.has_name(name)
    return from_name[name] ~= nil
end

--- Get the rules for a tag name.
--
-- Note, do not modify the returned table, make a deep copy if a modified
-- version is needed.
--
function module.rules_for_name(name)
    return from_name[name]
end

--- Configurable way to get "the next tag".
--
-- It can navigate across screens, rotate tags or create new ones.
--
-- The "WMii workflow" is to create a new tag when you reach the last one and
-- remove empty tags.
--
function module.get_next_tag(t, args)
    --TODO eminent style create
    --TODO rotate
    --TODO args.direction
    --TODO args.rotate_tags
    --TODO args.rotate_screens
    --TODO args.fallback
end

-- Handled imperatively.
function extra_properties.init() end
function extra_properties.name() end

-- function extra_properties.multi_class(t, c, props, value)
--     --TODO
-- end

function delayed_properties.switch_to_tags(t, c, props, value)
    atag.viewmore(c and c:tags() or t, c and c.screen or (t and t.screen))
end

function delayed_properties.view_only(t, c, props, value)
    t:view_only()
end

-- Add signals.
gobject._setup_class_signals(module)

--@DOC_rule_COMMON@

return module
