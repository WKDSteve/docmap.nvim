---@module 'standalone.bit'
--- LuaJIT's `bit` library for a PUC Lua 5.3+ host, the part of it the plugins this engine loads use.
---
--- **Why this exists.** `runtime-analysis.telemetry.fingerprint` does `require("bit")` at load time, and the
--- whole telemetry module tree requires it. Plain Lua 5.4 has no `bit` module, so `require("runtime-analysis.
--- telemetry")` failed in the standalone engine, `core/telemetry_join.lua` read that as "not installed" (its
--- soft dependency), and `--api=telemetry` answered `available:false, reason:"no data"` with a real store on
--- disk (found 2026-11-23 with the window of docmap-desktop). `standalone/vim_shim.lua` installs this module
--- as `bit` when the host has none; under LuaJIT (Neovim) the real one is used and this file is never read.
---
--- Semantics are LuaJIT's: every result is a signed 32-bit integer, shifts use the low 5 bits of the count.
--- The operators `~ & | << >>` are written inside `load` strings because LuaJIT cannot parse them, and this
--- file is also parsed by the editor's tooling and by `luacheck` on LuaJIT-flavoured configurations.

local M = {}

local ops = assert(load(
  [[
  local M = {}
  local function wrap(x)
    x = x & 0xFFFFFFFF
    if x >= 0x80000000 then
      x = x - 0x100000000
    end
    return x
  end
  M.wrap = wrap
  function M.bnot(a) return wrap(~a) end
  function M.band(a, b) return wrap(a & b) end
  function M.bor(a, b) return wrap(a | b) end
  function M.bxor(a, b) return wrap(a ~ b) end
  function M.lshift(a, n) return wrap((a & 0xFFFFFFFF) << (n & 31)) end
  function M.rshift(a, n) return wrap((a & 0xFFFFFFFF) >> (n & 31)) end
  function M.arshift(a, n)
    n = n & 31
    local v = wrap(a)
    if v >= 0 then return wrap(v >> n) end
    return wrap(~((~v) >> n))
  end
  return M
]],
  "=standalone.bit"
))()

local wrap = ops.wrap

---Number to a signed 32-bit integer (LuaJIT rounds a float to the nearest integer first).
---@param x number
---@return integer
function M.tobit(x)
  if math.type(x) == "float" then
    x = math.floor(x + 0.5)
  end
  return wrap(x)
end

---@param x integer
---@return integer
function M.bnot(x)
  return ops.bnot(M.tobit(x))
end

---Variadic like LuaJIT: `bit.bxor(a, b, c, ...)`.
---@param name "band"|"bor"|"bxor"
---@return fun(a: integer, ...: integer): integer
local function fold(name)
  local f = ops[name]
  return function(a, ...)
    local acc = M.tobit(a)
    for i = 1, select("#", ...) do
      acc = f(acc, M.tobit((select(i, ...))))
    end
    return acc
  end
end

M.band = fold("band")
M.bor = fold("bor")
M.bxor = fold("bxor")

---@param x integer
---@param n integer
---@return integer
function M.lshift(x, n)
  return ops.lshift(M.tobit(x), n)
end

---@param x integer
---@param n integer
---@return integer
function M.rshift(x, n)
  return ops.rshift(M.tobit(x), n)
end

---@param x integer
---@param n integer
---@return integer
function M.arshift(x, n)
  return ops.arshift(M.tobit(x), n)
end

---@param x integer
---@param n integer
---@return integer
function M.rol(x, n)
  n = n % 32
  local v = M.tobit(x)
  return M.bor(ops.lshift(v, n), ops.rshift(v, 32 - n))
end

---@param x integer
---@param n integer
---@return integer
function M.ror(x, n)
  return M.rol(x, 32 - (n % 32))
end

---@param x integer
---@return integer
function M.bswap(x)
  local v = M.tobit(x)
  return M.bor(
    ops.lshift(v, 24),
    ops.lshift(ops.band(v, 0xFF00), 8),
    ops.band(ops.rshift(v, 8), 0xFF00),
    ops.rshift(v, 24)
  )
end

---Hex digits of the low `n` nibbles; a negative `n` gives upper case (LuaJIT's rule). Default 8.
---@param x integer
---@param n? integer
---@return string
function M.tohex(x, n)
  n = n or 8
  local upper = n < 0
  if upper then
    n = -n
  end
  if n > 8 then
    n = 8
  end
  local s = ("%08x"):format(M.tobit(x) % 4294967296)
  s = s:sub(9 - n)
  return upper and s:upper() or s
end

return M
