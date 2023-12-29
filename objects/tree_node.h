/*
 * tree.h - Interface the client/drawin order between the  C-API and Lua.
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

#ifndef AWESOME_OBJECTS_TREE_NODE_H
#define AWESOME_OBJECTS_TREE_NODE_H

#include <stdint.h>

#include "common/luaobject.h"
#include "common/luaclass.h"
#include "draw.h"

/* What kinf of payload is stored in the node.
 *
 * Each node has only one type and cannot change over time.
 */
typedef enum {
    TREE_NODE_TYPE_NEW,
    TREE_NODE_TYPE_BRANCH,
    TREE_NODE_TYPE_CLIENT,
    TREE_NODE_TYPE_DRAWIN,
    TREE_NODE_TYPE_DEFUNCT
} tree_node_type_t;

/*
 * Extra properties, mostly private APIs.
 */
typedef enum {
    TREE_NODE_FLAGS_NONE               = 0x0 << 0,
    /* Allow `:wrap()` */
    TREE_NODE_FLAGS_MODE_TREE          = 0x1 << 0,
    /* Disallow `:wrap()` */
    TREE_NODE_FLAGS_MODE_LIST          = 0x1 << 1,
    /* Do not allow mutations */
    TREE_NODE_FLAGS_READ_ONLY          = 0x1 << 2,
    /* Block `:detach()` */
    TREE_NODE_FLAGS_PROTECTED          = 0x1 << 3,
    /* See ICCCM WM_NORMAL_HINTS */
    TREE_NODE_FLAGS_HONOR_MAX_WIDTH    = 0x1 << 4,
    TREE_NODE_FLAGS_HONOR_MAX_HEIGHT   = 0x1 << 5,
    TREE_NODE_FLAGS_HONOR_MIN_WIDTH    = 0x1 << 6,
    TREE_NODE_FLAGS_HONOR_MIN_HEIGHT   = 0x1 << 7,
    TREE_NODE_FLAGS_HONOR_BASE_WIDTH   = 0x1 << 8,
    TREE_NODE_FLAGS_HONOR_BASE_HEIGHT  = 0x1 << 9,
    TREE_NODE_FLAGS_HONOR_MIN_ASPECT   = 0x1 << 10,
    TREE_NODE_FLAGS_HONOR_MAX_ASPECT   = 0x1 << 11,
    TREE_NODE_FLAGS_HONOR_RESIZE_W_INC = 0x1 << 12,
    TREE_NODE_FLAGS_HONOR_RESIZE_H_INC = 0x1 << 13,
    /* Prevent use-after-free */
    TREE_NODE_HAS_WEAK_REF             = 0x1 << 14,
    /* When there is a lua `awful.placement` function set */
    TREE_NODE_HAS_PLACEMENT            = 0x1 << 15,
    /* Allow direct control of the visibility */
    TREE_NODE_OVERRIDE_BAN             = 0x1 << 16,
    TREE_NODE_OVERRIDE_UNBAN           = 0x1 << 17,
} tree_node_flags_t;

typedef struct tree_node_pair_t {
    struct tree_node_t *previous, *next;
} tree_node_pair_t;

typedef struct tree_node_gaps_t
{
    uint16_t left;
    uint16_t right;
    uint16_t top;
    uint16_t bottom;
} tree_node_gaps_t;

typedef struct tree_node_t
{
    LUA_OBJECT_HEADER

    tree_node_type_t type;

    /* The parent tree node */
    struct tree_node_t *parent;

    /* Linked list with the other items with the same `parent` */
    struct tree_node_pair_t siblings;

    /* Various boolean properties */
    tree_node_flags_t flags;

    union {
         /* type TREE_NODE_TYPE_DRAWIN and TREE_NODE_TYPE_CLIENT */
        struct {
            /* void* to avoid dependency loop (can be a client or drawin)*/
            void *ptr;
            /* This is the stored geometry, not the current client/drawin one */
            area_t geometry;
            /* Margins ("useless" gaps) to put around a client/wibox */
            tree_node_gaps_t gaps;
            /* Linked list of all nodes which are referenced by a client or drawin */
            struct tree_node_pair_t ref;
        } window;

        /* TREE_NODE_TYPE_BRANCH */
        struct {
            struct tree_node_t *head;
            struct tree_node_t *tail;
        } children;

    } object;
} tree_node_t;

lua_class_t tree_node_class;
LUA_OBJECT_FUNCS(tree_node_class, tree_node_t, tree_node)

void tree_node_class_setup(lua_State *);

void tree_node_append(lua_State *L, tree_node_t *node, tree_node_t *parent);
void tree_node_push(lua_State *L, tree_node_t *node, tree_node_t *parent);
void tree_node_insert_before(lua_State *L, tree_node_t *node, tree_node_t *other);
void tree_node_insert_after(lua_State *L, tree_node_t *node, tree_node_t *other);
void tree_node_wrap(lua_State *L, tree_node_t *to_wrap, tree_node_t *wrapper);

void tree_node_unlink_client(lua_State *L, void *c);
void tree_node_unlink_drawin(lua_State *L, void *d);

/* The node before `node` (recursive) */
tree_node_t * tree_node_find_previous(tree_node_t *node);
/* The node after `node` (recursive) */
tree_node_t * tree_node_find_next(tree_node_t *node);
/* The tail of the deepest sub-tree */
tree_node_t * tree_node_find_tail(tree_node_t *node);
/* The node without a parent */
tree_node_t * tree_node_find_root(tree_node_t *k);

#endif

// vim: filetype=c:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
