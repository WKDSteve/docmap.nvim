---@module 'scripts.fleet_report'
--- The Duplicates, Quicks and Findings tabs over many repositories, and what turns up in more than one of them.
---
---   nvim -n -i NONE --headless -u NONE -l scripts/fleet_report.lua <root>...             # Markdown on stdout
---   nvim -n -i NONE --headless -u NONE -l scripts/fleet_report.lua --dir=E:/repos        # every repository in a folder
---   nvim -n -i NONE --headless -u NONE -l scripts/fleet_report.lua --dir=E:/repos --json # the data, one JSON object
---
--- Options:
---   --dir=<folder>      add every subfolder that holds a `.git` (repeatable); `--skip=` filters them
---   --skip=<pattern>    a Lua pattern of folder names to leave out of `--dir` (default `%-wt%-`: worktree copies)
---   --json              the joined data instead of Markdown
---   --top=<n>           rows per table (default 25)
---   --with-generated    keep built output (`dist-*`, bundles, `node_modules`), left out by default
---
--- Reads every repository and writes nothing into any of them. Progress goes to stderr, the report to stdout.
--- Exit 0 when a report was made, 1 when at least one repository could not be scanned (the report still lists the
--- others), 2 for wrong arguments or no repository at all.

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local engine_root = here:match("^(.*)/scripts/[^/]+$") or "."

--- Put a dependency on the runtimepath, if it is not already reachable: an environment variable, a `.deps/` checkout,
--- a sibling checkout (the same three places `scripts/gen_map.lua` looks).
---@param modname string
---@param dirname string
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = engine_root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(engine_root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(("fleet_report: %s not found (probed require('%s')).\n"):format(dirname, modname))
  os.exit(2)
end

vim.opt.runtimepath:prepend(engine_root)
ensure("lib.nvim.fs.read", "lib.nvim")

---@param message string
local function usage(message)
  io.stderr:write("fleet_report: " .. message .. "\n")
  io.stderr:write(
    "usage: nvim -n -i NONE --headless -u NONE -l scripts/fleet_report.lua "
      .. "[--dir=<folder>]... [--skip=<pattern>] [--json] [--top=<n>] [--with-generated] [<root>...]\n"
  )
  os.exit(2)
end

local dirs, roots = {}, {}
local skip = "%-wt%-"
local as_json, with_generated = false, false
local top = 25
for _, a in ipairs(_G.arg or {}) do
  if a:match("^%-%-dir=") then
    dirs[#dirs + 1] = a:sub(#"--dir=" + 1)
  elseif a:match("^%-%-skip=") then
    skip = a:sub(#"--skip=" + 1)
  elseif a == "--json" then
    as_json = true
  elseif a == "--with-generated" then
    with_generated = true
  elseif a:match("^%-%-top=") then
    top = tonumber(a:sub(#"--top=" + 1))
    if not top or top < 1 then
      usage("--top wants a positive number")
    end
  elseif a:sub(1, 2) == "--" then
    usage("unknown option " .. a)
  else
    roots[#roots + 1] = a
  end
end

for _, dir in ipairs(dirs) do
  if vim.fn.isdirectory(dir) == 0 then
    usage(dir .. " is not a folder")
  end
  local names = {}
  for name, kind in vim.fs.dir(dir) do
    if
      kind == "directory"
      and not name:find(skip)
      and vim.uv.fs_stat(dir .. "/" .. name .. "/.git")
    then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    roots[#roots + 1] = dir:gsub("\\", "/"):gsub("/+$", "") .. "/" .. name
  end
end
if #roots == 0 then
  usage("no repository given")
end

local fleet = require("docmap.core.fleet")
local repos, failed = fleet.scan_roots(roots, {
  with_generated = with_generated,
  progress = function(line)
    io.stderr:write(line .. "\n")
  end,
})
local joined = fleet.join(repos)
if as_json then
  joined.failed = failed
  io.stdout:write(require("docmap.core.json").encode(joined) .. "\n")
else
  io.stdout:write(table.concat(fleet.render(joined, { top = top }), "\n") .. "\n")
  for _, f in ipairs(failed) do
    io.stdout:write(("\nNot scanned: %s (%s)\n"):format(f.root, (f.error:match("[^\n]*"))))
  end
end
vim.cmd("cq " .. (#failed > 0 and 1 or 0))
