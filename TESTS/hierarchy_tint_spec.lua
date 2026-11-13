-- TESTS/hierarchy_tint_spec.lua — the tint of the Modules view
--
-- One switch tints the Modules boxes by a measure of everything below each box: the share of documented or
-- tested functions, or the density of FIX and of TODO/HACK/PERF markers. It is an encoding, not a layout, and it
-- is computed in the page from what the payload already carries.
--
-- Two halves:
--   * the arithmetic (totals over a subtree, the steps, what a box prints) runs here for real: the maps slice
--     is evaluated in `node` with a small tree in place of the page (skipped without `node`);
--   * the wiring (the switch, the link, the legend, the export) is pinned as text, like the other page specs.
-- The behaviour in a real window is TESTS/sheets/hierarchy-tint.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq

  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "tint: " .. msg)
  end

  -- ── The wiring ───────────────────────────────────────────────────────────
  has(
    '<select id="htint" aria-label="Tint the Modules boxes">',
    "one switch, a native select (keyboard for free)"
  )
  has('<option value="">off</option>', "off is a choice, and the first one")
  has("tint: null,", "off is the default state")
  has(
    'if((s.view || "modules") === "modules" && s.tint) parts.push("tint=" + encodeURIComponent(s.tint));',
    "the link carries the tint in the Modules view only, and only when on"
  )
  has(
    'else if(k === "tint") s.tint = (v === "doc" || v === "test" || v === "fix" || v === "debt") ? v : null;',
    "an unknown tint in a link is no tint"
  )
  has("    applyTint();\n", "every draw paints the tint (reconcile resets a box)")
  has("items = items.concat(tintLegend());", "the legend of the view carries the steps")
  has("var tintLine = tintLegendText();", "the export carries the legend line")
  has(
    "'fill=\"'+paint.rgb+'\" fill-opacity=\"'+paint.opacity+'\"/>'",
    "the export draws the tint as colour plus opacity"
  )
  has('"hier.tint":', "the switch explains itself")
  has(
    'document.getElementById("htintwrap").style.display = (s.view || "modules") === "modules" ? "" : "none";',
    "the switch shows in the Modules view only"
  )
  -- both themes define the colour, and the print sheet too
  local _, n = src:gsub("%-%-tint:%d+,%d+,%d+;", "")
  eq(n, 5, "tint: the colour is defined for light, dark (media and attribute) and print")

  -- The payload is untouched: the tint reads `functions`, `markers` and `stats`.
  local html_lua = H.slurp((vim.fn.getcwd():gsub("\\", "/")) .. "/lua/docmap/core/render/html.lua")
  ok(html_lua:find("tint", 1, true) ~= nil, "tint: the control is in the page")
  ok(
    (html_lua:match("local payload = json.encode%(%{(.-)\n  %}%)") or ""):find("tint", 1, true)
      == nil,
    "tint: nothing about it rides in the payload"
  )

  -- ── The arithmetic, in node ──────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.10b_maps")
  local program = table.concat({
    "var nodes = [",
    ' { id: "r", children: ["a", "b", "e"], stats: { lines: 3000 },',
    "   functions: [ { documented: true, tested: true } ] },",
    ' { id: "a", children: [], stats: { lines: 1000 }, markers: [ { kind: "FIX" }, { kind: "TODO" }, { kind: "NOTE" } ],',
    "   functions: [ { documented: false, tested: true }, { documented: false, tested: false },",
    "                { documented: false, internal: true, tested: false } ] },",
    ' { id: "b", children: [], stats: { lines: 2000 }, markers: [ { kind: "PERF" }, { kind: "HACK" }, { kind: "FIX" },',
    '   { kind: "FIX" }, { kind: "FIX" }, { kind: "FIX" }, { kind: "FIX" }, { kind: "FIX" } ],',
    "   functions: [ { documented: true, tested: false }, { documented: true, tested: false } ] },",
    ' { id: "e", children: [], stats: { lines: 0 }, functions: [] }',
    "];",
    "var byId = {}; nodes.forEach(function(n){ byId[n.id] = n; });",
    'var state = { tab: "hierarchy", view: "modules", tint: "doc" };',
    "var hstage = { classList: { toggle: function(){} } }, hboxes = {};",
    "var document = { getElementById: function(){ return { addEventListener: function(){} }; } };",
    "function esc(s){ return s; } function navigate(){}",
    slice,
    "var out = {};",
    '["doc", "test", "fix", "debt"].forEach(function(mode){',
    '  ["r", "a", "b", "e"].forEach(function(id){',
    "    var t = tintOf(id, mode); out[mode + ':' + id] = t.level + '|' + t.text + '|' + t.tip;",
    "  });",
    "});",
    'out.mode = tintMode(); state.view = "deps"; out.otherView = String(tintMode());',
    'state.view = "modules"; state.tint = "nonsense"; out.unknown = String(tintMode());',
    'state.tint = "fix"; out.legend = tintLegendText();',
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "tint: the slice runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}")

  -- documented: @internal functions are left out of the total (as in the Documentation panel)
  eq(
    got["doc:a"],
    "4|0%|0 of 2 functions documented (0%)",
    "tint: an internal function is not counted"
  )
  eq(
    got["doc:b"],
    "0|100%|2 of 2 functions documented (100%)",
    "tint: a full share keeps the plain box"
  )
  eq(
    got["doc:r"],
    "1|60%|3 of 5 functions documented (60%)",
    "tint: a box stands for its whole subtree"
  )
  eq(
    got["doc:e"],
    "null|–|no functions to measure",
    "tint: nothing to measure is said, not drawn as 0%"
  )
  -- tested: every function counts
  eq(
    got["test:a"],
    "3|33%|1 of 3 functions tested (33%)",
    "tint: tested counts internal functions too"
  )
  eq(got["test:r"], "3|33%|2 of 6 functions tested (33%)", "tint: tested over the subtree")
  -- the FIX family apart from TODO/HACK/PERF; NOTE is neither
  eq(
    got["fix:a"],
    "2|1|1 FIX marker in 1000 lines (1.0 per 1,000)",
    "tint: one FIX per 1,000 lines is step 2"
  )
  eq(
    got["fix:b"],
    "3|6|6 FIX markers in 2000 lines (3.0 per 1,000)",
    "tint: three per 1,000 is step 3"
  )
  eq(got["fix:r"], "2|7|7 FIX markers in 3000 lines (2.3 per 1,000)", "tint: FIX over the subtree")
  eq(
    got["debt:a"],
    "2|1|1 TODO/HACK/PERF marker in 1000 lines (1.0 per 1,000)",
    "tint: TODO counts as debt, NOTE and FIX do not"
  )
  eq(
    got["debt:b"],
    "2|2|2 TODO/HACK/PERF markers in 2000 lines (1.0 per 1,000)",
    "tint: PERF and HACK count as debt"
  )
  eq(got["debt:e"], "null|–|no lines to measure", "tint: no lines, no density")
  -- the mode
  eq(got.mode, "doc", "tint: on in the Modules view")
  eq(got.otherView, "null", "tint: off in every other view")
  eq(got.unknown, "null", "tint: an unknown mode is off")
  ok(
    got.legend:find("Tint: FIX markers per 1,000 lines", 1, true) ~= nil
      and got.legend:find("none · under 1 · 1 to 3 · 3 to 6 · 6 and more", 1, true) ~= nil,
    "tint: the legend line states the thresholds"
  )
end
