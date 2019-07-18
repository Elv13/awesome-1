local gdebug = require("gears.debug")

return gdebug.deprecate_class(
    require("ruled.client"),
    "awful.rules",
    "ruled.client",
    { deprecated_in = 5}
)
