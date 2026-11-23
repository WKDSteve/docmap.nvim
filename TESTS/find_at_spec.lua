-- TESTS/find_at_spec.lua — from a place in a file to its node in the map: `find.at`, `find.fragment`,
-- `find.parse_position`, `:DocMap here` and the CLI's `--at=`.

return function(H)
  local eq, ok = H.eq, H.ok
  local find = require("docmap.core.find")

  ---A module `pkg/a` with an outer function that holds a nested one, one beside them, and a file node with none.
  ---@return Docmap.IR
  local function sample()
    return {
      root = "lua",
      order = { "lua/pkg/a", "lua/pkg/b.lua" },
      nodes = {
        ["lua/pkg/a"] = {
          id = "lua/pkg/a",
          path = "lua/pkg/a",
          module = "pkg.a",
          source = "lua/pkg/a/init.lua",
          functions = {
            { name = "M.outer", line = 10, line_end = 30 },
            { name = "inner", line = 15, line_end = 20 },
            { name = "M.later", line = 40, line_end = 45 },
          },
        },
        ["lua/pkg/b.lua"] = {
          id = "lua/pkg/b.lua",
          path = "lua/pkg/b.lua",
          source = "lua/pkg/b.lua",
          functions = {},
        },
      },
    }
  end

  local ir = sample()
  local function same(got, want, what)
    ok(vim.deep_equal(got, want), what .. ": got " .. vim.inspect(got))
  end
  ---@type fun(...): Docmap.FindHit
  local function at(...)
    return assert(find.at(ir, ...))
  end

  -- ---------------------------------------------------------------- find.at
  local hit = at("lua/pkg/a/init.lua", 12)
  eq(hit.kind, "function", "at: a line inside a function resolves to the function")
  eq(hit.key, "lua/pkg/a#M.outer", "at: ...with the key the page uses")

  hit = at("lua/pkg/a/init.lua", 17)
  eq(hit.fn.name, "inner", "at: a nested function wins over the one around it")

  hit = at("lua/pkg/a/init.lua", 22)
  eq(hit.fn.name, "M.outer", "at: after the nested function the outer one holds the line again")

  hit = at("lua/pkg/a/init.lua", 35)
  eq(hit.kind, "module", "at: a line between functions resolves to the module")
  eq(hit.id, "lua/pkg/a", "at: ...the node that owns the file")
  eq(hit.key, nil, "at: ...and has no function key")

  hit = at("lua/pkg/b.lua", 3)
  eq(hit.kind, "module", "at: a file without any function resolves to its node")
  eq(hit.id, "lua/pkg/b.lua", "at: ...the file node")

  eq(find.at(ir, "lua/other.lua", 3), nil, "at: a file the map does not know is nil")

  hit = at("lua\\pkg\\a\\init.lua", 41)
  eq(hit.fn.name, "M.later", "at: backslashes are the same path")
  hit = at("E:/proj/lua/pkg/a/init.lua", 41, nil, "E:\\proj")
  eq(hit.fn.name, "M.later", "at: an absolute path is made relative to the root")

  hit = at("lua/pkg/a/init.lua", 33, 42)
  eq(hit.fn.name, "M.later", "at: a range between functions takes the function it overlaps most")
  hit = at("lua/pkg/a/init.lua", 17, 42)
  eq(hit.fn.name, "inner", "at: a range starting in a function takes that one")
  hit = at("lua/pkg/a/init.lua", 31, 33)
  eq(hit.kind, "module", "at: a range that touches no function is the module")

  -- ------------------------------------------------------- find.parse_position
  local file, first, last = find.parse_position("lua/x.lua:12-20")
  same({ file, first, last }, { "lua/x.lua", 12, 20 }, "parse: file:first-last")
  file, first, last = find.parse_position("lua/x.lua:7")
  same({ file, first, last }, { "lua/x.lua", 7, nil }, "parse: file:line")
  file, first, last = find.parse_position("C:/x.lua")
  same({ file, first, last }, { "C:/x.lua", nil, nil }, "parse: a drive colon is no line")
  file, first = find.parse_position("C:/x.lua:9")
  same({ file, first }, { "C:/x.lua", 9 }, "parse: a drive and a line")

  -- ---------------------------------------------------------- find.fragment
  eq(
    find.fragment({ id = "lua/pkg/a", kind = "module" }),
    "#tab=tree&id=lua%2Fpkg%2Fa",
    "fragment: a module is the tree tab at its node"
  )
  eq(
    find.fragment({ id = "lua/pkg/a", kind = "function", key = "lua/pkg/a#M.outer" }),
    "#tab=tree&id=lua%2Fpkg%2Fa&fn=lua%2Fpkg%2Fa%23M.outer",
    "fragment: a function adds its key"
  )

  -- ------------------------------------------------------ :DocMap here
  local here = require("docmap.bindings.usrcmds.here")
  local function ctx_for(range)
    local calls = { warn = {}, opened = {} }
    return {
      cfg = { root = "/proj" },
      range = range,
      handle = {
        ir = function()
          return ir
        end,
      },
      notify = {
        warn = function(m)
          calls.warn[#calls.warn + 1] = m
        end,
      },
      open_map = function(h)
        calls.opened[#calls.opened + 1] = h
        return true
      end,
    },
      calls
  end

  local ctx, calls = ctx_for(nil)
  here.run(ctx, "lua/pkg/a/init.lua:17")
  same(
    calls.opened,
    { "#tab=tree&id=lua%2Fpkg%2Fa&fn=lua%2Fpkg%2Fa%23inner" },
    "here: opens at the function"
  )

  ctx, calls = ctx_for({ 41, 43 })
  here.run(ctx, "lua/pkg/a/init.lua")
  eq(#calls.opened, 1, "here: a range is the position")
  ok(calls.opened[1]:find("M.later", 1, true) ~= nil, "here: ...the function of the range")

  ctx, calls = ctx_for(nil)
  here.run(ctx, "lua/nope.lua:1")
  eq(#calls.opened, 0, "here: an unknown file opens nothing")
  eq(#calls.warn, 1, "here: ...and says so")

  -- `--print` writes `<id>\t<key>\t<fragment>` and opens nothing; capture what it writes.
  ctx, calls = ctx_for(nil)
  local written = {}
  local real_out = here.out
  here.out = function(s)
    written[#written + 1] = s
  end
  local done, err = pcall(here.run, ctx, "lua/pkg/b.lua:2 --print")
  here.out = real_out
  ok(done, "here --print: runs (" .. tostring(err) .. ")")
  eq(#calls.opened, 0, "here --print: opens nothing")
  eq(
    written[1],
    "lua/pkg/b.lua\t-\t#tab=tree&id=lua%2Fpkg%2Fb.lua\n",
    "here --print: id, key (- for none) and fragment, tab separated"
  )
end
