-- TESTS/fleet_report_args_spec.lua — the arguments of `scripts/fleet_report.lua`, run as the user runs it.
--
-- A subprocess `nvim -n -i NONE --headless -u NONE -l scripts/fleet_report.lua` over a temp folder of fake
-- repositories: `--dir` takes folders with a `.git`, leaves out worktree copies (`-wt-`), `--skip` matches and the
-- built-in private list, and `--include-private` lifts only the last. The private names are taken from
-- `fleet.PRIVATE`, never written here: this repository is public (TESTS/fleet_cli_spec.lua greps every tracked file).

return function(H)
  local ok, eq = H.ok, H.eq
  local fleet = require("docmap.core.fleet")

  local script = vim.fn.getcwd():gsub("\\", "/") .. "/scripts/fleet_report.lua"
  local base = (vim.fn.tempname():gsub("\\", "/")) .. "-fleet-args"
  local private_name = "zz-" .. fleet.PRIVATE[1]:upper() .. "-notes"

  ---A folder that looks like a repository: a `.git` and one documented Lua module.
  ---@param name string
  local function fake_repo(name)
    local dir = ("%s/%s"):format(base, name)
    vim.fn.mkdir(dir .. "/.git", "p")
    vim.fn.mkdir(dir .. "/lua/m", "p")
    H.write(dir .. "/lua/m/init.lua", {
      "---@module 'm'",
      "--- A module.",
      "local M = {}",
      "function M.f() return 1 end",
      "return M",
    })
  end
  for _, name in ipairs({ "alpha", "beta", "x-wt-1", "skipme", private_name }) do
    fake_repo(name)
  end
  vim.fn.mkdir(base .. "/nogit/lua", "p")

  ---@param args string[]
  ---@return { code: integer, stdout: string, stderr: string }
  local function run(args)
    local cmd = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", script }
    vim.list_extend(cmd, args)
    local r = vim.system(cmd, { text = true }):wait(120000)
    return { code = r.code, stdout = r.stdout or "", stderr = r.stderr or "" }
  end

  ---The repository names a `--json` report covers.
  ---@param out string
  ---@return string comma-separated, sorted
  local function repos_of(out)
    local okj, data = pcall(vim.json.decode, out)
    local names = {}
    for _, r in ipairs(okj and type(data) == "table" and data.repos or {}) do
      names[#names + 1] = r.repo
    end
    table.sort(names)
    return table.concat(names, ",")
  end

  -- `--dir`: folders with a `.git`, minus `-wt-`, `--skip` and the private list.
  do
    local r = run({ "--dir=" .. base, "--skip=skipme", "--json" })
    eq(r.code, 0, "--dir: exit 0\n" .. r.stderr)
    eq(repos_of(r.stdout), "alpha,beta", "--dir: only alpha and beta are read")
    ok(
      r.stderr:find("skipped " .. private_name, 1, true) ~= nil,
      "--dir: stderr names the private folder it left out\n" .. r.stderr
    )
  end

  -- A skip list that is not a valid alternation (`a|b`, a Lua pattern has no `|`) does not let the private one in.
  do
    local r = run({ "--dir=" .. base, "--skip=skipme|beta", "--json" })
    eq(r.code, 0, "a mistyped --skip: exit 0\n" .. r.stderr)
    local names = vim.split(repos_of(r.stdout), ",")
    ok(
      not vim.tbl_contains(names, private_name),
      "a mistyped --skip: the private folder is still not read"
    )
    ok(vim.tbl_contains(names, "skipme"), "a mistyped --skip skips nothing")
  end

  -- `--include-private` lifts only the private list.
  do
    local r = run({ "--dir=" .. base, "--skip=skipme", "--include-private", "--json" })
    eq(r.code, 0, "--include-private: exit 0\n" .. r.stderr)
    eq(
      repos_of(r.stdout),
      "alpha,beta," .. private_name,
      "--include-private: the private folder is read"
    )
  end

  -- A root named on the command line is read, with a warning.
  do
    local r = run({ base .. "/" .. private_name, "--json" })
    eq(r.code, 0, "a named private root: exit 0\n" .. r.stderr)
    eq(repos_of(r.stdout), private_name, "a named private root is read")
    ok(
      r.stderr:find("warning:", 1, true) ~= nil,
      "a named private root warns on stderr\n" .. r.stderr
    )
  end

  -- Wrong arguments exit 2; `--top` wants a positive number.
  for _, bad in ipairs({
    { "--dir=" .. base, "--top=0" },
    { "--dir=" .. base, "--top=x" },
    { "--dir=" .. base .. "/missing" },
    { "--nope" },
    {},
  }) do
    local r = run(bad)
    eq(r.code, 2, "exit 2 for " .. table.concat(bad, " ") .. "\n" .. r.stderr)
  end
  ok(
    run({ "--dir=" .. base, "--top=0" }).stderr:find("--top", 1, true) ~= nil,
    "--top=0 names the option"
  )

  -- A root that cannot be scanned: exit 1, the others still reported.
  do
    local r = run({ base .. "/alpha", base .. "/does-not-exist", "--json" })
    eq(r.code, 1, "an unreadable root: exit 1\n" .. r.stderr)
    eq(repos_of(r.stdout), "alpha", "an unreadable root: the others are still reported")
  end

  vim.fn.delete(base, "rf")
end
