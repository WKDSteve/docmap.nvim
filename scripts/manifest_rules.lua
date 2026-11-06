-- scripts/manifest_rules.lua -- what a measured manifest must hold, whatever the probes reached.
-- Plain Lua, read by scripts/bundle_manifest.lua (PUC Lua, no Neovim) and by its spec.

local M = {}

-- A module no probe reaches that another one needs at run time: `rules.settings` requires
-- `rules.env` lazily, only with `$RULES_TRUST` set, so a build without it would not measure it.
M.COMPANIONS = {
  { module = "rules.settings", needs = "rules.env" },
}

---The modules a manifest lacks.
---@param names table<string, boolean> the module names of the manifest
---@return string[] missing one line per module, saying which module asks for it
function M.missing(names)
  local out = {}
  for _, rule in ipairs(M.COMPANIONS) do
    if names[rule.module] and not names[rule.needs] then
      out[#out + 1] = rule.needs .. " (needed by " .. rule.module .. ")"
    end
  end
  return out
end

return M
