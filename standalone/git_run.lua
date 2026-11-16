---@module 'standalone.git_run'
--- The standalone build's git runner for the `--api=` routes: `io.popen`
--- through the platform shell, every argument quoted by
--- `standalone/shell_quote.lua`.
---
--- Pulled out of `standalone/docmap.lua` so it can be tested without `lfs`,
--- `dkjson` or the vim shim (`TESTS/git_run_spec.lua`): it needs only `io`,
--- `os` and `string`.
---
--- ## A `%` in a git format, under cmd.exe
---
--- `shell_quote` refuses every value with a `%` on Windows, rightly: cmd.exe
--- expands `%NAME%` even inside double quotes, and `cmd /c` has no escape for
--- it. Every pretty format git knows is written with `%` (`--format=%H%x1f%h`),
--- so that refusal used to take `--api=commits` and the stale check of
--- `rules/judged` with it on Windows.
---
--- The format does not have to travel on the command line, though. Git reads
--- named pretty formats from its configuration (`pretty.<name>`), and
--- `-c include.path=<file>` pulls a configuration file into one invocation.
--- So on Windows a `--format=`/`--pretty=` value with a `%` in it is written to
--- a temporary configuration file as `pretty.docmapN`, the argument becomes
--- `--pretty=docmapN`, and the command line carries no `%` at all. Any other
--- argument with a `%` is still refused, exactly as before.
local M = {}

local shell_quote = require("standalone.shell_quote")

---A byte of a format value that is spelled as git's own `%xNN` placeholder in
---the configuration file: control bytes (git's formats here use `\31` and
---`\30` as separators), and the two characters a quoted configuration value
---treats specially. Git expands `%xNN` to that byte, so the output is the same.
---@param c string
---@return string
local function as_placeholder(c)
  return ("%%x%02x"):format(c:byte())
end

---Split git's `--format=`/`--pretty=` argument into its kind and value.
---@param arg_ string
---@return string? kind `tformat:` or `format:`
---@return string? value
local function format_value(arg_)
  local value = arg_:match("^%-%-format=(.*)$")
  if value then
    -- `--format=X` is `--pretty=tformat:X` (git-log(1)), unless X names a
    -- built-in format, which has no `%` and never reaches the rewrite.
    local kind, rest = value:match("^(t?format:)(.*)$")
    if kind then
      return kind, rest
    end
    return "tformat:", value
  end
  local pretty = arg_:match("^%-%-pretty=(.*)$")
  if pretty then
    local kind, rest = pretty:match("^(t?format:)(.*)$")
    if kind then
      return kind, rest
    end
    -- `--pretty=X` with a placeholder in it is `--pretty=tformat:X` as well (git-log(1)); a
    -- built-in name (`oneline`, ...) has no `%` and is left alone by the caller.
    if pretty:find("%", 1, true) then
      return "tformat:", pretty
    end
  end
  return nil
end

---Move every format value that holds a `%` out of `args` into named pretty
---formats. Pure: returns the new argument list and the configuration text, or
---`args` unchanged and nil when nothing needs moving.
---@param args string[]
---@return string[] args
---@return string? config Text of a git configuration file, nil when no value moved.
function M.pretty_aliases(args)
  local out, lines = {}, {}
  for i, a in ipairs(args) do
    local kind, value = format_value(a)
    if kind and value and value:find("%", 1, true) then
      local name = "docmap" .. (#lines + 1)
      local spelled = value:gsub('[%c"\\]', as_placeholder)
      lines[#lines + 1] = ('\t%s = "%s%s"'):format(name, kind, spelled)
      out[i] = "--pretty=" .. name
    else
      out[i] = a
    end
  end
  if #lines == 0 then
    return out, nil
  end
  return out, "[pretty]\n" .. table.concat(lines, "\n") .. "\n"
end

local written = 0
-- Differs between processes: the address of a fresh table. `math.random` alone does not, under
-- an interpreter that does not seed it (LuaJIT), and two engines started in the same second
-- would then write one file and read each other's formats.
local process_tag = (tostring({}):match("(%x+)$") or "0")

---A path for the temporary configuration file, in the user's temp directory.
---@return string? path
local function temp_path()
  local dir = os.getenv("TEMP") or os.getenv("TMP")
  if not dir or dir == "" then
    return nil
  end
  for _ = 1, 20 do
    written = written + 1
    local path = ("%s/docmap-git-%s-%d-%d-%d.gitconfig"):format(
      (dir:gsub("\\", "/"):gsub("/+$", "")),
      process_tag,
      os.time(),
      math.random(0, 0x7fffffff),
      written
    )
    local probe = io.open(path, "rb")
    if not probe then
      return path
    end
    probe:close()
  end
  return nil
end

---Whether `program` (the first element of an argument list) is git: `git`,
---`git.exe` or a path ending in one of them, in any case.
---@param program string?
---@return boolean
function M.is_git(program)
  if type(program) ~= "string" then
    return false
  end
  local name = (program:match("[^/\\]+$") or ""):lower()
  return name == "git" or name == "git.exe"
end

---Quote an argument list `{ program, arg, ... }` into one shell command line.
---
---Every element goes through `shell_quote`, which refuses what it cannot
---quote safely. When the program is git and `windows` is set, the format
---values with a `%` are moved into a temporary git configuration first (see
---the module comment), so git is the one program whose `%` arguments survive
---cmd.exe; any other program's `%` is still refused.
---
---Shared by `M.run` and the vim shim's `vim.fn.system`
---(`standalone/vim_shim.lua`), so the two cannot drift apart again.
---@param cmd string[]
---@param windows boolean
---@return string? line Nil when an argument cannot be quoted or the configuration cannot be written.
---@return fun()|string cleanup_or_err Removes the temporary configuration (call it after the command ran); the error when `line` is nil.
function M.command_line(cmd, windows)
  local args = cmd
  local config_path
  local function cleanup()
    if config_path then
      os.remove(config_path)
      config_path = nil
    end
  end

  if windows and M.is_git(cmd[1]) then
    local rest = {}
    for i = 2, #cmd do
      rest[#rest + 1] = cmd[i]
    end
    local rewritten, config = M.pretty_aliases(rest)
    if config then
      config_path = temp_path()
      local fd = config_path and io.open(config_path, "wb")
      if not fd then
        config_path = nil
        return nil, "could not write a temporary git configuration for a format with a %"
      end
      fd:write(config)
      fd:close()
      args = { cmd[1], "-c", "include.path=" .. config_path }
      for _, a in ipairs(rewritten) do
        args[#args + 1] = a
      end
    end
  end

  local parts = {}
  for i, a in ipairs(args) do
    local quoted, err = shell_quote.quote(a, windows)
    if not quoted then
      cleanup()
      return nil, err
    end
    parts[i] = quoted
  end
  return table.concat(parts, " "), cleanup
end

---Run git in `o.root` via `io.popen`, the standalone build's only subprocess
---capability (`vim.system` does not exist outside Neovim).
---
---**Failure is read from the output, not the exit code.** stderr is merged
---into the captured stream (`2>&1`), and output starting with
---`fatal:`/`error:`/`usage:` is a failure. A heuristic, kept on purpose:
---reading the exit status instead would change what the `--api=` routes call
---an error, and none of the formats requested here can start with one of the
---three words.
---@param o table Needs `o.root`.
---@param args string[]
---@param windows boolean True on Windows (cmd.exe quoting, and the format rewrite above).
---@return string|nil stdout
---@return string|nil err
function M.run(o, args, windows)
  local quoted_root, root_err = shell_quote.quote(o.root, windows)
  if not quoted_root then
    return nil, root_err
  end

  local cmd = { "git" }
  for _, a in ipairs(args) do
    cmd[#cmd + 1] = a
  end
  local line, cleanup = M.command_line(cmd, windows)
  if not line then
    return nil, cleanup --[[@as string]]
  end
  ---@cast cleanup fun()

  local cd = (windows and "cd /d " or "cd ") .. quoted_root .. " && "
  local fh = io.popen(cd .. line .. " 2>&1", "r")
  if not fh then
    cleanup()
    return nil, "could not start git"
  end
  local out = fh:read("*a") or ""
  fh:close()
  cleanup()
  if out:match("^%s*fatal:") or out:match("^%s*error:") or out:match("^%s*usage:") then
    return nil, (out:gsub("%s+$", ""))
  end
  return out
end

return M
