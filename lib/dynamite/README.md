# Dynamite

This module offers an drop-in alternative to AwesomeWM `awful.layout` with the
following extra capabilities:

 * Runtime split and tabbing (like i3)
 * Full support for tabs
 * A declarative syntax to define new layouts
 * Serialization, including client position
 * The ability to track and modify the layout state
 * Introspection

## Installation

First, install the latest git version of AwesomeWM. Using the latest stable
release may or may not work, but is **not** supported.

```sh
cd ~/.config/awesome
git clone https://github.com/elv13/dynamite
```

In your `rc.lua`, add `local dynamite = require("dynamite")` after
`local awful = require("awful")`.

Done! It is recommended to always test in Xephyr before reloading Awesome. There
is no other change required, AwesomeWM is now using the dynamite layouts
instead of the regular ones. No change will be visible until new features are
enabled.

#### Unit tests and documentation

The best way to run the tests and generate the documentation is linking this
module directly to AwesomeWM source.

```sh
ln -l /path/to/dynamite /path/to/awesome/lib/
ln -l /path/to/dynamite/tests /path/to/awesome/tests/examples/dynamite
```

And compile AwesomeWM normally.

## Documentation

This modules, just like AwesomeWM itself, uses `ldoc`. See

https://elv13.github.io/libraries/dynamite.html

## Recommanded addons

The Collision module has a branch dedicated for this module adding:

 * All the widgets necessary to visualize splitting and tabbing at runtime
 * A launcher widget with built-in support for dynamic layouts
 * All the visual hints for navigation

## History, design and scope

The original version of this module was developed in 2010 for Awesome 3.4. A
major rewrite was started in late 2015 to merge the layout "object tree" with
the regular `wibox.layout` code. This allows this module to share the whole
hierarchy and layout logic with the regular `wibox`/`wibar` widget system. This
module is developed alongside AwesomeWM and thus always require the latest git
commit of AwesomeWM to work as intended. As soon as pieces of this module are
stable enough, they are merged upstream until nothing remains.

The "end game" for this module is to provide a complete framework for tiling
window managing that's both easy to use, extensible and out feature every other
tiling systems in existence.

It doesn't currently aim to provide all the possible widgets and addons. They
may eventually be added, but for now this module is for the tiling system only
along with the bare minimum widgets to make good use of its features.
