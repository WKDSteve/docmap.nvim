---@module 'docmap.core.lang.c'
--- C, registered as a language backend. Real work lives in `cfamily.lua`,
--- shared with `cpp.lua` — see that file's header for the two decisions this
--- language forced: what a header's prototypes are, and what stands in for a
--- module system when there is none.
---
--- `.h` is claimed here rather than by `cpp.lua`. A header shared between
--- the two parses as C in either grammar for the shapes this backend reads,
--- and claiming it twice would give one file two module identities — which
--- is a wrong answer rather than a duplicate.

local M = require("docmap.core.lang.cfamily").backend(
  "c",
  "c",
  { "c", "h" },
  { "src", "lib", "source" }
)

-- C only, not C++: `cpp.lua` claims neither `.c` nor `.h`, and its keywords (`const`, `static`, `auto`) mean other
-- things, so it decorates nothing until it has a glossary of its own. `c` and `h` share this one table.
M.glossary = require("docmap.core.lang.glossary.c")

require("docmap.core.lang_registry").register(M.name, M)

return M
