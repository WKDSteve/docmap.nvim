---@module 'docmap.bindings.usrcmds.here'
--- `:DocMap here [file[:line[-last]]] [--print]` — open the map at the function under the cursor.
---
--- The editor half of "from a place in the code to its node in the map": the position is resolved by
--- `core/find.lua` (`find.at`), and the page is opened with the fragment `find.fragment` builds, which is
--- `open` with a hash exactly like `graph`. With a range (`:'<,'>DocMap here`) the selection is the position.
---
--- `--print` writes the answer — `<node id>`, `<function key or ->`, `<fragment>`, tab separated — instead of
--- opening a browser: what a headless run, a script or another app calls to share this resolution.

local i18n = require("docmap.core.i18n")

local M = {}

---Where `--print` writes; replaced by a spec.
---@param text string
function M.out(text)
  io.stdout:write(text)
end

---@param ctx Docmap.Bindings.Ctx
---@param arg string `[file[:line[-last]]] [--print]`.
function M.run(ctx, arg)
  local print_only = false
  local spec = vim.trim((arg:gsub("%-%-print", function()
    print_only = true
    return ""
  end)))

  local file, first, last
  if spec ~= "" then
    file, first, last = require("docmap.core.find").parse_position(spec)
  else
    file = vim.api.nvim_buf_get_name(0)
  end
  if file == "" then
    ctx.notify.warn(i18n.t("editor.here.no-file"))
    return
  end
  if not first then
    if ctx.range then
      first, last = ctx.range[1], ctx.range[2]
    else
      first = vim.api.nvim_win_get_cursor(0)[1]
    end
  end

  local find = require("docmap.core.find")
  local hit = find.at(ctx.handle.ir(), file, first, last, ctx.cfg.root)
  if not hit then
    ctx.notify.warn(i18n.t("editor.here.no-node", { file = file }))
    return
  end

  local fragment = find.fragment(hit)
  if print_only then
    M.out(table.concat({ hit.id, hit.key or "-", fragment }, "\t") .. "\n")
    return
  end
  ctx.open_map(fragment)
end

return M
