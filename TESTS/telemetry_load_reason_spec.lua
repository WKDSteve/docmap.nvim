-- TESTS/telemetry_load_reason_spec.lua — `--api=telemetry` says *why* runtime-analysis cannot be read.
--
-- `soft_require.probe` and `telemetry_join.load` fold three things into one `nil`: runtime-analysis is not installed,
-- it is installed but does not load (a standalone engine without LuaJIT's `bit` did exactly that, 2026-11-23, and
-- answered "no data" for a store real Neovim reads), and nothing was stored. The first two now have a `reason` of
-- their own (and a stable `reason_code`); "no store" stays "no data".

return function(H)
  local eq, ok = H.eq, H.ok
  local MOD = "runtime-analysis.telemetry"
  local soft = require("docmap.core.soft_require")
  local join = require("docmap.core.telemetry_join")
  local api = require("docmap.core.api")

  local saved_loaded, saved_preload = package.loaded[MOD], package.preload[MOD]
  local function restore()
    package.loaded[MOD], package.preload[MOD] = saved_loaded, saved_preload
  end

  ---Make `require(MOD)` throw `message`, or (nil) behave as if the module did not exist.
  ---@param message string?
  local function broken(message)
    package.loaded[MOD] = nil
    package.preload[MOD] = message and function()
      error(message, 0)
    end or nil
  end

  -- a module that is not there: "missing". The finder sees no such module only when it is not preloaded and not on
  -- the path, so ask for one nobody has.
  local _, state, err = soft.probe_detail("docmap-spec-no-such-module")
  eq(state, "missing", "probe_detail: a module nobody has is 'missing'")
  eq(err, nil, "probe_detail: 'missing' carries no error text")

  -- the module is there, a require of its own fails: "error", with one line and no path
  package.preload["docmap-spec-throws"] = function()
    error(
      "module 'bit' not found:\n\tno field package.preload['bit']\n\tno file '/home/someone/.luarocks/bit.lua'",
      0
    )
  end
  local _, state2, err2 = soft.probe_detail("docmap-spec-throws")
  package.preload["docmap-spec-throws"] = nil
  eq(state2, "error", "probe_detail: a module that throws while loading is 'error', not 'missing'")
  ok(
    type(err2) == "string" and not err2:find("[\r\n]"),
    "probe_detail: the error is one line (" .. tostring(err2) .. ")"
  )
  ok(not tostring(err2):find("someone", 1, true), "probe_detail: no path of the user in the error")
  ok(tostring(err2):find("bit", 1, true) ~= nil, "probe_detail: the error still says what failed")

  -- a throw with a file position and a Windows path
  package.preload["docmap-spec-throws2"] = function()
    error("C:\\Users\\someone\\fingerprint.lua:5: attempt to call a nil value", 0)
  end
  local _, _, err3 = soft.probe_detail("docmap-spec-throws2")
  package.preload["docmap-spec-throws2"] = nil
  ok(
    not tostring(err3):find("someone", 1, true),
    "probe_detail: a Windows path is dropped too (" .. tostring(err3) .. ")"
  )

  -- the route, over a project with a map and a namespace
  local host = (vim.fn.tempname():gsub("\\", "/"))
  vim.fn.mkdir(host .. "/docs/map", "p")
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local namespace = "docmap-telemetry-reason-spec"
  local docmap = require("docmap")
  local scan_opts = require("docmap.config").build(
    root .. "/TESTS/fixtures/lookup_page",
    { source = "lua/look", telemetry_namespace = namespace }
  )
  local map = assert(io.open(host .. "/docs/map/module_map.json", "wb"))
  map:write(docmap.to_json(docmap.scan_full(scan_opts)))
  map:close()
  local opts =
    require("docmap.config").build(host, { source = "lua/look", telemetry_namespace = namespace })

  local function route()
    local ok_call, answer = pcall(api.telemetry, opts, nil)
    ok(ok_call, "api.telemetry does not throw (" .. tostring(answer) .. ")")
    return ok_call and answer or {}
  end

  broken("module 'bit' not found:\n\tno file '/home/someone/bit.lua'")
  local failed = route()
  eq(failed.available, false, "a dependency that throws on load: not available")
  eq(
    failed.reason_code,
    "runtime-analysis-load-failed",
    "a dependency that throws on load: its own code"
  )
  ok(failed.reason ~= "no data", "a dependency that throws on load is not reported as 'no data'")
  ok(
    tostring(failed.reason):find("bit", 1, true) ~= nil,
    "the load error is the reason (" .. tostring(failed.reason) .. ")"
  )
  ok(not tostring(failed.reason):find("someone", 1, true), "no path of the user in the reason")
  ok(not tostring(failed.reason):find("[\r\n]"), "the reason is one line")
  eq(join.availability(), "error", "availability: 'error' when the load throws")

  -- not installed: the preload is gone and the finder would have to find it on the path; hide it behind a loader
  -- that reports the name as missing, as the real finder does
  package.loaded[MOD] = nil
  package.preload[MOD] = nil
  local key = rawget(package, "searchers") and "searchers" or "loaders"
  local real_finders = package[key]
  package[key] = {}
  local absent = route()
  eq(join.availability(), "missing", "availability: 'missing' when the module cannot be found")
  package[key] = real_finders
  eq(absent.reason_code, "runtime-analysis-not-found", "not installed: its own code")
  ok(absent.reason ~= "no data", "not installed is not reported as 'no data'")

  -- the loaded case is unchanged: a module that loads but has nothing stored for the namespace says "no data"
  package.loaded[MOD] = {
    load = function()
      return nil
    end,
  }
  local nothing = route()
  eq(nothing.reason, "no data", "installed, nothing stored: still 'no data'")
  eq(nothing.reason_code, nil, "installed, nothing stored: no load-failure code")
  eq(join.availability(), "ok", "availability: 'ok' when the module loads")

  restore()
  vim.fn.delete(host, "rf")
end
