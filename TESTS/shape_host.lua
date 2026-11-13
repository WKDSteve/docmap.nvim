-- TESTS/shape_host.lua — the host behind TESTS/sheets/shape-diff*.sheet.lua, as a process of its own.
--
--   nvim --headless -u NONE -l TESTS/shape_host.lua <repo root> <runtimepath> <port>
--
-- A file page cannot compare maps: it has nobody to ask for the commits or for the comparison. The sheets
-- therefore need a host, and they get the real one: `:DocMap serve` (`editor/serve.lua`, `core/api.lua`,
-- `core/diff.lua`) over the artifacts of the maps_page fixture. Only git is stood in for, with two commits whose
-- maps differ from the one on disk in a known way, so a sheet can say what must be marked:
--
--   OLDER (aaaaaaa…): no `app.util.orphan` yet; an `app.core.cache` that `app.core.store` required;
--                     `app.util.text` required `app.core.store`; `app.ui.window` did not require
--                     `app.core.store` yet.
--   NEWER (bbbbbbb…): this map without `app.util.orphan`.
--
-- A process of its own, because a server in the editor that runs the sheet does not answer while that editor
-- waits for the browser. TESTS/sheets_spec.lua starts it, waits for the `ready` line and stops it again.

local root, rtp, port = arg[1], arg[2], tonumber(arg[3])
assert(root and rtp and port, "usage: shape_host.lua <repo root> <runtimepath> <port>")
-- in front of this process's own runtime, so a caller may hand over only what it adds
vim.o.runtimepath = rtp .. "," .. vim.o.runtimepath

local OLDER, NEWER = ("a"):rep(40), ("b"):rep(40)

---The map of the fixture as an older commit held it.
---@param json string The current artifact.
---@param with_cache boolean The OLDER shape (see the head of this file); false for NEWER.
---@return string
local function older_map(json, with_cache)
  local doc = vim.json.decode(json, { luanil = { object = true, array = true } })
  local ORPHAN, CORE = "lua/app/util/orphan.lua", "lua/app/core"
  local STORE, TEXT, WINDOW =
    "lua/app/core/store.lua", "lua/app/util/text.lua", "lua/app/ui/window.lua"
  local CACHE = "lua/app/core/cache.lua"
  local nodes, store = {}, nil
  for _, n in ipairs(doc.nodes) do
    if n.id ~= ORPHAN then
      nodes[#nodes + 1] = n
    end
    if n.id == STORE then
      store = n
    end
    n.children = vim.tbl_filter(function(c)
      return c ~= ORPHAN
    end, n.children or {})
    if n.id == CORE and with_cache then
      table.insert(n.children, CACHE)
    end
  end
  assert(store, "shape host: the maps_page fixture has lua/app/core/store.lua")
  if with_cache then
    local cache = vim.deepcopy(store)
    cache.id, cache.path, cache.source, cache.name = CACHE, CACHE, CACHE, "cache.lua"
    cache.module, cache.summary, cache.functions, cache.markers =
      "app.core.cache", "Kept nothing.", {}, {}
    nodes[#nodes + 1] = cache
    local edges = {}
    for _, e in ipairs(doc.edges or {}) do
      if not (e.kind == "require" and e.from == WINDOW and e.to == STORE) then
        edges[#edges + 1] = e
      end
    end
    edges[#edges + 1] =
      { kind = "require", from = STORE, to = CACHE, line = 1, to_module = "app.core.cache" }
    edges[#edges + 1] =
      { kind = "require", from = TEXT, to = STORE, line = 1, to_module = "app.core.store" }
    doc.edges = edges
  end
  doc.nodes = nodes
  return vim.json.encode(doc)
end

local docmap = require("docmap")
local opts =
  require("docmap.config").build(root .. "/TESTS/fixtures/maps_page", { source = "lua/app" })
local ir, findings = docmap.scan_full(opts)
local host = root .. "/TESTS/sheets/out/shape-host"
vim.fn.mkdir(host .. "/docs/map", "p")
local now = docmap.to_json(ir)
for name, body in pairs({
  ["index.html"] = docmap.render.html(ir, findings, opts),
  ["module_map.json"] = now,
}) do
  local f = assert(io.open(host .. "/docs/map/" .. name, "wb"))
  f:write(body)
  f:close()
end

local maps = { [OLDER] = older_map(now, true), [NEWER] = older_map(now, false) }
local url, err = require("docmap.editor.serve").start({
  root = host,
  out_dir = "docs/map",
  serve_port = port,
  git = function(_, args)
    if args[1] == "log" then
      -- the record format of `api.commits`: fields parted by \31, records by \30
      local record = "%s\31%s\31Ada\31%s\31%s\30\n"
      return record:format(NEWER, "bbbbbbb", "2026-01-02", "the newer commit")
        .. record:format(OLDER, "aaaaaaa", "2026-01-01", "the older commit")
    end
    local sha = args[1] == "show" and (args[2] or ""):match("^(%x+):docs/map/module_map%.json$")
    if sha and maps[sha] then
      return maps[sha]
    end
    return nil, "no such object"
  end,
})
if not url then
  io.stdout:write("failed " .. tostring(err) .. "\n")
  io.stdout:flush()
  os.exit(1)
end
io.stdout:write("ready " .. url .. "\n")
io.stdout:flush()
-- Until the spec that started this stops it. Bounded, so a spec that died leaves no server behind for long.
vim.wait(120000, function()
  return false
end, 200)
