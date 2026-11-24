---@module 'docmap.core.soft_require'
--- The one place that probes for an optional dependency, so `pcall(require,
--- "...")` is not hand-rolled at every call site that needs one. Every
--- optional integration this plugin has — `runtime-analysis.nvim`,
--- `pdfport.nvim`, `which-key.nvim`, `mdview.nvim`, and a couple of specific
--- `lib.nvim` submodules (`progress`, `deps.spec`) — goes through `M.probe`
--- instead of its own inline `pcall`.
---
--- Delegates to `lib.nvim.require.safe`, which is the same `pcall(require,
--- name)` -> `(ok, mod)` primitive this module used to reimplement from
--- scratch — `lib.nvim` is already a hard dependency of this repo (`core/`
--- itself unconditionally requires several `lib.nvim.fs.*` submodules), so
--- there was no reason to hand-roll a second one. Pure Lua either way, no
--- `vim.api`/`vim.fn` in the call path — safe to call from `core/`, which
--- this module itself lives in.
---
--- This does not change *what* callers do with a missing dependency (that
--- stays call-site-specific: some fall back silently, some warn once, some
--- are purely informational — `editor/health.lua`'s three severities are
--- unaffected by this module and read as before). It only removes the
--- duplicated probing logic itself — `core/api.lua` alone used to run the
--- identical `pcall(require, "runtime-analysis.telemetry")` at two separate
--- call sites in the same file.

local M = {}

---@generic T
---@param modname string
---@return T|nil mod `nil` if `modname` could not be required (not installed).
function M.probe(modname)
  local ok, mod = require("lib.nvim.require").safe(modname)
  if ok then
    return mod
  end
  return nil
end

---One line of a load failure that is safe to show: the first line of the message, without the `file:line:` prefix
---Lua puts in front of it, and with every path (the user's home included) replaced by `<path>`.
---@param message any
---@return string
local function one_line(message)
  local line = tostring(message):match("[^\r\n]*")
  line = line:gsub("^%S+:%d+: ", "")
  line = line:gsub("[%w_%.%-:]*[/\\][^%s'\"]*", "<path>")
  if #line > 200 then
    line = line:sub(1, 200)
  end
  return line
end

---Like `probe`, but says *why* a module is not there.
---
---`probe` answers `nil` for two different things: the module is not installed, and it is installed but one of
---its own requires fails (a standalone engine without `bit`, found 2026-11-23). The first is "not found" by the
---name asked for; anything else is "error", with a one-line text.
---@param modname string
---@return any? mod
---@return "ok"|"missing"|"error" state
---@return string? err One line, no paths; only with `"error"`.
function M.probe_detail(modname)
  local ok, mod = pcall(require, modname)
  if ok then
    return mod, "ok", nil
  end
  local text = tostring(mod)
  local not_found = "module '" .. modname .. "' not found"
  if text:sub(1, #not_found) == not_found then
    return nil, "missing", nil
  end
  return nil, "error", one_line(text)
end

return M
