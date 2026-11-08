-- TESTS/html_assets_spec.lua — the page's stylesheet and script live in their own modules
--
-- `render/html.lua` used to hold 10000 lines of CSS and JavaScript as two Lua long strings. They moved to
-- `render/html/css.lua` and `render/html/js/*.lua` (the script in ordered slices). What this file pins:
--
--   * every slice file is listed in `html/js/init.lua`, and every listed slice exists, so a new slice cannot be
--     forgotten (it would silently be missing from every page);
--   * the page carries the stylesheet and the whole script, unchanged by the join;
--   * the joined script is syntactically JavaScript (`node --check`), which the slices on their own are not:
--     they are cut between two statements and only the whole is a program. Without `node` that part skips.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/docmap/core/render/html"

  -- ── Every slice on disk is in the list, and the other way round ──────────
  local listed = {}
  for name in H.slurp(root .. "/js/init.lua"):gmatch('"docmap%.core%.render%.html%.js%.([%w_]+)"') do
    listed[#listed + 1] = name
  end
  local on_disk = {}
  for _, file in ipairs(vim.fn.glob(root .. "/js/*.lua", false, true)) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    if name ~= "init" then
      on_disk[#on_disk + 1] = name
    end
  end
  table.sort(on_disk)
  eq(
    vim.inspect(listed),
    vim.inspect(on_disk),
    "html assets: the slices listed are the slices on disk, in file-name order"
  )
  ok(#listed >= 2, "html assets: the script is more than one slice")

  -- ── The join is the script the page carries ──────────────────────────────
  local css = require("docmap.core.render.html.css")
  local js = require("docmap.core.render.html.js")
  local parts = {}
  for _, name in ipairs(listed) do
    local slice = require("docmap.core.render.html.js." .. name)
    ok(
      slice:sub(-1) == "\n",
      "html assets: slice " .. name .. " ends with a line end, so the join needs no separator"
    )
    parts[#parts + 1] = slice
  end
  eq(js, table.concat(parts), "html assets: the script is the slices joined as they are")
  ok(js:find("^%(function%(%){") ~= nil, "html assets: the script opens its one function")
  ok(js:find("}%)%(%);\n$") ~= nil, "html assets: the script closes it and calls it")
  ok(css:find("^:root{") ~= nil, "html assets: the stylesheet starts with the root variables")

  local dir = (H.canonical(vim.fn.tempname()))
  H.write(
    dir .. "/lua/core/init.lua",
    { "---@module 'core'", "--- A module.", "local M = {}", "return M" }
  )
  local ir = require("docmap.core.scan").scan(require("docmap.config").build(dir))
  local html = require("docmap.core.render.html").render(ir, {}, {})
  ok(html:find(js, 1, true) ~= nil, "html assets: the page carries the whole script")
  ok(html:find(css, 1, true) ~= nil, "html assets: the page carries the whole stylesheet")

  -- ── The whole is a program ───────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(js, "\n", { plain = true }))
  local result = vim.system({ "node", "--check", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  ok(
    result.code == 0,
    "html assets: the joined script parses — " .. vim.trim(result.stderr or "")
  )
end
