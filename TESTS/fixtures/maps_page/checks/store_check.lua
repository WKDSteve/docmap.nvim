-- Names the functions the fixture counts as tested.
local text = require("app.util.text")
assert(text.trim(" a ") == "a")
assert(#text.words("a b") == 2)
require("app.core.store").load("k")
