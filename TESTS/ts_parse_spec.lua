-- TESTS/ts_parse_spec.lua — `docmap.core.ts_parse`
--
-- The parse cache `scan_full` opens around itself. Profiling `generate` over
-- lib.nvim found every source parsed twice (functions + markers for each
-- module, coverage + check for each spec file); this module makes the second
-- ask a lookup. What could go wrong is all about scope: a tree kept after the
-- scan, a tree handed out for a different source, a cache left open by a
-- stage that threw. Those are what these cases pin.

return function(H)
  local eq, ok = H.eq, H.ok

  local ts_parse = require("docmap.core.ts_parse")

  ---Count real `get_string_parser` calls while `fn` runs.
  ---@param fn fun()
  ---@return integer
  local function parses_during(fn)
    local orig = vim.treesitter.get_string_parser
    local n = 0
    vim.treesitter.get_string_parser = function(...)
      n = n + 1
      return orig(...)
    end
    local okc, err = pcall(fn)
    vim.treesitter.get_string_parser = orig
    assert(okc, err)
    return n
  end

  local SRC = "local function f(a)\n  return a\nend\n"

  -- Outside a scope: nothing is kept, every ask parses.
  do
    ok(not ts_parse.active(), "no scope is open at rest")
    local n = parses_during(function()
      ok(ts_parse.root(SRC, "lua") ~= nil, "a valid source yields a root")
      ok(ts_parse.root(SRC, "lua") ~= nil)
    end)
    eq(n, 2, "outside a scope every call parses afresh")
  end

  -- Inside a scope: one parse per source, the same tree each time.
  do
    local first, second
    local n = parses_during(function()
      ts_parse.scoped(function()
        ok(ts_parse.active(), "the scope is open inside scoped()")
        first = ts_parse.root(SRC, "lua")
        second = ts_parse.root(SRC, "lua")
      end)
    end)
    eq(n, 1, "a scope parses each source once")
    assert(first ~= nil and second ~= nil, "both asks yield a root")
    eq(first:type(), "chunk")
    -- `equal` compares the node's identity inside its tree, so two separate
    -- parses of the same text are not equal; one cached tree is.
    ok(first:equal(second), "the second ask gets the first tree")
    ok(not ts_parse.active(), "the scope closes when scoped() returns")
  end

  -- A different source is never answered from another one's entry.
  do
    local other = "return 1\n"
    local n = parses_during(function()
      ts_parse.scoped(function()
        local a = ts_parse.root(SRC, "lua")
        local b = ts_parse.root(other, "lua")
        assert(a ~= nil and b ~= nil, "both sources parse")
        eq(select(3, b:range()), 1, "the second source got its own tree")
      end)
    end)
    eq(n, 2, "two sources, two parses")
  end

  -- A failure is remembered as a failure, not retried and not turned into a
  -- root: an unknown grammar is nil every time, and costs one attempt.
  do
    local n = parses_during(function()
      ts_parse.scoped(function()
        eq(ts_parse.root(SRC, "no_such_grammar_xyz"), nil)
        eq(ts_parse.root(SRC, "no_such_grammar_xyz"), nil)
      end)
    end)
    eq(n, 1, "a failed parse is cached as a failure inside the scope")
  end

  -- Nested scopes share the outer cache and do not close it early.
  do
    local n = parses_during(function()
      ts_parse.scoped(function()
        ts_parse.root(SRC, "lua")
        ts_parse.scoped(function()
          ts_parse.root(SRC, "lua")
        end)
        ok(ts_parse.active(), "the inner scope leaves the outer one open")
        ts_parse.root(SRC, "lua")
      end)
    end)
    eq(n, 1, "the inner scope reuses the outer cache")
    ok(not ts_parse.active())
  end

  -- A stage that throws closes the scope and its error arrives unchanged.
  do
    local okc, err = pcall(ts_parse.scoped, function()
      ts_parse.root(SRC, "lua")
      error("docmap: boom", 0)
    end)
    ok(not okc)
    eq(err, "docmap: boom", "the error passes through as raised")
    ok(not ts_parse.active(), "an error does not leave the cache open")
  end

  -- `scan_full` is the scope: the trees die with the scan.
  do
    local root = vim.fn.tempname()
    H.write(root .. "/lua/x/init.lua", { "---@module 'x'", "--- X.", "local M = {}", "return M" })
    local seen_active = false
    local orig = ts_parse.root
    ---@diagnostic disable-next-line: duplicate-set-field
    ts_parse.root = function(...)
      seen_active = seen_active or ts_parse.active()
      return orig(...)
    end
    local okc, err = pcall(require("docmap").scan_full, { root = root, luals = false })
    ts_parse.root = orig
    ok(okc, tostring(err))
    ok(seen_active, "scan_full parses inside a ts_parse scope")
    ok(not ts_parse.active(), "and closes it when it returns")
  end
end
