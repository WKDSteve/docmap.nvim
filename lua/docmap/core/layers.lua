---@module 'docmap.core.layers'
--- The layering rules of `opts.layers`, read two ways: as a test of one
--- require edge (`crossing`, what the `layer-violation` check asks) and as a
--- picture of the whole tree (`map`, what the Layers view of the page draws).
---
--- Both live here so they cannot disagree: the view marks an edge red with the
--- same function that makes the check report it.
---
--- ## How bands come out of rules that are pairs
---
--- A rule is not "these are the layers, in this order". It is one forbidden
--- direction: modules under `from` may not require modules under `to` (or, in
--- the sibling form, no direct child of a prefix may require another). A
--- picture in bands needs an order, so it is derived:
---
---   * every prefix a rule names is a **layer**; a module belongs to the layer
---     with the longest prefix it sits under, which is the reading the check
---     has (`from = "a"`, `to = "a.b"` means "a, outside a.b");
---   * `from` may not reach `to` puts `from` **below** `to`: the forbidden
---     direction is up, so what may be depended on is drawn underneath;
---   * the band of a layer is the longest chain of such steps below it.
---
--- Rules need not form an order. `a` may not reach `b` and `b` may not reach
--- `a` is a sensible pair of rules (two halves that must not know each other)
--- and has no above and below. Layers that forbid each other in a circle are
--- therefore put in **one band, side by side**, and reported in `loops`, so
--- the view can say that no order holds among them. That makes the picture
--- total: every rule set has one, and the part of it that is no order is
--- named instead of guessed.
---
--- The sibling form adds no order either: its prefix is one layer, flagged
--- `siblings`, whose members may not reach each other.

local M = {}

---Prefix match on module-path segments, not raw string prefix: `lib.vim`
---must match `lib.vim.buffer` and never `lib.vimx`.
---@param module string
---@param prefix string
---@return boolean
function M.under(module, prefix)
  return module == prefix or module:sub(1, #prefix + 1) == prefix .. "."
end

---The direct child of `prefix` that `module` sits in (`prefix.x` for
---`prefix.x.y`), or nil when `module` is not strictly below `prefix`.
---@param module string
---@param prefix string
---@return string?
function M.child_of(module, prefix)
  if module == prefix or not M.under(module, prefix) then
    return nil
  end
  local seg = module:sub(#prefix + 2):match("^[^.]+")
  return seg and (prefix .. "." .. seg) or nil
end

---Whether `module` is one of the rule's explicitly shared targets.
---@param module string
---@param rule Docmap.LayerRule
---@return boolean
function M.allowed(module, rule)
  for _, prefix in ipairs(rule.allow or {}) do
    if M.under(module, prefix) then
      return true
    end
  end
  return false
end

---Which two layers an edge crosses under `rule`, or nil when it does not
---break the rule. Two forms share one finding: the pair form (`from`/`to`,
---one prefix may not reach another) and the sibling form (`siblings`: no
---direct child of the prefix may reach another direct child). The sibling
---form exists because "no backend requires another" over 23 backends would
---otherwise be 23 x 22 hand-written pairs that go stale with every backend.
---@param src string Module path of the requiring side.
---@param dst string Module path of the required side.
---@param rule Docmap.LayerRule
---@return string? from_layer
---@return string? to_layer
function M.crossing(src, dst, rule)
  if M.allowed(dst, rule) then
    return nil
  end
  if rule.siblings then
    local a, b = M.child_of(src, rule.siblings), M.child_of(dst, rule.siblings)
    if a and b and a ~= b then
      return a, b
    end
    return nil
  end
  if not (rule.from and rule.to) then
    return nil
  end
  -- `from` must be outside `rule.to`'s own scope, not just inside
  -- `rule.from`'s — otherwise a rule like `{from="docmap.core",
  -- to="docmap.core.lang"}` also fires on `core.lang.js`
  -- requiring `core.lang.ecma`: both modules sit trivially "under"
  -- `docmap.core` by prefix, so without this exclusion every
  -- intra-`core.lang` require would be misread as the very
  -- core-into-lang boundary crossing the rule exists to catch, not
  -- an edge that stays inside `core.lang` the whole way.
  if M.under(src, rule.from) and not M.under(src, rule.to) and M.under(dst, rule.to) then
    return rule.from, rule.to
  end
  return nil
end

---The keys of a table, sorted. Written out because this module runs under
---`standalone/vim_shim.lua` too, which has no `vim.tbl_keys`.
---@param t table<string, any>
---@return string[]
local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

---The strongly connected components of a small directed graph, each sorted,
---in a stable order (Tarjan, over sorted ids).
---@param ids string[] Sorted node ids.
---@param out table<string, string[]> Sorted successor lists.
---@return string[][]
local function components(ids, out)
  local index, low, on_stack, stack, n, result = {}, {}, {}, {}, 0, {}
  local function visit(v)
    n = n + 1
    index[v], low[v] = n, n
    stack[#stack + 1] = v
    on_stack[v] = true
    for _, w in ipairs(out[v] or {}) do
      if not index[w] then
        visit(w)
        low[v] = math.min(low[v], low[w])
      elseif on_stack[w] then
        low[v] = math.min(low[v], index[w])
      end
    end
    if low[v] == index[v] then
      local comp = {}
      repeat
        local w = table.remove(stack)
        on_stack[w] = nil
        comp[#comp + 1] = w
      until w == v
      table.sort(comp)
      result[#result + 1] = comp
    end
  end
  for _, v in ipairs(ids) do
    if not index[v] then
      visit(v)
    end
  end
  return result
end

---One layer of the picture.
---@class Docmap.LayerUnit
---@field id string The module prefix the rules name.
---@field band integer 0 is the lowest band: what the others may depend on.
---@field siblings boolean True when a sibling rule forbids its direct children to reach each other.
---@field modules string[] Node ids of the modules in it, in the order of the map.

---One require that breaks a rule.
---@class Docmap.LayerViolation
---@field from string Node id of the requiring module.
---@field to string Node id of the required module.
---@field from_layer string
---@field to_layer string
---@field rule integer Index into `rules`.
---@field line integer? Line of the require.

---The tree as bands, for the Layers view.
---@class Docmap.LayerMap
---@field rules Docmap.LayerRule[] The rules as declared.
---@field units Docmap.LayerUnit[] Sorted by band, then id.
---@field bands integer How many bands there are.
---@field unassigned string[] Node ids of the modules no rule names.
---@field shared string[] Node ids of the modules a rule's `allow` exempts as a target.
---@field loops string[][] Groups of layers that forbid each other in a circle: no order holds among them.
---@field violations Docmap.LayerViolation[] In the order of the require edges.

---The tree laid out in the bands the rules imply, or nil when no rule is
---declared (a layering nobody stated has no picture).
---@param ir Docmap.IR
---@param rules Docmap.LayerRule[]?
---@return Docmap.LayerMap?
function M.map(ir, rules)
  rules = rules or {}
  if #rules == 0 then
    return nil
  end

  -- The layers: every prefix a rule names.
  local unit_by_id = {}
  local function unit(prefix)
    if type(prefix) ~= "string" or prefix == "" then
      return nil
    end
    local u = unit_by_id[prefix]
    if not u then
      u = { id = prefix, band = 0, siblings = false, modules = {} }
      unit_by_id[prefix] = u
    end
    return u
  end
  local below = {} -- below[a][b]: a rule forbids a to reach b, so a sits below b
  for _, rule in ipairs(rules) do
    if rule.siblings then
      local u = unit(rule.siblings)
      if u then
        u.siblings = true
      end
    elseif rule.from and rule.to then
      local a, b = unit(rule.from), unit(rule.to)
      if a and b and a ~= b then
        below[a.id] = below[a.id] or {}
        below[a.id][b.id] = true
      end
    end
  end
  local ids = sorted_keys(unit_by_id)
  if #ids == 0 then
    return nil
  end

  -- The order, where there is one. Layers that forbid each other in a circle
  -- collapse into one component; the components form a chain-free graph, and
  -- a band is the longest way up to a component from the bottom.
  local out = {}
  for _, a in ipairs(ids) do
    out[a] = sorted_keys(below[a] or {})
  end
  local comps = components(ids, out)
  local comp_of = {}
  for i, comp in ipairs(comps) do
    for _, id in ipairs(comp) do
      comp_of[id] = i
    end
  end
  local band_of_comp = {}
  local function band(i)
    if band_of_comp[i] then
      return band_of_comp[i]
    end
    band_of_comp[i] = 0 -- a component never reaches itself again, so this is only a start value
    local best = 0
    for _, b in ipairs(comps[i]) do
      -- everything that sits below `b` pushes this component one band up
      for _, a in ipairs(ids) do
        if below[a] and below[a][b] and comp_of[a] ~= i then
          best = math.max(best, band(comp_of[a]) + 1)
        end
      end
    end
    band_of_comp[i] = best
    return best
  end
  local loops, bands = {}, 0
  for i, comp in ipairs(comps) do
    local n = band(i)
    bands = math.max(bands, n + 1)
    for _, id in ipairs(comp) do
      unit_by_id[id].band = n
    end
    if #comp > 1 then
      loops[#loops + 1] = comp
    end
  end
  table.sort(loops, function(a, b)
    return a[1] < b[1]
  end)

  -- Every module goes to the layer with the longest prefix it sits under.
  local by_length = {}
  for i, prefix in ipairs(ids) do
    by_length[i] = prefix
  end
  table.sort(by_length, function(a, b)
    if #a ~= #b then
      return #a > #b
    end
    return a < b
  end)
  local unassigned, shared = {}, {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.kind ~= "namespace" then
      local home
      for _, prefix in ipairs(by_length) do
        if M.under(node.module, prefix) then
          home = unit_by_id[prefix]
          break
        end
      end
      if home then
        home.modules[#home.modules + 1] = id
      else
        unassigned[#unassigned + 1] = id
      end
      for _, rule in ipairs(rules) do
        if M.allowed(node.module, rule) then
          shared[#shared + 1] = id
          break
        end
      end
    end
  end

  local violations = {}
  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" then
      local from, to = ir.nodes[edge.from], ir.nodes[edge.to]
      if from and to and from.module and to.module then
        for i, rule in ipairs(rules) do
          local from_layer, to_layer = M.crossing(from.module, to.module, rule)
          if from_layer then
            violations[#violations + 1] = {
              from = edge.from,
              to = edge.to,
              from_layer = from_layer,
              to_layer = to_layer,
              rule = i,
              line = edge.line,
            }
          end
        end
      end
    end
  end

  local units = {}
  for _, id in ipairs(ids) do
    units[#units + 1] = unit_by_id[id]
  end
  table.sort(units, function(a, b)
    if a.band ~= b.band then
      return a.band < b.band
    end
    return a.id < b.id
  end)

  local declared = {}
  for i, rule in ipairs(rules) do
    declared[i] = {
      from = rule.from,
      to = rule.to,
      siblings = rule.siblings,
      allow = rule.allow,
      why = rule.why,
    }
  end

  return {
    rules = declared,
    units = units,
    bands = bands,
    unassigned = unassigned,
    shared = shared,
    loops = loops,
    violations = violations,
  }
end

return M
