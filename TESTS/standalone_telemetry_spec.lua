-- TESTS/standalone_telemetry_spec.lua — `--api=telemetry` of the standalone engine reads a real store.
--
-- The standalone engine runs under plain Lua, where `require("bit")` fails (LuaJIT's library):
-- `runtime-analysis.telemetry.fingerprint` needs it, so the whole telemetry tree did not load,
-- `core/telemetry_join.lua` took that for "not installed", and the engine answered
-- `{"available":false,"reason":"no data"}` for a store that real Neovim reads (found 2026-11-23 with the window of
-- docmap-desktop). `standalone/bit.lua` is the answer; this spec is the proof from the outside: the store is written
-- by the real runtime-analysis in this editor, the engine is the real `standalone/docmap.lua` under a PUC Lua.
--
-- Needs runtime-analysis.nvim on the runtimepath and a PUC Lua with `lfs` and `dkjson` on PATH; without either
-- it prints an n/a line (the gate `standalone` of `scripts/ci.lua` has the same need).

return function(H)
  H.with_restore({ groups = { "ra_telemetry_" } }, function()
    local eq, ok = H.eq, H.ok

    if not pcall(require, "runtime-analysis.telemetry") then
      print("n/a  runtime-analysis.nvim not on the runtimepath (set RUNTIME_ANALYSIS_DIR)")
      return
    end

    local root = (vim.fn.getcwd():gsub("\\", "/"))

    -- the same pick as the `standalone` gate of `scripts/ci.lua` (Lua 5.3+ with lfs and dkjson), from one place
    local lua = dofile(root .. "/scripts/puc_lua.lua").find()
    if not lua then
      print("n/a  no PUC Lua 5.3+ with lfs and dkjson on PATH")
      return
    end

    -- `standalone/bit.lua` against the editor's own `bit` (LuaJIT): the module runs under the PUC Lua, which prints
    -- what it answers for values around the edges of 32 bits, and the editor computes the same with the real one
    do
      local real = require("bit")
      local script = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({
        'local bit = dofile(arg[1] .. "/standalone/bit.lua")',
        "local values = { 0, 1, 255, 65535, 2166136261, 16777619, 2147483647, 2147483648, 4294967295, -1, -2147483648 }",
        "for _, a in ipairs(values) do",
        '  for _, name in ipairs({ "tobit", "bnot", "bswap" }) do',
        '    print(("%s %d %d"):format(name, a, bit[name](a)))',
        "  end",
        '  for _, name in ipairs({ "lshift", "rshift", "arshift", "rol", "ror" }) do',
        "    for _, n in ipairs({ 0, 1, 8, 24, 31 }) do",
        '      print(("%s %d %d %d"):format(name, a, n, bit[name](a, n)))',
        "    end",
        "  end",
        '  for _, name in ipairs({ "band", "bor", "bxor" }) do',
        "    for _, b in ipairs(values) do",
        '      print(("%s %d %d %d"):format(name, a, b, bit[name](a, b)))',
        "    end",
        "  end",
        "  for _, n in ipairs({ 8, 4, -8, 1 }) do",
        '    print(("tohex %d %d %s"):format(a, n, bit.tohex(a, n)))',
        "  end",
        "end",
        'print(("bxor3 %d"):format(bit.bxor(1, 2, 4)))',
      }, script)
      local ran = vim.system({ lua, script, root }, { text = true }):wait(30000)
      vim.fn.delete(script)
      ok(
        ran.code == 0,
        "standalone bit: the module runs under PUC Lua (" .. tostring(ran.stderr) .. ")"
      )
      local checked, differs = 0, {}
      for line in (ran.stdout or ""):gmatch("[^\r\n]+") do
        local f = vim.split(line, " ", { plain = true })
        local name = f[1]
        local want
        if name == "tohex" then
          want = real.tohex(tonumber(f[2]), tonumber(f[3]))
        elseif name == "bxor3" then
          want = real.bxor(1, 2, 4)
        elseif #f == 3 then
          want = real[name](tonumber(f[2]))
        elseif name == "band" or name == "bor" or name == "bxor" then
          want = real[name](tonumber(f[2]), tonumber(f[3]))
        else
          want = real[name](tonumber(f[2]), tonumber(f[3]))
        end
        local got = f[#f]
        checked = checked + 1
        if tostring(want) ~= got then
          differs[#differs + 1] = ("%s: PUC %s, LuaJIT %s"):format(line, got, tostring(want))
        end
      end
      ok(checked > 400, "standalone bit: many values were compared (" .. checked .. ")")
      eq(#differs, 0, "standalone bit: agrees with LuaJIT's bit (" .. (differs[1] or "all") .. ")")
    end

    ---The checkout of a dependency: the one providing `rel` on the runtimepath, else the usual places
    ---(`$<NAME>_DIR`, `.deps/<name>`, beside this checkout).
    ---@param name string e.g. "lib.nvim"
    ---@param rel string a file below the checkout's `lua/`
    ---@return string?
    local function checkout_of(name, rel)
      local found = vim.api.nvim_get_runtime_file("lua/" .. rel, false)[1]
      if found then
        local dir = found
        for _ = 1, select(2, rel:gsub("/", "")) + 2 do
          dir = vim.fs.dirname(dir)
        end
        return (dir:gsub("\\", "/"))
      end
      local env = vim.env[(name:gsub("[.-]", "_")):upper() .. "_DIR"] or ""
      for _, dir in ipairs({ env, root .. "/.deps/" .. name, vim.fs.dirname(root) .. "/" .. name }) do
        if dir ~= "" and vim.fn.isdirectory(dir .. "/lua") == 1 then
          return (dir:gsub("\\", "/"))
        end
      end
      return nil
    end
    local ra_dir = checkout_of("runtime-analysis.nvim", "runtime-analysis/telemetry/init.lua")
    local lib_dir = checkout_of("lib.nvim", "lib/nvim/health.lua")
    ok(
      ra_dir ~= nil and lib_dir ~= nil,
      "standalone telemetry: the checkouts of runtime-analysis.nvim and lib.nvim are found"
    )

    local host = (vim.fn.tempname():gsub("\\", "/"))
    vim.fn.mkdir(host, "p")
    local namespace = "docmap-standalone-telemetry-spec"

    -- the project: the map of the lookup-page fixture, with function facts, as a project that keeps its map has it
    local docmap = require("docmap")
    local opts = require("docmap.config").build(
      root .. "/TESTS/fixtures/lookup_page",
      { source = "lua/look", telemetry_namespace = namespace }
    )
    local ir = docmap.scan_full(opts)
    vim.fn.mkdir(host .. "/docs/map", "p")
    local map = assert(io.open(host .. "/docs/map/module_map.json", "wb"))
    map:write(docmap.to_json(ir))
    map:close()
    local cfg = assert(io.open(host .. "/.docmap.json", "wb"))
    cfg:write(vim.json.encode({ source = "lua/look", telemetry_namespace = namespace }))
    cfg:close()

    -- the store, where the engine looks for it: `stdpath("state")/runtime-analysis.nvim` below XDG_STATE_HOME
    local state_home = host .. "/state"
    local is_windows = vim.fn.has("win32") == 1
    local store_dir = state_home
      .. "/"
      .. (is_windows and "nvim-data" or "nvim")
      .. "/runtime-analysis.nvim"
    local telemetry = require("runtime-analysis.telemetry")
    local looks = {
      start = function(value)
        return value
      end,
    }
    local inst = telemetry.new({ namespace = namespace, persist = true, dir = store_dir })
    inst.wrap(looks, "look", { module_id = "look" })
    inst.start()
    looks.start("a")
    looks.start("b")
    inst.flush()
    inst.stop()
    ok(
      vim.uv.fs_stat(store_dir .. "/telemetry/" .. namespace .. ".json") ~= nil,
      "standalone telemetry: the store was written where the engine looks"
    )

    local env = vim.tbl_extend("force", vim.fn.environ(), {
      XDG_STATE_HOME = state_home,
      RUNTIME_ANALYSIS_NVIM_DIR = ra_dir,
      LIB_NVIM_DIR = lib_dir,
    })
    local done = vim
      .system(
        { lua, root .. "/standalone/docmap.lua", host, "--api=telemetry" },
        { cwd = root, env = env, text = true }
      )
      :wait(60000)
    ok(
      done.code == 0,
      "standalone telemetry: the engine answers (exit "
        .. tostring(done.code)
        .. ": "
        .. tostring(done.stderr)
        .. ")"
    )
    local decoded_ok, answer = pcall(vim.json.decode, done.stdout or "")
    ok(
      decoded_ok and type(answer) == "table",
      "standalone telemetry: the answer is JSON (" .. tostring(done.stdout) .. ")"
    )
    answer = decoded_ok and answer or {}

    eq(
      answer.available,
      true,
      "standalone telemetry: the store is read, not 'no data' (" .. tostring(answer.reason) .. ")"
    )
    eq(answer.namespace, namespace, "standalone telemetry: the namespace of the project")
    local row
    for _, r in ipairs(answer.rows or {}) do
      if r.fn == "M.start" then
        row = r
      end
    end
    ok(
      row ~= nil,
      "standalone telemetry: the join has a row for the wrapped function ("
        .. vim.json.encode(answer.rows or {})
        .. ")"
    )
    eq(row and row.calls, 2, "standalone telemetry: the two recorded calls arrive in the row")

    vim.fn.delete(host, "rf")
  end)
end
