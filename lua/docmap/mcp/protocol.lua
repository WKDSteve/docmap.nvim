---@module 'docmap.mcp.protocol'
--- JSON-RPC 2.0 dispatch for the MCP server — the half that has nothing to do
--- with stdio.
---
--- The protocol itself is `lib.nvim.mcp.server` (it started here and moved to
--- lib.nvim so that tasks, rules and testing serve their tools the same way).
--- What is left in this file is docmap's side of it: one lib server per
--- installed handle, with the catalogue of `tools.lua` registered on it, the
--- `instructions` text, and `request` / `dispatch` as functions over a server
--- (the shape `TESTS/mcp_spec.lua` drives, in-process, with real JSON strings).
---
--- **Envelope JSON is `vim.json`, payload JSON is `docmap.core.json`.**
--- The envelope is lib's; the payload is encoded by `tools.lua`, byte-stable
--- across runs.
---
--- The rules the protocol keeps (a notification is never answered, a failing
--- tool is an `isError` result the model sees, a malformed line is `-32700`,
--- a crash inside dispatch `-32603`, the version echo of `SUPPORTED`) are
--- documented and specified in lib.nvim (`lua/lib/nvim/mcp/server/README.md`).

require("docmap.mcp.@types")

local lib_server = require("lib.nvim.mcp.server")
local tools = require("docmap.mcp.tools")

local M = {}

M.VERSION = "0.1.0"

---Spec revisions this server claims to speak, newest first (lib.nvim's list).
---@type string[]
M.SUPPORTED = lib_server.SUPPORTED

local INSTRUCTIONS = "Tools over a scanned Lua/JS module map: module tree, require graph, "
  .. "call graph and documentation-drift findings for the repository this server was "
  .. "started in. Answers come from a scan held in memory — call docmap_rescan after "
  .. "editing files."

---Build a server bound to one installed handle.
---@param handle Docmap.Handle
---@param opts { name?: string, out_dir?: string }?
---@return Docmap.Mcp.Server
function M.new(handle, opts)
  opts = opts or {}
  local server = lib_server.new({
    name = opts.name or "docmap.nvim",
    version = M.VERSION,
    instructions = INSTRUCTIONS,
  })
  ---@cast server Docmap.Mcp.Server
  server.handle = handle
  server.out_dir = opts.out_dir
  for _, entry in ipairs(tools.list()) do
    local name = entry.name
    server:add(name, {
      description = entry.description,
      input_schema = entry.inputSchema,
      run = function(args)
        return tools.call(handle, name, args, { out_dir = server.out_dir })
      end,
    })
  end
  return server
end

---Handle one decoded JSON-RPC message; `nil` for a notification.
---@param server Docmap.Mcp.Server
---@param msg table Decoded JSON-RPC request or notification.
---@return table? response `nil` for notifications.
function M.request(server, msg)
  return server:request(msg)
end

---Decode one line, dispatch it, and encode the response; `nil` when nothing
---goes back (a notification, a blank line).
---@param server Docmap.Mcp.Server
---@param line string One newline-delimited JSON-RPC message.
---@return string? encoded response, without a trailing newline.
function M.dispatch(server, line)
  return server:dispatch(line)
end

return M
