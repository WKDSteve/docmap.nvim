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
  local ok, eq = H.ok, H.eq
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

  -- A route probe that ends before its module (shape/<sha> against a map that is not committed)
  -- must stop the build instead of shipping a binary without docmap.core.diff.
  local shape_missing = rules.missing({}, { "shape/abc1234" })
  eq(#shape_missing, 1, "a shape probe without docmap.core.diff is reported")
  ok(shape_missing[1]:find("docmap.core.diff", 1, true), "the report names docmap.core.diff")
  ok(shape_missing[1]:find("shape/abc1234", 1, true), "and the route whose probe missed it")
  eq(#rules.missing({ ["docmap.core.diff"] = true, ["docmap.core.history"] = true }, {
    "commit/abc1234",
    "shape/abc1234",
  }), 0, "with both route modules nothing is missing")
  ok(
    rules.missing({}, { "commit/abc1234" })[1]:find("docmap.core.history", 1, true),
    "commit needs history"
  )

  -- `--fleet` is a mode of the entry point, measured like a route: without docmap.core.fleet the binary would
  -- answer `docmap --fleet` with "module not found"
  local fleet_missing = rules.missing({}, { "--fleet" })
  eq(#fleet_missing, 1, "a --fleet probe without docmap.core.fleet is reported")
  ok(fleet_missing[1]:find("docmap.core.fleet", 1, true), "the report names docmap.core.fleet")
  ok(
    fleet_missing[1]:find("the probe of --fleet did", 1, true),
    "and the mode, not an --api= route"
  )
  eq(
    #rules.missing({ ["docmap.core.fleet"] = true }, { "--fleet" }),
    0,
    "with it nothing is missing"
  )

  local script = read("scripts/bundle_manifest.lua")
  ok(script:find('probe("--fleet", {', 1, true), "the build probes --fleet")
  ok(
    script:find('probed_routes[#probed_routes + 1] = "--fleet"', 1, true),
    "and asks the rule about it"
  )
  ok(
    script:find("manifest_rules.missing(staged, probed_routes)", 1, true),
    "the build asks for its route probes"
  )
  ok(
    not script:find('"--api=shape/" .. head_sha, "--out-dir=', 1, true),
    "the shape probe reads the committed map, not the throwaway out-dir"
  )
  ok(script:find('\n%s+require%("rules%.env"%)'), "the build measures rules.env explicitly")
  ok(script:find("manifest_rules.missing", 1, true), "the build asks the rule")
  ok(
    read(".github/workflows/release-engine.yml"):find("scripts/manifest_rules.lua", 1, true),
    "a change of the rule runs the release workflow"
  )
end
