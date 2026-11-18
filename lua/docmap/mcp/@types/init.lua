---@meta
---@module 'docmap.mcp.@types'
--- Types for the MCP server layer, split across `mcp/protocol.lua` (JSON-RPC
--- dispatch) and `mcp/tools.lua` (the tool catalogue).

---One server instance, bound to one installed handle: a `lib.nvim.mcp.server`
---with docmap's catalogue registered on it.
---@class Docmap.Mcp.Server: Lib.Mcp.Server
---@field handle Docmap.Handle
---@field out_dir? string Repo-relative output directory — the one piece of `Docmap.Opts` a tool call needs that `handle` does not carry. See `mcp/tools.lua`'s `docmap_checklist`.

---@class Docmap.Mcp.ToolCtx
---@field out_dir? string Repo-relative output directory, for excluding the generated map from history walks. Only `docmap_checklist` uses this today.

return {}
