/*
 * tree_node.c - Interface the client/drawin order between the  C-API and Lua.
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

#include "objects/tree_node.h"
#include "objects/drawable.h"
#include "client.h"
#include "drawin.h"
#include "common/xutil.h"

#include <math.h>

/* TODO :copy_custom_properties_to(targer, deep)
 * TODO _show/_hide/ for hidden/visible clients
 * TODO iterate parent and update _stacking to use it
 */

/**
 * Structure to manipulate `client`s and `wibox`es stacking order and geometry.
 *
 * This module allows to group clients alongside wiboxes. It is a building
 * block of the layout system. Generally, it isn't required to directly use this
 * module to acheive anything. It is used under the hood for storing layout
 * geometry when a tag is not selected and to manage the z-index and layers such
 * as `client.ontop`.
 *
 * The `awful.tree` object is just a sub-class of `awful.tree.node`. The only
 * difference is that `awful.tree` has more signals than the `awful.tree.node`s.
 *
 * Multiple signals are forwarded from the clients, wiboxes and tags to make it
 * easier to create stateful layouts. Note that none of them are necessary to
 * use this module.
 *
 * Here is a concrete example of the `awful.tree` which backs the layering
 * subsystem:
 *
 * @DOC_awful_tree_layers1_EXAMPLE@
 *
 *
 * Lifecycle notes
 * ===============
 *
 * * When a client is killed, `"request::cleanup"` is sent to all tree (root
 *   node). If the node isn't unlinked after the signal, it will be
 *   automatically removed.
 * * The `wibox` are held using weak references. They can be garbage collected
 *   even if present in a tree. When this happen, `"request::cleanup"` is sent,
 *   but it doesn't have the wibox since it has already been deleted. The nodes
 *   will be removed from the tree automatically.
 * * When a tree is garbage collected, so are all nodes.
 * * `client:swap()` does not affect trees. The user must connect those signals
 *   and handle them if needed.
 * * Instances exposes by the screen, tags or the root object are read only. To
 *   modify them you must implement a layout object or `arrange` function.
 *
 * @author Emmanuel Lepage-Vallee &lt;elv1313@gmail.com&gt;
 * @classmod awful.tree
 */

/*
 * C-side implementation of `awful.tree`.
 *
 * The C side is needed because:
 *
 *  * The stacking order need to be accessed after the Lua VM finishes.
 *  * The client "list" need to be iterated to find clients based on their X11 id
 *  * The tag `clients` property need to preserve the order for each tag
 *  * It's faster to render the tag without a complex seuquence of capi<->lua
 *    dance.
 *  * It's possible to attach "local" client and drawin properties like geometry
 *    which may differ from the "current, real geometry". For example, a client
 *    tagged in multiple places having different geometry for each tags.
 *  * Skip unecessary `arrange` and `restack` calls.
 *  * Move/restack only a subset of the client/drawin instead of all of them all
 *    the time.
 *  * Need a reliable way to prevent use_after_free if the Lua side isn't
 *    correctly updating the tree (for example, due to an error in one of the
 *    user side signal handler).
 */

/**
 * The total geometry for this node and all children.
 *
 * Note that this property is read only for tree node and writable for client
 * and wibox nodes.
 *
 * Note that doing `my_node.geometry.x = 1337` is not supported. The geometry
 * can only be set as a full table. However, the table does not need to contain
 * all aspects, so `my_node.geometry = { x = 1337}` will work.
 *
 * @property geometry
 * @tparam table geometry The geometry.
 * @tparam[opt=1] integer geometry.x The horizontal position.
 * @tparam[opt=1] integer geometry.y The vertical position.
 * @tparam[opt=1] integer geometry.width The width.
 * @tparam[opt=1] integer geometry.height The height.
 * @propertyunit pixel
 * @propemits true true
 * @see client.geometry
 * @see wibox.geometry
 * @see gaps
 * @see effective_geometry
 */

/**
 * The geometry with gaps and size hints applied.
 *
 * This should be equal or smaller than `geometry` unless the minimum width and
 * height are honored and larger than `geometry`. When the `effective_geometry` is
 * smaller than the `geometry` and a `placement` function is set, it will be
 * used to place the client within the parent area. That `placement` function
 * is not allowed to change the width and height.
 *
 * @property effective_geometry
 * @tparam table effective_geometry The geometry.
 * @tparam[opt=1] integer effective_geometry.x The horizontal position.
 * @tparam[opt=1] integer effective_geometry.y The vertical position.
 * @tparam[opt=1] integer effective_geometry.width The width.
 * @tparam[opt=1] integer effective_geometry.height The height.
 * @readonly
 * @propertyunit pixel
 * @see client.geometry
 * @see wibox.geometry
 * @see gaps
 * @see honor_size_hints
 * @see geometry
 */

/**
 * Padding (usually called "useless gaps") to put around a client or wibox.
 *
 * Note that doing `my_node.gaps.left = 1337` is not supported. The gaps can
 * only be set as a full table or a number.However, the table does not need to
 * contain all sides, so `my_node.gaps = { left = 1337}` will work.
 *
 * @property gaps
 * @tparam[opt=0] integer|table|nil gaps
 * @tparam[opt=0] integer gaps.left The gap on the left of a client or wibox.
 * @tparam[opt=0] integer gaps.right The gap on the right of a client or wibox.
 * @tparam[opt=0] integer gaps.top The gap on the top of a client or wibox.
 * @tparam[opt=0] integer gaps.bottom The gap on the bottom of a client or wibox.
 * @propertytype integer The same value for each side.
 * @propertytype table A different value for each side.
 * @propertytype nil When called on a branch or `awful.tree` root node.
 * @propertyunit pixel
 * @rangestart 0
 * @rangestop 65535
 * @propemits true true
 * @see geometry
 */

/**
 * Get the node which has no further parent.
 *
 * Note that this can return itself when it is the root.
 *
 * @property root
 * @tparam awful.tree.node root
 * @propertydefault It can be `self` when the `type` is `"root`". Otherwise it
 *  will the recursive `parent`.
 * @readonly
 */

/**
 * Return the client object, if any.
 *
 * This only works on client nodes.
 *
 * @property client
 * @tparam[opt=nil] client|nil client
 * @propemits true true
 * @propertytype nil When the node `type` isn't `"client"`.
 * @propertytype client When the node `type` is `"client"`.
 * @emits client::replaced
 * @emitstparam awful.tree self The tree object.
 * @emitstparam awful.tree.node node The client node which had its client replaced.
 * @emitstparam client previous_client The client object it previously held.
 * @see request::client_swap
 * @see type
 * @see clients
 */

/**
 * Return a table with all clients held by this node and any children.
 *
 * For the `"client"` node `type`, this returns a table with the `.client`. For
 * the `"branch"` node type, this return all client found by `:iterate_children`
 *
 * When setting this property, if the a client isn't already present in the
 * (sub-) tree, `"request::add_client"` will be emitted. If no node containing
 * the client is added once the request is completed,
 * `:append_new { client = c }` will be used as a fallback. It will also emit
 * `"request::remove_client"` if necessary and use `:detach()` as a fallback.
 *
 * @property clients
 * @tparam[opt={}] table clients
 * @tablerowtype The collection of all children clients, unordered.
 * @emits request::add_client
 * @emitstparam awful.tree|awful.tree.node self Itself.
 * @emitstparam string context In this case, always `"set_clients"`.
 * @emitstparam table hints A table with a `client` key.
 * @emits request::remove_client
 * @emitstparam awful.tree|awful.tree.node self Itself.
 * @emitstparam string context In this case, always `"set_clients"`.
 * @emitstparam table hints A table with a `client` key.
 * @see client
 */

/**
 * Return the wibox object, if any.
 *
 * This only works on wibox nodes.
 *
 * @property wibox
 * @tparam[opt=nil] wibox|nil wibox
 * @propertytype nil When the node `type` isn't `"wibox"`.
 * @propertytype wibox When the node `type` is `"wibox"`.
 * @readonly
 * @see type
 * @see client
 * @see wiboxes
 */

/**
 * Return a table with all wiboxes held by this node and any children.
 *
 * @property wiboxes
 * @tparam[opt={}] table wiboxes
 * @tablerowtype The collection of all children `wibox`es.
 * @readonly
 * @see wibox
 */

/**
 * The parent node.
 *
 * @DOC_awful_tree_parent1_EXAMPLE@
 *
 * @property parent
 * @tparam[opt=nil] awful.tree.node|awful.tree|nil parent
 * @readonly
 * @propertytype nil When there is no parent.
 * @propertytype awful.tree.node When there is a parent.
 * @propertytype awful.tree When the parent is the root object.
 * @see first_child
 * @see last_child
 */

/**
 * The previous node which has the same `parent`.
 *
 * @DOC_awful_tree_previous_sibling1_EXAMPLE@
 *
 * @property previous_sibling
 * @tparam[opt=nil] awful.tree.node|nil previous_sibling
 * @readonly
 * @propertytype nil When there is no previous sibling.
 * @propertytype awful.tree.node When there is a previous sibling.
 * @see next_sibling
 * @see previous
 * @see parent
 */

/**
 * The next node which has the same parent.
 *
 * @DOC_awful_tree_next_sibling1_EXAMPLE@
 *
 * @property next_sibling
 * @tparam[opt=nil] awful.tree.node|nil next_sibling
 * @readonly
 * @propertytype nil When there is no next sibling.
 * @propertytype awful.tree.node When there is a next sibling.
 * @see previous_sibling
 * @see next
 * @see parent
 */

/**
 * The previous node as if the tree was a flat list.
 *
 * @DOC_awful_tree_previous1_EXAMPLE@
 *
 * @property previous
 * @tparam[opt=nil] awful.tree.node|nil previous
 * @readonly
 * @propertytype nil When there is no previous node.
 * @propertytype awful.tree.node When there is a previous node.
 * @see next
 * @see previous_sibling
 * @see parent
 */

/**
 * The next node as if the tree was a flat list.
 *
 * @DOC_awful_tree_next1_EXAMPLE@
 *
 * @property next
 * @tparam[opt=nil] awful.tree.node|nil next
 * @readonly
 * @propertytype nil When there is no next node.
 * @propertytype awful.tree.node When there is a next node.
 * @see previous
 * @see next_sibling
 * @see parent
 */

/**
 * The first direct child.
 *
 * @DOC_awful_tree_first_child1_EXAMPLE@
 *
 * @property first_child
 * @tparam[opt=nil] awful.tree.node|nil first_child
 * @readonly
 * @propertytype nil When there is no children.
 * @propertytype awful.tree.node When there is a child.
 * @see last_child
 * @see parent
 */

/**
 * The last direct child.
 *
 * @DOC_awful_tree_last_child1_EXAMPLE@
 *
 * @property last_child
 * @tparam[opt=nil] awful.tree.node|nil last_child
 * @readonly
 * @propertytype nil When there is no children.
 * @propertytype awful.tree.node When there is a child.
 * @see first_child
 * @see parent
 */

/**
 * What is the node content.
 *
 * An `awful.tree.node` can contain a client, wibox or other nodes. Those are
 * mutually exclusive and cannot be changed after the node has been created. The
 * closest way to change the type is to use `:wrap()` and `:join()`.
 *
 * @DOC_awful_tree_type1_EXAMPLE@
 *
 * @property type
 * @tparam string type
 * @propertydefault This depends of which method created the node.
 * @propertyvalue "branch" A node which can (optionally) contain other nodes.
 * @propertyvalue "awful.tree" A `"branch"` node without a parent.
 * @propertyvalue "client" A node which contain a client.
 * @propertyvalue "wibox" A node which contain a wibox.
 * @see wrap
 * @see join
 * @readonly
 */

/**
 * When applying the geometry, honor the client size hints.
 *
 * This is for client nodes only.
 *
 * See the [ICCCM](https://x.org/releases/X11R7.6/doc/xorg-docs/specs/ICCCM/icccm.html#wm_normal_hints_property)
 * documentation.
 *
 * @property honor_size_hints
 * @tparam[opt=true] table|boolean honor_size_hints
 * @tparam[opt=false] boolean honor_size_hints.maximum_width The maximum width
 *  the client claims to support.
 * @tparam[opt=false] boolean honor_size_hints.maximum_height The maximum height
 *  the client claims to support.
 * @tparam[opt=false] boolean honor_size_hints.minimum_width The minimum width
 *  the client claims to support.
 * @tparam[opt=false] boolean honor_size_hints.minimum_height The minimum height
 *  the client claims to support.
 * @tparam[opt=false] boolean honor_size_hints.base_width The "default" width.
 * @tparam[opt=false] boolean honor_size_hints.base_height The "default" height.
 * @tparam[opt=false] boolean honor_size_hints.minimum_aspect_ratio The relation
 *  between the horizontal and vertical size.
 * @tparam[opt=false] boolean honor_size_hints.maximum_aspect_ratio The relation
 *  between the horizontal and vertical size.
 * @tparam[opt=false] boolean honor_size_hints.resize_width_increment The minimum
 *  num of pixels by which the width can be increased or decreased.
 * @tparam[opt=false] boolean honor_size_hints.resize_height_increment The minimum
 *  num of pixels by which the height can be increased or decreased.
 * @propertytype boolean Set all hints to `true` or `false`.
 * @propertytype table Set each hints individually.
 * @propemits true false
 * @see client.size_hints
 * @see client.size_hints_honor
 * @see placement
 * @see geometry
 */

/**
 * When `true`, `:cleanup()` won't remove the node and `:detach()` will fail.
 *
 * This property is recursive. If any of the children nodes are protected, this
 * will return `true`.
 *
 * @property protected
 * @tparam[opt=false] boolean protected
 * @propemits true true
 * @see cleanup
 */

/**
 * When `true`, none of the `awful.tree` mutator methods will work.
 *
 * This property is recursive. If any of the `parent` nodes are read only, then
 * this is also read only. This property cannot be set. All user created trees
 * are read-write and most internal ones are read-only.
 *
 * @property read_only
 * @tparam[opt=false] boolean read_only
 * @readonly
 */

/**
 * Is `false` when the node has been deleted.
 *
 * Deleted nodes cannot be re-used, they should not be kept in tables or it
 * will leak memory.
 *
 * @property valid
 * @tparam[opt=true] boolean valid
 * @readonly
 */

/**
 * Emitted when one of the children node sets the `client` property.
 *
 * This signal is only present in the `awful.tree` root object, not individual
 * nodes.
 *
 * @signal client::replaced
 * @tparam awful.tree self The tree object.
 * @tparam awful.tree.node node The client node which had its client replaced.
 * @tparam client previous_client The client object it previously held.
 * @see client
 */

/**
 * Emitted when the node order changed.
 *
 * It can be due to additions, deletions or order changes.
 *
 * @signal reorderred
 * @tparam awful.tree self The `awful.tree` object.
 * @tparam string source Which method or event caused the change.
 * @tparam awful.tree|awful.tree.node branch The branch node closest to the
 *  change.
 */

/**
 * Emitted when a node has been removed from the tree.
 *
 * @signal request::cleanup_node
 * @tparam awful.tree self The node about to be removed.
 * @tparam string context Why the node is being removed.
 * @tparam table hints Any other information.
 * @tparam awful.tree.node hints.node The node to cleanup.
 * @see request::cleanup
 */

/**
 * Emitted when a node has been removed from the tree.
 *
 * This signal is sent on individual nodes. Use `request::cleanup_node` if you
 * need to receive all removed nodes on the `awful.tree` root object.
 *
 * @signal request::cleanup
 * @tparam awful.tree self The node about to be removed.
 * @tparam string context Why the node is being removed.
 * @tparam table hints Any other information.
 * @tparam awful.tree.node hints.node The node to cleanup.
 * @see request::cleanup_node
 */

/**
 * Emitted on the `awful.tree` root node when a client is added.
 *
 * @signal client::added
 * @tparam awful.tree self The `awful.tree` root node.
 * @tparam client client The client.
 * @tparam awful.tree.node hints.node The node which contain the client.
 * @see wibox::added
 * @see client::replaced
 */

/**
 * Emitted on the `awful.tree` root node when a wibox is added.
 *
 * @signal wibox::added
 * @tparam awful.tree self The `awful.tree` root node.
 * @tparam wibox wibox The wibox.
 * @tparam awful.tree.node hints.node The node which contain the wibox.
 * @see client::added
 */

lua_class_t tree_node_class;

/* Geometry, but using 2 points rather than x/y/width/height. */
typedef struct
{
    /* Top left point */
    int x0, y0;
    /* Bottom right point */
    int x1, y1;
} extents_t;

/* RIAA object to catch __gc events on Lua 5.1.
 *
 * Lua 5.2 and above have a metatable `__gc` for tables, but 5.1 do not. This
 * userdata some purpose is to get this `__gc` event on an `awful.tree` object.
 *
 * It holds a pointer to the "real" root object and call `unlink_node` when
 * the tree_node_weak_ref_t goes out of scope. This works as long as nobody
 * try to use the private API of `tree_node_t`.
 *
 * This is the equivalent of an `std::unique_ptr` in C++.
 */
typedef struct tree_node_weak_ref_t
{
    LUA_OBJECT_HEADER
    tree_node_t *root_node;
} tree_node_weak_ref_t;

lua_class_t tree_node_weak_ref_class;
LUA_OBJECT_FUNCS(tree_node_weak_ref_class, tree_node_weak_ref_t, tree_node_weak_ref)

static inline int
max(int a, int b)
{
    return a > b ? a : b;
}

static inline int
min(int a, int b)
{
    return a > b ? b : a;
}

/* Common luaA_checkudata and `.value` errors */
static inline void
check_valid(lua_State *L, tree_node_t *self, const char *method)
{
    if (!self)
        luaL_error(L,
            "Only non nil `awful.tree.node` objects can be passed to %s",
            method);

    if (self->type == TREE_NODE_TYPE_DEFUNCT)
        luaL_error(L,
            "Trying to use `%s` on a tree node which has been deleted.",
            method);
}

/* Prevent method from moving a node to another tree because it makes it too
 * easy to corrupt a protected structure.
 */
static inline void
check_root(lua_State *L, tree_node_t *n1, tree_node_t *n2, const char *method)
{
    if (tree_node_find_root(n1) != tree_node_find_root(n2))
        luaL_error(L, "Cannot use %s to move nodes to a different tree", method);
}

/* The Lua test cannot check for DEFUNCT nodes because they are not longer
 * mapped in Lua (so they appear as `nil` to protect against crashes).
 *
 * This method makes sure this doesn't happen and also check some tree integrity
 * while at it.
 */
static void
check_integrity(lua_State *L, tree_node_t *self)
{
    switch (self->type) {
    case TREE_NODE_TYPE_BRANCH:
        /* It should not be possible to have a `head` with no `tail`. */
        if ((self->object.children.head || self->object.children.tail) &&
          !(self->object.children.head && self->object.children.tail))
            luaL_error(L, "Head without tail or tail without head");

        tree_node_t *child = self->object.children.head;

        for (; child; child = child->siblings.next)
        {
            if (child->parent != self)
                luaL_error(L, "Invalid parent");

            if (child->siblings.next &&
              child->siblings.next->siblings.previous != child)
                luaL_error(L, "Invalid sibling linked list");

            check_integrity(L, child);
        }
        break;
    case TREE_NODE_TYPE_DEFUNCT:
        luaL_error(L, "Defunt item still linked");
        break;
    case TREE_NODE_TYPE_CLIENT:
    case TREE_NODE_TYPE_DRAWIN:
    case TREE_NODE_TYPE_NEW:
        break;
    }

    if (self->parent)
    {
        bool found = false;
        tree_node_t *child = self->parent->object.children.head;

        if (child && child->siblings.previous)
            luaL_error(L, "Head has a previous sibling");

        for (; child; child = child->siblings.next)
        {
            if (child == self)
            {
                found = true;
                break;
            }
        }

        if (!found)
            luaL_error(L, "Parent does not contain child");

        tree_node_t *tail = self->parent->object.children.tail;

        if (tail && tail->siblings.next)
            luaL_error(L, "Tail has a next sibling");
    }
}

static const char *
get_type_name(tree_node_t *self)
{
    switch (self->type) {
    case TREE_NODE_TYPE_NEW:
        return "new";
    case TREE_NODE_TYPE_BRANCH:
        return self->parent ? "branch" : "awful.tree";
    case TREE_NODE_TYPE_CLIENT:
        return "client";
    case TREE_NODE_TYPE_DRAWIN:
        return "wibox";
    case TREE_NODE_TYPE_DEFUNCT:
        return "defunct";
    }
    return "";
}

static void init_pair(tree_node_pair_t *pair)
{
    pair->previous = NULL;
    pair->next     = NULL;
}

static void init_children(tree_node_t *node)
{
    node->object.children.head = NULL;
    node->object.children.tail = NULL;
}

static bool
is_protected(tree_node_t *self)
{
    for (tree_node_t *n = self; n && n != self->siblings.next; n = tree_node_find_next(n))
        if (n->flags & TREE_NODE_FLAGS_PROTECTED)
            return true;

    return false;
}

static bool
is_read_only(tree_node_t *self)
{
    do {
        if (self->flags & TREE_NODE_FLAGS_READ_ONLY)
            return true;
    } while ((self = self->parent));

    return false;
}

static int
luaA_tree_node_weak_ref_new(lua_State *L)
{
    /* Push the first key before iterating */
    lua_pushnil(L);

    tree_node_t *root_node = NULL;

    /* Iterate over the property keys */

    while (lua_next(L, 2))
    {
        if (lua_isstring(L, -2) && !a_strcmp(luaL_checkstring(L, -2), "root_node"))
            root_node = luaA_checkudata(
                L, -1, &tree_node_class
            );

        /* Remove value */
        lua_pop(L, 1);
    }

    if (root_node && root_node->flags & TREE_NODE_HAS_WEAK_REF)
        luaL_error(L, "Do not use the `_tree_node` private API.");

    const int ret = luaA_class_new(L, &tree_node_weak_ref_class);

    lua_pushvalue(L, -1);

    tree_node_weak_ref_t *weak_ref = (tree_node_weak_ref_t *) lua_topointer(
        L, -1
    );

    weak_ref->root_node = root_node;

    if (root_node)
        root_node->flags |= TREE_NODE_HAS_WEAK_REF;

    return ret;
}

static int
luaA_tree_node_weak_ref_init_root_node(lua_State *L, tree_node_weak_ref_t *ref)
{
    ref->root_node = luaA_object_ref_class(
        L, -1, &tree_node_weak_ref_class
    );

    return 0;
}

/* Extract the `wibox` from a `drawin`.
 *
 * The public API works with the high level `wibox` object while C works with
 * a drawin.
 */
static void
push_wibox(lua_State *L, drawin_t *d)
{
    const int old_top = lua_gettop(L);
    luaA_object_push(L, d);

    /* `wibox/init.lua` add this *function* (it is not a method) to get the
     * wibox which owns this drawin. */
    lua_pushstring(L, "get_wibox");
    lua_gettable(L, -2);

    /* If the `wibox` library didn't create this drawin (aka, someone used a
     * private API), then this won't exist. */
    if (!lua_isfunction(L, -1))
    {
        lua_pop(L, 1);
        lua_pushnil(L);
        return;
    }

    /* Calling `get_wibox()` failed, ignore it */
    if (lua_pcall(L, 0, 1, 0) != LUA_OK)
    {
        lua_pushnil(L);
        return;
    }

    /* Move the wibox back in the stack then make it the sole "new" entry */
    lua_replace(L, old_top + 1);
    lua_settop (L, old_top + 1);
}

static tree_node_t *
tree_node_allocator(lua_State *L)
{
    tree_node_t *ret = tree_node_new(L);

    ret->flags             = TREE_NODE_FLAGS_NONE;
    ret->type              = TREE_NODE_TYPE_NEW;
    ret->object.window.ptr = NULL;
    ret->parent            = NULL;

    init_pair(&ret->siblings);
    init_pair(&ret->object.window.ref);

    return ret;
}

/** Create a new tree_node object.
 * \param L The Lua VM state.
 * \return The number of elements pushed on stack.
 */
static int
luaA_tree_node_create_node(lua_State *L, int args_idx)
{
    tree_node_t *previous = NULL;
    tree_node_t *next     = NULL;
    tree_node_t *parent   = NULL;
    tree_node_t *wrap     = NULL;

    tree_node_flags_t flags = TREE_NODE_FLAGS_MODE_TREE;

    /* Push the first key before iterating */
    lua_pushnil(L);

    /* Iterate over the property keys */
    while(lua_next(L, args_idx))
    {
        /* Check that the key is a string.
         * We cannot call tostring blindly or Lua will convert a key that is a
         * number TO A STRING, confusing lua_next() */
        if(lua_isstring(L, -2))
        {
            const char *prop = luaL_checkstring(L, -2);

            /* `luaA_object_ref_class` isn't needed because all tree internal
             * C references are weak. The GC will call unlink, which will get
             * rid of all pointers. Even if "we care", it's the method jobs
             * to increment the references, not the consturctor. */
            if (!a_strcmp(prop, "previous"))
                previous = luaA_checkudata(L, -1, &tree_node_class);
            else if (!a_strcmp(prop, "next"))
                next = luaA_checkudata(L, -1, &tree_node_class);
            else if (!a_strcmp(prop, "parent"))
                parent = luaA_checkudata(L, -1, &tree_node_class);
            else if (!a_strcmp(prop, "wrap"))
                wrap = luaA_checkudata(L, -1, &tree_node_class);
            else if (!a_strcmp(prop, "mode"))
                if (!a_strcmp(luaL_checkstring(L, -1), "list"))
                    flags |= TREE_NODE_FLAGS_MODE_LIST;
        }

        /* Remove value */
        lua_pop(L, 1);
    }

    const int ret = luaA_class_new(L, &tree_node_class);

    /* Duplicate the node and add a reference to it. This is needed for all
     * the `tree_node_t*` getters. If the object isn't in the registry, they
     * return `nil`.
     */
    lua_pushvalue(L, -1);
    tree_node_t *node = luaA_object_ref_class(L, -1, &tree_node_class);

    /* Default to `TREE` when no client or drawin is provided */
    if (node->type == TREE_NODE_TYPE_NEW)
        node->type = TREE_NODE_TYPE_BRANCH;

    node->flags |= flags;

    switch (node->type)
    {
    case TREE_NODE_TYPE_BRANCH:
        init_children(node);
        if (!(node->flags & TREE_NODE_FLAGS_MODE_LIST))
            node->flags |= TREE_NODE_FLAGS_MODE_TREE;
        break;
    default:
        break;
    }

    if (previous)
        tree_node_insert_after(L, node, previous);
    else if (next)
        tree_node_insert_before(L, node, next);
    else if (parent)
        tree_node_append(L, node, parent);
    else if (wrap)
        tree_node_wrap(L, wrap, node);

    const int old_top = lua_gettop(L);

    /* Send `awful.tree` signals */
    switch (node->type)
    {
    case TREE_NODE_TYPE_NEW:
    case TREE_NODE_TYPE_DEFUNCT:
    case TREE_NODE_TYPE_BRANCH:
        break;
    case TREE_NODE_TYPE_CLIENT:
        luaA_object_push(L, tree_node_find_root(node));
        luaA_object_push(L, (client_t *) node->object.window.ptr);
        luaA_object_push(L, node);
        luaA_object_emit_signal(L, -3, "client::added", 2);
        lua_settop(L, old_top);
        break;
    case TREE_NODE_TYPE_DRAWIN:
        /* FIXME We cannot push the wibox because it's `nil` when `not visible` */
        if (((drawin_t *) node->object.window.ptr)->visible)
        {
            luaA_object_push(L, tree_node_find_root(node));
            push_wibox(L, node->object.window.ptr);
            luaA_object_push(L, node);
            luaA_object_emit_signal(L, -3, "wibox::added", 2);
            lua_settop(L, old_top);
        }
        break;
    }

    return ret;
}


static int
luaA_tree_node_new(lua_State *L)
{
    return luaA_tree_node_create_node(L, 2);
}

static void
remove_node(tree_node_pair_t *previous, tree_node_pair_t *current, tree_node_pair_t *next)
{
    if (next)
        next->previous = current->previous;

    if (previous)
        previous->next = current->next;
}

static void
unlink_node(lua_State *L, tree_node_t *node, bool detach, const char *context)
{
    /* This can happen with `pcall()` which fail in some `request::` handlers */
    if (node->type == TREE_NODE_TYPE_DEFUNCT)
        return;
    /* Notify Lua first while the node is still in its original place */
    if (detach && context)
    {
        tree_node_t *root = tree_node_find_root(node);

        /* Emit the signal on the `root` node.
         *
         * There is a race condition here, check the type
         */
        if (root && root != node && root->type != TREE_NODE_TYPE_DEFUNCT)
        {
            /* self */
            luaA_object_push(L, root);

            /* Seen happen in some specific `pcall()` failures. */
            if (luaA_toudata(L, -1, &tree_node_class))
            {
                /* Add the context */
                lua_pushstring(L, context);

                /* Hints */
                lua_newtable(L);

                luaA_object_push(L, node);
                lua_setfield(L, -2, "node");

                luaA_object_emit_signal(L, -3, "request::cleanup_node", 2);
            }

            /* Pop `self` */
            lua_pop(L, 1);
        }

        /* self, since it may not be in the stack (ex: killed clients) */
        luaA_object_push(L, node);

        /* Seen happen in some specific `pcall()` failures. */
        if (luaA_toudata(L, -1, &tree_node_class))
        {
            /* Add the context */
            lua_pushstring(L, context);

            /* Hints */
            lua_newtable(L);

            luaA_object_push(L, node);
            lua_setfield(L, -2, "node");

            /* Emit the signal on every single nodes */
            luaA_object_emit_signal(L, -3, "request::cleanup", 2);
        }

        /* Pop `self` */
        lua_pop(L, 1);
    }

    /* If this is a tree, then recursively unlink all children
     *
     * warning: Do not add code above this beside signals. Having `parent` with
     * `type == DEFUNCT` will crash.
     */
    if (detach && node->type == TREE_NODE_TYPE_BRANCH)
    {
        while (node->object.children.tail)
            unlink_node(L, node->object.children.tail, true, "parent_unlinked");

        init_children(node);
    }

    if (node->parent && node->parent->object.children.head == node)
        node->parent->object.children.head = node->siblings.next;

    if (node->parent && node->parent->object.children.tail == node)
        node->parent->object.children.tail = node->siblings.previous;

    if (detach) {
        if (node->type == TREE_NODE_TYPE_CLIENT)
        {
            client_t *c = (client_t*) node->object.window.ptr;

            if (c->tree_nodes == node)
                c->tree_nodes = node->object.window.ref.next;
        }
        else if (node->type == TREE_NODE_TYPE_DRAWIN)
        {
            drawin_t *d = (drawin_t*) node->object.window.ptr;

            if (d->tree_nodes == node)
                d->tree_nodes = node->object.window.ref.next;
        }

        remove_node(
            node->object.window.ref.previous ?
                &node->object.window.ref.previous->object.window.ref : NULL,
            &node->object.window.ref,
            node->object.window.ref.next ?
                &node->object.window.ref.next->object.window.ref : NULL
        );

        init_pair(&node->object.window.ref);
    }

    remove_node(
        node->siblings.previous ? &node->siblings.previous->siblings : NULL,
        &node->siblings,
        node->siblings.next ? &node->siblings.next->siblings : NULL
    );

    /* Reset the data structures */
    init_pair(&node->siblings);
    node->parent = NULL;

    /* Unref the `DEFUNCT` object. It might *not* be wiped yet, but it can no
     * longer be used */
    if (detach && node->type != TREE_NODE_TYPE_DEFUNCT)
    {
        node->type = TREE_NODE_TYPE_DEFUNCT;
        luaA_object_unref(L, node);
    }
}

static void
tree_node_wipe(tree_node_t *node)
{
    /* Ideally, there's nothing do do because the node was discarded by the
     * tree or it's `tree_node_weak_ref`. */
    if (node->type != TREE_NODE_TYPE_DEFUNCT)
        return;

    lua_State *L = globalconf_get_lua_State();

    if (node->type == TREE_NODE_TYPE_BRANCH && node->object.children.head)
        luaL_error(L, "Trying to delete a non-empty tree, this is a bug");

    unlink_node(L, node, true, NULL);
}

static void
tree_node_weak_ref_wipe(tree_node_weak_ref_t *ref)
{
    lua_State *L = globalconf_get_lua_State();

    if (ref->root_node && ref->root_node->type != TREE_NODE_TYPE_DEFUNCT)
    {
        ref->root_node->flags &= ~TREE_NODE_HAS_WEAK_REF;
        unlink_node(L, ref->root_node, true, NULL);
    }
}

static void
tree_node_swap(tree_node_t *first, tree_node_t *second)
{
    if (first == second || !second) return;

    /* Keep all of them as variables to avoid having to handle corner cases */
    tree_node_t *first_previous  = first->siblings.previous;
    tree_node_t *first_next      = first->siblings.next;
    tree_node_t *second_previous = second->siblings.previous;
    tree_node_t *second_next     = second->siblings.next;
    tree_node_t *first_parent    = first->parent;
    tree_node_t *second_parent   = second->parent;

    if (first->siblings.previous == second)
    {
        /* Swap joint nodes (first is after second) */
        if (second_previous)
            second_previous->siblings.next = first;

        if (first_next)
            first_next->siblings.previous = second;

        first->siblings.next      = second;
        second->siblings.previous = first;
        second->siblings.next     = first_next;
        first->siblings.previous  = second_previous;
    }
    else if (first->siblings.next == second)
    {
        /* Swap joint nodes (second is after first) */
        if (first_previous)
            first_previous->siblings.next = second;

        if (second_next)
            second_next->siblings.previous = first;

        second->siblings.previous = first_previous;
        first->siblings.next      = second_next;
        first->siblings.previous  = second;
        second->siblings.next     = first;
    }
    else
    {
        /* Swap disjoint nodes */
        first->siblings.next      = second_next;
        first->siblings.previous  = second_previous;
        second->siblings.next     = first_next;
        second->siblings.previous = first_previous;

        first->parent = second_parent;
        second->parent = first_parent;

        if (first_previous)
            first_previous->siblings.next = second;

        if (second_previous)
            second_previous->siblings.next = first;

        if (first_next)
            first_next->siblings.previous = second;

        if (second_next)
            second_next->siblings.previous = first;
    }

    /* Check all data before making changes to avoid corner cases */
    const bool is_second_first = second_parent
        && second_parent->object.children.head == second;
    const bool is_first_first  = first_parent
        && first_parent->object.children.head == first;
    const bool is_second_last  = second_parent
        && second_parent->object.children.tail == second;
    const bool is_first_last   = first_parent
        && first_parent->object.children.tail == first;

    /* Update the `first_child` */
    if (is_second_first)
        second_parent->object.children.head = first;

    if (is_first_first)
        first_parent->object.children.head = second;

    /* Update the `last_child` */
    if (is_second_last)
        second_parent->object.children.tail = first;

    if (is_first_last)
        first_parent->object.children.tail = second;
}

/**
 * Swap 2 nodes.
 *
 * @DOC_awful_tree_swap1_EXAMPLE@
 *
 * @method :swap
 * @tparam awful.tree.node other The other node.
 * @treturn boolean `true` if it was swapped and `false` if the tree is read
 *  only or `other == self`.
 */
static int
luaA_tree_node_swap(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":swap()");

    if (is_read_only(self))
    {
        lua_pushboolean(L, false);
        return 1;
    }

    tree_node_t *second = luaA_checkudata(L, -1, &tree_node_class);

    if (!second)
    {
        luaL_error(L, "`:swap()` need to receive an `awful.tree.node` object.");
        return 0;
    }

    check_valid(L, second, ":swap()");

    if (!second->parent)
    {
        luaL_error(L, "`:swap()` does not work on root `awful.tree` objects.");
        return 0;
    }

    if (self == second)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    check_root(L, self, second, ":swap()");

    tree_node_swap(self, second);

    //luaA_object_push(L, second); //FIXME
    //lua_pushboolean(L, true);
    //luaA_object_emit_signal(L, -3, "swapped", 2);

    lua_pushboolean(L, true);

    return 1;
}

void tree_node_wrap(lua_State *L, tree_node_t *to_wrap, tree_node_t *wrapper)
{
    tree_node_swap(to_wrap, wrapper);
    tree_node_append(L, to_wrap, wrapper);
}

/**
 * Merge all children nodes and remove `self`.
 *
 * Note: This is not recursive.
 *
 * @DOC_awful_tree_join1_EXAMPLE@
 *
 * @method :join
 * @treturn boolean `true` if it was joined or `false` if the tree is read
 *  only or `self` is `protected`.
 * @see detach
 */
static int
luaA_tree_node_join(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":join()");

    if (self->type != TREE_NODE_TYPE_BRANCH)
        luaL_error(L,
            "`:join()` can only be called on a tree node, not a %s",
            get_type_name(self));

    if (!self->parent)
        luaL_error(L,"Cannot `:join()` an `awful.tree` root object.");

    /* Check for protected on `self`, not the children */
    if (is_read_only(self) || self->flags & TREE_NODE_FLAGS_PROTECTED)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    tree_node_t *parent           = self->parent;
    tree_node_t *previous_sibling = self->siblings.previous;
    tree_node_t *next_sibling     = self->siblings.next;
    tree_node_t *first_child      = self->object.children.head;
    tree_node_t *last_child       = self->object.children.tail;

    init_children(self);
    unlink_node(L, self, true, "join");

    /* In this case, `:join()` is the same as `:unlink()`, so there is nothing
     * to actually join */
    if (!first_child)
    {
        lua_pushboolean(L, true);
        return 1;
    }

    /* Link the old inner children to the previous siblings */
    if (previous_sibling)
    {
        previous_sibling->siblings.next = first_child;
        first_child->siblings.previous = previous_sibling;
    }
    else
    {
        parent->object.children.head = first_child;
        first_child->siblings.previous = NULL;
    }

    if (next_sibling)
    {
        next_sibling->siblings.previous = last_child;
        last_child->siblings.next = next_sibling;
    }
    else
    {
        parent->object.children.tail = last_child;
        last_child->siblings.next = NULL;
    }

    /* Set the parent for all in-between nodes */
    for (; first_child != next_sibling; first_child = first_child->siblings.next)
        first_child->parent = parent;

    lua_pushboolean(L, true);
    return 1;
}

/**
 * Make the node passed as argument the first child node of `self`.
 *
 * @DOC_awful_tree_push1_EXAMPLE@
 *
 * @method :push
 * @tparam awful.tree.node other The node which will become the new
 *   `first_child` of `self`.
 * @treturn boolean If the node was inserted. It will be `false` when the
 *   `awful.tree` is read only or `other` isn't a valid `awful.tree.node`.
 * @see append
 * @see move_after
 * @see move_before
 * @see first_child
 */
static int
luaA_tree_node_push(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":push()");

    if (self->type != TREE_NODE_TYPE_BRANCH)
        luaL_error(L, "`:push()` can only be called on a tree node, not a %s",
            get_type_name(self));

    tree_node_t *to_push = luaA_checkudata(L, 2, &tree_node_class);

    if (is_read_only(self) || (!to_push) || self == to_push)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    check_valid(L, to_push, ":push()");
    check_root(L, self, to_push, ":push()");

    tree_node_push(L, to_push, self);
    lua_pushboolean(L, true);

    return 1;
}

/**
 * Make the node passed as argument the last child node of `self`.
 *
 * @DOC_awful_tree_append1_EXAMPLE@
 *
 * @method :append
 * @tparam awful.tree.node other The node which will become the new
 *   `last_child` of `self`.
 * @treturn boolean If the node was inserted. It will be `false` when the
 *   `awful.tree` is read only or `other` isn't a valid `awful.tree.node`.
 * @see push
 * @see move_after
 * @see move_before
 * @see last_child
 */
static int
luaA_tree_node_append(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":append()");

    if (self->type != TREE_NODE_TYPE_BRANCH)
        luaL_error(L, "`:append()` can only be called on a tree node, not a %s",
            get_type_name(self));

    tree_node_t *to_append = luaA_checkudata(L, 2, &tree_node_class);

    if (is_read_only(self) || (!to_append) || self == to_append)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    check_valid(L, to_append, ":append()");
    check_root(L, self, to_append, ":append()");

    tree_node_append(L, to_append, self);
    lua_pushboolean(L, true);

    return 1;
}

/**
 * Remove a node from the tree.
 *
 * Once detached, it can no longer be used again. This will also invalidate all
 * children.
 *
 * If the node or any of its children are `protected` or if the tree is read
 * only, this method wont do anything and will return `false`.
 *
 * @DOC_awful_tree_detach1_EXAMPLE@
 *
 * @method :detach
 * @treturn boolean If the node was detached. It will be `false` when the node
 *  is `protected` or the `awful.tree` is read only.
 * @emits request::cleanup
 * @emitstparam awful.tree self The tree object.
 * @emitstparam awful.tree self The tree object.
 * @emitstparam string context Why the node is being removed.
 * @emitstparam table hints Any other information.
 * @emitstparam awful.tree.node hints.node Empty.
 * @emits request::cleanup_node
 * @emitstparam awful.tree self The tree object.
 * @emitstparam string context Why the node is being removed.
 * @emitstparam table hints Any other information.
 * @emitstparam awful.tree.node hints.node The node to cleanup.
 * @see join
 */
static int
luaA_tree_node_detach(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":detach()");

    /* Those nodes *must* use the `tree_node_weak_ref_t` object. */
    if (!self->parent)
        luaL_error(L, "Cannot call `:detach()` on an `awful.tree` root node");

    if (is_protected(self) || is_read_only(self))
    {
        lua_pushboolean(L, false);
        return 1;
    }

    unlink_node(L, self, true, "detach");
    lua_pushboolean(L, true);

    return 1;
}

static tree_node_t *
tree_node_fork_node(lua_State *L, tree_node_t *to_fork, tree_node_t *parent)
{
    lua_newtable(L);

    /* `args` setup */
    if (parent)
    {
        lua_pushstring(L, "parent");
        luaA_object_push(L, parent);
        lua_settable(L, -3);
    }

    switch (to_fork->type)
    {
    case TREE_NODE_TYPE_NEW:
    case TREE_NODE_TYPE_DEFUNCT:
        break;
    case TREE_NODE_TYPE_CLIENT:
        lua_pushstring(L, "client");
        luaA_object_push(L, (client_t *) to_fork->object.window.ptr);
        lua_settable(L, -3);
        break;
    case TREE_NODE_TYPE_DRAWIN:
        lua_pushstring(L, "_drawin");
        luaA_object_push(L, (drawin_t *) to_fork->object.window.ptr);
        lua_settable(L, -3);
        break;
    case TREE_NODE_TYPE_BRANCH:
        break;
    }

    /* Create a new node */
    luaA_tree_node_create_node(L, lua_gettop(L));
    tree_node_t *new_node = luaA_checkudata(L, -1, &tree_node_class);

    /* Pop the args table and the tree_node */
    lua_pop(L, 2);

    new_node->flags = to_fork->flags;

    /* Copy attributes */
    switch (to_fork->type)
    {
    case TREE_NODE_TYPE_CLIENT:
    case TREE_NODE_TYPE_DRAWIN:
        new_node->object.window.geometry = to_fork->object.window.geometry;
        break;
    case TREE_NODE_TYPE_BRANCH:
        /* Copy the children */
        for (tree_node_t *node = to_fork->object.children.head; node; node = node->siblings.next)
            tree_node_fork_node(L, node, new_node);

        break;
    default:
        break;
    }

    return new_node;
}

/**
 * Copy an entire (sub-)tree into a new `awful.tree` instance.
 *
 * It only copy the official `awful.tree` properties, it does *not* copy the
 * custom properties.
 *
 * @method :fork
 * @treturn awful.tree The copy of `self` as a new `awful.tree`.
 */
static int
luaA_tree_node_fork(lua_State *L)
{
    tree_node_t *self = luaA_checkudata(L, 1, &tree_node_class);
    tree_node_t *node = tree_node_fork_node(L, self, NULL);

    luaA_object_push(L, node);

    return 1;
}

/**
 * Remove all unprotected nodes from the tree.
 *
 * @method :cleanup
 * @treturn nil|awful.tree The removed nodes, if any.
 * @see protected
 */
static int
luaA_tree_node_cleanup(lua_State *L)
{
    return 1;
}

/**
 * Insert `self` before `other`.
 *
 * This method takes an existing node, remove it from its current position and
 * insert it before `self`. The `other` node must be part of the same tree.
 *
 * @DOC_awful_tree_insert_before1_EXAMPLE@
 *
 * @method :move_before
 * @tparam awful.tree.node other The node which will be inserted.
 * @treturn boolean If the node was inserted. It will be `false` when the
 *   `awful.tree` is read only.
 * @see move_after
 * @see push
 * @see append
 */
static int
luaA_tree_node_move_before(lua_State *L)
{
    tree_node_t *self  = luaA_checkudata(L, 1, &tree_node_class);
    tree_node_t *other = luaA_checkudata(L, 2, &tree_node_class);
    check_valid(L, self , ":move_before()");
    check_valid(L, other, ":move_before()");
    check_root (L, self , other, ":move_before()");

    if (is_read_only(self) || (!other) || other == self)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    tree_node_insert_before(L, self, other);
    lua_pushboolean(L, true);

    return 1;
}

/**
 * Move `self` after `other`.
 *
 * This method takes an existing node, remove it from its current position and
 * insert it after `self`. The `other` node must be part of the same tree.
 *
 * @DOC_awful_tree_insert_after1_EXAMPLE@
 *
 * @method :move_after
 * @tparam awful.tree.node other The node which will be inserted.
 * @treturn boolean If the node was inserted. It will be `false` when the
 *   `awful.tree` is read only or `other` isn't a valid `awful.tree.node`.
 * @see move_before
 * @see push
 * @see append
 */
static int
luaA_tree_node_move_after(lua_State *L)
{
    tree_node_t *self  = luaA_checkudata(L, 1, &tree_node_class);
    tree_node_t *other = luaA_checkudata(L, 2, &tree_node_class);
    check_valid(L, self , ":move_after()");
    check_valid(L, other, ":move_after()");
    check_root (L, self , other, ":move_after()");

    if (is_read_only(self) || (!other) || other == self)
    {
        lua_pushboolean(L, false);
        return 1;
    }

    tree_node_insert_after(L, self, other);
    lua_pushboolean(L, true);

    return 0;
}

static int
luaA_tree_node_apply_geometry(lua_State *L)
{
    tree_node_t *first = luaA_checkudata(L, 1, &tree_node_class);
    tree_node_t *last  = tree_node_find_tail(first);
    check_valid(L, first, ":_apply_geometry()");
    check_valid(L, last , ":_apply_geometry()");

    bool honor_hints   = true;

    if(lua_gettop(L) == 2)
        honor_hints = luaA_checkboolean(L, 2);

    do {
        if (first->type == TREE_NODE_TYPE_CLIENT)
        {
            client_resize(
                (client_t*) first->object.window.ptr,
                first->object.window.geometry,
                honor_hints
            );
        }
        else if (first->type == TREE_NODE_TYPE_DRAWIN)
        {
            drawin_t *d = (drawin_t *) first->object.window.ptr;
            luaA_object_push(L, d);
            drawin_moveresize(L, -1, first->object.window.geometry);
        }
    } while (first != last && (first = tree_node_find_next(first)) && first);

    return 0;
}

static xcb_window_t
get_window(tree_node_t *node)
{
    if (node->type == TREE_NODE_TYPE_CLIENT)
        return ((client_t *) node->object.window.ptr)->frame_window;
    else if (node->type == TREE_NODE_TYPE_DRAWIN)
        return ((drawin_t *) node->object.window.ptr)->window;

    return XCB_NONE;
}

static int
luaA_tree_node_apply_stacking(lua_State *L)
{
    xcb_window_t previous = XCB_NONE;

    /* The tail of the tree is the node closer to the wallpaper
     * each iteration goes toward to "front".
     */
    tree_node_t *front = luaA_checkudata(L, 1, &tree_node_class);
    tree_node_t *back  = tree_node_find_tail(front);
    check_valid(L, front, ":_apply_stacking()");

    /* Find the initial value of `previous`. Note that this assume the tree
     * contains it. That is ok because this function is a private API and it is
     * Lua jobs to only call it on "complete" trees.
     */
    for (tree_node_t *prev = back; prev && previous == XCB_NONE; prev = tree_node_find_next(prev))
        previous = get_window(prev);

    /* Iterate *toward* `self` */
    do {
        if (back->type == TREE_NODE_TYPE_CLIENT || back->type == TREE_NODE_TYPE_DRAWIN)
        {
            xcb_window_t above = get_window(back);
            window_stack_above(above, previous);
            previous = above == XCB_NONE ? previous : above;
        }
    } while (back != front && (back = tree_node_find_previous(back)) && back);

    return 0;
}

/* Debugging only */
static int
luaA_tree_node_check_integrity(lua_State *L)
{
    tree_node_t *self  = luaA_checkudata(L, 1, &tree_node_class);
    check_valid(L, self, ":_check_integrity()");
    check_integrity(L, self);

    return 0;
}

static int
luaA_tree_node_get_type(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".type");
    lua_pushstring(L, get_type_name(self));
    return 1;
}

static int
luaA_tree_node_get_mode(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".mode");

    if (self->type != TREE_NODE_TYPE_BRANCH)
    {
        luaL_error(L, "`.mode` can only be called on a `branch` node");
        return 0;
    }

    if (self->flags & TREE_NODE_FLAGS_MODE_TREE)
        lua_pushstring(L, "tree");
    else if (self->flags & TREE_NODE_FLAGS_MODE_LIST)
        lua_pushstring(L, "list");

    return 1;
}

static bool
tree_node_check_valid(tree_node_t *self)
{
    return self->type != TREE_NODE_TYPE_DEFUNCT;
}

static int
luaA_tree_node_get_protected(lua_State *L, tree_node_t *self)
{
    lua_pushboolean(L, is_protected(self));
    return 1;
}

static int
luaA_tree_node_set_protected(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".protected");

    const bool previous = self->flags & TREE_NODE_FLAGS_PROTECTED;
    const bool value    = luaA_checkboolean(L, -1);

    if (previous == value)
        return 0;

    self->flags  = self->flags & ~TREE_NODE_FLAGS_PROTECTED;
    self->flags |= value ?
        TREE_NODE_FLAGS_PROTECTED : TREE_NODE_FLAGS_NONE;

    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_PROTECTED);
    lua_pushboolean(L, previous);

    if (self->type == TREE_NODE_TYPE_NEW)
        return 0;

    luaA_object_emit_signal(L, -5, "property::protected", 2);
    lua_pop(L, 2);

    return 0;
}

static int
luaA_tree_node_get_read_only(lua_State *L, tree_node_t *self)
{
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_READ_ONLY);
    return 1;
}

static int
luaA_tree_node_set_read_only(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, "._read_only");

    const bool previous = self->flags & TREE_NODE_FLAGS_READ_ONLY;
    const bool value    = luaA_checkboolean(L, -1);

    if (previous == value)
        return 0;

    self->flags  = self->flags & ~TREE_NODE_FLAGS_READ_ONLY;
    self->flags |= value ?
        TREE_NODE_FLAGS_READ_ONLY : TREE_NODE_FLAGS_NONE;

    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_READ_ONLY);
    lua_pushboolean(L, previous);

    if (self->type == TREE_NODE_TYPE_NEW)
        return 0;

    luaA_object_emit_signal(L, -5, "property::_read_only", 2);
    lua_pop(L, 2);

    return 0;
}

static int
luaA_tree_node_get_honor_size_hints(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".honor_size_hints");

    if (self->type != TREE_NODE_TYPE_CLIENT)
        luaL_error(L,
            "`.honor_size_hints` only works on client node, not a %s",
            get_type_name(self));

    lua_createtable(L, 0, 8);

    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MAX_WIDTH);
    lua_setfield(L, -2, "maximum_width");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MAX_HEIGHT);
    lua_setfield(L, -2, "maximum_height");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MIN_WIDTH);
    lua_setfield(L, -2, "minimum_width");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MIN_HEIGHT);
    lua_setfield(L, -2, "minimum_height");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_BASE_WIDTH);
    lua_setfield(L, -2, "base_width");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_BASE_HEIGHT);
    lua_setfield(L, -2, "base_height");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MIN_ASPECT);
    lua_setfield(L, -2, "minimum_aspect_ratio");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_MAX_ASPECT);
    lua_setfield(L, -2, "maximum_aspect_ratio");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_RESIZE_W_INC);
    lua_setfield(L, -2, "resize_width_increment");
    lua_pushboolean(L, self->flags & TREE_NODE_FLAGS_HONOR_RESIZE_H_INC);
    lua_setfield(L, -2, "resize_height_increment");

    return 1;
}

static bool
luaA_get_size_hint(lua_State *L, int idx, const char* name)
{
    lua_getfield(L, -1, name);
    const bool ret = lua_isboolean(L, -1) && luaA_checkboolean(L, -1);
    lua_pop(L, 1);
    return ret;
}

static int
luaA_tree_node_set_honor_size_hints(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".honor_size_hints");

    if (self->type != TREE_NODE_TYPE_CLIENT)
        luaL_error(L,
            "`.honor_size_hints` only works on client node, not a %s",
            get_type_name(self));

    const uint32_t all_flags = TREE_NODE_FLAGS_HONOR_MAX_WIDTH
        | TREE_NODE_FLAGS_HONOR_MAX_HEIGHT
        | TREE_NODE_FLAGS_HONOR_MIN_WIDTH
        | TREE_NODE_FLAGS_HONOR_MIN_HEIGHT
        | TREE_NODE_FLAGS_HONOR_BASE_WIDTH
        | TREE_NODE_FLAGS_HONOR_BASE_HEIGHT
        | TREE_NODE_FLAGS_HONOR_MIN_ASPECT
        | TREE_NODE_FLAGS_HONOR_MAX_ASPECT
        | TREE_NODE_FLAGS_HONOR_RESIZE_W_INC
        | TREE_NODE_FLAGS_HONOR_RESIZE_H_INC;

    uint32_t new_flags = TREE_NODE_FLAGS_NONE;

    if (lua_isboolean(L, -1))
    {
        new_flags = luaA_checkboolean(L, -1) ? all_flags : TREE_NODE_FLAGS_NONE;
    }
    else if (lua_istable(L, -1))
    {
        new_flags |= luaA_get_size_hint(L, -1, "maximum_width") ?
            TREE_NODE_FLAGS_HONOR_MAX_WIDTH : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "maximum_height") ?
            TREE_NODE_FLAGS_HONOR_MAX_HEIGHT : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "minimum_width") ?
            TREE_NODE_FLAGS_HONOR_MIN_WIDTH : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "minimum_height") ?
            TREE_NODE_FLAGS_HONOR_MIN_HEIGHT : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "base_width") ?
            TREE_NODE_FLAGS_HONOR_BASE_WIDTH : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "base_height") ?
            TREE_NODE_FLAGS_HONOR_BASE_HEIGHT : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "minimum_aspect_ratio") ?
            TREE_NODE_FLAGS_HONOR_MIN_ASPECT : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "maximum_aspect_ratio") ?
            TREE_NODE_FLAGS_HONOR_MAX_ASPECT : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "resize_width_increment") ?
            TREE_NODE_FLAGS_HONOR_RESIZE_W_INC : TREE_NODE_FLAGS_NONE;
        new_flags |= luaA_get_size_hint(L, -1, "resize_height_increment") ?
            TREE_NODE_FLAGS_HONOR_RESIZE_H_INC : TREE_NODE_FLAGS_NONE;
    }

    self->flags  = (self->flags & ~all_flags) | new_flags;

    if (self->type == TREE_NODE_TYPE_NEW)
        return 0;

    luaA_tree_node_get_honor_size_hints(L, self);

    luaA_object_emit_signal(L, -4, "property::honor_size_hints", 1);
    lua_pop(L, 2);

    return 0;
}

static int
luaA_tree_node_push_gaps(lua_State *L, tree_node_gaps_t gaps)
{
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, gaps.left);
    lua_setfield(L, -2, "left");
    lua_pushinteger(L, gaps.right);
    lua_setfield(L, -2, "right");
    lua_pushinteger(L, gaps.top);
    lua_setfield(L, -2, "top");
    lua_pushinteger(L, gaps.bottom);
    lua_setfield(L, -2, "bottom");
    return 1;
}

static int
luaA_tree_node_get_gaps(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".gaps");

    switch (self->type) {
    case TREE_NODE_TYPE_CLIENT:
    case TREE_NODE_TYPE_DRAWIN:
        luaA_tree_node_push_gaps(L, self->object.window.gaps);
        break;
    default:
        lua_pushnil(L);
        break;
    }
    return 1;
}

static uint16_t
luaA_check_range(lua_State *L, int idx)
{
    const int value = luaL_checkinteger(L, idx);
    if (value < 0)
        luaL_error(L, "`.gaps` cannot be negative.");
    else if (value > 65535)
        luaL_error(L, "`.gaps` cannot be greater than 65535.");

    return value;
}

static int
luaA_tree_node_set_gaps(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".gaps");

    if (self->type == TREE_NODE_TYPE_BRANCH)
    {
        luaL_error(L, "`.gaps` cannot be set on branches.");
        return 0;
    }

    tree_node_gaps_t old = self->object.window.gaps;

    if (lua_isnumber(L, -1))
    {
        const uint16_t value = luaA_check_range(L, -1);

        self->object.window.gaps = (tree_node_gaps_t) {
            .left   = value,
            .right  = value,
            .top    = value,
            .bottom = value
        };
    }
    else if (lua_istable(L, -1))
    {
        tree_node_gaps_t new = self->object.window.gaps;

        new.left = round(
            luaA_getopt_number_range(
                L, -1, "left", new.left, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        new.right = round(
            luaA_getopt_number_range(
                L, -1, "right", new.right, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        new.top = ceil(
            luaA_getopt_number_range(
                L, -1, "top", new.top, MIN_X11_SIZE, MAX_X11_SIZE));
        new.bottom = ceil(
            luaA_getopt_number_range(
                L, -1, "bottom", new.bottom, MIN_X11_SIZE, MAX_X11_SIZE));

        self->object.window.gaps = new;
    }
    else
    {
        return 0;
    }

    if (self->type == TREE_NODE_TYPE_NEW)
        return 0;

    luaA_tree_node_push_gaps(L, self->object.window.gaps);
    luaA_tree_node_push_gaps(L, old);

    luaA_object_emit_signal(L, -5, "property::gaps", 2);
    lua_pop(L, 2);

    return 0;
}


static int
luaA_tree_node_get_client(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".client");

    switch (self->type) {
    case TREE_NODE_TYPE_CLIENT:
        luaA_object_push(L, self->object.window.ptr);
        break;
    default:
        lua_pushnil(L);
        break;
    }
    return 1;
}

static int
luaA_tree_node_get_clients(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".clients");
    lua_newtable(L);

    int count = 0;

    for (tree_node_t *n = self; n && n != self->siblings.next; n = tree_node_find_next(n))
        if (n->type == TREE_NODE_TYPE_CLIENT)
        {
            luaA_tree_node_get_client(L, n);
            lua_rawseti(L, -2, ++count);
        }

    return 1;
}

static int
luaA_tree_node_get_parent(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".parent");

    if (self->parent)
        luaA_object_push(L, self->parent);
    else
        lua_pushnil(L);

    return 1;
}

static int
luaA_tree_node_init_client(lua_State *L, tree_node_t *self)
{
    client_t *c = luaA_checkudata(L, -1, &client_class);

    self->type = TREE_NODE_TYPE_CLIENT;
    self->object.window.ptr = c;
    self->object.window.geometry = (area_t) {
        .x      = 0,
        .y      = 0,
        .width  = 0,
        .height = 0
    };
    self->object.window.gaps = (tree_node_gaps_t) {
        .left   = 0,
        .right  = 0,
        .top    = 0,
        .bottom = 0
    };

    if (c->tree_nodes)
        c->tree_nodes->object.window.ref.previous = self;

    self->object.window.ref.next = c->tree_nodes;
    c->tree_nodes = self;

    return 0;
}

static int
luaA_tree_node_set_client(lua_State *L, tree_node_t *self)
{
    if (self->type != TREE_NODE_TYPE_CLIENT)
    {
        luaL_error(L, "`.client` only works on when the node type is already "
            "`client`.");
        return 0;
    }

    check_valid(L, self, ".client");

    client_t *old_c = (client_t *) self->object.window.ptr;
    client_t *new_c = luaA_checkudata(L, -1, &client_class);

    if (old_c == new_c)
        return 0;

    if (!new_c)
    {
        luaL_error(L, "`.client` only support non-nil `client` objects");
    }

    self->object.window.ptr = new_c;

    luaA_object_push(L, new_c);
    luaA_object_push(L, old_c);
    luaA_object_emit_signal(L, -5, "property::client", 2);
    lua_pop(L, 2);

    /* Also send a signal on the tree root */
    luaA_object_push(L, tree_node_find_root(self));
    luaA_object_push(L, self);
    luaA_object_push(L, old_c);
    luaA_object_emit_signal(L, -4, "client::replaced", 3);
    lua_pop(L, 4);

    return 0;
}

static int
luaA_tree_node_get_drawin(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, "._drawin");
    switch (self->type) {
    case TREE_NODE_TYPE_DRAWIN:
        luaA_object_push(L, self->object.window.ptr);
        break;
    default:
        lua_pushnil(L);
        break;
    }
    return 1;
}

static int
luaA_tree_node_init_drawin(lua_State *L, tree_node_t *self)
{
    drawin_t *d = luaA_checkudata(L, -1, &drawin_class);

    if (!d)
        return 0;

    self->type = TREE_NODE_TYPE_DRAWIN;
    self->object.window.ptr = d;
    self->object.window.geometry = (area_t) {
        .x      = 0,
        .y      = 0,
        .width  = 0,
        .height = 0
    };
    self->object.window.gaps = (tree_node_gaps_t) {
        .left   = 0,
        .right  = 0,
        .top    = 0,
        .bottom = 0
    };

    if (d->tree_nodes)
        d->tree_nodes->object.window.ref.previous = self;

    self->object.window.ref.next = d->tree_nodes;
    d->tree_nodes = self;

    return 0;
}

static int
luaA_tree_node_get_wibox(lua_State *L, tree_node_t *self)
{
    if (self->type != TREE_NODE_TYPE_DRAWIN)
    {
        lua_pushnil(L);
        return 1;
    }

    push_wibox(L, (drawin_t *) self->object.window.ptr);

    return 1;
}

static int
luaA_tree_node_get_wiboxes(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, "._wiboxes");
    lua_newtable(L);

    int count = 0;

    for (tree_node_t *n = self; n && n != self->siblings.next; n = tree_node_find_next(n))
        if (n->type == TREE_NODE_TYPE_DRAWIN)
        {
            luaA_tree_node_get_wibox(L, n);
            lua_rawseti(L, -2, ++count);
        }

    return 1;
}

static int
luaA_tree_node_get_next_sibling(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".next_sibling");
    luaA_object_push(L, self->siblings.next);
    return 1;
}

static int
luaA_tree_node_get_previous_sibling(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".previous_sibling");
    luaA_object_push(L, self->siblings.previous);
    return 1;
}

static int
luaA_tree_node_get_next(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".next");
    tree_node_t *next = tree_node_find_next(self);

    if (next)
        luaA_object_push(L, next);
    else
        lua_pushnil(L);

    return 1;
}

static int
luaA_tree_node_get_previous(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".previous");
    tree_node_t *previous = tree_node_find_previous(self);

    if (previous)
        luaA_object_push(L, previous);
    else
        lua_pushnil(L);

    return 1;
}

static int
luaA_tree_node_get_first_child(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".first_child");

    if (self->type != TREE_NODE_TYPE_BRANCH)
    {
        luaL_error(L, "`.first_child` can only be called on a `branch` node");
        return 0;
    }

    if (self->object.children.head && self->object.children.head->type == TREE_NODE_TYPE_DEFUNCT)
    {
        luaL_error(L, "`.first_child` is deleted, this is a bug.");
        return 0;
    }

    tree_node_t *t = self->object.children.head;

    luaA_object_push(L, t);

    return 1;
}

static int
luaA_tree_node_get_last_child(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".last_child");

    if (self->type != TREE_NODE_TYPE_BRANCH)
    {
        luaL_error(L, "`.last_child` can only be called on a `branch` node");
        return 0;
    }

    if (self->object.children.tail && self->object.children.tail->type == TREE_NODE_TYPE_DEFUNCT)
    {
        luaL_error(L, "`.last_child` is deleted, this is a bug.");
        return 0;
    }

    luaA_object_push(L, self->object.children.tail);
    return 1;
}

static int
luaA_tree_node_find_root(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".root");

    luaA_object_push(L, tree_node_find_root(self));

    return 1;
}

static void
compute_geometry(tree_node_t *node, extents_t *out)
{
    #define GEO node->object.window.geometry
    switch (node->type) {
    case TREE_NODE_TYPE_NEW:
    case TREE_NODE_TYPE_DEFUNCT:
        break;
    case TREE_NODE_TYPE_CLIENT:
    case TREE_NODE_TYPE_DRAWIN:
        out->x0 = min(out->x0, GEO.x             );
        out->y0 = min(out->y0, GEO.y             );
        out->x1 = max(out->x1, GEO.x + GEO.width );
        out->y1 = max(out->y1, GEO.y + GEO.height);
        break;
    case TREE_NODE_TYPE_BRANCH:
        for (; node; node = node->siblings.next)
            compute_geometry(node, out);
        break;
    }
    #undef GEO
}

static int
luaA_tree_node_get_geometry(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".geometry");

    extents_t geo = (extents_t) {
       .x0 = INT_MAX,
       .x1 = 0,
       .y0 = INT_MAX,
       .y1 = 0,
    };

    compute_geometry(self, &geo);

    luaA_pusharea(L, (area_t) {
        .x      = geo.x0,
        .y      = geo.y0,
        .width  = geo.x1 - geo.x0,
        .height = geo.y1 - geo.y0
    });

    return 1;
}

static int
luaA_tree_node_set_geometry(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".geometry");

    area_t geo, old_geo;

    switch (self->type) {
    case TREE_NODE_TYPE_DEFUNCT:
    case TREE_NODE_TYPE_BRANCH:
        luaL_error(L, "Setting the geometry only works on a client or drawin node (%s)",
            get_type_name(self));
        break;
    case TREE_NODE_TYPE_NEW:
    case TREE_NODE_TYPE_CLIENT:
    case TREE_NODE_TYPE_DRAWIN:
        geo     = self->object.window.geometry;
        old_geo = self->object.window.geometry;

        luaA_checktable(L, -1);
        geo.x = round(
            luaA_getopt_number_range(
                L, -1, "x", geo.x, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        geo.y = round(
            luaA_getopt_number_range(
                L, -1, "y", geo.y, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        geo.width = ceil(
            luaA_getopt_number_range(
                L, -1, "width", geo.width, MIN_X11_SIZE, MAX_X11_SIZE));
        geo.height = ceil(
            luaA_getopt_number_range(
                L, -1, "height", geo.height, MIN_X11_SIZE, MAX_X11_SIZE));
        self->object.window.geometry = geo;

        if (AREA_EQUAL(old_geo, geo))
            return 0;

        /* Emit the signal */
        if (self->type != TREE_NODE_TYPE_NEW)
        {
            luaA_pusharea(L, geo);
            luaA_pusharea(L, old_geo);
            luaA_object_emit_signal(L, -5, "property::geometry", 2);
            lua_pop(L, 2);

            if (old_geo.x != geo.x)
                luaA_object_emit_signal(L, -1, "property::x", 0);
            if (old_geo.y != geo.y)
                luaA_object_emit_signal(L, -1, "property::y", 0);
            if (old_geo.width != geo.width)
                luaA_object_emit_signal(L, -1, "property::width", 0);
            if (old_geo.height != geo.height)
                luaA_object_emit_signal(L, -1, "property::height", 0);
        }
        break;
    }

    return 0;
}

/* Only call on client nodes */
static area_t
get_effective_geometry(lua_State *L, tree_node_t *self)
{
    const int top = lua_gettop(L);

    extents_t extents = (extents_t) {
       .x0 = INT_MAX,
       .x1 = 0,
       .y0 = INT_MAX,
       .y1 = 0,
    };

    compute_geometry(self, &extents);

    const area_t total_geo = {
        .x      = extents.x0,
        .y      = extents.y0,
        .width  = extents.x1 - extents.x0,
        .height = extents.y1 - extents.y0
    };

    area_t client_geo = total_geo;

    tree_node_gaps_t *gaps = &self->object.window.gaps;

    /* Substract he gaps */
    client_geo.x      += gaps->left;
    client_geo.y      += gaps->top;
    client_geo.width   = max(1, client_geo.width  - (gaps->left + gaps->right ));
    client_geo.height  = max(1, client_geo.height - (gaps->top  + gaps->bottom));

    /* Apply the side hints */
    client_t *c = (client_t*) self->object.window.ptr;
    client_geo  = client_apply_size_hints(c, client_geo);

    if (!(self->flags & TREE_NODE_HAS_PLACEMENT))
        return client_geo;

    /* Apply the placement */
    lua_pushvalue(L, -2);
    lua_pushstring(L, "get_placement");
    lua_gettable(L, -2);

    /* There is no placement */
    if (!lua_isfunction(L, -1))
    {
        lua_settop(L, top);
        return client_geo;
    }

    /* Add `self` to the stack (again) */
    lua_pushvalue(L, -2);

    /* Calling `get_placement()` */
    if (lua_pcall(L, 1, 1, 0) != LUA_OK)
    {
        lua_settop(L, top);
        return client_geo;
    }

    /* Add `awful.placement` object arguments */
    lua_newtable(L);
    luaA_pusharea(L, client_geo);
    lua_setfield(L, -2, "geometry");

    /* Add `awful.placement` args arguments */
    lua_newtable(L);
    lua_pushboolean(L, true);
    lua_setfield(L, -2, "pretend");
    luaA_tree_node_get_geometry(L, self);
    lua_setfield(L, -2, "bounding_rect");

    /* Calling `get_placement()` */
    if (lua_pcall(L, 2, 1, 0) != LUA_OK)
        luaL_error(L, "Calling the `awful.tree.placement` function "
            "failed because: %s", lua_tostring(L, -1));

    /* Get the `awful.placement` results */
    if(!lua_istable(L, -1))
    {
        lua_settop(L, top);
        return client_geo;
    }

    client_geo = (area_t) {
        .x      = round(luaA_getopt_number_range(L, -1, "x"     ,
                        client_geo.x, MIN_X11_COORDINATE, MAX_X11_COORDINATE)),
        .y      = round(luaA_getopt_number_range(L, -1, "y"     ,
                        client_geo.y, MIN_X11_COORDINATE, MAX_X11_COORDINATE)),
        .width  = round(luaA_getopt_number_range(L, -1, "width" ,
                        client_geo.width, MIN_X11_COORDINATE, MAX_X11_COORDINATE)),
        .height = round(luaA_getopt_number_range(L, -1, "height",
                        client_geo.height, MIN_X11_COORDINATE, MAX_X11_COORDINATE))
    };

    lua_settop(L, top);

    if (client_geo.x < total_geo.x)
        luaL_error(L, "The tree node placement function returned an out of "
            "bound (%d:%d) `x` value of %d",
            total_geo.x, total_geo.x+total_geo.width, client_geo.x);
    else if (client_geo.y < total_geo.y)
        luaL_error(L, "The tree node placement function returned an out of "
            "bound (%d:%d) `y` value of %d",
            total_geo.x, total_geo.y+total_geo.height, client_geo.y);


    return client_geo;
}

static int
luaA_tree_node_get_effective_geometry(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".geometry");

    if (self->type != TREE_NODE_TYPE_CLIENT)
        return luaA_tree_node_get_geometry(L, self);

    luaA_pusharea(L, get_effective_geometry(L, self));

    return 1;
}

static int
luaA_tree_node_set_has_placement(lua_State *L, tree_node_t *self)
{
    check_valid(L, self, ".geometry");

    if (self->type != TREE_NODE_TYPE_CLIENT)
        return 0;


    const bool value = luaA_checkboolean(L, -1);

    self->flags = (self->flags & ~TREE_NODE_HAS_PLACEMENT) |
        value ? TREE_NODE_HAS_PLACEMENT : TREE_NODE_FLAGS_NONE;

    return 0;
}


void
tree_node_append(lua_State *L, tree_node_t *node, tree_node_t *parent)
{
    if (parent->type != TREE_NODE_TYPE_BRANCH)
        luaL_error(L,
            "`:append()` can only be called on a tree node, not a %s. "
            "Use `:move_after()`.",
            get_type_name(parent));

    unlink_node(L, node, false, NULL);

    tree_node_t *old_last = parent->object.children.tail;

    parent->object.children.tail = node;
    node->parent                 = parent;
    node->siblings.previous      = old_last;
    node->siblings.next          = NULL;

    if (!parent->object.children.head)
        parent->object.children.head = node;

    if (old_last)
        old_last->siblings.next = node;
}

void
tree_node_push(lua_State *L, tree_node_t *node, tree_node_t *parent)
{
    if (parent->type != TREE_NODE_TYPE_BRANCH)
        luaL_error(L,
            "`:push()` can only be called on a tree node, not a %s. "
            "Use `:move_before()`.",
            get_type_name(parent));

    unlink_node(L, node, false, NULL);

    tree_node_t *old_first = parent->object.children.head;

    parent->object.children.head = node;
    node->parent                 = parent;
    node->siblings.next          = old_first;
    node->siblings.previous      = NULL;

    if (!parent->object.children.tail)
        parent->object.children.tail = node;

    if (old_first)
        old_first->siblings.previous = node;
}

void
tree_node_insert_before(lua_State *L, tree_node_t *to_insert, tree_node_t *self)
{
    unlink_node(L, to_insert, false, NULL);

    if (self->parent && self->parent->object.children.head == self)
        self->parent->object.children.head = to_insert;

    to_insert->siblings.next     = self;
    to_insert->siblings.previous = self->siblings.previous;

    if (self->siblings.previous)
        self->siblings.previous->siblings.next = to_insert;

    self->siblings.previous = to_insert;
    to_insert->parent       = self->parent;
}

void
tree_node_insert_after(lua_State *L, tree_node_t *to_insert, tree_node_t *self)
{
    unlink_node(L, to_insert, false, NULL);

    if (self->parent && self->parent->object.children.tail == self)
        self->parent->object.children.tail = to_insert;

    to_insert->siblings.previous = self;
    to_insert->siblings.next     = self->siblings.next;

    if (self->siblings.next)
        self->siblings.next->siblings.previous = to_insert;

    self->siblings.next = to_insert;
    to_insert->parent   = self->parent;
}

void
tree_node_unlink_client(lua_State *L, void *cp)
{
    client_t *c = (client_t*) cp;

    for (tree_node_t *node = c->tree_nodes; node; node = c->tree_nodes)
        unlink_node(L, node, true, "client_killed");
}

void
tree_node_unlink_drawin(lua_State *L, void *dp)
{
    drawin_t *d = (drawin_t*) dp;

    for (tree_node_t *node = d->tree_nodes; node; node = d->tree_nodes)
        unlink_node(L, node, true, "wibox_garbage_collected");
}

tree_node_t *
tree_node_find_previous(tree_node_t *node)
{
    /* Traverse the branches until there's a leaf */
    if (node->siblings.previous && node->siblings.previous->type ==
        TREE_NODE_TYPE_BRANCH )
    {
        tree_node_t *candidate = node->siblings.previous->object.children.tail;

        while (candidate && candidate->type == TREE_NODE_TYPE_BRANCH &&
          candidate->object.children.tail)
            candidate = candidate->object.children.tail;

        return candidate ? candidate : node->siblings.previous;
    }

    if (node->siblings.previous)
        return node->siblings.previous;
    else if (node->parent)
        return node->parent;

    return NULL;
}

tree_node_t *
tree_node_find_next(tree_node_t *node)
{
    if (node->type == TREE_NODE_TYPE_BRANCH && node->object.children.head)
        return node->object.children.head;
    else if (node->siblings.next)
        return node->siblings.next;

    /* Traverse the tree toward the root until a next node is found */
    if (node->parent)
    {
        tree_node_t *candidate = node->parent;

        while ((!candidate->siblings.next) && candidate->parent != NULL)
            candidate = candidate->parent;

        return candidate->siblings.next;
    }

    return NULL;
}

tree_node_t*
tree_node_find_tail(tree_node_t *node)
{
    while (node->type == TREE_NODE_TYPE_BRANCH
      && node->object.children.tail)
        node = node->object.children.tail;

    return node;
}

tree_node_t*
tree_node_find_root(tree_node_t *node)
{
    while (node->parent)
        node = node->parent;

    return node;
}

void
tree_node_class_setup(lua_State *L)
{
    static const struct luaL_Reg tree_node_methods[] =
    {
        LUA_CLASS_METHODS(tree_node)
        { "__call", luaA_tree_node_new },
        { NULL, NULL }
    };

    static const struct luaL_Reg tree_node_meta[] =
    {
        LUA_OBJECT_META(tree_node)
        LUA_CLASS_META
        /* Tree manipulation methods                */
        { "swap"       , luaA_tree_node_swap        },
        { "join"       , luaA_tree_node_join        },
        { "push"       , luaA_tree_node_push        },
        { "append"     , luaA_tree_node_append      },
        { "detach"     , luaA_tree_node_detach      },
        { "fork"       , luaA_tree_node_fork        },
        { "cleanup"    , luaA_tree_node_cleanup     },
        { "move_before", luaA_tree_node_move_before },
        { "move_after" , luaA_tree_node_move_after  },

        /* Window management methods                        */
        { "_apply_geometry" , luaA_tree_node_apply_geometry  },
        { "_apply_stacking" , luaA_tree_node_apply_stacking  },

        /* Debugging                                        */
        { "_check_integrity", luaA_tree_node_check_integrity },

        {NULL, NULL},
    };

    luaA_class_setup(L, &tree_node_class, "_tree_node", NULL,
                     (lua_class_allocator_t) tree_node_allocator,
                     (lua_class_collector_t) tree_node_wipe,
                     (lua_class_checker_t)   tree_node_check_valid,
                     luaA_class_index_miss_property, luaA_class_newindex_miss_property,
                     tree_node_methods, tree_node_meta);
    luaA_class_add_property(&tree_node_class, "geometry",
                            (lua_class_propfunc_t) luaA_tree_node_set_geometry,
                            (lua_class_propfunc_t) luaA_tree_node_get_geometry,
                            (lua_class_propfunc_t) luaA_tree_node_set_geometry);
    luaA_class_add_property(&tree_node_class, "effective_geometry",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_effective_geometry,
                            NULL);
    luaA_class_add_property(&tree_node_class, "_root",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_find_root,
                            NULL);
    luaA_class_add_property(&tree_node_class, "client",
                            (lua_class_propfunc_t) luaA_tree_node_init_client,
                            (lua_class_propfunc_t) luaA_tree_node_get_client,
                            (lua_class_propfunc_t) luaA_tree_node_set_client);
    luaA_class_add_property(&tree_node_class, "_clients",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_clients,
                            NULL);
    luaA_class_add_property(&tree_node_class, "_drawin",
                            (lua_class_propfunc_t) luaA_tree_node_init_drawin,
                            (lua_class_propfunc_t) luaA_tree_node_get_drawin,
                            NULL);
    luaA_class_add_property(&tree_node_class, "_wibox",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_wibox,
                            NULL);
    luaA_class_add_property(&tree_node_class, "_wiboxes",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_wiboxes,
                            NULL);
    luaA_class_add_property(&tree_node_class, "_parent",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_parent,
                            NULL);
    luaA_class_add_property(&tree_node_class, "previous_sibling",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_previous_sibling,
                            NULL);
    luaA_class_add_property(&tree_node_class, "next_sibling",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_next_sibling,
                            NULL);
    luaA_class_add_property(&tree_node_class, "previous",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_previous,
                            NULL);
    luaA_class_add_property(&tree_node_class, "next",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_next,
                            NULL);
    luaA_class_add_property(&tree_node_class, "first_child",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_first_child,
                            NULL);
    luaA_class_add_property(&tree_node_class, "last_child",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_last_child,
                            NULL);
    luaA_class_add_property(&tree_node_class, "type",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_type,
                            NULL);
    luaA_class_add_property(&tree_node_class, "protected",
                            (lua_class_propfunc_t) luaA_tree_node_set_protected,
                            (lua_class_propfunc_t) luaA_tree_node_get_protected,
                            (lua_class_propfunc_t) luaA_tree_node_set_protected);
    luaA_class_add_property(&tree_node_class, "_read_only",
                            (lua_class_propfunc_t) luaA_tree_node_set_read_only,
                            (lua_class_propfunc_t) luaA_tree_node_get_read_only,
                            (lua_class_propfunc_t) luaA_tree_node_set_read_only);
    luaA_class_add_property(&tree_node_class, "read_only",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_read_only,
                            NULL);
    luaA_class_add_property(&tree_node_class, "mode",
                            NULL,
                            (lua_class_propfunc_t) luaA_tree_node_get_mode,
                            NULL);
    luaA_class_add_property(&tree_node_class, "honor_size_hints",
                            (lua_class_propfunc_t) luaA_tree_node_set_honor_size_hints,
                            (lua_class_propfunc_t) luaA_tree_node_get_honor_size_hints,
                            (lua_class_propfunc_t) luaA_tree_node_set_honor_size_hints);
    luaA_class_add_property(&tree_node_class, "_has_placement",
                            (lua_class_propfunc_t) luaA_tree_node_set_has_placement,
                            (lua_class_propfunc_t) NULL,
                            (lua_class_propfunc_t) luaA_tree_node_set_has_placement);
    luaA_class_add_property(&tree_node_class, "gaps",
                            (lua_class_propfunc_t) luaA_tree_node_set_gaps,
                            (lua_class_propfunc_t) luaA_tree_node_get_gaps,
                            (lua_class_propfunc_t) luaA_tree_node_set_gaps);

    static const struct luaL_Reg tree_node_weak_ref_methods[] =
    {
        LUA_CLASS_METHODS(tree_node_weak_ref)
        { "__call", luaA_tree_node_weak_ref_new },
        { NULL, NULL }
    };

    static const struct luaL_Reg tree_node_weak_ref_meta[] =
    {
        LUA_OBJECT_META(tree_node_weak_ref)
        LUA_CLASS_META
        {NULL, NULL},
    };

    luaA_class_setup(L, &tree_node_weak_ref_class, "_tree_node_weak_ref", NULL,
                     (lua_class_allocator_t) tree_node_weak_ref_new,
                     (lua_class_collector_t) tree_node_weak_ref_wipe,
                     NULL,
                     luaA_class_index_miss_property, luaA_class_newindex_miss_property,
                     tree_node_weak_ref_methods, tree_node_weak_ref_meta);

    luaA_class_add_property(&tree_node_class, "root_node",
                            (lua_class_propfunc_t) luaA_tree_node_weak_ref_init_root_node,
                            (lua_class_propfunc_t) NULL,
                            (lua_class_propfunc_t) NULL);
}

// vim: filetype=c:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
