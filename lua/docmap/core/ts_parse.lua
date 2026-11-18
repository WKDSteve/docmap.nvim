---@module 'docmap.core.ts_parse'
--- Parse a source string once per scan, however many stages ask for its tree.
---
--- **Measured, not guessed.** Profiling `generate` over lib.nvim (497
--- modules, 276 spec files) counted 1484 `parser:parse()` calls for 742
--- distinct sources: every module was parsed by `functions.scan_file` and
--- again by `markers.scan_source`, every spec file by `coverage.resolve`
--- and again by `check`'s test-reference pass. About 1.6 s of a 10 s run,
--- half of it repeated work.
---
--- The cache only lives inside `scoped()`, which `scan_full` wraps around
--- itself. Outside a scope every call parses afresh and keeps nothing, so a
--- caller that scans one file (a spec, `install()`'s single-file path, the
--- LSP-free hover) holds no trees it will never ask for again, and nothing
--- outlives the scan that filled it: the trees are dropped when the scope
--- ends, also when a stage throws.
---
--- Keyed by the source *string*, not by path: two reads of one file give two
--- equal strings, and a stage that rewrote the source before parsing must not
--- be handed the tree of the original. LuaJIT interns strings, so the lookup
--- costs a hash probe, not a byte compare.

local M = {}

---@type table<string, table<string, TSTree|false>>?
local cache = nil
local depth = 0

---Parse `src` with `grammar` and return the root, or `nil` when the grammar
---is missing or the parse fails -- the same quiet `nil` every caller used to
---produce on its own, since a file treesitter cannot read still has text
---that the rest of the scan uses.
---@param src string
---@param grammar string
---@return TSNode?
function M.root(src, grammar)
  local by_src = cache and cache[grammar]
  if by_src then
    local hit = by_src[src]
    if hit ~= nil then
      return hit and hit:root() or nil
    end
  end

  local tree = false
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, grammar)
  -- `not parser` is for the type rather than the runtime: `pcall` hands back
  -- the error message as its second value.
  if ok and parser then
    local ok_parse, trees = pcall(function()
      return parser:parse()
    end)
    if ok_parse and trees and trees[1] then
      tree = trees[1]
    end
  end

  if cache then
    cache[grammar] = cache[grammar] or {}
    cache[grammar][src] = tree
  end
  return tree and tree:root() or nil
end

---Run `fn` with the cache on; drop every cached tree when the outermost
---scope ends. Nested scopes share the outer cache. Errors pass through
---unchanged (level 0), after the cache is released. `fn` hands its results
---out through upvalues, which keeps a multi-value caller like `scan_full`
---free of pack/unpack.
---@param fn fun()
function M.scoped(fn)
  depth = depth + 1
  if depth == 1 then
    cache = {}
  end
  local ok, err = pcall(fn)
  depth = depth - 1
  if depth == 0 then
    cache = nil
  end
  if not ok then
    error(err, 0)
  end
end

---Whether a scope is open. For specs.
---@return boolean
function M.active()
  return cache ~= nil
end

return M
