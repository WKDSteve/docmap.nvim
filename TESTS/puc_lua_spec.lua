-- TESTS/puc_lua_spec.lua — `scripts/puc_lua.lua` picks a PUC Lua of version 5.3 or newer that loads the rocks.
--
-- The standalone engine dies under Lua 5.1; the pick is shared by the `standalone` gate of `scripts/ci.lua` and
-- `TESTS/standalone_telemetry_spec.lua`. The probes (`exists`, `version_of`, `loads_rocks`) are replaced, so the spec
-- needs no particular interpreter on this machine.

return function(H)
  local eq, ok = H.eq, H.ok
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local function fresh(versions, rocks)
    local m = dofile(root .. "/scripts/puc_lua.lua")
    m.exists = function(exe)
      return versions[exe] ~= nil
    end
    m.version_of = function(exe)
      return versions[exe]
    end
    m.loads_rocks = function(exe)
      return rocks[exe] == true
    end
    return m
  end

  local m = fresh({}, {})
  eq(m.is_modern("Lua 5.1"), false, "puc_lua: Lua 5.1 is too old")
  eq(m.is_modern("Lua 5.2"), false, "puc_lua: Lua 5.2 is too old")
  eq(m.is_modern("Lua 5.3"), true, "puc_lua: Lua 5.3 is enough")
  eq(m.is_modern("Lua 5.4"), true, "puc_lua: Lua 5.4 is enough")
  eq(m.is_modern(nil), false, "puc_lua: no version is not modern")

  -- a 5.1 `lua` that loads the rocks is not picked
  local only_old = fresh({ lua = "Lua 5.1" }, { lua = true })
  local exe, found = only_old.find()
  eq(exe, nil, "puc_lua: a Lua 5.1 with both rocks is not a usable interpreter")
  eq(#found, 1, "puc_lua: the old interpreter is still reported as found")
  eq(
    found[1].version,
    "Lua 5.1",
    "puc_lua: with its version, so the skip can say 'only Lua 5.1 found'"
  )

  -- a 5.1 first on PATH does not hide a 5.4 further down the candidate list
  local mixed = fresh(
    { ["lua5.4"] = "Lua 5.4", lua = "Lua 5.1" },
    { ["lua5.4"] = true, lua = true }
  )
  eq(mixed.find(), "lua5.4", "puc_lua: the modern candidate wins")
  mixed.candidates = { "lua", "lua5.4" }
  eq(mixed.find(), "lua5.4", "puc_lua: an old interpreter earlier in the list does not hide it")

  -- modern but without the rocks: skipped, the next candidate is tried
  local rockless = fresh({ ["lua5.4"] = "Lua 5.4", ["lua5.3"] = "Lua 5.3" }, { ["lua5.3"] = true })
  eq(rockless.find(), "lua5.3", "puc_lua: a modern Lua without the rocks is passed over")

  local none = fresh({}, {})
  local nexe, nfound = none.find()
  ok(nexe == nil and #nfound == 0, "puc_lua: nothing on PATH is nothing found")
end
