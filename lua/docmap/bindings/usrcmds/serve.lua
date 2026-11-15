---@module 'docmap.bindings.usrcmds.serve'
--- `:DocMap serve [stop]` — the local map server.
---
--- The runtime docmap deliberately did without one until the History tab
--- needed it: a `file://` page cannot fetch, so "compute this commit when I
--- click it" requires an origin, and an origin requires a server. See
--- `editor/serve.lua` for the security and lifecycle rules that come with it.

local i18n = require("docmap.core.i18n")

local M = {}

---@param ctx Docmap.Bindings.Ctx
---@param arg string Everything after "serve" — "" or "stop".
function M.run(ctx, arg)
  local serve = require("docmap.editor.serve")
  local sub = vim.trim(arg or "")

  if sub == "stop" then
    if serve.stop() then
      ctx.notify.info(i18n.t("editor.serve.stopped"))
    else
      ctx.notify.info(i18n.t("editor.serve.not-running"))
    end
    return
  end
  if sub ~= "" then
    ctx.notify.warn(i18n.t("editor.serve.unknown-argument", { argument = sub }))
    return
  end

  -- Which tree the server was answering for *before* this call, so the
  -- message can tell "already running" apart from "moved to this repo".
  local before = serve.info()
  local url, err = serve.start(ctx.cfg)
  if not url then
    ctx.notify.warn(i18n.t("editor.serve.start-failed", { error = tostring(err) }))
    return
  end

  local root = (ctx.cfg.root or ""):gsub("\\", "/"):gsub("/+$", "")
  local repo = root:match("([^/]+)$") or root

  -- Naming the repository is the whole point of this message, not decoration.
  -- Without it, a server left running for another tree reported "already
  -- running at <url>" — and that URL answered for somewhere else, which read
  -- as a broken map rather than as the wrong repository.
  local state
  if not before then
    state = "listening"
  elseif (before.root or ""):gsub("\\", "/"):gsub("/+$", "") == root then
    state = "already-running"
  else
    state = "moved"
  end

  ctx.notify.info(
    i18n.t("editor.serve.state." .. state, { url = url, repo = repo, command = ctx.command_name })
  )
end

return M
