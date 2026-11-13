-- TESTS/coupling_view_spec.lua — the Coupling view of the Hierarchy: modules as a scatter plot, fan-out across
-- and fan-in up, with four named corners.
--
-- Two halves, as in hierarchy_tint_spec.lua:
--   * the arithmetic (which corner, which modules, in which order, where each dot goes) runs here for real:
--     the maps slice is evaluated in `node` with a small tree in place of the page (skipped without `node`);
--   * the wiring (the button, the view, the hand-off, the explanation) is pinned as text.
-- The behaviour in a real window is TESTS/sheets/coupling-view.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq

  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "coupling: " .. msg)
  end

  -- ── The wiring ───────────────────────────────────────────────────────────
  has('data-view="coupling" data-explain="view.coupling">Coupling</button>', "a Coupling button")
  has("coupling: 1 };", "a known view (an unknown one falls back to Modules)")
  has(
    'function isAltView(v){ return v === "tree" || v === "treemap" || v === "coupling"; }',
    "it draws outside the zooming diagram, like Tree and Treemap"
  )
  has('else if(view === "coupling") drawCoupling(hcenter);', "drawAltView hands it off")
  has('"view.coupling":', "the view explains itself")
  has("var COUPLING_HIGH = 5;", "the threshold is one stated number")
  has(
    "': a module is a hub, tangle or pass-through from ' + COUPLING_HIGH + ' on</span>'",
    "the bar says where the lines are"
  )
  has(
    'if(dot && byId[dot.dataset.id]) navigate({ tab: "tree", id: dot.dataset.id });',
    "a click opens the module"
  )
  has('aria-live="polite"', "the readout is announced")
  -- nothing new in the payload: the plot reads `requires` and `required_by`
  local html_lua = H.slurp((vim.fn.getcwd():gsub("\\", "/")) .. "/lua/docmap/core/render/html.lua")
  ok(
    (html_lua:match("local payload = json.encode%(%{(.-)\n  %}%)") or ""):find("coupling", 1, true)
      == nil,
    "coupling: nothing about it rides in the payload"
  )

  -- ── The arithmetic, in node ──────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.10b_maps")
  local program = table.concat({
    "function ids(n, p){ var a = []; for(var i = 0; i < n; i++) a.push(p + i); return a; }",
    "var nodes = [",
    ' { id: "r", children: ["hub", "tangle", "pass", "leafA", "leafB", "alone", "sub"],',
    "   requires: [], required_by: [] },",
    ' { id: "hub", module: "app.hub", requires: ids(1, "x"), required_by: ids(7, "y") },',
    ' { id: "tangle", requires: ids(5, "x"), required_by: ids(5, "y") },',
    ' { id: "pass", requires: ids(9, "x"), required_by: ids(4, "y") },',
    ' { id: "leafA", requires: ids(1, "x"), required_by: ids(1, "y") },',
    ' { id: "leafB", requires: ids(1, "x"), required_by: ids(1, "y") },',
    ' { id: "alone", requires: [], required_by: [] },',
    ' { id: "sub", children: ["deep"], requires: [], required_by: ids(2, "y") },',
    ' { id: "deep", requires: ids(4, "x"), required_by: [] }',
    "];",
    "var byId = {}; nodes.forEach(function(n){ byId[n.id] = n; });",
    'var state = { tab: "hierarchy", view: "coupling", hidden: [] };',
    "var hstage = { classList: { toggle: function(){} } }, hboxes = {};",
    "var haltBody = { addEventListener: function(){} }, haltBar = {};",
    "var document = { getElementById: function(){ return { addEventListener: function(){} }; } };",
    "function esc(s){ return s; } function navigate(){} function isHidden(){ return false; }",
    slice,
    "var out = {};",
    "out.corners = [couplingCorner(5, 4), couplingCorner(5, 5), couplingCorner(4, 5), couplingCorner(4, 4),",
    "  couplingCorner(0, 0)].join(',');",
    "var rows = couplingRows('r');",
    "out.order = rows.map(function(r){ return r.id + ':' + r.corner; }).join(' ');",
    "out.sub = couplingRows('sub').map(function(r){ return r.id; }).join(' ');",
    "out.text = couplingText(rows[1]);",
    "out.ticks = couplingTicks(9).join(',') + '|' + couplingTicks(120).join(',');",
    "var L = couplingLayout(rows, 600, 400);",
    "function at(id){ return L.dots.filter(function(d){ return d.row.id === id; })[0]; }",
    "out.max = L.maxIn + '/' + L.maxOut;",
    "out.frame = [L.left, L.top, L.right, L.bottom].join(',');",
    "out.split = Math.round(L.x(5)) + ',' + Math.round(L.y(5));",
    "out.hubLeftOfLine = at('hub').x < L.x(5) && at('hub').y < L.y(5);",
    "out.tangleOnLines = Math.round(at('tangle').x) === Math.round(L.x(5)) && Math.round(at('tangle').y) === Math.round(L.y(5));",
    "out.passRightBelow = at('pass').x > L.x(5) && at('pass').y > L.y(5);",
    "var a = at('leafA'), b = at('leafB');",
    "out.sameCell = a.x === L.x(1) && a.y === L.y(1);",
    "out.apart = Math.round(Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)) * 10) / 10;",
    "out.inside = L.dots.every(function(d){ return d.x >= L.left - 6 && d.x <= L.right + 6 && d.y >= L.top - 6 && d.y <= L.bottom + 6; });",
    "var small = couplingLayout([rows[4]], 600, 400);",
    "out.smallMax = small.maxIn + '/' + small.maxOut;",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "coupling: the slice runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}")

  eq(got.corners, "hub,tangle,pass,leaf,leaf", "coupling: 5 is many, on either axis")
  eq(
    got.order,
    "tangle:tangle hub:hub pass:pass deep:leaf sub:leaf leafA:leaf leafB:leaf",
    "coupling: the expensive corners first, then the larger number, then the id; a module without an edge is left out"
  )
  eq(got.sub, "deep sub", "coupling: the center and what is below it, the larger number first")
  eq(
    got.text,
    "app.hub · required by 7 · requires 1 · hub",
    "coupling: a dot says the module, both numbers and its corner"
  )
  eq(got.ticks, "0,1,2,5|0,1,2,5,10,20,50,100", "coupling: the ticks stop at the largest value")
  eq(got.max, "7/9", "coupling: each axis runs to its own largest value")
  eq(got.frame, "46,14,584,366", "coupling: the plot leaves room for the two axes")
  ok(got.hubLeftOfLine, "coupling: a hub sits above the fan-in line and left of the fan-out line")
  ok(
    got.tangleOnLines,
    "coupling: a module at 5/5 sits on both lines (the lines are where many begins)"
  )
  ok(
    got.passRightBelow,
    "coupling: a pass-through sits right of the fan-out line and below the fan-in line"
  )
  ok(got.sameCell, "coupling: the first module of a cell sits on the cell")
  eq(
    got.apart,
    5.2,
    "coupling: a second module with the same numbers gets a dot of its own beside it"
  )
  ok(got.inside, "coupling: every dot is inside the frame")
  eq(
    got.smallMax,
    "5/5",
    "coupling: the lines are always in the plot, however small the numbers are"
  )
end
