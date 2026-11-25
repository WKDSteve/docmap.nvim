-- scripts/manifest_rules.lua -- what a measured manifest must hold, whatever the probes reached.
-- Plain Lua, read by scripts/bundle_manifest.lua (PUC Lua, no Neovim) and by its spec.

local M = {}

-- A module no probe reaches that another one needs at run time: `rules.settings` requires
-- `rules.env` lazily, only with `$RULES_TRUST` set, so a build without it would not measure it.
M.COMPANIONS = {
  { module = "rules.settings", needs = "rules.env" },
}

-- The module a route probe exists to measure. A probe that ends before it (the route answers
-- `available = false`, say because the probe asked for a map that is not committed) leaves the
-- module out of the manifest without an error, and the binary then dies with "module not found"
-- on the first real request. Found that way for `shape/<sha>` and `docmap.core.diff`.
M.ROUTE_MODULES = {
  { route = "commit/", needs = "docmap.core.history" },
  { route = "shape/", needs = "docmap.core.diff" },
  -- not a route but a mode of the entry point (`docmap --fleet <root>...`), probed the same way
  { route = "--fleet", needs = "docmap.core.fleet", probe = "--fleet" },
}

---The modules a manifest lacks.
---@param names table<string, boolean> the module names of the manifest
---@param routes? string[] the `--api=` routes the build probed (`shape/<sha>`, ...)
---@return string[] missing one line per module, saying which module or route asks for it
function M.missing(names, routes)
  local out = {}
  for _, rule in ipairs(M.COMPANIONS) do
    if names[rule.module] and not names[rule.needs] then
      out[#out + 1] = rule.needs .. " (needed by " .. rule.module .. ")"
    end
  end
  for _, route in ipairs(routes or {}) do
    for _, rule in ipairs(M.ROUTE_MODULES) do
      if route:sub(1, #rule.route) == rule.route and not names[rule.needs] then
        local probe = rule.probe or ("--api=" .. route)
        out[#out + 1] = rule.needs .. " (the probe of " .. probe .. " did not load it)"
      end
    end
  end
  return out
end

return M
