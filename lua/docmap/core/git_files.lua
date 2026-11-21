---@module 'docmap.core.git_files'
--- The repository's remote and branch, read from the files in `.git` instead
--- of asking a `git` process.
---
--- Every `:DocMap` (and every rescan, after each save with `watch = true`)
--- wants the "origin" remote and the current branch for the page's links, and
--- `:DocBrowse traffic` wants the remote again right after. Asked through
--- `git remote get-url` and `git symbolic-ref`, that was two synchronous
--- processes per scan, ~55 ms of a frozen editor on Windows. Both answers sit
--- in two small files: `HEAD` (the branch) and `config` (the remote), so they
--- are read directly -- no process, nothing to cache for the common case.
---
--- Only what the files cannot answer exactly the way git would goes to git,
--- once per distinct file content (cached by it, so a changed `HEAD` or
--- `config` is a new key and never a stale answer):
---   * a detached HEAD (git abbreviates the sha to a length only it knows),
---   * a HEAD pointing outside `refs/heads/`,
---   * a config that includes other files or rewrites URLs (`insteadOf`), or
---     a URL the remote parser does not understand.
---
--- Plain `io` and `string` only: `core/scan.lua` also runs inside the
--- standalone build under PUC Lua.

local M = {}

---Answers of the git fallback, keyed by the file content they were asked for.
---A changed file is a new key; the table is emptied in place once it grows
---past `CACHE_MAX` (a long session switching many branches).
---@type table<string, string|false>
local cache = {}
local cache_size = 0
local CACHE_MAX = 64

---@param path string
---@return string|nil
local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local ok, text = pcall(fd.read, fd, "*a")
  fd:close()
  if ok and type(text) == "string" then
    return text
  end
  return nil
end

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param p string
---@return boolean
local function is_absolute(p)
  return p:sub(1, 1) == "/" or p:match("^%a:[/\\]") ~= nil
end

---@param base string
---@param p string
---@return string
local function resolve(base, p)
  p = p:gsub("\\", "/")
  if is_absolute(p) then
    return p
  end
  return base .. "/" .. p
end

---Where the repository's files live for `root`: the nearest `.git` above it.
---@param root string
---@return { gitdir: string, commondir: string, top: string }|nil
function M.find(root)
  local dir = root:gsub("\\", "/"):gsub("/+$", "")
  while dir ~= "" do
    local gitdir
    if read(dir .. "/.git/HEAD") then
      gitdir = dir .. "/.git"
    else
      -- A linked worktree or a submodule: `.git` is a file naming the real
      -- directory, relative to the file's own directory.
      local text = read(dir .. "/.git")
      local target = text and text:match("^gitdir:%s*(.-)%s*$")
      if target and target ~= "" then
        gitdir = resolve(dir, target)
      end
    end
    if gitdir then
      local common = read(gitdir .. "/commondir")
      local commondir = common and trim(common) ~= "" and resolve(gitdir, trim(common)) or gitdir
      return { gitdir = gitdir, commondir = commondir, top = dir }
    end
    local parent = dir:match("^(.*)/[^/]*$")
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

---Ask git once for a key and remember the answer (`false`: git had none).
---@param key string
---@param ask fun(): string|nil
---@return string|nil
local function remembered(key, ask)
  local hit = cache[key]
  if hit == nil then
    local ok, value = pcall(ask)
    hit = (ok and type(value) == "string" and value ~= "") and value or false
    if cache_size >= CACHE_MAX then
      for k in pairs(cache) do
        cache[k] = nil
      end
      cache_size = 0
    end
    cache[key] = hit
    cache_size = cache_size + 1
  end
  return hit or nil
end

---The `url` of `[remote "<name>"]` in a config text, the first one like
---`git remote get-url`. `unsure` when the text could change the answer in a
---way this reader does not follow (includes, URL rewrites, quoting).
---@param text string
---@param name string
---@return string|nil url
---@return boolean unsure
function M.config_url(text, name)
  local lower = text:lower()
  if lower:find("%[%s*include") or lower:find("insteadof") or lower:find("pushinsteadof") then
    return nil, true
  end
  local in_section = false
  for line in text:gmatch("[^\r\n]+") do
    local header = line:match("^%s*%[(.-)%]")
    if header then
      local kind, sub = header:match('^%s*(%S+)%s+"(.*)"%s*$')
      in_section = kind ~= nil and kind:lower() == "remote" and sub == name
      if not kind and header:lower():match("^%s*remote%.") then
        -- The old `[remote.origin]` spelling: lower-cased by git, leave it to git.
        return nil, true
      end
    elseif in_section then
      local key, value = line:match("^%s*([%w%-]+)%s*=%s*(.-)%s*$")
      if key and key:lower() == "url" then
        if value == "" or value:find('["\\]') or value:find("%s[#;]") then
          return nil, true
        end
        return value, false
      end
    end
  end
  return nil, false
end

---The parsed "origin"-style remote of `root` (`lib.nvim.git.remote` shape),
---or nil (no repository, no such remote, a URL nobody can parse).
---@param root string
---@param name? string Remote name, default "origin".
---@return table|nil
function M.remote(root, name)
  name = name or "origin"
  local parse = require("lib.nvim.git.remote").parse_remote
  local info = M.find(root)
  if not info then
    return nil
  end
  local text = read(info.commondir .. "/config") or ""
  local url, unsure = M.config_url(text, name)
  if url and not unsure then
    local parsed = parse(url)
    if parsed then
      return parsed
    end
  elseif not unsure then
    return nil
  end
  local asked = remembered("remote\0" .. info.commondir .. "\0" .. name .. "\0" .. text, function()
    return require("lib.nvim.git").remote_url(name, { dir = root })
  end)
  return asked and parse(asked) or nil
end

---The current branch of `root`, or for a detached HEAD git's short sha
---(`lib.nvim.git.current_ref`'s answer); nil outside a repository.
---@param root string
---@return string|nil
function M.ref(root)
  local info = M.find(root)
  if not info then
    return nil
  end
  local head = read(info.gitdir .. "/HEAD")
  if not head then
    return nil
  end
  head = trim(head)
  local branch = head:match("^ref:%s*refs/heads/(.+)$")
  if branch then
    return branch
  end
  return remembered("ref\0" .. info.gitdir .. "\0" .. head, function()
    if head:match("^%x+$") then
      -- Detached: `current_ref` would first try `symbolic-ref`, which must fail.
      local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured({
        "git",
        "-C",
        root,
        "rev-parse",
        "--short",
        "HEAD",
      })
      return ok and type(out) == "string" and trim(out) or nil
    end
    return require("lib.nvim.git").current_ref(root)
  end)
end

---Forget every remembered git answer (tests).
function M.clear()
  for k in pairs(cache) do
    cache[k] = nil
  end
  cache_size = 0
end

return M
