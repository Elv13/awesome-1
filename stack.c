/*
 * stack.c - client stack management
 *
 * Copyright © 2008-2009 Julien Danjou <julien@danjou.info>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 */

#include "stack.h"
#include "objects/window.h"
#include "ewmh.h"

void
stack_windows(lua_State *L, const char *context, client_t *c, drawin_t *d)
{
    /* Context */
    lua_pushstring(L, context);

    /* Create hints table */
    lua_newtable(L);

    lua_pushstring(L, "client");
    if (c)
        luaA_object_push(L, c);
    else
        lua_pushnil(L);

    lua_settable(L, -3);

    lua_pushstring(L, "drawin");
    if (d)
        luaA_object_push(L, d);
    else
        lua_pushnil(L);

    lua_settable(L, -3);

    printf("\n\nC SIDE RESTACK! %s\n", context);
    luaA_class_emit_signal(L, &client_class, "request::restack", 2);
}

/** Stack a client above.
 * \param c The client.
 * \param previous The previous client on the stack.
 * \return The next-previous!
 */
static xcb_window_t
stack_client_above(client_t *c, xcb_window_t previous)
{
    window_stack_above(c->frame_window, previous);

    previous = c->frame_window;

    return previous;
}

/*
 * Allow Lua to define the stacking order of clients and wiboxes.
 *
 * This is the handler for the `client` "request::apply_stacking" signal.
 *
 * The first argument is the `context`, which is unused. The second is the
 * `hints` table, which contains `content`.
 *
 * The table must contain `client` and `wibox` object. Index `1` is the closest
 * to the root (wallpaper) and the last index is the closest to the top.
 */
int
luaA_set_stacking_order(lua_State *L) {
    xcb_window_t next = XCB_NONE;

    if(lua_gettop(L) == 2)
    {
        luaA_checktable(L, 2);

        /* Get the `content` argument from the request hints table. */
        lua_getfield(L, 2, "content");

        if (lua_isnil(L, 3)) {
            lua_pop(L, 2);
            return 0;
        }

        luaA_checktable(L, 3);

        lua_pushnil(L);

        while(lua_next(L, 3))
        {
            if (luaA_class_get(L, -1) == &client_class)
            {
                client_t *c = luaA_object_ref_class(L, -1, &client_class);
                next = stack_client_above(c, next);
                luaA_object_unref(L, c);
            }
            else if (luaA_class_get(L, -1) == &drawin_class)
            {
                drawin_t *d = luaA_object_ref_class(L, -1, &drawin_class);
                //window_stack_above(d->window, next);
                next = d->window;
                luaA_object_unref(L, d);
            }
            else
                return luaL_error(L, "`request::apply_stacking` only works on clients and drawins");
        }

        lua_pop(L, 2);
    }

    return 0;
}


// vim: filetype=c:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
