---@module 'docmap.bindings.usrcmds.helptags'
--- `:DocMap helptags` — regenerate this plugin's own `doc/tags`.
---
--- Mostly a convenience for working *on* the plugin: every plugin manager runs
--- `:helptags` on install and update, so a user who installed normally never
--- needs this. A local checkout on `runtimepath` — the way the plugin is
--- developed — has no such step, and `:help docmap.nvim` then fails with
--- a "Sorry, no help for" that looks like the docs are missing rather than
--- unindexed.
---
--- Finds the directory through `nvim_get_runtime_file` rather than by walking
--- up from this file: the answer wanted is "where is the `doc/` Neovim will
--- actually search", which is a runtimepath question, and a path derived from
--- `debug.getinfo` would be right about the checkout and wrong about the
--- installation whenever the two differ.
---
--- `doc/tags` is in `.gitignore` — it is a generated index over committed
--- `.txt` sources, and committing it would put a file in the tree that every
--- clone regenerates differently.

local i18n = require("docmap.core.i18n")

local M = {}

---@param ctx Docmap.Bindings.Ctx
function M.run(ctx)
  local found = vim.api.nvim_get_runtime_file("doc/docmap.txt", false)
  if #found == 0 then
    ctx.notify.warn(i18n.t("editor.helptags.not-found"), {
      i18n.t("editor.helptags.not-found-detail"),
    })
    return
  end

  local doc_dir = vim.fs.dirname(found[1])
  local ok, err = pcall(vim.cmd.helptags, doc_dir)
  if not ok then
    ctx.notify.warn(
      i18n.t("editor.helptags.write-failed", { dir = doc_dir, error = tostring(err) })
    )
    return
  end

  ctx.notify.info(i18n.t("editor.helptags.wrote", { dir = doc_dir }))
end

return M
