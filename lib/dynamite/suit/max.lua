---------------------------------------------------------------------------
--- A layout with clients on top of each other filling all the space
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016 Emmanuel Lepage Vallee
-- @release @AWESOME_VERSION@
-- @module dynamite
---------------------------------------------------------------------------
local dynamic = require( "dynamite.base"         )
local wibox   = require( "wibox"                 )
local l_ratio = require( "dynamite.layout.ratio" )
local stack   = require( "dynamite.layout.stack" )

--- All clients are maximized on top of each other.
--
-- **Client count scaling**:
--
--@DOC_dynamite_suit_max_scaling_EXAMPLE@
--
-- **nmaster effect**:
--
-- Unused
--
-- **ncol effect**:
--
-- Unused
--
-- **master\_width\_factor effect**:
--
-- Unused
--
-- **gap effect**:
--
-- The "useless" gap tag property will change the spacing between clients.
--@DOC_dynamite_suit_max_gap_EXAMPLE@
--
-- **screen padding effect**:
--
--@DOC_dynamite_suit_max_padding_EXAMPLE@
-- See `awful.screen.padding`
-- @clientlayout dynamite.max

local function ctr()
    local main_layout = wibox.widget {
        {
            {
                id     = "main_stack",
                layout = stack,
            },
            layout = l_ratio.vertical
        },
        layout = l_ratio.horizontal
    }

    function main_layout:add(...)
        local mstack = main_layout:get_children_by_id("main_stack")[1]
        mstack:add(...)
    end

    return main_layout
end

local module                     = dynamic("max"       , ctr)
module.fullscreen                = dynamic("fullscreen", ctr)
module.fullscreen.honor_workarea = false
module.fullscreen.honor_gap      = false

return module
-- kate: space-indent on; indent-width 4; replace-tabs on;
