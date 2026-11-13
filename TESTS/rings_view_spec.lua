-- TESTS/rings_view_spec.lua — the Rings view of the Hierarchy: every module on the ring of its shortest require
-- chain from an entry module, and a last ring for what the entry does not reach.
--
-- Two halves, as in coupling_view_spec.lua:
--   * the arithmetic (distances, the default entry, which ring, where each box goes, what a box says) runs here
--     for real: the maps slice is evaluated in `node` with a small tree in place of the page (skipped without
--     `node`);
--   * the wiring (the button, the view, the hand-off, the entry select, the export) is pinned as text.
-- The behaviour in a real window is TESTS/sheets/rings-view.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq

  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "rings: " .. msg)
  end

  -- ── The wiring ───────────────────────────────────────────────────────────
  has('data-view="rings" data-explain="view.rings">Rings</button>', "a Rings button")
  has("rings: 1, layers: 1, coupling: 1 };", "a known view (an unknown one falls back to Modules)")
  has('else if(view === "rings") built = layoutRings(hcenter);', "drawHierarchy hands it off")
  has(
    "var laid = built.positions ? { positions: built.positions, maxRowWidth: 0 } : layerPositions(built.layers);",
    "a view may bring positions of its own; every other one is still laid out in layers"
  )
  has(
    "if(built.extent){ totalW = built.extent.w; totalH = built.extent.h; }",
    "the canvas is the view's own extent"
  )
  has("if(built.decor) built.decor(svg, svgNS);", "the rings are drawn into the diagram's own svg")
  has("if(built.paint) built.paint();", "the boxes are marked after every reconcile")
  has('"view.rings":', "the view explains itself")
  has('"hier.entry":', "the entry select explains itself")
  has(
    '<select id="hentry" aria-label="The module the rings start at"></select>',
    "an entry select with a name"
  )
  has(
    'document.getElementById("hentrywrap").style.display = s.view === "rings" ? "" : "none";',
    "the entry select shows in the Rings view only"
  )
  has(
    "if(byId[ev.target.value]) navigate({ center: ev.target.value, fn: null });",
    "choosing an entry is a navigation: it rides in the link as the center"
  )
  has(
    'return (findByNode[id] || []).some(function(f){ return f.check === "unreferenced-module"; });',
    "the unreachable ring reads the unreferenced-module finding, it does not guess it"
  )
  has(
    'b.addEventListener("click", function(){ navigate({ tab: "findings" }); });',
    "the note leads to the findings"
  )
  -- zoom and export are the diagram's own: the view is no alt view, and the export knows the rings
  has(
    'function isAltView(v){ return v === "tree" || v === "treemap" || v === "coupling"; }',
    "it draws in the zooming diagram, unlike Tree, Treemap and Coupling"
  )
  has('svg.querySelectorAll(".hring").forEach(function(el){', "the SVG export carries the rings")
  has(
    'svg.querySelectorAll(".hring-label, .hmap-label").forEach(function(el){',
    "the SVG export carries their names"
  )
  has(
    'if(ringEdge && !(hgraph.classList.contains("focusing") && p.classList.contains("near"))) return;',
    "an arrow the screen does not show is not exported"
  )
  has(
    "if(isMapView(state.view)) return;",
    "zooming past the edge does not jump to another level: there is none"
  )
  has(
    "#hsvg .hedge.hedge-quiet{opacity:0}",
    "the arrows are hidden until a box is pointed at or pinned"
  )
  has("#hgraph.focusing .hedge.hedge-quiet.near{opacity:1}", "and shown for that box")
  has(
    'hboxes[k].classList.toggle("near", k === key || !!near[k]);',
    "a box that is not on the chain is dimmed on every hover, not on every second one"
  )
  has(
    "if(built.overlay) built.overlay(svg, svgNS);",
    "the names of the rings are written over the arrows"
  )
  -- nothing new in the payload: the rings read the require edges and the findings the page already has
  local html_lua = H.slurp((vim.fn.getcwd():gsub("\\", "/")) .. "/lua/docmap/core/render/html.lua")
  ok(
    (html_lua:match("local payload = json.encode%(%{(.-)\n  %}%)") or ""):find("rings", 1, true)
      == nil,
    "rings: nothing about it rides in the payload"
  )

  -- ── The arithmetic, in node ──────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.10b_maps")
  -- The page around the slice: what slices 01 to 08 declare and this one reads.
  local page = table.concat({
    "var PAD = 20, BOX_W = 168, BOX_H = 52;",
    "function setup(nodes, edges, findings, root){",
    "  IR = { nodes: nodes, edges: edges, root: root };",
    "  byId = {}; nodes.forEach(function(n){ byId[n.id] = n; });",
    "  depOut = {}; depIn = {}; findByNode = {};",
    "  edges.forEach(function(e){ (depOut[e.from] = depOut[e.from] || []).push(e);",
    "    (depIn[e.to] = depIn[e.to] || []).push(e); });",
    "  findings.forEach(function(f){ (findByNode[f.node] = findByNode[f.node] || []).push(f); });",
    "}",
    "var IR, byId, depOut, depIn, findByNode;",
    "function mod(id, name, depth, kind){ return { id: id, module: name, name: id, depth: depth, kind: kind || 'file' }; }",
    "function req(from, to, deferred){ return { kind: 'require', from: from, to: to, to_module: 'app.' + to, line: 3,",
    "  deferred: !!deferred }; }",
    'var state = { tab: "hierarchy", view: "rings", hidden: [] };',
    "var hstage = { classList: { toggle: function(){} } }, hboxes = {};",
    "var haltBody = { addEventListener: function(){} }, haltBar = {};",
    "var made = [];",
    "var document = { getElementById: function(){ return { addEventListener: function(){} }; },",
    "  createElement: function(tag){ var el = { tag: tag, kids: [], appendChild: function(k){ this.kids.push(k); },",
    "    addEventListener: function(){} }; made.push(el); return el; },",
    "  createTextNode: function(t){ return { text: t }; } };",
    "function esc(s){ return s; } function navigate(){} function isHidden(){ return false; }",
  }, "\n")
  local program = table.concat({
    page,
    slice,
    "var out = {};",
    -- A folder at the root, an entry its own child requires back, a chain two deep, a module only a lazy
    -- require reaches, and three modules nothing reaches: one with the finding and a require of its own, one
    -- required only by that one, one alone and exempt from the finding.
    "setup([",
    "  { id: 'r', name: 'r', kind: 'namespace', depth: 0 },",
    "  mod('a', 'app', 1, 'module'), mod('b', 'app.b', 2), mod('c', 'app.c', 2), mod('d', 'app.d', 2),",
    "  mod('lazy', 'app.lazy', 2), mod('e', 'app.e', 1), mod('f', 'app.f', 2), mod('g', 'app.g', 2),",
    "  { id: 'ns', name: 'ns', kind: 'namespace', module: 'app.ns', depth: 1 }",
    "], [ req('a', 'b'), req('a', 'c'), req('b', 'd'), req('c', 'd'), req('c', 'a'), req('d', 'lazy', true),",
    "     req('e', 'f'), req('a', 'ns') ],",
    "   [ { node: 'e', check: 'unreferenced-module' }, { node: 'e', check: 'missing-doc' },",
    "     { node: 'b', check: 'missing-doc' } ], 'r');",
    "var w = ringDistances('a');",
    "out.dist = ['a', 'b', 'c', 'd', 'lazy', 'e', 'ns'].map(function(id){ return id + '=' + w.dist[id]; }).join(' ');",
    "out.via = w.via.d.from + ',' + w.via.lazy.from;",
    "out.entries = ringEntries().join(' ');",
    "out.fallback = ringDefaultEntry();",
    "var built = layoutRings('r');",
    "out.layers = built.layers.map(function(l){ return l.join(','); }).join(' | ');",
    "out.count = built.count + '/' + built.truncated;",
    "out.centerKey = built.centerKey;",
    "out.shown = JSON.stringify(ringShown);",
    "out.edges = built.edges.map(function(e){ return e.from + '>' + e.to + (/deferred/.test(e.cls) ? '~' : ''); }).join(' ');",
    "out.near = Object.keys(built.neighbours.lazy).sort().join(',');",
    "out.edgeNear = [built.edgeNear('lazy', 'd', 'lazy'), built.edgeNear('lazy', 'b', 'd'),",
    "  built.edgeNear('lazy', 'a', 'b'), built.edgeNear('lazy', 'a', 'c'), built.edgeNear('b', 'b', 'd'),",
    "  built.edgeNear('b', 'a', 'c')].join(',');",
    "out.tips = ['a', 'lazy', 'e', 'f', 'g'].map(built.tip).join(' | ');",
    "var P = built.positions;",
    "out.entryMid = (P.a.x + BOX_W / 2) * 2 === built.extent.w && (P.a.y + BOX_H / 2) * 2 === built.extent.h;",
    "function apart(pos){ var ids = Object.keys(pos), bad = 0;",
    "  for(var i = 0; i < ids.length; i++) for(var j = i + 1; j < ids.length; j++){",
    "    var p = pos[ids[i]], q = pos[ids[j]];",
    "    if(Math.abs(p.x - q.x) < BOX_W && Math.abs(p.y - q.y) < BOX_H) bad++; }",
    "  return bad; }",
    "function inside(b){ return Object.keys(b.positions).every(function(id){ var p = b.positions[id];",
    "  return p.x >= PAD && p.y >= PAD && p.x + BOX_W <= b.extent.w - PAD && p.y + BOX_H <= b.extent.h - PAD; }); }",
    "out.overlaps = apart(P); out.inside = inside(built);",
    -- farther out means farther from the entry, ring by ring (measured in the units of the layout)
    "function radius(id){ var dx = (P[id].x - P.a.x) / RING_AX, dy = (P[id].y - P.a.y) / RING_AY;",
    "  return Math.round(Math.sqrt(dx * dx + dy * dy) * 100) / 100; }",
    "out.radii = ['b', 'd', 'lazy', 'e'].map(radius).join(',');",
    "out.note = ringNote().kids[0].text;",
    "out.noteButton = ringNote().kids.length;",
    "var picked = layoutRings('e');",
    "out.picked = picked.layers.map(function(l){ return l.join(','); }).join(' | ') + ' ' + ringShown.picked;",
    "out.pickedNote = ringNote().kids[0].text;",
    "out.edge = ringEdge({ x: 0, y: 0 }, { x: 400, y: 0 }) + ' / ' + ringEdge({ x: 0, y: 0 }, { x: 0, y: 300 }) +",
    "  ' / ' + ringEdge({ x: 0, y: 0 }, { x: 0, y: 0 });",
    -- the root of the map is the entry when it is a module that requires something
    "ringDefault = undefined;",
    "setup([ mod('top', 'top', 0, 'module'), mod('x', 'top.x', 1), mod('y', 'top.y', 1) ],",
    "  [ req('top', 'x'), req('x', 'top') ], [], 'top');",
    "out.rootEntry = ringDefaultEntry() + ' ' + ringEntries().join(',');",
    -- nothing requires anything: the first module by depth and name, alone in the middle
    "ringDefault = undefined;",
    "setup([ mod('m2', 'zeta', 1), mod('m1', 'alpha', 1) ], [], [], 'none');",
    "var flat = layoutRings('none');",
    "out.flat = ringDefaultEntry() + ' ' + flat.layers.map(function(l){ return l.join(','); }).join(' | ');",
    -- no module at all
    "ringDefault = undefined;",
    "setup([ { id: 'r', name: 'r', kind: 'namespace' } ], [], [], 'r');",
    "out.empty = layoutRings('r').count;",
    -- a ring too long for one row takes several, and no two boxes overlap
    "ringDefault = undefined;",
    "var many = [ mod('hub', 'hub', 0, 'module') ], manyEdges = [];",
    "for(var k = 0; k < 150; k++){ many.push(mod('n' + k, 'hub.n' + k, 1)); manyEdges.push(req('hub', 'n' + k)); }",
    "for(var k2 = 0; k2 < 40; k2++){ many.push(mod('o' + k2, 'orphan.o' + k2, 1)); }",
    "setup(many, manyEdges, [], 'hub');",
    "var wide = layoutRings('hub');",
    "out.wide = wide.count + ' ' + apart(wide.positions) + ' ' + inside(wide) + ' ' + wide.layers.length;",
    -- the cap cuts the unreachable ring first
    "ringDefault = undefined;",
    "var big = [ mod('hub', 'hub', 0, 'module') ], bigEdges = [];",
    "for(var b1 = 0; b1 < 350; b1++){ big.push(mod('n' + b1, 'hub.n' + b1, 1)); bigEdges.push(req('hub', 'n' + b1)); }",
    "for(var b2 = 0; b2 < 100; b2++){ big.push(mod('o' + b2, 'orphan.o' + b2, 1)); }",
    "setup(big, bigEdges, [], 'hub');",
    "var capped = layoutRings('hub');",
    "out.capped = capped.count + ' ' + capped.truncated + ' ' + capped.layers[1].length + ' ' + capped.layers[2].length +",
    "  ' ' + ringShown.total + ' ' + ringShown.outside;",
    "out.cappedNote = capped.truncNote;",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "rings: the slice runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}")

  eq(
    got.dist,
    "a=0 b=1 c=1 d=2 lazy=3 e=undefined ns=undefined",
    "rings: the distance is the shortest require chain; a lazy require counts, a namespace is no module"
  )
  eq(got.via, "b,d", "rings: a module is reached by the first require that gets there")
  eq(
    got.entries,
    "e",
    "rings: the roots are the modules that require something and that nothing requires"
  )
  eq(
    got.fallback,
    "a",
    "rings: the default entry is the module that reaches the most, although its own child requires it back"
  )
  eq(
    got.layers,
    "a | b,c | d | lazy | e,f,g",
    "rings: a ring per distance, then what is not reached: the finding first, then by depth and name"
  )
  eq(got.count, "8/false", "rings: every module is drawn once")
  eq(got.centerKey, "a", "rings: the entry is the middle of the view")
  eq(
    got.shown,
    '{"entry":"a","picked":false,"total":8,"reached":5,"depth":3,"outside":3,"unref":1}',
    "rings: the numbers under the diagram"
  )
  eq(
    got.edges,
    "a>b a>c b>d d>lazy~",
    "rings: one arrow per reached module, the require that reached it first"
  )
  eq(got.near, "a,b,d", "rings: pointing at a box lights its chain back to the entry")
  eq(
    got.edgeNear,
    "true,true,true,false,true,false",
    "rings: the arrows of the chain and the ones leaving the box are shown, no others"
  )
  eq(
    got.tips,
    "the entry: the rings count the requires from here"
      .. " | 3 requires from the entry: app → app.b → app.d → app.lazy"
      .. " | not reachable from app: nothing in this map requires it (unreferenced-module)"
      .. " | not reachable from app: required only by app.e, which the entry does not reach either"
      .. " | not reachable from app: nothing in this map requires it",
    "rings: a box says why it is where it is"
  )
  ok(got.entryMid, "rings: the entry sits in the middle of the canvas")
  eq(got.overlaps, 0, "rings: no two boxes overlap")
  ok(got.inside, "rings: every box is inside the canvas")
  eq(got.radii, "1.3,2.6,3.9,5.2", "rings: one ring is one gap farther out than the one before")
  eq(
    got.note,
    "Started at app, the entry of this map (the center is a folder). app reaches 5 of 8 modules, the farthest "
      .. "3 requires away. 3 modules are not reachable from it: 1 carries the unreferenced-module finding "
      .. "(nothing requires it), the others are required only by unreachable modules or are exempt from that check. ",
    "rings: the note says both numbers and ties the last ring to the finding"
  )
  eq(got.noteButton, 2, "rings: with a finding in the ring, the note has a way to the findings")
  eq(
    got.picked,
    "e | f | a,b,c,d,g,lazy true",
    "rings: any module can be the entry; what it does not reach is the last ring"
  )
  eq(
    got.pickedNote,
    "app.e reaches 2 of 8 modules, the farthest 1 require away. 6 modules are not reachable from it. ",
    "rings: without a finding in the ring the note claims none"
  )
  eq(
    got.edge,
    "M168.0,26.0 L400.0,26.0 / M84.0,52.0 L84.0,300.0 / M84,26",
    "rings: an arrow runs from border to border, whichever side faces"
  )
  eq(
    got.rootEntry,
    "top top",
    "rings: the root of the map is the entry when it is a module, whoever requires it"
  )
  eq(
    got.flat,
    "m1 m1 | m2",
    "rings: without a single require the first module stands alone and the rest is unreachable"
  )
  eq(got.empty, 0, "rings: a map without a module draws nothing (and says so)")
  eq(
    got.wide,
    "191 0 true 3",
    "rings: a ring of 150 takes several rows, and still no two boxes overlap"
  )
  eq(
    got.capped,
    "400 true 350 49 451 100",
    "rings: the cap takes from the unreachable ring first, and the numbers stay those of the whole tree"
  )
  eq(
    got.cappedNote,
    "Showing 400 of 451 modules: the unreachable ring and the deepest rings are cut first.",
    "rings: a cut diagram says so"
  )
end
