-- TESTS/layers_view_spec.lua — the Layers view of the Hierarchy: the tree in the bands its `layers` rules imply,
-- every require that breaks a rule as a red arrow.
--
-- Three parts:
--   * the derivation (`core/layers.lua`: which layer, which band, what is no order, which require breaks a rule)
--     runs in Lua, against this repository's own four rules and against rule sets that form no order;
--   * the payload contract: a rendered page carries `layers`, and carries none without rules;
--   * the page: the wiring is pinned as text, and the layout (where every frame and box goes, which edges are
--     drawn) runs in `node` with a small payload in place of the page (skipped without `node`).
-- The behaviour in a real window is TESTS/sheets/layers-view.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq
  local layers = require("docmap.core.layers")
  local cwd = (vim.fn.getcwd():gsub("\\", "/"))

  ---A small IR: module paths, and requires between them.
  ---@param modules string[] Module paths; a trailing `/` marks a namespace.
  ---@param requires string[][] Pairs `{ from, to }` of module paths.
  ---@return Docmap.IR
  local function tree(modules, requires)
    local ir = { nodes = {}, order = {}, edges = {}, root = "root", meta = {} }
    for _, m in ipairs(modules) do
      local namespace = m:sub(-1) == "/"
      local name = namespace and m:sub(1, -2) or m
      local id = "lua/" .. name:gsub("%.", "/") .. (namespace and "" or ".lua")
      ir.nodes[id] = { id = id, module = name, kind = namespace and "namespace" or "file" }
      ir.order[#ir.order + 1] = id
    end
    for i, pair in ipairs(requires) do
      ir.edges[#ir.edges + 1] = {
        kind = "require",
        from = "lua/" .. pair[1]:gsub("%.", "/") .. ".lua",
        to = "lua/" .. pair[2]:gsub("%.", "/") .. ".lua",
        line = i,
      }
    end
    ---@diagnostic disable-next-line: return-type-mismatch
    return ir
  end
  local function id(m)
    return "lua/" .. m:gsub("%.", "/") .. ".lua"
  end
  local function units(map)
    local parts = {}
    for _, u in ipairs(map.units) do
      parts[#parts + 1] = u.id
        .. ":"
        .. u.band
        .. (u.siblings and ":sib" or "")
        .. ":"
        .. #u.modules
    end
    return table.concat(parts, " ")
  end
  local function loops(map)
    local parts = {}
    for _, group in ipairs(map.loops) do
      parts[#parts + 1] = table.concat(group, "+")
    end
    return table.concat(parts, " ")
  end

  -- ── This repository's own rules ──────────────────────────────────────────
  local own = vim.json.decode(assert(H.slurp(cwd .. "/.docmap.json"))).layers
  eq(#own, 4, "layers: this repository declares four rules (three pairs and the sibling rule)")
  local ir = tree({
    "docmap",
    "docmap.config",
    "docmap.core.check",
    "docmap.core.scan",
    "docmap.core.lang_registry",
    "docmap.core.lang/",
    "docmap.core.lang.js",
    "docmap.core.lang.ecma",
    "docmap.core.lang.python",
    "docmap.editor.browse",
    "docmap.bindings.usrcmds",
  }, {
    { "docmap", "docmap.core.check" },
    { "docmap.editor.browse", "docmap.core.scan" },
    { "docmap.core.check", "docmap.editor.browse" },
    { "docmap.core.scan", "docmap.bindings.usrcmds" },
    { "docmap.core.lang_registry", "docmap.core.lang.js" },
    { "docmap.core.lang.js", "docmap.core.lang.ecma" },
    { "docmap.core.lang.js", "docmap.core.lang.python" },
    { "docmap.core.lang.js", "docmap.core.scan" },
  })
  local map = assert(layers.map(ir, own))
  eq(
    units(map),
    "docmap.core:0:3 docmap.bindings:1:1 docmap.core.lang:1:sib:3 docmap.editor:1:1",
    "layers: the core is the base; editor, bindings and the backends sit one band above it"
  )
  eq(map.bands, 2, "layers: three pair rules from one layer make two bands")
  eq(
    table.concat(map.units[1].modules, " "),
    id("docmap.core.check")
      .. " "
      .. id("docmap.core.scan")
      .. " "
      .. id("docmap.core.lang_registry"),
    "layers: a module goes to the longest prefix it sits under, on a segment boundary "
      .. "(lang_registry is core, not core.lang), and a namespace is no module"
  )
  eq(
    table.concat(map.unassigned, " "),
    id("docmap") .. " " .. id("docmap.config"),
    "layers: what no rule names is listed, not dropped"
  )
  eq(
    table.concat(map.shared, " "),
    id("docmap.core.lang.ecma"),
    "layers: a module of an allow list is marked as a shared target"
  )
  eq(loops(map), "", "layers: these rules form an order")
  local broken = {}
  for _, v in ipairs(map.violations) do
    broken[#broken + 1] = ("%s>%s %s|%s #%d"):format(
      ir.nodes[v.from].module,
      ir.nodes[v.to].module,
      v.from_layer,
      v.to_layer,
      v.rule
    )
  end
  eq(
    table.concat(broken, "\n"),
    table.concat({
      "docmap.core.check>docmap.editor.browse docmap.core|docmap.editor #1",
      "docmap.core.scan>docmap.bindings.usrcmds docmap.core|docmap.bindings #2",
      "docmap.core.lang_registry>docmap.core.lang.js docmap.core|docmap.core.lang #3",
      "docmap.core.lang.js>docmap.core.lang.python docmap.core.lang.js|docmap.core.lang.python #4",
    }, "\n"),
    "layers: the four requires that break a rule, each with its two layers and its rule; a require of a "
      .. "shared module and a require downwards break none"
  )
  eq(map.violations[1].line, 3, "layers: a broken require keeps its line")
  eq(
    #map.rules == 4 and map.rules[1].why,
    own[1].why,
    "layers: the rules ride along as declared, with their reason"
  )

  -- the check asks the same function, so the picture and the finding cannot disagree
  local check_src = assert(H.slurp(cwd .. "/lua/docmap/core/check.lua"))
  ok(
    check_src:find('local crossing = require("docmap.core.layers").crossing', 1, true) ~= nil,
    "layers: the layer-violation check uses the crossing test of core/layers.lua"
  )
  ok(
    check_src:find("local function crossing", 1, true) == nil,
    "layers: and keeps no second copy of it"
  )
  local function cross(src, dst, rule)
    local a, b = layers.crossing(src, dst, rule)
    return tostring(a) .. "|" .. tostring(b)
  end
  eq(cross("a.x", "a.b.y", { from = "a", to = "a.b" }), "a|a.b", "layers: crossing, the pair form")
  eq(
    cross("a.b.x", "a.b.y", { from = "a", to = "a.b" }),
    "nil|nil",
    "layers: crossing does not fire inside the target layer"
  )
  eq(cross("p.a.x", "p.b", { siblings = "p" }), "p.a|p.b", "layers: crossing, the sibling form")
  eq(
    cross("p.a.x", "p.b", { siblings = "p", allow = { "p.b" } }),
    "nil|nil",
    "layers: an allowed target breaks no rule"
  )

  -- ── Rule sets and their order ────────────────────────────────────────────
  local four = tree({ "a.x", "b.x", "c.x", "d.x" }, {})
  local chain = assert(layers.map(four, { { from = "a", to = "b" }, { from = "b", to = "c" } }))
  eq(units(chain), "a:0:1 b:1:1 c:2:1", "layers: a chain of rules is a band per step")
  local longest = assert(
    layers.map(
      four,
      { { from = "a", to = "c" }, { from = "a", to = "b" }, { from = "b", to = "c" } }
    )
  )
  eq(
    units(longest),
    "a:0:1 b:1:1 c:2:1",
    "layers: the band is the longest way up, not the first rule read"
  )
  local mutual = assert(layers.map(four, { { from = "a", to = "b" }, { from = "b", to = "a" } }))
  eq(
    units(mutual) .. " | " .. loops(mutual) .. " | " .. mutual.bands,
    "a:0:1 b:0:1 | a+b | 1",
    "layers: two layers that forbid each other have no order: one band, and the loop is named"
  )
  local circle = assert(layers.map(four, {
    { from = "a", to = "b" },
    { from = "b", to = "c" },
    { from = "c", to = "a" },
    { from = "c", to = "d" },
  }))
  eq(
    units(circle) .. " | " .. loops(circle) .. " | " .. circle.bands,
    "a:0:1 b:0:1 c:0:1 d:1:1 | a+b+c | 2",
    "layers: a circle of three shares a band, and what one of them may not reach is still above it"
  )
  local only_siblings = assert(layers.map(four, { { siblings = "a" } }))
  eq(
    units(only_siblings) .. " | " .. #only_siblings.unassigned,
    "a:0:sib:1 | 3",
    "layers: a sibling rule alone is one layer on one band"
  )
  eq(layers.map(four, {}), nil, "layers: no rule, no picture")
  eq(layers.map(four, nil), nil, "layers: no rules at all, no picture")
  eq(
    layers.map(four, { { why = "nothing" } }),
    nil,
    "layers: a rule that names no prefix adds no layer"
  )

  -- ── The payload contract ─────────────────────────────────────────────────
  local docmap = require("docmap")
  local function payload_of(fixture_opts)
    local scanned, findings = docmap.scan_full(fixture_opts)
    local html = docmap.render.html(scanned, findings, fixture_opts)
    local i = html:find('id="ir"', 1, true)
    local from = html:find(">", i, true) + 1
    local to = html:find("</script>", from, true) - 1
    local raw = html:sub(from, to):gsub("<" .. string.char(92) .. "/", "</")
    return vim.json.decode(raw, { luanil = { object = true, array = true } }), findings
  end
  local fixture = cwd .. "/TESTS/fixtures/maps_page"
  local opts = require("docmap.config").build(fixture, { source = "lua/app" })
  local payload, findings = payload_of(opts)
  local L = payload.layers
  ok(type(L) == "table", "layers payload: a page of a tree with rules carries `layers`")
  eq(
    units(L),
    "app.util:0:2 app.core:1:2 app.ui:2:2",
    "layers payload: the fixture's two rules make three bands"
  )
  eq(L.bands, 3, "layers payload: the number of bands")
  eq(
    table.concat(L.unassigned, " "),
    "lua/app",
    "layers payload: the root module is named by no rule"
  )
  eq(
    type(L.shared) == "table" and #L.shared,
    0,
    "layers payload: no allow list, no shared module (an empty list, not null)"
  )
  eq(type(L.loops) == "table" and #L.loops, 0, "layers payload: no loop (an empty list, not null)")
  eq(#L.violations, 1, "layers payload: the one require that breaks a rule")
  eq(
    table.concat({
      L.violations[1].from,
      L.violations[1].to,
      L.violations[1].from_layer,
      L.violations[1].to_layer,
    }, " "),
    "lua/app/core/store.lua lua/app/ui/window.lua app.core app.ui",
    "layers payload: a broken require names its two modules by node id and its two layers"
  )
  eq(
    L.rules[L.violations[1].rule].why,
    "the core knows no window",
    "layers payload: and points at its rule"
  )
  local reported = 0
  for _, f in ipairs(findings) do
    if f.check == "layer-violation" then
      reported = reported + 1
    end
  end
  eq(reported, #L.violations, "layers payload: as many broken requires as layer-violation findings")
  local bare = require("docmap.config").build(fixture, { source = "lua/app" })
  bare.layers = nil
  eq(payload_of(bare).layers, nil, "layers payload: without rules the page carries no `layers`")

  -- ── The wiring ───────────────────────────────────────────────────────────
  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "layers: " .. msg)
  end
  has('data-view="layers" data-explain="view.layers">Layers</button>', "a Layers button")
  has("rings: 1, layers: 1, coupling: 1 };", "a known view")
  has('else if(view === "layers") built = layoutLayers();', "drawHierarchy hands it off")
  has('function isMapView(v){ return v === "rings" || v === "layers"; }', "a map of the whole tree")
  has('"view.layers":', "the view explains itself")
  has(
    'layers = require("docmap.core.layers").map(ir, opts.layers),',
    "the payload carries the derivation"
  )
  has('if(view === "layers"){', "a map without rules gets a message of its own")
  has("No layers are declared for this map.", "which says what is missing")
  has(
    'edges.push({ from: v.from, to: v.to, cls: "hedge hedge-viol", marker: "viol", top: true,',
    "a broken require is an edge of its own class, over the boxes"
  )
  has(
    'if(svgTop) svgTop.classList.add("settling");',
    "the arrow over the boxes waits with the other edges while the boxes move"
  )
  has(
    "if(svgTop) hstage.appendChild(svgTop);",
    "the layer over the boxes is the last child of the stage"
  )
  has(
    'hstage.querySelectorAll("svg .hedge").forEach(function(p){',
    "hover reaches the edges of both layers"
  )
  has(
    'if(svgTop) svgTop.querySelectorAll(".hedge").forEach(edgeOut);',
    "the SVG export carries the edges drawn over the boxes"
  )
  has('svg.querySelectorAll(".hband, .hunit").forEach(function(el){', "and the bands and frames")
  has(
    'if(state.view === "layers"){ leaveForTree(box); return; }',
    "a second click opens the module: the view has no center to move"
  )
  has(
    ".hedge-viol{stroke:var(--error);stroke-width:2.5;opacity:.95}",
    "a broken require is heavier"
  )
  has("#hsvg .hedge.hedge-quiet{opacity:0}", "every other require waits for a pointed-at box")

  -- ── The layout, in node ──────────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.10b_maps")
  local program = table.concat({
    "var PAD = 20, BOX_W = 168, BOX_H = 52, GAP_X = 16;",
    "var IR = { nodes: [], edges: [], root: 'r' }, byId = {}, depOut = {}, depIn = {}, findByNode = {};",
    "function mod(id, name){ var n = { id: id, module: name, name: id, kind: 'file' }; IR.nodes.push(n); byId[id] = n; }",
    "function req(from, to){ IR.edges.push({ kind: 'require', from: from, to: to, to_module: (byId[to] || {}).module, line: 7 }); }",
    'var state = { tab: "hierarchy", view: "layers", hidden: [] };',
    "var hstage = { classList: { toggle: function(){} } }, hboxes = {};",
    "var haltBody = { addEventListener: function(){} }, haltBar = {};",
    "var document = { getElementById: function(){ return { addEventListener: function(){} }; },",
    "  createElement: function(tag){ return { tag: tag, kids: [], appendChild: function(k){ this.kids.push(k); },",
    "    addEventListener: function(){} }; },",
    "  createTextNode: function(t){ return { text: t }; } };",
    "function esc(s){ return s; } function navigate(){} function isHidden(){ return false; }",
    slice,
    "var out = {};",
    "out.none = layoutLayers().count;",
    "out.cols = [1, 2, 5, 6, 31, 72, 500].map(layerCols).join(',');",
    -- two bands: `base` below, `ui` and `io` above (io with nine modules), one module no rule names
    "['b1', 'b2', 'b3'].forEach(function(id){ mod(id, 'app.base.' + id); });",
    "['u1', 'u2'].forEach(function(id){ mod(id, 'app.ui.' + id); });",
    "var io = []; for(var k = 0; k < 9; k++){ mod('i' + k, 'app.io.i' + k); io.push('i' + k); }",
    "mod('top', 'app');",
    "req('u1', 'b1'); req('b2', 'u2'); req('b2', 'b3'); req('top', 'u1'); req('b1', 'gone');",
    "IR.layers = { rules: [{ from: 'app.base', to: 'app.ui', why: 'the base knows no window' },",
    "    { from: 'app.base', to: 'app.io' }, { from: 'app.base', to: 'app.ui' }],",
    "  units: [{ id: 'app.base', band: 0, siblings: false, modules: ['b1', 'b2', 'b3'] },",
    "    { id: 'app.io', band: 1, siblings: true, modules: io },",
    "    { id: 'app.ui', band: 1, siblings: false, modules: ['u1', 'u2', 'stale'] }],",
    "  bands: 2, unassigned: ['top'], shared: ['i0'], loops: [],",
    -- the same require breaks two rules: one arrow, two reasons
    "  violations: [{ from: 'b2', to: 'u2', from_layer: 'app.base', to_layer: 'app.ui', rule: 1 },",
    "    { from: 'b2', to: 'u2', from_layer: 'app.base', to_layer: 'app.ui', rule: 3 }] };",
    "var built = layoutLayers();",
    "var P = built.positions;",
    "out.count = built.count + '/' + built.truncated;",
    "out.shown = JSON.stringify(layerShown);",
    "out.path = built.path;",
    "function apart(pos){ var ids = Object.keys(pos), bad = 0;",
    "  for(var i = 0; i < ids.length; i++) for(var j = i + 1; j < ids.length; j++){",
    "    var p = pos[ids[i]], q = pos[ids[j]];",
    "    if(Math.abs(p.x - q.x) < BOX_W && Math.abs(p.y - q.y) < BOX_H) bad++; }",
    "  return bad; }",
    "function inside(b){ return Object.keys(b.positions).every(function(id){ var p = b.positions[id];",
    "  return p.x >= PAD && p.y >= PAD && p.x + BOX_W <= b.extent.w - PAD && p.y + BOX_H <= b.extent.h - PAD; }); }",
    "out.overlaps = apart(P); out.inside = inside(built);",
    "out.above = P.u1.y < P.b1.y && P.i0.y < P.b1.y && P.b1.y < P.top.y;",
    "out.sameBand = P.u1.y === P.i0.y;",
    "out.ioGrid = [P.i0, P.i2, P.i3, P.i8].map(function(p){ return (p.x - P.i0.x) + ':' + (p.y - P.i0.y); }).join(' ');",
    "out.ioLeftOfUi = P.i0.x < P.u1.x;",
    "out.edges = built.edges.map(function(e){ return e.from + '>' + e.to + ':' + e.cls.split(' ').pop() + (e.top ? '^' : ''); }).join(' ');",
    "out.violLabel = built.edges[built.edges.length - 1].label;",
    -- what the view draws below and over the edges
    "function fake(){ var made = []; return { made: made, svg: { appendChild: function(el){ made.push(el); } } }; }",
    "document.createElementNS = function(ns, tag){ return { tag: tag, a: {}, setAttribute: function(k, v){ this.a[k] = v; } }; };",
    "var below = fake(); built.decor(below.svg, 'ns');",
    "out.decor = below.made.map(function(el){ return el.a['class']; }).join(' | ');",
    "var over = fake(); built.overlay(over.svg, 'ns');",
    "out.overlay = over.made.map(function(el){ return el.textContent; }).join(' | ');",
    -- what a box says
    "function box(){ return { kids: [], cls: [], dataset: {}, title: '', _spec: { title: 'T' },",
    "  classList: { add: function(){} }, querySelector: function(){ return null; }, appendChild: function(k){ this.kids.push(k); } }; }",
    "Object.keys(P).forEach(function(id){ var b = box(); b.classList.add = function(c){ b.cls.push(c); }; hboxes[id] = b; });",
    "built.paint();",
    "function said(id){ var b = hboxes[id]; return b.cls.join(',') + '|' + (b.kids[0] ? b.kids[0].textContent : '') + '|' + b.dataset.layer + '|' + b.title; }",
    "out.b2 = said('b2'); out.u2 = said('u2'); out.i0 = said('i0'); out.b1 = said('b1'); out.top = said('top');",
    "out.short = [mapShortName('b1', 'app.base'), mapShortName('top', 'app'), mapShortName('b1', 'app.ba'), mapShortName('b1', undefined)].join(' ');",
    "out.note = layerNote().kids[0].text; out.noteButton = layerNote().kids.length;",
    -- a rule set without an order, and none broken
    "IR.layers.violations = []; IR.layers.loops = [['app.io', 'app.ui']];",
    "layoutLayers(); out.loopNote = layerNote().kids[0].text; out.loopButton = layerNote().kids.length;",
    -- the cap: a layer shows its first modules, the ones in a broken rule first
    "IR.layers.loops = []; var many = [];",
    "for(var m = 0; m < 700; m++){ mod('m' + m, 'app.base.m' + m); many.push('m' + m); }",
    "IR.layers.units[0].modules = many; IR.layers.unassigned = [];",
    "IR.layers.violations = [{ from: 'm699', to: 'u2', from_layer: 'app.base', to_layer: 'app.ui', rule: 1 }];",
    "var capped = layoutLayers();",
    "out.capped = capped.count + ' ' + capped.truncated + ' ' + !!capped.positions.m699 + ' ' + !!capped.positions.m650 +",
    "  ' ' + apart(capped.positions) + ' ' + inside(capped);",
    "out.cappedNote = capped.truncNote;",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "layers: the slice runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}")

  eq(got.none, 0, "layers: a page without `layers` draws nothing (and says why)")
  eq(
    got.cols,
    "1,2,2,3,5,8,10",
    "layers: a frame is about twice as wide as high, ten boxes at most"
  )
  eq(
    got.count,
    "15/false",
    "layers: every module of the payload that the map still has is drawn once"
  )
  eq(
    got.shown,
    '{"rules":3,"bands":2,"layers":3,"layered":14,"loose":1,"broken":1,"loops":[]}',
    "layers: the numbers under the diagram; two rules on one require are one broken require"
  )
  eq(got.path, "3 rules · layers", "layers: the path names the rules, there is no center")
  eq(got.overlaps, 0, "layers: no two boxes overlap")
  ok(got.inside, "layers: every box is inside the canvas")
  ok(got.above, "layers: a higher band is drawn above, what no rule names at the bottom")
  ok(got.sameBand, "layers: the layers of one band stand side by side")
  eq(got.ioGrid, "0:0 368:0 0:74 368:148", "layers: nine modules are a grid of three by three")
  ok(got.ioLeftOfUi, "layers: the layers of a band keep the order of the payload")
  eq(
    got.edges,
    "u1>b1:hedge-quiet b2>b3:hedge-quiet top>u1:hedge-quiet b2>u2:hedge-viol^",
    "layers: the broken require is one edge over the boxes; the others wait, and an edge to a missing node is skipped"
  )
  eq(
    got.violLabel,
    "app.base.b2 requires app.ui.u2, but app.base must not reach into app.ui (the base knows no window)\n"
      .. "app.base.b2 requires app.ui.u2, but app.base must not reach into app.ui",
    "layers: the arrow says the rule it breaks, and its reason"
  )
  eq(
    got.decor,
    "hband | hband | hband hband-loose | hunit hunit-sib | hunit | hunit",
    "layers: a stripe per band, a dashed one for what no rule names, a frame per layer"
  )
  eq(
    got.overlay,
    "band 2 of 2 · a rule forbids a band below to require it"
      .. " | band 1 of 2 · the base: no rule forbids anything to require it"
      .. " | named by no rule · 1 module"
      .. " | app.io · 9 modules · siblings | app.ui · 2 modules | app.base · 3 modules",
    "layers: every band and every layer is named"
  )
  eq(
    got.b2,
    "lv-from|breaks a rule · 1 require|app.base|T\n"
      .. "app.base.b2 requires app.ui.u2, but app.base must not reach into app.ui (the base knows no window)\n"
      .. "app.base.b2 requires app.ui.u2, but app.base must not reach into app.ui",
    "layers: the requiring module is marked and says so in words"
  )
  eq(
    got.u2,
    "lv-to||app.ui|T\nrequired against a rule by app.base.b2",
    "layers: the required module names who reaches it"
  )
  eq(
    got.i0,
    "|shared target|app.io|T\na rule's allow list exempts it as a target",
    "layers: a shared module says that it is one"
  )
  eq(got.b1, "||app.base|", "layers: a module in no broken rule keeps its own tooltip")
  eq(got.top, "|||", "layers: a module no rule names belongs to no layer")
  eq(
    got.short,
    "b1 app app.base.b1 app.base.b1",
    "layers: a box drops the prefix its frame states, on a segment boundary only"
  )
  eq(
    got.note,
    "3 rules put 14 modules into 3 layers on 2 bands. 1 module is named by no rule. "
      .. "1 require breaks a rule (the red arrow). ",
    "layers: the note counts rules, layers, bands and broken requires"
  )
  eq(got.noteButton, 2, "layers: with a broken require the note leads to the findings")
  eq(
    got.loopNote,
    "3 rules put 14 modules into 3 layers on 2 bands. 1 module is named by no rule. No require breaks a rule. "
      .. "No order holds among app.io, app.ui: they forbid each other in a circle, so they share a band. ",
    "layers: rules that form no order are said to form none"
  )
  eq(got.loopButton, 1, "layers: without a broken require there is nothing to lead to")
  eq(
    got.capped,
    "211 true true false 0 true",
    "layers: past the cap a layer shows its first modules, the one in a broken rule among them"
  )
  eq(
    got.cappedNote,
    "Showing 211 of 711 modules: a layer shows its first 200, the ones in a broken rule first.",
    "layers: a cut diagram says so"
  )
end
