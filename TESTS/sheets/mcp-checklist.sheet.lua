-- TESTS/sheets/mcp-checklist.sheet.lua -- the MCP tool `docmap_checklist`, as a coding agent calls it.
-- The MCP server (`nvim --headless -l scripts/mcp_server.lua`) reads one JSON-RPC line at a time and hands it to
-- `docmap.mcp.protocol`; the sheet hands the same lines to the same dispatcher in this editor, so the tool's
-- `git log` is traced. The stdio loop itself is lib.nvim's (`lib.nvim.mcp.server`).
return {
  id = "docmap.mcp-checklist",
  title = "The MCP tool docmap_checklist answers which checklist items are stale",
  feature = "docmap.mcp-checklist",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    {
      lua = [[
        local protocol = require("docmap.mcp.protocol")
        local handle = require("docmap").install(P.opts({ root = _G.root, watch = false }))
        _G.mcp = protocol.new(handle, { name = "app", out_dir = "docs/map" })
        protocol.dispatch(_G.mcp, vim.json.encode({
          jsonrpc = "2.0",
          id = 1,
          method = "initialize",
          params = {
            protocolVersion = "2025-06-18",
            capabilities = {},
            clientInfo = { name = "sheet", version = "1" },
          },
        }))
      ]],
      timeout = 30000,
      note = "an agent starts the server and says hello",
    },
    {
      lua = [[_G.reply = require("docmap.mcp.protocol").dispatch(_G.mcp, vim.json.encode({
        jsonrpc = "2.0",
        id = 2,
        method = "tools/call",
        params = { name = "docmap_checklist", arguments = { state = "all" } },
      }))]],
      timeout = 30000,
      note = "it calls the checklist tool",
    },
    {
      expect = "type(_G.reply) == 'string' and _G.reply:find('stale', 1, true) ~= nil"
        .. " and _G.reply:find('unverified', 1, true) ~= nil or error(vim.inspect(_G.reply))",
      note = "the answer has the stale and the unverified item",
    },
  },
}
