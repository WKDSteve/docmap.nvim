-- TESTS/sheets/support/project.lua -- the project the rpc feature sheets work in.
--
-- A sheet loads it in its first `lua` step (`dofile("TESTS/sheets/support/project.lua").make()`; the child's working
-- directory is the repository root). It copies the small Lua tree of TESTS/fixtures/maps_page into a fresh temporary
-- folder, adds a checklist ledger and a GitHub remote, commits it twice (so `HEAD~1` exists) and makes that folder
-- the working directory, as a person would `:cd` into a project. Every git call here is the sheet's preparation:
-- `testing perf` counts what runs from a file below TESTS/ apart from the plugin's own starts.
--
-- It also keeps every message the plugin sends (`_G.notes`, the text of each `vim.notify`) so that a step can wait
-- for the answer of a command without reading the message area, and sets up `:DocMap` the way a user's spec does.

local M = {}

local FIXTURE = "TESTS/fixtures/maps_page"

---@param cwd string
---@param args string[]
---@return string stdout
local function git(cwd, args)
  local cmd = {
    "git",
    "-c",
    "user.name=t",
    "-c",
    "user.email=t@example.test",
    "-c",
    "commit.gpgsign=false",
    -- the machine's global hooks are not part of this
    "-c",
    "core.hooksPath=" .. cwd .. "/.git/no-hooks",
  }
  vim.list_extend(cmd, args)
  local done = vim.system(cmd, { cwd = cwd, text = true }):wait(30000)
  assert(done.code == 0, table.concat(args, " ") .. ": " .. tostring(done.stderr))
  return vim.trim(done.stdout or "")
end
M.git = git

---@param path string
---@param text string
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end
M.write = write

---Replace `old` (plain text, must be there) by `new` in the file at `path`.
---@param path string
---@param old string
---@param new string
function M.edit(path, old, new)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  local at = assert(text:find(old, 1, true), "not in " .. path .. ": " .. old)
  write(path, text:sub(1, at - 1) .. new .. text:sub(at + #old))
end

---Commit the map the project has now (`docs/map`), as a repository that keeps its map does.
---@return nil
function M.commit_map()
  git(_G.root, { "add", "docs/map" })
  git(_G.root, { "commit", "-q", "-m", "map" })
end

---@param from string
---@param to string
local function copy_tree(from, to)
  vim.fn.mkdir(to, "p")
  for name, kind in vim.fs.dir(from) do
    if kind == "directory" then
      copy_tree(from .. "/" .. name, to .. "/" .. name)
    else
      local src = assert(io.open(from .. "/" .. name, "rb"))
      write(to .. "/" .. name, src:read("*a"))
      src:close()
    end
  end
end

local CHECKLIST = table.concat({
  "## Store",
  "",
  "- [x] The store keeps one value per key",
  "      <!-- @ref lua/app/core/store.lua:1 -->",
  "      <!-- @verified 2020-01-01 -->",
  "",
  "- [ ] The window closes on q",
  "      <!-- @ref lua/app/ui/window.lua -->",
  "",
}, "\n")

---The options of `:DocMap` for the project: the tree is `lua/app`.
---@param extra table|nil
---@return table
function M.opts(extra)
  return vim.tbl_extend(
    "force",
    { source = "lua/app", lua_root = "lua", title = "app" },
    extra or {}
  )
end

---Make the project, `:cd` into it and set up `:DocMap` (with `extra` options).
---@param extra table|fun(root: string): table|nil options, or a function of the root that returns them
---@return string root
function M.make(extra)
  local root = vim.fs.normalize(vim.fn.tempname()) .. "-docmap-sheet"
  local real = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()
  copy_tree(vim.fs.normalize(real) .. "/" .. FIXTURE, root)
  write(root .. "/docs/CHECKLIST.md", CHECKLIST)
  git(root, { "init", "-q", "-b", "main" })
  git(root, { "remote", "add", "origin", "https://github.com/example/app.git" })
  git(root, { "add", "-A" })
  git(root, { "commit", "-q", "-m", "first" })
  M.edit(
    root .. "/lua/app/core/store.lua",
    "function M.save() end",
    "function M.save()\n  return true\nend"
  )
  git(root, { "add", "-A" })
  git(root, { "commit", "-q", "-m", "second" })
  root = vim.uv.fs_realpath(root) or root
  vim.cmd.cd(vim.fn.fnameescape(root))
  _G.root = vim.fs.normalize(root)
  _G.P = M

  _G.notes = {}
  local notify = vim.notify
  vim.notify = function(msg, ...)
    _G.notes[#_G.notes + 1] = tostring(msg)
    return notify(msg, ...)
  end
  vim.o.cmdheight = 4

  local opts = type(extra) == "function" and extra(_G.root) or extra
  require("docmap").setup(M.opts(opts --[[@as table|nil]]))
  return _G.root
end

---Whether any message so far contains `text` (plain).
---@param text string
---@return boolean
function M.said(text)
  for _, note in ipairs(_G.notes or {}) do
    if note:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Run the command-line entry of docmap (`scripts/gen_map.lua <argv>`, `core/cli.lua`) in this editor.
---
---The CLI is the same `cli.run` in its own `nvim -l`; run here, its starts are traced. It writes to stdout and
---stderr, which in this child carry the RPC channel: both are kept in `_G.cli_out` while it runs.
---@param argv string[]
---@return integer exit_code
function M.cli(argv)
  _G.cli_out = {}
  local sink = {
    write = function(self, ...)
      for _, part in ipairs({ ... }) do
        _G.cli_out[#_G.cli_out + 1] = tostring(part)
      end
      return self
    end,
    flush = function(self)
      return self
    end,
  }
  local stdout, stderr = io.stdout, io.stderr
  rawset(io, "stdout", sink)
  rawset(io, "stderr", sink)
  local ok, code = pcall(require("docmap.core.cli").run, M.opts({ root = _G.root }), argv)
  rawset(io, "stdout", stdout)
  rawset(io, "stderr", stderr)
  assert(ok, code)
  return code
end

---Whether a line of a window on the screen contains `text` (plain).
---@param text string
---@return boolean
function M.shows(text)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if line:find(text, 1, true) then
        return true
      end
    end
  end
  return false
end

local PLATFORM = { "is_windows", "is_wsl", "is_macos" }

---Let lib.nvim take its Linux way to the system opener (`xdg-open`) until `real_platform()`.
---
---On Windows lib.nvim hands a page to `explorer.exe` or `rundll32.exe`, and the `.cmd` stand-ins of `fakes` never
---catch a name with `.exe` (System32 wins and a real browser opens); on macOS `open` is the opener. The Linux way
---ends at the `xdg-open` stand-in on every system, so the sheet sees what would be opened and nothing opens.
---@return nil
function M.pretend_linux()
  M.saved_platform = {}
  for _, name in ipairs(PLATFORM) do
    local mod = "lib.nvim.cross.platform." .. name
    M.saved_platform[mod] = package.loaded[mod]
    package.loaded[mod] = function()
      return false
    end
  end
end

---Undo `pretend_linux()`.
---@return nil
function M.real_platform()
  for mod, was in pairs(M.saved_platform or {}) do
    package.loaded[mod] = was
  end
  M.saved_platform = nil
end

---What the `xdg-open` stand-in was handed, in order, one string per call (its arguments joined by a blank: the
---Windows stand-in splits an argument at `=` and `&`).
---@return string[]
function M.opened()
  local seen = {}
  for _, call in ipairs(require("testing.fake_programs").read(vim.env.TESTING_FAKES, "xdg-open")) do
    seen[#seen + 1] = table.concat(call.argv, " ")
  end
  return seen
end

---GET `path` from the running map server; the answer lands in `_G.answer` (`nil` until the server closed it).
---@param path string
---@return nil
function M.get(path)
  local url = assert(require("docmap.editor.serve").info(), "no map server").url
  local host, port = url:match("^https?://([^:/]+):(%d+)")
  if host == "localhost" then
    host = "127.0.0.1"
  end
  _G.answer = nil
  local got = {}
  local tcp = assert(vim.uv.new_tcp())
  tcp:connect(host, tonumber(port), function(err)
    assert(not err, err)
    tcp:write(("GET %s HTTP/1.0\r\nHost: %s:%s\r\n\r\n"):format(path, host, port))
    tcp:read_start(function(read_err, chunk)
      if chunk then
        got[#got + 1] = chunk
      else
        tcp:close()
        _G.answer = read_err and ("error: " .. read_err) or table.concat(got)
      end
    end)
  end)
end

return M
