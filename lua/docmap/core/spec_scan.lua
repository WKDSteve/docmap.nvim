---@module 'docmap.core.spec_scan'
--- One read and one parse per spec file per scan, for both stages that ask.
---
--- `coverage.resolve` wants every identifier a spec mentions; `check`'s
--- test-reference pass wants the require bindings and `alias.field` accesses.
--- They used to read and parse each spec separately (lib.nvim: 276 files,
--- ~0.4 s twice). This reads a file once, runs both query sets over the one
--- tree, and keeps the *facts* (name sets, a few small tables), never the
--- tree, for the rest of the scan (`ts_parse.memo`), so the peak memory the
--- `ts_parse` header measured does not move. Outside a scan scope nothing is
--- kept and each call recomputes.

local M = {}

local IDENT_QUERY = vim.treesitter.query.parse("lua", "(identifier) @id")

--- What one spec file has to say; see `check.lua` for why these shapes.
--- `@bind` is only counted: a name bound twice in a file is not reasoned about.
local TEST_QUERY = vim.treesitter.query.parse(
  "lua",
  [[
  (variable_declaration (assignment_statement (variable_list (identifier) @bind)))
  (parameters (identifier) @bind)

  (variable_declaration
    (assignment_statement
      (variable_list (identifier) @alias)
      (expression_list
        (function_call
          name: (identifier) @req (#eq? @req "require")
          arguments: (arguments (string) @module)))))

  (dot_index_expression table: (identifier) @tbl field: (identifier) @field)
]]
)

---@class Docmap.SpecFacts
---@field names table<string, boolean> Every identifier mentioned.
---@field bound table<string, integer> Times each name is bound in the file.
---@field module_of table<string, string> `local alias = require("module")`.
---@field members { alias: string, field: string, row: integer }[] `alias.field` accesses, 0-based row.

---First node of a capture, across both `iter_matches` shapes.
---@param match table
---@param id integer?
---@return TSNode?
local function first(match, id)
  local v = id and match[id]
  if not v then
    return nil
  end
  return type(v) == "table" and v[1] or v
end

---@param src string
---@return Docmap.SpecFacts
local function parse(src)
  local facts = { names = {}, bound = {}, module_of = {}, members = {} }
  local root = require("docmap.core.ts_parse").root(src, "lua")
  if not root then
    return facts
  end

  for id, node in IDENT_QUERY:iter_captures(root, src) do
    if IDENT_QUERY.captures[id] == "id" then
      facts.names[vim.treesitter.get_node_text(node, src)] = true
    end
  end

  local cap = {}
  for id, name in ipairs(TEST_QUERY.captures) do
    cap[name] = id
  end
  for _, match in TEST_QUERY:iter_matches(root, src) do
    local bind_node = first(match, cap.bind)
    if bind_node then
      local name = vim.treesitter.get_node_text(bind_node, src)
      facts.bound[name] = (facts.bound[name] or 0) + 1
    end

    local alias_node = first(match, cap.alias)
    local module_node = first(match, cap.module)
    if alias_node and module_node then
      local alias = vim.treesitter.get_node_text(alias_node, src)
      local module = vim.treesitter.get_node_text(module_node, src)
      facts.module_of[alias] = (module:gsub("^['\"]", ""):gsub("['\"]$", ""))
    end

    local tbl_node = first(match, cap.tbl)
    local field_node = first(match, cap.field)
    if tbl_node and field_node then
      facts.members[#facts.members + 1] = {
        alias = vim.treesitter.get_node_text(tbl_node, src),
        field = vim.treesitter.get_node_text(field_node, src),
        row = select(1, tbl_node:range()),
      }
    end
  end
  return facts
end

---The facts of the spec file at `path`, or `nil` when it cannot be read.
---@param path string
---@return Docmap.SpecFacts?
function M.facts(path)
  local memo = require("docmap.core.ts_parse").memo("spec_scan")
  local hit = memo and memo[path]
  if hit then
    return hit
  end

  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local src = fd:read("*a")
  fd:close()

  local facts = parse(src)
  if memo then
    memo[path] = facts
  end
  return facts
end

return M
