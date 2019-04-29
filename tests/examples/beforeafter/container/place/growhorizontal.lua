--DOC_HIDE_ALL
--DOC_GEN_IMAGE
local first, second, lbl1, lbl2 = ...
assert(first and second and lbl1 and lbl2)

local wibox     = require("wibox")
local beautiful = require("beautiful")

first.widget = wibox.widget {
    {
        {
            {
                text   = "foo",
                widget = wibox.widget.textbox
            },
            bg     = beautiful.bg_normal,
            widget = wibox.container.background,
        },
        grow_horizontal = false,
        widget =  wibox.container.place
    },
    border_color  = beautiful.border_color,
    border_width  = 1,
    forced_width  = 250,
    forced_height = 100,
    widget = wibox.container.background
}

second.widget = wibox.widget {
    {
        {
            {
                text   = "foo",
                widget = wibox.widget.textbox
            },
            bg     = beautiful.bg_normal,
            widget = wibox.container.background,
        },
        grow_horizontal = true,
        widget =  wibox.container.place
    },
    border_color  = beautiful.border_color,
    border_width  = 1,
    forced_width  = 250,
    forced_height = 100,
    widget = wibox.container.background
}

lbl1.markup = "<b>grow_horizontal</b> = <i>false</i>"
lbl2.markup = "<b>grow_horizontal</b> = <i>true</i>"
