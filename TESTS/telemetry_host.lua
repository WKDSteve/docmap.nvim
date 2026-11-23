-- TESTS/telemetry_host.lua — the host behind TESTS/sheets/served-runtime-detail.sheet.lua, as a process of its own.
--
--   nvim --headless -u NONE -l TESTS/telemetry_host.lua <host dir> <port>
--
-- Run from the repo root as the app `telemetry-host` of `.testing.lua` (`sheets.apps`), like TESTS/shape_host.lua:
-- the real `:DocMap serve` (`editor/serve.lua`, `core/api.lua`) over the map of the lookup_page fixture, on a free
-- port, with a telemetry store the sheet knows exactly. Its first stdout line, the URL, becomes `${host}`.
--
-- The store is the one `runtime-analysis.telemetry` reads for the namespace below. It lives under
-- `stdpath("state")`, so the app is started with `XDG_STATE_HOME` inside `${temp}` (`.testing.lua`), and this file
-- refuses to write when the store is not below the host dir: a fixture must never land in the machine's real store.
--
-- What the data holds, written by the real runtime-analysis (wrap, start with profile_args/time/errors/call_tree,
-- call, flush), then topped up to a known total:
--   look.start       13 calls (3 of them today), one raised an error, timed, two callers... fingerprinted arguments
--   look.store.load  wrapped, never called: `calls == 0`
--   look.store.old_load is not wrapped: no row, "not measured"

local host, port = arg[1], tonumber(arg[2])
assert(host and port, "usage: telemetry_host.lua <host dir> <port>")
local root = vim.fs.normalize(vim.fn.getcwd())

---The runtimepath this host adds: the caller's, or the repo and its dependencies found the way testing.nvim does.
---@return string
local function added_rtp()
  local given = vim.env.DOCMAP_SHAPE_HOST_RTP
  if given and given ~= "" then
    return given
  end
  local dirs = { root }
  for _, dep in ipairs({ "lib.nvim", "runtime-analysis.nvim", "ui.nvim" }) do
    local env = vim.env[dep:gsub("%.nvim$", ""):gsub("%-", "_"):upper() .. "_NVIM_DIR"]
    dirs[#dirs + 1] = (env and env ~= "") and env or vim.fs.dirname(root) .. "/" .. dep
  end
  return table.concat(dirs, ",")
end
vim.o.runtimepath = added_rtp() .. "," .. vim.o.runtimepath

local NAMESPACE = "docmap-sheet-telemetry"

---Say why the host cannot run, the way the sheet's `ready` line shows it, and stop.
---@param why string
local function die(why)
  io.stdout:write("failed " .. why .. "\n")
  io.stdout:flush()
  os.exit(1)
end

local paths = require("runtime-analysis.telemetry.paths")
local store_dir = vim.fs.normalize(paths.dir())
if store_dir:lower():sub(1, #vim.fs.normalize(host)) ~= vim.fs.normalize(host):lower() then
  die("the telemetry store " .. store_dir .. " is not below " .. host .. " (XDG_STATE_HOME)")
end

-- the map of the page, as shape_host.lua writes it
local docmap = require("docmap")
local opts = require("docmap.config").build(
  root .. "/TESTS/fixtures/lookup_page",
  { source = "lua/look", telemetry_namespace = NAMESPACE }
)
local ir, findings = docmap.scan_full(opts)
vim.fn.mkdir(host .. "/docs/map", "p")
for name, body in pairs({
  ["index.html"] = docmap.render.html(ir, findings, opts),
  ["module_map.json"] = docmap.to_json(ir),
}) do
  local f = assert(io.open(host .. "/docs/map/" .. name, "wb"))
  f:write(body)
  f:close()
end

-- the measurement
local telemetry = require("runtime-analysis.telemetry")
local store = require("runtime-analysis.telemetry.store")
store.clear(NAMESPACE, { dir = store_dir })

local looks = {
  start = function(arg1)
    if arg1 == "boom" then
      error("fixture failure")
    end
    return arg1
  end,
}
local stores = {
  load = function(key)
    return key
  end,
}
local inst = telemetry.new({ namespace = NAMESPACE, persist = true })
inst.wrap(looks, "look", { module_id = "look" })
inst.wrap(stores, "look.store", { module_id = "look.store" })
inst.start({ profile_args = true, time = true, errors = true, call_tree = true })
local function call_start(value)
  -- a Lua closure between, so the caller the store records is this file and not `[C]` (pcall)
  -- (no `return` of the call: a tail call drops the closure's frame)
  return pcall(function()
    local result = looks.start(value)
    return result
  end)
end
call_start("alpha")
call_start("alpha")
call_start("boom")
inst.flush()
inst.stop()

-- topped up: a total that differs from the week, so the sheet can tell "calls" from "this week"
local data = assert(store.load(NAMESPACE, { dir = store_dir }), "the fixture store was not written")
data.functions["look.start"].calls = data.functions["look.start"].calls + 10
store.save(NAMESPACE, data, { dir = store_dir })

local url, err = require("docmap.editor.serve").start({
  root = host,
  out_dir = "docs/map",
  serve_port = port,
  title = NAMESPACE,
  telemetry_namespace = NAMESPACE,
})
if not url then
  die(tostring(err))
end
io.stdout:write(url .. "\n")
io.stdout:flush()
-- Until the sheet ends. Bounded, so a sheet that died leaves no server behind for long.
vim.wait(120000, function()
  return false
end, 200)
