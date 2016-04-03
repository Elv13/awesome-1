---------------------------------------------------------------------------
--- A drop-in replacment for the stateless layout suits
--
-- This system also add the possibility to write handlers enabling the use
-- of tabs, spliters or custom client decorator.
--
-- Any wibox.layout compliant layout can be implemented. Monkey-patching
-- `dynamite.widget.placeholder` also allow modules to define extra features
-- for tiled clients.
--
-- To enable this system, add `require("dynamite")` at the top
-- of your `rc.lua`
--
-- Overview
-- --------
--
-- There is 4 ways to use this module. The first one replicates the traditional
-- way AwesomeWM tiling works. There is preprogrammed `suit`s. Each suits will
-- place the `client`s according to a set of rules. This is called automatic
-- tiling and is the default.
--
-- The second way is to use custom suits created using the declarative syntax.
-- unlike the old Awesome 1.x-4.x custom layout suits, it is no longer
-- necessary to have Ph.D in geometry to get it right. It also handle features
-- such as resizing that were never really supported by custom layouts.
--
-- The third way is manual tiling. You start with a maximized client, then
-- manually subdivise the space as you go.
--
-- Finally, it is possible to use the `floating` suit, in which case the whole
-- thing is irrelevant and there the tiling is handled by the snapping feature.
--
-- Components
-- ----------
--
-- This module provide extended versions of many `wibox` widgets and layouts.
-- They add extra features such as:
--
-- * Mouse resizing to the existing layouts.
-- * "Insertion points" to dynamically alter the layout
-- * Sleep and awake mode to avoid using CPU when the layout isn't displayed
--
-- While the normal variants of the layouts can be used directly, it is
-- highly recommended to use the `dynamite` versions of those layouts to avoid
-- experiencing some bugs.
--
-- TODO add an auto generated list of layouts and widgets
--
-- Custom layout examples
-- ----------------------
--
-- **Simple tiling layout**:
--
--@DOC_dynamite_suit_manual_scaling1_EXAMPLE@
--
-- **In place client spawning**:
--
-- The `dynamite.widget.spawn` allows to add "future" clients directly into
-- a layout:
--
--    local mycustomtilelayout = dynamite {
--        {
--            {
--                command = "urxvt -e 'bash -c \"nano ~/.config/awesome\"'",
--                widget = dynamite.widget.spawn,
--            },
--            max_elements = 1,
--            priority     = 3,
--            layout       = dynamite.layout.ratio.vertical
--        },
--        {
--            {
--                command = "urxvt -e 'top'",
--                widget = dynamite.widget.spawn,
--            },
--            reflow       = true,
--            max_elements = 3,
--            priority     = 1,
--            layout       = dynamite.layout.ratio.vertical
--        },
--        layout = dynamite.layout.ratio.horizontal
--    }
--
-- See the `client.startup_id` for an overview of the limitations and
-- workarounds available to mitigate them.
--
-- **A column and a layout.tabbed stack**:
--
--@DOC_dynamite_suit_manual_scaling2_EXAMPLE@
--
-- **Using master width factor and alignment**:
--
--@DOC_dynamite_suit_manual_scaling3_EXAMPLE@
--
-- **Adding margins:**:
--
--@DOC_dynamite_suit_manual_scaling_margin_EXAMPLE@
--
-- **Apply a reflection:**:
--
--@DOC_dynamite_suit_manual_mirror_EXAMPLE@
--
-- **Use different layouts depending on the number of clients:**:
--
-- A basic use case with 2 type of layouts depending only on the number of
-- client.
--
--@DOC_dynamite_suit_manual_conditional_EXAMPLE@
--
-- A more useful example using "real" layout suites:
--
--@DOC_dynamite_suit_manual_conditional2_EXAMPLE@
--
-- Serialization and introspection
-- -------------
--
-- TODO show how to use `awesome-client` to extract and load layouts.
--
-- FAQ
-- ---
--
-- **Is it possible to create all layouts using the declarative syntax**:
--
-- No, creating "complex" suits is required to use more advanced layout
-- features like `master_width_factor` and `master_fill_policy`. Declarative
-- custom layouts is usually good enough for the normal use cases if you
-- don't plan to use these properties.
--
-- **If there a change of behavior compared to the classic AwesomeWM layout, is it a bug?**:
--
-- It is probable a bug. Some suits gained new features such as better resizing
-- or using tabs when there is too many clients, but otherwise they should behave
-- the same as they used to do.
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016-2018 Emmanuel Lepage Vallee
-- @tilinglib dynamite
---------------------------------------------------------------------------
local static = require( "awful.layout" )

local suits = {
    tile      = require("dynamite.suit.tile"      ),
    fair      = require("dynamite.suit.fair"      ),
    max       = require("dynamite.suit.max"       ),
    corner    = require("dynamite.suit.corner"    ),
    tree      = require("dynamite.suit.treesome"  ),
    magnifier = require("dynamite.suit.magnifier" ),

    layout = require("dynamite.layout"),
    widget = require("dynamite.widget"),
}

-- Monkeypatch the stateless layout system so the dynamic versions are used
local to_replace = {
    [static.suit.tile           ] = suits.tile           ,
    [static.suit.tile.left      ] = suits.tile.left      ,
    [static.suit.tile.bottom    ] = suits.tile.bottom    ,
    [static.suit.tile.top       ] = suits.tile.top       ,
    [static.suit.fair           ] = suits.fair           ,
    [static.suit.fair.horizontal] = suits.fair.horizontal,
    [static.suit.max            ] = suits.max            ,
    [static.suit.max.fullscreen ] = suits.max.fullscreen ,
    [static.suit.corner.nw      ] = suits.corner.nw      ,
    [static.suit.corner.ne      ] = suits.corner.ne      ,
    [static.suit.corner.sw      ] = suits.corner.sw      ,
    [static.suit.corner.se      ] = suits.corner.se      ,
    [static.suit.magnifier      ] = suits.magnifier      ,
}

for k, v in ipairs(static.layouts) do
    if to_replace[v] then
        static.layouts[k] = to_replace[v]
    end
end

static.suit.tile      = suits.tile
static.suit.fair      = suits.fair
static.suit.max       = suits.max
static.suit.corner    = suits.corner
static.suit.treesome  = suits.tree
static.suit.corner    = suits.corner
static.suit.magnifier = suits.magnifier

suits.register = require("dynamite.base").register

local custom = require("dynamite.suit.manual")

return setmetatable(suits, {__call = function(_, ...) return custom(...) end})
