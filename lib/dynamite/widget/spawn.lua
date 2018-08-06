---------------------------------------------------------------------------
--- Spawn a client in a reserved spot.
--
-- It accept all usual client properties.
--
-- Note: this only works with client with a proper implementation of the startup
-- notification protocol. For other client, see `client.startup_id` for more
-- information about how to make them work.
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2018 Emmanuel Lepage Vallee
-- @module dynamite.widget.spawn
---------------------------------------------------------------------------
local aspawn  = require( "awful.spawn"       )
local wbase   = require( "wibox.widget.base" )
local lbase   = require( "dynamite.base"     )
local gtable  = require( "gears.table"       )

local module = {}

local is_registered = false

local futures = {}

local function arules_callback(c, props, callbacks)
    local args = futures[c.startup_id]

    if args then
        props.tag = args.tag
        lbase._place_client(c, args.tag, args._wdg)
        futures[c.startup_id] = nil
    end

end

local function spawn(self)
    if (not self._private.command) or self._private.command == "" then
        return
    end

    -- Only allow this once, even if the command is replaced.
    if self._private.spawned then
        return
    end

    self._private.spawned = true

    local pid, snid = aspawn(self._private.command)

    -- The command was not found / no memory / no pid / no file descriptor / etc
    if type(pid) == "string" then
        return
    end

    -- Well, it failed, too bad
    if not snid then return end

    futures[snid] = {
        _wdg = self,
        tag = self._private.tag
    }
end

--- The command to be executed.
-- @property command
-- @tparam table|string command The command

--- The delay before spawing the command.
-- @property delay
-- @param number In milliseconds.

--- If the command has to be executed even if the tag isn't selected.
-- @property init
-- @param[opt=false] boolean

--- If the area must be reserved even before the client has been created.
--
-- When set to `true`, this widget will use space even if it is empty.
--
-- @property displace
-- @param[opt=false] boolean

--- The delay before canceling and self destruction.
-- @property timeout
-- @param number In milliseconds.

function module:set_command(com)
    self._private.command = com

    -- Only spawn now if the user say so.
    if self._private.init then
        spawn(self)
    end
end

function module:set_init(v)
    self._private.init = v
    spawn(self)
end

function module:fit(ctx)
    -- There is a race condition if the client starts very, very fast while the
    -- layout is still being parsed.
    self._private.tag = ctx.tag

    return 1, 1
end

-- Make invisible by default.
function module:get_visible()
    return self._private.displace or wbase.widget.get_visible(self)
end

function module:wake_up()
    spawn(self)
end

local function new(_, args)
    local ret = wbase.make_widget(nil, nil, {
        enable_properties = true,
    })

    gtable.crush(ret, module, true)

    if not is_registered then
        local r = require("awful.rules")
        assert(r.add_rule_source(
            "awful.dlayout", arules_callback, {"snid", "awful.spawn"}, {"tyrannical", "awful.rules"}
        ))

        is_registered = true
    end

    return ret
end

return setmetatable(module, {__call = new})
