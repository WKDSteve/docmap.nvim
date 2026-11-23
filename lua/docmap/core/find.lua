---@module 'docmap.core.find'
--- Resolve a user-typed name to a node id.
---
--- One function, in its own file, and the reason is the layering rule rather
--- than tidiness. This lived on `command.lua` — the editor half — while
--- `tagfiles.lua` reached across for it, which made the core depend on the
--- editor for a lookup that touches nothing but the IR. The
--- `docmap.core` → `docmap.editor` layer rule found it the
--- moment it was declared, which is the entire point of declaring it.

local M = {}

---Three ways, in order of how specific they are: a declared `@module` path, a
---raw node id, and — for a **namespace**, a directory with no `init.lua` and
---therefore no `@module` at all — the module path its location implies. That
---last one is not a nicety: `lua/lib/nvim/fs` is a namespace, so
---`:DocMap graph deps lib.nvim.fs` found nothing until it was added, and
---namespaces are precisely the aggregation points a dependency graph is
---interesting at.
---@param ir Docmap.IR
---@param name string
---@param lua_root string
---@return string? node_id
function M.node(ir, name, lua_root)
  local check = require("docmap.core.check")
  local fallback
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module == name or id == name then
      return id
    end
    if not fallback and not node.module then
      if check.expected_module(node.path .. "/init.lua", lua_root) == name then
        fallback = id
      end
    end
  end
  return fallback
end

---`file:line`, `file:first-last` or a bare file → file, first, last. A Windows drive colon (`C:/x.lua:3`) is
---not a line separator: only a trailing `:<digits>[-<digits>]` is.
---@param spec string
---@return string file
---@return integer? first
---@return integer? last
function M.parse_position(spec)
  local file, first, last = spec:match("^(.-):(%d+)%-(%d+)$")
  if file then
    return file, tonumber(first), tonumber(last)
  end
  file, first = spec:match("^(.-):(%d+)$")
  if file then
    return file, tonumber(first), nil
  end
  return spec, nil, nil
end

---@class Docmap.FindHit
---@field id string Node id (the module, or the file node, that owns the position).
---@field kind "function"|"module"
---@field fn? Docmap.FunctionInfo The innermost function that holds the position; set when `kind` is "function".
---@field key? string `<node id>#<function name>`, the key the page and the marks use for a function.

---A repository-relative, forward-slash path: what `node.source` holds.
---@param file string
---@param root? string
---@return string
local function relative(file, root)
  local f = file:gsub("\\", "/"):gsub("^%./", "")
  if root then
    local r = root:gsub("\\", "/"):gsub("/+$", "")
    if f:sub(1, #r + 1):lower() == (r .. "/"):lower() then
      f = f:sub(#r + 2)
    end
  end
  return f
end

---The function of `node` that holds `first`..`last`: the innermost one that covers `first`, else the one that
---overlaps the range most. A function's span is `line`..`line_end` (1-based, inclusive).
---@param node Docmap.Node
---@param first integer
---@param last integer
---@return Docmap.FunctionInfo?
local function function_at(node, first, last)
  local best, best_span
  for _, fn in ipairs(node.functions or {}) do
    local top, bottom = fn.line, fn.line_end or fn.line
    if top <= first and first <= bottom then
      local span = bottom - top
      if not best_span or span < best_span then
        best, best_span = fn, span
      end
    end
  end
  if best then
    return best
  end
  local most = 0
  for _, fn in ipairs(node.functions or {}) do
    local top, bottom = fn.line, fn.line_end or fn.line
    local overlap = math.min(bottom, last) - math.max(top, first) + 1
    if overlap > most then
      best, most = fn, overlap
    end
  end
  return best
end

---Which node a position in a file belongs to: the innermost function that holds the line, else the module (the node
---that owns the file), else nil — a file the map does not know.
---
---With `last` the position is a range (a visual selection): the function holding `line` wins, else the function the
---range overlaps most, else the module.
---
---Reads the IR only: a build without function data (the Neovim-free standalone) answers with the module.
---@param ir Docmap.IR
---@param file string Repository-relative or absolute (then `root` strips the project prefix).
---@param line integer 1-based.
---@param last? integer 1-based end of a range.
---@param root? string
---@return Docmap.FindHit?
function M.at(ir, file, line, last, root)
  local want = relative(file, root)
  local found
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.source and node.source:gsub("\\", "/") == want then
      found = node
      break
    end
  end
  if not found then
    return nil
  end
  local first = math.min(line, last or line)
  local fn = function_at(found, first, math.max(line, last or line))
  if fn then
    return { id = found.id, kind = "function", fn = fn, key = found.id .. "#" .. fn.name }
  end
  return { id = found.id, kind = "module" }
end

---Percent-encode like the page's `encodeURIComponent`, which decodes the fragment.
---@param s string
---@return string
local function encode(s)
  return (s:gsub("[^%w%-_%.!~%*'%(%)]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

---The fragment that opens the page at `hit`: the tree, the node, and — for a function — its key.
---@param hit Docmap.FindHit
---@return string fragment With the leading "#".
function M.fragment(hit)
  local out = "#tab=tree&id=" .. encode(hit.id)
  if hit.key then
    out = out .. "&fn=" .. encode(hit.key)
  end
  return out
end

return M
