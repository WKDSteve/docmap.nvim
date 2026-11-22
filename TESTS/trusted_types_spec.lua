-- TESTS/trusted_types_spec.lua — the generated page runs under `require-trusted-types-for 'script'`.
--
-- docmap-desktop shows the map in a blob frame that inherits the CSP of its page, and a page that requires Trusted
-- Types must not assign a string to `innerHTML`, `outerHTML`, `insertAdjacentHTML` or `document.write` (nor use
-- `DOMParser`, `createContextualFragment`, `template.innerHTML`, which are sinks too). Two checks:
--
--   * the source of the page script has none of those assignments (the page builds its markup strings into nodes
--     with `markupNodes`, slice 01b_markup, and nowhere else);
--   * a real Chromium (Playwright) opens pages rendered from the fixtures, served with the CSP as a header, and
--     opens every tab, view, menu and popup it finds: a `securitypolicyviolation`, a console error or an uncaught
--     error is a failure (TESTS/browser/trusted_types_check.js). Without node, playwright or chromium that part
--     skips, as a browser sheet does.
-- @cache-inputs TESTS/browser/ TESTS/fixtures/keyword_page/ TESTS/fixtures/maps_page/ TESTS/fixtures/routes_page/ TESTS/fixtures/lookup_page/ lua/docmap/

---@param H table harness from TESTS/run.lua
return function(H)
  local ok, eq = H.ok, H.eq
  local root = (vim.fn.getcwd():gsub("\\", "/"))

  -- ── No string sink in the script ─────────────────────────────────────────
  local sinks = {
    "innerHTML",
    "outerHTML",
    "insertAdjacentHTML",
    "document.write",
    "DOMParser",
    "createContextualFragment",
  }
  local script = require("docmap.core.render.html.js")
  -- the comments of a slice may name the sinks (they explain why there are none): only code counts
  local code = script:gsub("//[^\n]*", "")
  for _, sink in ipairs(sinks) do
    ok(not code:find(sink, 1, true), "page script: no " .. sink)
  end
  eq(select(2, code:gsub("%.src%s*=", "")), 0, "page script: no assignment to a .src")

  -- ── The page under the policy ────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    H.skip("trusted types: no node on PATH")
    return
  end
  local docmap = require("docmap")
  local out = root .. "/TESTS/sheets/out"
  vim.fn.mkdir(out, "p")
  local pages = {
    { "tt-keyword", "keyword_page", "lua" },
    { "tt-maps", "maps_page", "lua/app" },
    { "tt-routes", "routes_page", "src" },
    { "tt-lookup", "lookup_page", "lua/look" },
  }
  local files = {}
  for _, p in ipairs(pages) do
    local fixture = root .. "/TESTS/fixtures/" .. p[2]
    local opts = require("docmap.config").build(fixture, { source = p[3] })
    local ir, findings = docmap.scan_full(opts)
    local path = out .. "/" .. p[1] .. ".html"
    local f = assert(io.open(path, "wb"))
    f:write(docmap.render.html(ir, findings, opts))
    f:close()
    files[#files + 1] = path
  end
  local cmd = { "node", root .. "/TESTS/browser/trusted_types_check.js" }
  vim.list_extend(cmd, files)
  local result = vim.system(cmd, { text = true, timeout = 600000 }):wait()
  if result.code == 77 then
    -- No node, playwright or chromium here: not applicable, said out loud (the harness has no skip).
    print("n/a  trusted types: " .. vim.trim(result.stdout or ""))
    return
  end
  ok(
    result.code == 0,
    "trusted types: the pages run clean under the policy — "
      .. vim.trim(result.stdout or "")
      .. vim.trim(result.stderr or "")
  )
end
