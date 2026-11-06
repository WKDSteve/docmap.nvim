-- The rule of scripts/manifest_rules.lua: a manifest with `rules.settings` holds `rules.env`, and
-- scripts/bundle_manifest.lua fails on it (it runs under PUC Lua with lfs, so the release workflow
-- is where it runs for real; here the rule and its wiring).

---@param rel string path relative to the repository root
---@return string
local function read(rel)
  local f = assert(io.open(vim.fn.getcwd() .. "/" .. rel, "rb"), "missing file: " .. rel)
  local text = f:read("*a")
  f:close()
  return text
end

return function(H)
  local ok = H.ok
  local rules = dofile(vim.fn.getcwd() .. "/scripts/manifest_rules.lua")

  ok(
    #rules.missing({ ["rules.settings"] = true }) == 1,
    "rules.settings without rules.env is reported"
  )
  ok(
    rules.missing({ ["rules.settings"] = true })[1]:find("rules.env", 1, true),
    "the report names rules.env"
  )
  ok(
    #rules.missing({ ["rules.settings"] = true, ["rules.env"] = true }) == 0,
    "with rules.env nothing is missing"
  )
  ok(
    #rules.missing({ ["core.docmap"] = true }) == 0,
    "a bundle without the rules engine needs neither"
  )

  local script = read("scripts/bundle_manifest.lua")
  ok(script:find('\n%s+require%("rules%.env"%)'), "the build measures rules.env explicitly")
  ok(script:find("manifest_rules.missing", 1, true), "the build asks the rule")
  ok(
    read(".github/workflows/release-engine.yml"):find("scripts/manifest_rules.lua", 1, true),
    "a change of the rule runs the release workflow"
  )
end
