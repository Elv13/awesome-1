--- A set of generic functions to manipulate layouts.
--
-- Awesome layouts provide multiple parameters
--
-- @tilinglib dynamite.utils
local gobject = require("gears.object")

local module = {}

--- Add or remove pixels in different directions.
--
-- Widgets wishing to implement resizing must listen to the
-- `request.is_accepted` signal. This signal has the originating requestor
-- as the first argument and a request object as the second. The widget must
-- check if the request is already granted using
-- `if request.is_accepted then return end` to avoid a single request to be
-- granted multiple time. Widgets are allowed to modify the `delta` property
-- of the request object without having to accept the request. To accept the
-- request, the widget must call `request:accept(self)`.
--
-- @param self self TODO remove once merged into the layout
-- @tparam widget self The client placeholder or widget to resize.
-- @tparam table delta The amount to resize in each direction.
-- @tparam number args.top
-- @tparam number args.bottom
-- @tparam number args.left
-- @tparam number args.right
-- @staticfct dynamite.utils.resize_widget
function module.resize_widget(_--[[self]], widget, delta)
    -- It uses a request object because returning values form signals is not
    -- supported and problematic. Also, it allows for "lower" widgets in the
    -- hierarchy to track the request even if they are not able to resize
    -- themselves.
    local request = gobject {
        enable_properties   = true,
        enable_auto_signals = true,
    }

    request.delta = delta

    function request:accept()
        request.is_accepted = true
    end

    widget:emit_signal_recursive("request::resize", request)

    return request.is_accepted
end

function module.resize_client(self, c, delta)
    local widget = self.client_to_wrapper[c]
    if not widget then return false end

    return module.resize_widget(self, widget, delta)
end

return module
