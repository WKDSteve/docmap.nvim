---@module 'docmap.core.ts_parse'
--- Hand the second stage that asks for the same source's tree the one the
--- first stage just parsed.
---
--- **Measured, not guessed.** Profiling `generate` over lib.nvim (497
--- modules, 276 spec files) counted 1484 `parser:parse()` calls for 742
--- distinct sources: every module was parsed by `functions.scan_file` and
--- again, right after, by `markers.scan_source`; every spec file by
--- `coverage.resolve` and again, a stage later, by `check`'s test-reference
--- pass. About 1.6 s of a 10 s run, half of it repeated work.
---
--- **One tree per grammar, not all of them.** Keeping every tree until the
--- scan ends removed both repeats (-30% on lib.nvim) and raised the peak
--- working set from 137 MB to 237 MB. The functions/markers pair asks back
--- to back, so remembering the last source alone catches it at no memory
--- cost (129 MB, -20%). The coverage/check pair is a stage apart and is not
--- caught by the tree memory; `core/spec_scan` shares that one by keeping
--- what both stages read from a spec file (a few name sets, no tree) in
--- `M.memo`.
---
--- The memory only exists inside `scoped()`, which `scan_full` wraps around
--- itself. Outside a scope every call parses afresh and keeps nothing, and
--- the last tree is dropped when the scope ends, also when a stage throws.
---
--- Compared by the source *string*, not by path: two reads of one file give
--- two equal strings, and a stage that rewrote the source before parsing
--- must not be handed the tree of the original. LuaJIT interns strings, so
--- the comparison is a pointer compare.

local M = {}

---Per grammar, the last source parsed and its tree (`false`: the parse failed).
---@type table<string, { src: string, tree: TSTree|false }>?
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
  local last = cache and cache[grammar]
  if last and last.src == src then
    return last.tree and last.tree:root() or nil
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
    cache[grammar] = { src = src, tree = tree }
  end
  return tree and tree:root() or nil
end

---Per scan, a bag for results derived from sources (not trees): what
---`core/spec_scan` keeps per spec file. `nil` outside a scope, so a caller
---outside one recomputes and keeps nothing, like `M.root`.
---@type table<string, table>?
local memos = nil

---The memo table named `name` of the open scope, created on first use; `nil`
---outside a scope. Released with the scope, errors included.
---@param name string
---@return table?
function M.memo(name)
  if not memos then
    return nil
  end
  memos[name] = memos[name] or {}
  return memos[name]
end

---Run `fn` with the memory on; drop the remembered trees when the outermost
---scope ends. Nested scopes share the outer cache. Errors pass through
---unchanged (level 0), after the cache is released. `fn` hands its results
---out through upvalues, which keeps a multi-value caller like `scan_full`
---free of pack/unpack.
---@param fn fun()
function M.scoped(fn)
  depth = depth + 1
  if depth == 1 then
    cache = {}
    memos = {}
  end
  local ok, err = pcall(fn)
  depth = depth - 1
  if depth == 0 then
    cache = nil
    memos = nil
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
