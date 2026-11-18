---@module 'docmap.mcp'
--- An MCP (Model Context Protocol) server exposing this repository's module
--- map to a coding agent.
---
--- Usage — as a subprocess, which is the only way MCP's stdio transport is
--- ever used:
---
---   nvim --headless -l scripts/mcp_server.lua
---
--- and in an agent's MCP configuration, the same command with the repository
--- as the working directory. Nothing listens on a port and nothing
--- authenticates, because with stdio there is nobody to authenticate: the
--- client *is* the parent process, and the trust boundary is the one the
--- operating system already draws around a subprocess. That is the whole
--- reason this was the cheap protocol to build first, and why it sidesteps
--- every question the hosted-web-app idea drowns in.
---
--- ### The two rules stdio imposes
---
--- 1. **stdout carries the protocol and nothing else.** One JSON object per
---    line, no framing headers (that is LSP; MCP delimits by newline). A
---    stray `print()` anywhere in the process corrupts the stream and the
---    client's next parse fails — which is why `serve` writes every diagnostic
---    to stderr, and why nothing in this module logs to stdout even on the
---    error paths.
--- 2. **The scan happens before the loop starts.** `install()` is slow enough
---    to notice on a large tree, and a client that sends `initialize` and
---    waits would otherwise be waiting on a filesystem walk it cannot see.
---    Doing it up front costs the same time but spends it before the client
---    is listening.
---
--- The protocol and the read loop are `lib.nvim.mcp.server`; `protocol.lua`
--- binds a lib server to a handle and `tools.lua` is the tool catalogue.

local protocol = require("docmap.mcp.protocol")

local M = {}

M.protocol = protocol

---Serve MCP over stdin/stdout until stdin closes.
---
---Blocks. Returns the process exit code rather than exiting, matching
---`core/cli.lua`'s posture: the caller that actually needs the process to stop
---is the wrapper script, not this function, and a function that returns is one
---a test could in principle drive with redirected handles.
---@param opts Docmap.Opts Passed straight to `docmap.install`.
---@return integer exit_code
---@raises string When `opts.root` is missing (from `docmap.install`).
function M.serve(opts)
  local docmap = require("docmap")

  -- Watching is explicitly off. A file-watch callback firing mid-request
  -- would swap the IR out from under a tool call that already read
  -- `handle.ir()`, so a client could get a node list from one scan and edges
  -- from the next. The agent asks for a rescan when it wants one —
  -- `docmap_rescan` exists precisely so that moment is the client's choice
  -- rather than an invisible race.
  local install_opts = vim.tbl_extend("force", opts, { watch = false })
  local handle = docmap.install(install_opts)

  local server =
    protocol.new(handle, { name = opts.title or "docmap.nvim", out_dir = opts.out_dir })

  -- The read loop is lib.nvim.mcp.server's: stdout carries the protocol and
  -- nothing else (print and vim.notify go to stderr while it runs), and each
  -- answer is flushed, since the Windows C runtime treats a line-buffered
  -- stdout as fully buffered and the client would wait for an answer that
  -- sits in the buffer. The "ready" line on stderr is lib's too.
  local code = server:serve()

  docmap.uninstall(handle)
  return code
end

return M
