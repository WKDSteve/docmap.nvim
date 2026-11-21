-- TESTS/spec_scan_spec.lua -- `docmap.core.spec_scan`
--
-- `coverage.resolve` and `check`'s test-reference pass both read each spec
-- file; inside a scan scope the second one must get the facts of the first
-- without a read or a parse, and nothing may outlive the scope.

return function(H)
  local eq, ok = H.eq, H.ok
  local spec_scan = require("docmap.core.spec_scan")
  local ts_parse = require("docmap.core.ts_parse")

  local path = H.tmpfile("_spec_scan.lua")
  local fd = assert(io.open(path, "w"))
  fd:write('local m = require("a.b")\nreturn function() return m.run, other end\n')
  fd:close()

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

  local f = assert(spec_scan.facts(path))
  ok(f.names.other and f.names.run, "identifiers are collected")
  eq(f.module_of.m, "a.b", "the require binding is resolved")
  eq(f.bound.m, 1)
  eq(#f.members, 1)
  eq(f.members[1].field, "run")
  eq(f.members[1].row, 1)

  eq(spec_scan.facts(path .. ".missing"), nil, "an unreadable file has no facts")

  eq(
    parses_during(function()
      spec_scan.facts(path)
      spec_scan.facts(path)
    end),
    2,
    "outside a scope every call parses"
  )

  local a, b
  eq(
    parses_during(function()
      ts_parse.scoped(function()
        a = spec_scan.facts(path)
        b = spec_scan.facts(path)
      end)
    end),
    1,
    "inside a scope the file is parsed once"
  )
  ok(a == b, "the second ask gets the same facts")
  eq(ts_parse.memo("spec_scan"), nil, "the memo is gone with the scope")
end
