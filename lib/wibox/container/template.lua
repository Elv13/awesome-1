---------------------------------------------------------------------------
--
-- A container designed to update its child widget value automatically.
--
-- This container parses the Lua code of the `reactive` functions to generate
-- the list of all object `connect_signal`s it needs to always display
-- up-to-date values. The goal of this widget is to enable easier model/view
-- when using the declarative syntax.
--
-- To use this container, you need to first define some `gears.objects` for
-- your model. You can use the existing Awesome API ones like `client`s or
-- `screen`s too. Here is a simple `gears.object`
--
--    local myobject = gears.object {
--        enable_properties   = true,
--        enable_auto_signals = true,
--    }
--    myobject.foo = 42
--
-- In this example, the `myobject` object has a `foo` property set to `42`. If
-- this property is modified later on and a `wibox.container.interval`
-- `reactive` expression contain it, the template will be updated to the new
-- value. Note that it only works with `gears.object` and constant values. It
-- cannot detect that a string or a normal table upvalue changed. It also
-- doesn't try to recursively parse each functions called by the expression
-- because it would be exponentially too slow. Within those limitation, the
-- system should be reliable.
--
--@DOC_wibox_container_defaults_interval_EXAMPLE@
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2018 Emmanuel Lepage Vallee
-- @classmod wibox.container.template
---------------------------------------------------------------------------

local gtable = require("gears.table")
local base = require("wibox.widget.base")

local module = { mt = {}, _accept_templates = true }

-- Convert into a flat list of parents.
local function build_path(path)
    local ret = {}
    while path do
        table.insert(ret, path.template)
        path = path.parent
    end

    return ret
end

local counter2 = 1

-- Parse the child widget tree and find how to access each roles.
local function drill(templates, parent, roles)
    -- All widgets must have ids
    if not templates.id then
        templates.id = "widget"..counter2
        counter2 = counter2 + 1
    end

    for property, v in pairs(templates) do
        local t = type(v)
        if t == "string" then
            for var, val in pairs(roles) do
                if var == v then
                    table.insert(
                        val, {
                            path = build_path{
                                parent   = parent,
                                template = templates,
                                property = property
                            },
                            property = property
                        }
                    )

                    -- Remove the value before the instance is created
                    templates[property] = nil
                end
            end
        elseif t == "table" and type(property) == "number" then
            drill(v, {parent = parent, template = templates}, roles)
        end
    end
end

-- Add some missing "id" properties to make sure the children widgets are
-- accessible.
local function fix_ids(roles)
    local ret = {}

    for role, instances in pairs(roles) do
        for _, instance in ipairs(instances) do
            local path = {}
            for _, frame in ipairs(instance.path) do
                table.insert(path, 1, frame.id)
            end

            table.remove(path, 1)

            if not ret[role] then
                ret[role] = {}
            end

            table.insert(ret[role], {path = path, property = instance.property})
        end
    end

    return ret
end

-- Convert the template into a widget instance.
local function init_template(template, roles)
    local inverted = {}

    for _, v in ipairs(roles) do
        inverted[v] = {}
    end

    drill(template, nil, inverted)

    local by_id = fix_ids(inverted)

    local wdg = base.make_widget_from_value(template)

    return wdg, by_id
end

function module:set_templates(templates)
    self._private.templates = templates[1]

    -- Thanks to the unpredictable property loading order try to parse now or
    -- wait until `set_variable` is called.
    if self._private.roles then
        self._private.widget, self._private.role_paths = init_template(
            self._private.templates, self._private.roles
        )
        self:emit_signal("widget::layout_changed")
        self:emit_signal("widget::redraw_needed")
    end
end

-- Layout this widget
function module:layout(_, width, height)
    if self._private.widget then
        return { base.place_widget_at(self._private.widget, 0, 0, width, height) }
    end
end

-- Fit this widget into the given area
function module:fit(context, width, height)
    if not self._private.widget then
        return 0, 0
    end

    return base.fit_widget(self, context, self._private.widget, width, height)
end

-- Get a list of all upvalue gears.objects
local function get_obj_list(fn)
    local ret = {}

    for i = 1, math.huge do
        local name, val = debug.getupvalue(fn, i)
        if not name then break end

        if type(val) == "table" and val.connect_signal then --FIXME use pcall for client and tag to work
            ret[name] = val
        end
    end

    return ret
end

-- Replace the upvalues with the proxy objects
local function setfenv2(original, proxy, env) -- luacheck: globals setfenv (compatibility with Lua 5.1)
    for i = 1, math.huge do
        local name = debug.getupvalue(original, i)
        if not name then break end

        if name ~= "_ENV" then
            debug.setupvalue(proxy, i, env[name])
        end
    end
end

local function getfenv2(fn)
    local ret = {}
    for i = 1, math.huge do
        local name, val = debug.getupvalue(fn, i)
        if not name then break end

        if name == "_ENV" then
            ret = setmetatable(ret, {__index = val})
        else
            ret[name] = val
        end
    end

    -- Sometime the _ENV is optimized away
    return ret
end

local function apply_role(self, role, func)
    local result = func()
    print("EVAL AGAIN", result, role)
    -- Find all widgets and update them
    for _, paths in ipairs(self._private.role_paths[role] or {}) do
        local w = self._private.widget
        for _, v in ipairs(paths.path) do
            w = w[v]
        end

        if w then
            w[paths.property] = result
        end
    end
end

-- Connect all signals
local function recursive_connect(children_proxy, source, callback)
    for _, prop in ipairs(children_proxy) do
        print("   prop:", prop.name)
        if source then
            source:connect_signal("property::"..prop.name, callback)
            if type(prop) == "table" and #(rawget(prop, "children") or {}) > 0 then
                --FIXME it need to disconnect the old signal when the object changes
                recursive_connect(rawget(prop, "children"), source[prop.name], callback)
            end
        end
    end
end

function module:set_reactive(functions)
    -- Build the list of roles
    self._private.roles = {}

    for var, func in pairs(functions) do
        local old_env = getfenv2(func) or {}
        local real_env = get_obj_list(func)

        table.insert(self._private.roles, var)

        -- Create a "fake" gears.object and use it to spy on which child objects
        -- or properties are used. Right now this system doesn't actually proxy
        -- method calls and properties values to the real object, but it could
        -- be implemented if more complex reactive expressions need to be
        -- supported.
        local function create_proxy_object(self2, name)
            local mt = { __index = create_proxy_object }

            -- For now, only shim math operations. __eq need real proxies
            for _, v in ipairs {"__add", "__unm", "__sub", "__mul", "__div",
                                "__idiv", "__mod", "__pow", "__concat" } do
                mt[v] = function() end
            end

            local o = setmetatable({name = name, parent = self2, children = {}}, mt)

            if self2 then
                table.insert(self2.children, o)
            end

            return o
        end

        -- This, along with some debug introspection calls allow to "parse" the
        -- function to get the list of gears.object properties to track. This,
        -- in turn allow to build a list of `connect_signal` to detect when to
        -- refresh the template.
        local ast_builder = nil
        ast_builder = setmetatable({}, {__index = function(_, key)
            -- This will happen if the object is from _ENV or _G
            if (not real_env[key]) and old_env[key] then
                local o = old_env[key]
                if type(o) == "table" and o.connect_signal then
                    o = create_proxy_object(nil, key)
                    ast_builder[key] = o
                    return ast_builder[key]
                end
            end

            return real_env[key] or old_env[key] end
        })

        -- Create dummy top level objects
        for k in pairs(real_env) do
            local o = create_proxy_object(nil, k)
            ast_builder[k] = o
        end

        -- Create a copy of the function
        local f = load(string.dump(func), nil, nil, ast_builder)

        -- Clone the upvalues
        setfenv2(func, f, ast_builder)

        -- Everything that isn't an expression is not supported and may fail
        pcall(f)

        local function callback()
            apply_role(self, var, func)
        end

        for _, obj in pairs(ast_builder) do
            print("\nVAR: ", obj.name)
            recursive_connect(obj.children, real_env[obj.name], callback)
        end
    end

    -- Either `templates` or `roles` is set first depending on the hash
    -- iteration order. Once both are set, create the widget.
    if self._private.templates then
        self._private.widget, self._private.role_paths = init_template(
            self._private.templates, self._private.roles
        )
        self:emit_signal("widget::layout_changed")
        self:emit_signal("widget::redraw_needed")
    end
end

local function new(args)
    args = args or {}
    local ret = base.make_widget(nil, nil, {enable_properties = true})

    gtable.crush(ret, module, true)
    gtable.crush(ret, args)

    return ret
end



function module.mt:__call(...)
    return new(...)
end

--@DOC_widget_COMMON@

--@DOC_object_COMMON@

return setmetatable(module, module.mt)
