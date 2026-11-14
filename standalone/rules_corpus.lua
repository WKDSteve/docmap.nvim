---@module 'standalone.rules_corpus'
--- What the optional real-corpus case of `scripts/ci.lua`'s `standalone` gate needs, as pure functions.
---
--- The fixture cases of that gate compare a dozen rules between Neovim and the standalone build and print both
--- answers when they differ. Over a real vault (several hundred rules, a catalog of half a megabyte) that print is
--- useless, and "every rule of every family" has to be written as a selection first. Both live here, with no
--- `vim.*`, so `TESTS/rules_corpus_spec.lua` can show that a divergence is found: the gate itself only runs on a
--- machine with a PUC Lua, its rocks and a vault.

local M = {}

---The selection that names every rule of a `rules/catalog` answer: its families, sorted, comma-separated.
---
---Families, not ids: `rules/run` refuses a selection of more than 64 KiB or 4096 items, and a vault has more rules
---than that long before it has that many families.
---@param catalog table A `rules/catalog` answer.
---@return string|nil selection nil when the catalog lists no rule with a family.
function M.selection(catalog)
  local seen, families = {}, {}
  for _, rule in ipairs(type(catalog) == "table" and catalog.rules or {}) do
    local family = type(rule) == "table" and rule.family or nil
    if type(family) == "string" and family ~= "" and not seen[family] then
      seen[family] = true
      families[#families + 1] = family
    end
  end
  if #families == 0 then
    return nil
  end
  table.sort(families)
  return table.concat(families, ",")
end

---A short, printable form of a leaf value.
---@param v any
---@return string
local function shown(v)
  if type(v) == "string" then
    local text = ("%q"):format(v)
    if #text > 160 then
      text = text:sub(1, 160) .. "..."
    end
    return text
  end
  if type(v) == "table" then
    return "a table"
  end
  return tostring(v)
end

---The keys of a table in a fixed order: numbers first, then the rest by their text.
---@param t table
---@return any[]
local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    local na, nb = type(a) == "number", type(b) == "number"
    if na ~= nb then
      return na
    end
    if na then
      return a < b
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

---The label of one step of the path: a rule or result is named by its id, not by its position.
---@param key any
---@param value any
---@return string
local function step(key, value)
  if type(key) == "number" then
    local id = type(value) == "table" and value.id or nil
    if type(id) == "string" then
      return ("[%d %s]"):format(key, id)
    end
    return ("[%d]"):format(key)
  end
  return "." .. tostring(key)
end

---The first place two answers differ, or nil when they are the same.
---
---Depth first in a fixed key order, so the same pair names the same place on every run.
---@param a any The answer of one host.
---@param b any The answer of the other.
---@param path string|nil Where `a` and `b` sit (for the recursion).
---@return string|nil difference `<path>: <a> ~= <b>`
function M.first_difference(a, b, path)
  path = path or "answer"
  if type(a) ~= "table" or type(b) ~= "table" then
    if a == b then
      return nil
    end
    return ("%s: %s ~= %s"):format(path, shown(a), shown(b))
  end
  local keys, seen = sorted_keys(a), {}
  for _, k in ipairs(keys) do
    seen[k] = true
  end
  for _, k in ipairs(sorted_keys(b)) do
    if not seen[k] then
      keys[#keys + 1] = k
    end
  end
  for _, k in ipairs(keys) do
    local av, bv = a[k], b[k]
    local diff = M.first_difference(av, bv, path .. step(k, av ~= nil and av or bv))
    if diff then
      return diff
    end
  end
  return nil
end

return M
