-- Test code: when something here comes back nil -- a `pcall(require, ...)`, a fixture read -- this file must crash
-- and name it.
---@diagnostic disable: need-check-nil
-- TESTS/c_calls_spec.lua -- C and C++ call edges, and the rule for a call across a header and its source.
--
-- The rule (written down in `core/lang/cfamily.lua`): a call is resolved in the calling file first, then through the
-- files it `#include`s. The first included header that declares the name is the callee's home, and the edge goes to
-- the definition in the header's own source (`a.h` -> `a.c`/`a.cpp`) when there is one, else to the prototype.
-- Overloads collapse into one target.
--
-- Edge counts below are worked out by hand from `TESTS/fixtures/ccalls`:
--   C:   main.c run -> main.c local (own file), main.c run -> util.c twice (through util.h, to the body),
--        util.c twice -> util.c bump (own file; two call sites, one edge)                        = 3 edges
--   C++: app.cpp main_app -> shape.cpp area (two call sites of two overloads, one target),
--        app.cpp main_app -> shape.cpp perimeter                                                = 2 edges

return function(H)
  local eq, ok = H.eq, H.ok
  local registry = require("docmap.core.lang_registry")

  for _, name in ipairs({ "c", "cpp" }) do
    local backend = registry.get(name)
    ok(backend ~= nil, name .. ": the backend is registered")
    eq(backend.emits_calls, true, name .. ": returns call sites")
    eq(backend.call_via_includes, true, name .. ": resolves a call through the includes")
  end

  local function has(grammar)
    local explicit = os.getenv("DOCMAP_" .. grammar:upper() .. "_PARSER")
    local added, loaded
    if explicit and explicit ~= "" then
      added, loaded = pcall(vim.treesitter.language.add, grammar, { path = explicit })
    else
      added, loaded = pcall(vim.treesitter.language.add, grammar)
    end
    return added and loaded == true
  end

  local root = (vim.fn.getcwd():gsub("\\", "/")) .. "/TESTS/fixtures/ccalls"
  ok(vim.fn.isdirectory(root) == 1, "c_calls: the fixture tree is checked in")

  if not (has("c") and has("cpp")) then
    print("n/a  c_calls: the c or cpp parser is not installed")
    return
  end

  local ir = require("docmap.core.scan").scan(require("docmap.config").build(root))

  local edges, count = {}, 0
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" then
      count = count + 1
      edges[e.from .. "#" .. e.from_fn .. ">" .. e.to .. "#" .. e.to_fn] = e
    end
  end

  eq(count, 5, "c_calls: three C edges and two C++ edges, no more")

  local own = edges["./main.c#run>./main.c#local"]
  ok(own, "c_calls: a call to a function of the same file resolves there")
  eq(own and own.confidence, "exact", "c_calls: ...exactly")

  local across = edges["./main.c#run>./util.c#twice"]
  ok(
    across,
    "c_calls: a call through an included header goes to the definition in the header's source"
  )
  eq(across and across.confidence, "exact", "c_calls: ...exactly, not by the bare-name guess")
  ok(not edges["./main.c#run>./util.h#twice"], "c_calls: ...and not to the prototype")

  ok(
    edges["./util.c#twice>./util.c#bump"],
    "c_calls: two calls of one function in one body are one edge"
  )

  ok(
    edges["./app.cpp#main_app>./shape.cpp#area"],
    "c_calls: a C++ call resolves through its header to the definition"
  )
  ok(
    edges["./app.cpp#main_app>./shape.cpp#perimeter"],
    "c_calls: ...a second function the same way"
  )
  ok(
    not edges["./app.cpp#main_app>./shape.hpp#area"],
    "c_calls: overloads are one target: no second edge, none to the prototype"
  )

  -- Qualified C++ calls (`TESTS/fixtures/ccalls_ns`), worked out by hand:
  --   user.cpp use_all -> cfg.cpp mutate      (`cfg::mutate`, declared inside `namespace cfg`)
  --   user.cpp use_all -> cfg.cpp deep        (`::cfg::inner::deep`, a nested namespace, from the global one)
  --   user.cpp use_all -> outline.cpp out::ol (`out::ol`, defined out of line as `int out::ol`)
  --   user.cpp local_call -> cfg.cpp deep     (`inner::deep` written inside `namespace cfg`)
  -- `std::max` is outside the tree: no edge.                                                         = 4 edges
  local ns_root = (vim.fn.getcwd():gsub("\\", "/")) .. "/TESTS/fixtures/ccalls_ns"
  local ns_ir = require("docmap.core.scan").scan(
    require("docmap.config").build(ns_root, { calls_heuristic = false })
  )
  local ns_edges, ns_count = {}, 0
  for _, e in ipairs(ns_ir.edges or {}) do
    if e.kind == "call" then
      ns_count = ns_count + 1
      ns_edges[e.from .. "#" .. e.from_fn .. ">" .. e.to .. "#" .. e.to_fn] = e
    end
  end
  eq(ns_count, 4, "c_calls ns: four qualified edges, no more")
  for _, key in ipairs({
    "./user.cpp#use_all>./cfg.cpp#mutate",
    "./user.cpp#use_all>./cfg.cpp#deep",
    "./user.cpp#use_all>./outline.cpp#out::ol",
    "./user.cpp#local_call>./cfg.cpp#deep",
  }) do
    ok(ns_edges[key], "c_calls ns: " .. key)
    eq(ns_edges[key] and ns_edges[key].confidence, "exact", "c_calls ns: exact, " .. key)
  end

  -- With the heuristic on (`TESTS/fixtures/ccalls_ns_order`):
  --   x.cpp g -> x.cpp f, exact: `b::f` inside `namespace a` is the global `b::f` of the file, never a guess at the
  --     `a::b::f` of y.cpp, which x.cpp does not include (every key is tried exactly before any is guessed)
  --   caller.cpp call_free -> nothing: `app::run` is a free function outside the tree, not the member `run` of
  --     `app::Helper` (a member is keyed with its class)
  --   caller.cpp call_member -> helper.cpp run: `app::Helper::run` finds the member
  local order_root = (vim.fn.getcwd():gsub("\\", "/")) .. "/TESTS/fixtures/ccalls_ns_order"
  local order_ir = require("docmap.core.scan").scan(
    require("docmap.config").build(order_root, { calls_heuristic = true })
  )
  local order = {}
  for _, e in ipairs(order_ir.edges or {}) do
    if e.kind == "call" then
      order[e.from .. "#" .. e.from_fn .. ">" .. e.to .. "#" .. e.to_fn] = e
    end
  end
  local own_f = order["./x.cpp#g>./x.cpp#f"]
  ok(own_f, "c_calls ns order: the file's own b::f\n" .. vim.inspect(vim.tbl_keys(order)))
  eq(own_f and own_f.confidence, "exact", "c_calls ns order: exact")
  ok(not order["./x.cpp#g>./y.cpp#f"], "c_calls ns order: no guess at y.cpp")
  for key in pairs(order) do
    ok(
      not key:find("^%./caller%.cpp#call_free>"),
      "c_calls ns order: app::run is not the member: " .. key
    )
  end
  ok(
    order["./caller.cpp#call_member>./helper.cpp#run"],
    "c_calls ns order: app::Helper::run is the member\n" .. vim.inspect(vim.tbl_keys(order))
  )
end
