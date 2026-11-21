---@module 'docmap.testing.git'
--- The few read-only git questions the testing provider asks, behind one
--- runner so a missing git, a non-repository and a failed command all collapse
--- into the same honest answer: `nil`, "I do not know".
---
--- Argument vectors only (no shell), and every revision or path that came from
--- a caller is placed after `--` or validated first, so a hostile `since`
--- (`--output=/etc/x`) can never become an option of git.

local M = {}

---Run `git -C <root> --no-optional-locks <args...>` and return trimmed stdout.
---@param root string
---@param args string[]
---@return string|nil out `nil` on any failure (no git, not a repository, non-zero exit); `""` when the command succeeded with no output.
function M.run(root, args)
  local argv = { "git", "--no-optional-locks", "-C", root }
  vim.list_extend(argv, args)
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(argv)
  if not ok or type(out) ~= "string" then
    return nil
  end
  return vim.trim(out)
end

---@class Docmap.Testing.GitStatus
---@field head string|nil Full sha of HEAD; nil before the first commit.
---@field paths string[] Root-relative paths with uncommitted changes, untracked files included.
---@field untracked string[] Root-relative untracked files (gitignore respected).

---The prefix of `root` below the top of its work tree ("" at the top): git
---status names paths from the top, the pathspecs here are relative to `root`.
---@param root string
---@return string
local function root_prefix(root)
  local abs = vim.fn.fnamemodify(root, ":p"):gsub("\\", "/"):gsub("/+$", "")
  local info = require("docmap.core.git_files").find(abs)
  if not info then
    return ""
  end
  local top = info.top
  local fold = vim.fn.has("win32") == 1 and string.lower or function(s)
    return s
  end
  if #abs > #top and fold(abs:sub(1, #top + 1)) == fold(top .. "/") then
    return abs:sub(#top + 2)
  end
  return ""
end

---Everything the freshness check and the untracked half of `changed_since`
---need, in one process: whether `root` is a work tree at all (nil when not),
---HEAD, and every changed or untracked path. Asked once per request instead
---of `rev-parse` twice, `status` twice and `ls-files --others`.
---@param root string
---@return Docmap.Testing.GitStatus|nil
function M.status(root)
  local out = M.run(root, {
    "status",
    "--porcelain=v2",
    "--branch",
    "-z",
    "--untracked-files=all",
  })
  if out == nil then
    return nil
  end
  local prefix = root_prefix(root)
  local st = { head = nil, paths = {}, untracked = {} }
  ---@param p string|nil Top-relative path.
  ---@param untracked boolean|nil
  local function add(p, untracked)
    if not p or p == "" then
      return
    end
    if prefix ~= "" then
      if p:sub(1, #prefix + 1) ~= prefix .. "/" then
        return
      end
      p = p:sub(#prefix + 2)
    end
    st.paths[#st.paths + 1] = p
    if untracked then
      st.untracked[#st.untracked + 1] = p
    end
  end
  local recs = vim.split(out, "\0", { plain = true })
  local i = 1
  while i <= #recs do
    local r = recs[i]
    local kind = r:sub(1, 2)
    if kind == "# " then
      local oid = r:match("^# branch%.oid (%x+)$")
      if oid then
        st.head = oid
      end
    elseif kind == "1 " then
      add(r:match("^1 %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$"))
    elseif kind == "2 " then
      -- A rename or copy: the next record is the original path, changed too.
      add(r:match("^2 %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$"))
      i = i + 1
      add(recs[i])
    elseif kind == "u " then
      add(r:match("^u %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$"))
    elseif kind == "? " then
      add(r:sub(3), true)
    end
    i = i + 1
  end
  return st
end

---Whether any of `pathspecs` (plain root-relative files or directories) has
---a change in `st`.
---@param st Docmap.Testing.GitStatus
---@param pathspecs string[]
---@return boolean
function M.dirty_in(st, pathspecs)
  for _, spec in ipairs(pathspecs) do
    local s = spec:gsub("^%./", ""):gsub("/+$", "")
    for _, p in ipairs(st.paths) do
      if s == "" or s == "." or p == s or p:sub(1, #s + 1) == s .. "/" then
        return true
      end
    end
  end
  return false
end

---The newest commit touching `pathspecs`: sha and committer time.
---@param root string
---@param pathspecs string[] Repo-relative paths; always passed after `--`.
---@return string|nil sha
---@return integer|nil time Unix seconds.
function M.last_commit(root, pathspecs)
  local args = { "log", "-1", "--format=%H%x09%ct", "--" }
  vim.list_extend(args, pathspecs)
  local out = M.run(root, args)
  if not out or out == "" then
    return nil, nil
  end
  local sha, ct = out:match("^(%x+)\t(%d+)$")
  if not sha then
    return nil, nil
  end
  return sha, tonumber(ct)
end

---Whether `ancestor` is an ancestor of (or equal to) `descendant`.
---@param root string
---@param ancestor string
---@param descendant string
---@return boolean
function M.is_ancestor(root, ancestor, descendant)
  if not (ancestor:match("^%x+$") and descendant:match("^%x+$")) then
    return false
  end
  return M.run(root, { "merge-base", "--is-ancestor", ancestor, descendant }) ~= nil
end

---A revision as the caller may spell it: refs, shas, `HEAD~3`, `main@{1}`.
---Anything that could be read as an option, contains whitespace or a control
---character, or is absurdly long is refused outright.
---@param rev any
---@return boolean
function M.valid_rev(rev)
  return type(rev) == "string"
    and #rev > 0
    and #rev <= 200
    and rev:sub(1, 1) ~= "-"
    and rev:match("^[%w%._/~^@{}%-]+$") ~= nil
    and not rev:find("..", 1, true)
end

---Repo-relative files changed since `rev` (committed, staged, unstaged) plus
---the untracked ones, deletions excluded (a deleted file has nothing to map).
---@param root string
---@param rev string A revision accepted by `valid_rev`.
---@param st? Docmap.Testing.GitStatus|false The request's `status` snapshot, if it has one already.
---@return string[]|nil files `nil` when git could not answer.
function M.changed_since(root, rev, st)
  local out = M.run(root, { "diff", "--name-only", "--diff-filter=d", "-z", rev, "--" })
  if out == nil then
    return nil
  end
  local files, seen = {}, {}
  ---@param blob string
  local function take(blob)
    for name in blob:gmatch("[^%z]+") do
      if not seen[name] then
        seen[name] = true
        files[#files + 1] = name
      end
    end
  end
  take(out)
  if st == nil then
    st = M.status(root)
  end
  if st then
    for _, name in ipairs(st.untracked) do
      take(name)
    end
  end
  table.sort(files)
  return files
end

return M
