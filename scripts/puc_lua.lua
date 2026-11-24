-- scripts/puc_lua.lua — the one place that picks a PUC Lua able to run the standalone engine.
--
-- Shared by the `standalone` gate of `scripts/ci.lua` and `TESTS/standalone_telemetry_spec.lua`, so the two can never
-- disagree about which interpreter the engine gets. Loaded with `dofile`, runs inside Neovim (needs `vim.system`).
--
-- The engine needs Lua 5.3 or newer: under 5.1 it dies while loading (`error loading module
-- 'docmap.core.lang.dart'`), and a 5.1 first on `$PATH` must not hide a usable 5.4 further down.

local M = {}

---Interpreter names, best first. `lua5.4` before `lua` because Debian-family images ship both and the bare name is
---often 5.1.
M.candidates = { "lua5.4", "lua5.3", "lua" }

---The `_VERSION` an interpreter reports, or nil when it does not run.
---@param exe string
---@return string?
function M.version_of(exe)
  local probe = vim.system({ exe, "-e", "io.write(_VERSION)" }, { text = true }):wait()
  if probe.code ~= 0 then
    return nil
  end
  return probe.stdout
end

---Whether `exe` is on PATH, and whether it loads both rocks: fields so a spec can replace the probes.
---@param exe string
---@return boolean
function M.exists(exe)
  return vim.fn.executable(exe) == 1
end

---@param exe string
---@return boolean
function M.loads_rocks(exe)
  return vim.system({ exe, "-e", "require('lfs') require('dkjson')" }):wait().code == 0
end

---Whether a `_VERSION` string is Lua 5.3 or newer.
---@param version string?
---@return boolean
function M.is_modern(version)
  local major, minor = tostring(version or ""):match("^Lua (%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  return major ~= nil and (major > 5 or (major == 5 and minor >= 3))
end

---Which of the two rocks `exe` cannot load, in order.
---@param exe string
---@return string[]
function M.missing_rocks(exe)
  local out = {}
  for _, rock in ipairs({ "lfs", "dkjson" }) do
    local probe = vim.system({ exe, "-e", ("require('%s')"):format(rock) }):wait()
    if probe.code ~= 0 then
      out[#out + 1] = rock
    end
  end
  return out
end

---Every candidate is probed, none is assumed: a PUC Lua that is too old, or cannot `require` the two rocks the build
---needs, is passed over for the next one.
---@return string? exe The first interpreter that is Lua 5.3+ and loads both rocks.
---@return { exe: string, version: string }[]? found Every interpreter on PATH, returned only when none worked, so the
---  caller can tell "none installed", "only Lua 5.1 installed" and "a modern one lacking a rock" apart.
function M.find()
  local found = {}
  for _, exe in ipairs(M.candidates) do
    if M.exists(exe) then
      local version = M.version_of(exe)
      if version then
        found[#found + 1] = { exe = exe, version = version }
        if M.is_modern(version) and M.loads_rocks(exe) then
          return exe
        end
      end
    end
  end
  return nil, found
end

return M
