-- Test code: a nil from a fixture read must crash and name itself.
---@diagnostic disable: need-check-nil
-- TESTS/check_test_files_summary_spec.lua — `missing-summary` leaves test files alone.
--
-- A test says what it is in its name and its suite title; 430 of the fleet's 700 `missing-summary` findings were
-- `*.test.ts`, `e2e/` and `test_*.py` files that open with `import`. The exemption is by path convention only:
-- a source file beside them with no header still gets the finding.

return function(H)
  local eq = H.eq
  local check = require("docmap.core.check")

  for _, p in ipairs({
    "src/a.test.ts",
    "src/lib/x.spec.js",
    "ui/e2e/login.ts",
    "tools/test_scan.py",
    "pkg/scan_test.go",
    "src/__tests__/a.ts",
    "crate/tests/api.rs",
    "srcwin.test.ts",
    "crates/sink/src/tests.rs",
  }) do
    eq(check.is_test_path(p), true, "test path: " .. p .. " is a test file")
  end
  for _, p in ipairs({
    "src/a.ts",
    "src/contest.ts",
    "src/latest/a.ts",
    "tools/scan.py",
    "src/testing.ts",
    "",
  }) do
    eq(check.is_test_path(p), false, "test path: '" .. p .. "' is not a test file")
  end
  eq(check.is_test_path(nil), false, "test path: nil is not a test file")

  local root = H.tmpfile("_test_files_summary")
  local function write(rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "fixture must be writable")
    fd:write(table.concat(lines, "\n") .. "\n")
    fd:close()
  end
  write("src/plain.ts", { "export function plain(): number {", "  return 1", "}" })
  write("src/plain.test.ts", { 'import { plain } from "./plain"', "test('plain', () => plain())" })

  local opts = require("docmap.config").build(root, { source = "src", out_dir = "docs/map" }, {
    warn = function() end,
  })
  local _, findings = require("docmap").scan_full(opts)
  local files = {}
  for _, f in ipairs(findings) do
    if f.code == "missing-summary" or f.check == "missing-summary" then
      files[#files + 1] = tostring((f.data or f).file or f.node)
    end
  end
  table.sort(files)
  eq(#files, 1, "test files: exactly one missing-summary (" .. table.concat(files, ",") .. ")")
  local ok = files[1] and files[1]:find("plain.ts", 1, true) ~= nil
  eq(
    ok and not files[1]:find("test", 1, true),
    true,
    "test files: the finding is for the plain source, not the test"
  )
end
