-- Test code: a nil from a fixture read must crash and name itself.
---@diagnostic disable: need-check-nil
-- TESTS/docs_members_spec.lua — `doc-references-missing` and what is not a function.
--
-- A document names `demo.LIMIT` (an exported constant) and `demo.timeout_ms` (a config option, declared only as
-- a `---@field` of the options class). Neither is a function, so the function index cannot hold them, and both
-- were reported as "module `demo` has no member". Measured over the fleet before: about 90 of 150 findings.
-- A name nothing declares must still be reported.

return function(H)
  local eq = H.eq
  local docs = require("docmap.core.docs")

  local root = H.tmpfile("_docs_members")
  local function write(rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docs-members spec: fixture must be writable")
    fd:write(table.concat(lines, "\n") .. "\n")
    fd:close()
  end

  write("lua/demo/init.lua", {
    "local M = {}",
    "M.LIMIT = 10",
    "local hidden = 3",
    "function M.setup() end",
    "return M",
  })
  write("lua/demo/@types.lua", {
    "---@class Demo.Config",
    "---@field timeout_ms integer Timeout",
    "---@field retries? integer",
    "---@field private secret string",
  })

  local ir = {
    order = { "n/demo" },
    nodes = {
      ["n/demo"] = {
        id = "n/demo",
        module = "demo",
        source = "lua/demo/init.lua",
        functions = { { name = "M.setup" } },
        symbols = {
          { name = "M.LIMIT", kind = "constant" },
          { name = "hidden", kind = "constant" },
        },
      },
    },
  }

  local idx = docs.build_index(ir)
  docs.index_fields(idx, ir, root)

  eq(
    docs.missing_member(idx, "demo.LIMIT"),
    nil,
    "docs-members: an exported `M.X = value` constant resolves"
  )
  local mod, miss = docs.missing_member(idx, "demo.hidden")
  eq(mod, "demo", "docs-members: a file-local binding is not part of the module's surface")
  eq(miss, "hidden", "docs-members: ... and is reported by name")
  eq(
    docs.missing_member(idx, "demo.timeout_ms"),
    nil,
    "docs-members: a `---@field` name is a config key, not a function"
  )
  eq(
    docs.missing_member(idx, "demo.retries"),
    nil,
    "docs-members: an optional `---@field name?` too"
  )
  eq(
    docs.missing_member(idx, "demo.secret"),
    nil,
    "docs-members: a visibility keyword before the field name is skipped"
  )
  eq(docs.missing_member(idx, "demo.setup"), nil, "docs-members: a function still resolves")
  local m2, miss2 = docs.missing_member(idx, "demo.gone")
  eq(m2, "demo", "docs-members: a name nothing declares is still reported")
  eq(miss2, "gone", "docs-members: ... by name")
  eq(
    idx.fields.integer,
    nil,
    "docs-members: the type after the field name is not taken for the name"
  )
end
