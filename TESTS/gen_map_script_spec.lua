-- TESTS/gen_map_script_spec.lua — `scripts/gen_map.lua` as the pre-commit hook and the CI `map` job run it.
--
-- Two things went wrong together: the script found lib.nvim by itself but not ui.nvim, so `docs/BINDINGS.md` was
-- only written with an extra `--cmd "set rtp^=…/ui.nvim"`; and it wrote the map before BINDINGS.md, so the map
-- counted the links of the old page and `--check` was red until a second run. Here the script runs in a copy of the
-- working tree with a stale BINDINGS.md and ui.nvim given only as `UI_NVIM_DIR`: one run must write the page and
-- leave a map that `--check` calls up to date.

return function(H)
  local ok, eq = H.ok, H.eq

  ---The checkout a module comes from, on this editor's runtimepath.
  ---@param modname string e.g. "ui.contextmenu"
  ---@return string?
  local function checkout_of(modname)
    local base = "lua/" .. modname:gsub("%.", "/")
    for _, file in ipairs({ base .. ".lua", base .. "/init.lua" }) do
      local hit = vim.api.nvim_get_runtime_file(file, false)[1]
      if hit then
        hit = hit:gsub("\\", "/")
        return (hit:sub(1, #hit - #file - 1))
      end
    end
    return nil
  end
  local ui_dir = checkout_of("ui.contextmenu")
  local lib_dir = checkout_of("lib.nvim.fs.read")
  if not ui_dir or not lib_dir then
    print("n/a  ui.nvim or lib.nvim is not on the runtimepath of this run")
    return
  end

  local repo = vim.fn.getcwd():gsub("\\", "/")
  local copy = (vim.fn.tempname():gsub("\\", "/")) .. "-gen-map"
  local files = vim.system({ "git", "ls-files", "-z" }, { cwd = repo, text = true }):wait(60000)
  eq(files.code, 0, "git ls-files")
  for _, rel in ipairs(vim.split(files.stdout or "", "\0", { trimempty = true })) do
    -- the script reads lua/, scripts/, docs/ and the root config; fixtures and tests are not needed
    if not rel:match("^TESTS/") and not rel:match("^standalone/") and not rel:match("^assets/") then
      local src, dst = repo .. "/" .. rel, copy .. "/" .. rel
      if vim.fn.filereadable(src) == 1 then
        vim.fn.mkdir(vim.fs.dirname(dst), "p")
        assert(vim.uv.fs_copyfile(src, dst))
      end
    end
  end

  -- A stale page: the rendered one without its code spans, which are what the map counts as references to a module
  -- (`core/docs.lua`), as if a binding had just gained one.
  local bindings = copy .. "/docs/BINDINGS.md"
  local fresh = H.slurp(bindings)
  local stale = fresh:gsub("`([^`\n]+)`", "%1")
  ok(stale ~= fresh, "the page has code spans to drop")
  local fd = assert(io.open(bindings, "wb"))
  fd:write(stale)
  fd:close()

  local env = { UI_NVIM_DIR = ui_dir, LIB_NVIM_DIR = lib_dir }
  ---@param args string[]
  ---@return table
  local function gen(args)
    local cmd = {
      vim.v.progpath,
      "-n",
      "-i",
      "NONE",
      "--headless",
      "-u",
      "NONE",
      "-l",
      "scripts/gen_map.lua",
    }
    vim.list_extend(cmd, args)
    return vim.system(cmd, { cwd = copy, env = env, text = true }):wait(180000)
  end

  local run = gen({})
  eq(run.code, 0, "one run exits 0\n" .. tostring(run.stderr))
  ok(
    (run.stdout or ""):find("wrote docs/BINDINGS.md", 1, true) ~= nil,
    "UI_NVIM_DIR is enough to write the page\n" .. tostring(run.stderr)
  )
  eq(H.slurp(bindings), fresh, "the page is rendered again")

  local check = gen({ "--check" })
  eq(
    check.code,
    0,
    "after one run the map is up to date\n" .. tostring(check.stdout) .. tostring(check.stderr)
  )

  vim.fn.delete(copy, "rf")
end
