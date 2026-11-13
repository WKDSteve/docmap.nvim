---@module 'docmap.core.render.html.js.04_directed_views_and_notes'
--- A slice of the page's script: Deps and Calls, box specs, keyed reconcile, Notes and markers.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Deps and Calls: the two directed views.
  //
  // Both are the same walk over different adjacency, so it is written once.
  // `dir` decides which way the walk runs: "out" follows edges forwards
  // (what this needs / calls), "in" follows them backwards (what needs /
  // calls this), "both" runs each independently from the same seeds and
  // places the results above and below the center.
  //
  // Running the two sides separately for "both" is not an optimisation, it is
  // the correct semantics: once a walk has gone *up* into callers, continuing
  // it downwards through those callers' other callees would fill the diagram
  // with functions that have nothing to do with the center. Doxygen's caller
  // graph makes the same choice.
  // =====================================================================
  function walk(seeds, adj, keyOf, dir, maxDepth, exists){
    var depth = {}, count = 0, truncated = false;

    seeds.forEach(function(k){
      if(exists(k) && depth[k] === undefined && count < MAX_HNODES){
        depth[k] = 0; count++;
      }
    });

    function side(sign, adjMap, pick){
      var queue = Object.keys(depth).filter(function(k){ return depth[k] === 0; })
        .map(function(k){ return { key: k, d: 0 }; });
      while(queue.length){
        var it = queue.shift();
        if(maxDepth > 0 && Math.abs(it.d) >= maxDepth) continue;
        var list = adjMap[it.key] || [];
        for(var i = 0; i < list.length; i++){
          var nxt = pick(list[i]);
          if(!exists(nxt) || depth[nxt] !== undefined) continue;
          if(count >= MAX_HNODES){ truncated = true; return; }
          depth[nxt] = it.d + sign;
          count++;
          queue.push({ key: nxt, d: it.d + sign });
        }
      }
    }

    if(dir === "out" || dir === "both") side(1, adj.out, keyOf.to);
    if(dir === "in" || dir === "both") side(-1, adj.in, keyOf.from);

    // Depths can be negative in "both" mode; layers is a dense array, so the
    // whole thing is shifted down by the deepest caller level.
    var min = 0;
    Object.keys(depth).forEach(function(k){ if(depth[k] < min) min = depth[k]; });

    var layers = [], included = {};
    Object.keys(depth).sort().forEach(function(k){
      var idx = depth[k] - min;
      included[k] = idx;
      (layers[idx] = layers[idx] || []).push(k);
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    return { layers: layers, included: included, count: count, truncated: truncated };
  }

  // Requires that resolve to nothing in the scanned tree, materialized into
  // boxes on demand. One box per module however many nodes reach for it —
  // "these four all pull in plenary" is the thing worth seeing, and four
  // separate boxes would hide exactly that. Keyed "ext:<module>" so they can
  // never collide with a node id, and given no `nodeId`, which is what stops
  // click, double-click and the context menu from offering to navigate into
  // something the map knows nothing about.
  function addExternals(built, maxDepth){
    var depthOf = {};
    Object.keys(built.included).forEach(function(id){
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        var d = built.included[id] + 1;
        if(maxDepth > 0 && d > maxDepth) return;
        if(depthOf[key] === undefined || d > depthOf[key]) depthOf[key] = d;
      });
    });

    Object.keys(depthOf).sort().forEach(function(key){
      if(built.count >= MAX_HNODES){ built.truncated = true; return; }
      var d = depthOf[key];
      while(built.layers.length <= d) built.layers.push([]);
      built.layers[d].push(key);
      built.included[key] = d;
      built.count++;
    });

    Object.keys(built.included).forEach(function(id){
      if(id.indexOf("ext:") === 0) return;
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        if(built.included[key] === undefined) return;
        built.edges.push({
          from: id, to: key,
          cls: "hedge hedge-dep external",
          marker: "dep",
          label: "requires " + mod + " (outside this map)"
        });
      });
    });
  }

  function layoutDeps(startId, dir, maxDepth, showExternal){
    var keyOf = { from: function(e){ return e.from; }, to: function(e){ return e.to; } };
    var built = walk([startId], { out: depOut, in: depIn }, keyOf, dir, maxDepth,
      function(k){ return !!byId[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "require") return;
      if(built.included[e.from] === undefined || built.included[e.to] === undefined) return;
      edges.push({
        from: e.from, to: e.to,
        cls: "hedge hedge-dep" + (e.deferred ? " deferred" : ""),
        marker: "dep",
        label: (e.deferred ? "lazy require " : "require ") + e.to_module + ":" + e.line
      });
    });
    built.edges = edges;
    if(showExternal) addExternals(built, maxDepth);
    return built;
  }

  function layoutCalls(startId, startFn, dir, maxDepth){
    var keyOf = {
      from: function(e){ return fnKey(e.from, e.from_fn); },
      to: function(e){ return fnKey(e.to, e.to_fn); }
    };
    // Centering on a node rather than a single function seeds every function
    // it declares: "what does this module call" is the question asked from
    // the node's own detail pane, and answering it one function at a time
    // would mean opening the view once per function.
    var seeds;
    if(startFn && fnByKey[startFn]){
      seeds = [startFn];
    } else {
      var n = byId[startId];
      seeds = ((n && n.functions) || []).map(function(fn){ return fnKey(startId, fn.name); });
    }

    var built = walk(seeds, { out: callOut, in: callIn }, keyOf, dir, maxDepth,
      function(k){ return !!fnByKey[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "call") return;
      var a = keyOf.from(e), b = keyOf.to(e);
      if(built.included[a] === undefined || built.included[b] === undefined) return;
      edges.push({
        from: a, to: b,
        cls: "hedge hedge-call" + (e.confidence === "heuristic" ? " weak" : ""),
        marker: "call",
        label: (e.confidence === "heuristic" ? "guessed call, line " : "call, line ") + e.line
      });
    });
    built.edges = edges;
    return built;
  }

  // Module Calls view: same shape as layoutDeps, but walking the
  // module-to-module edges collapsed above (moduleCallOut/moduleCallIn)
  // instead of per-function call edges — one weighted arrow per pair of
  // modules rather than one per call site.
  function layoutModuleCalls(startId, dir, maxDepth, showExternal){
    var keyOf = { from: function(e){ return e.from; }, to: function(e){ return e.to; } };
    var built = walk([startId], { out: moduleCallOut, in: moduleCallIn }, keyOf, dir, maxDepth,
      function(k){ return !!byId[k]; });

    var edges = [];
    Object.keys(moduleCallEdgeByPair).forEach(function(key){
      var e = moduleCallEdgeByPair[key];
      if(built.included[e.from] === undefined || built.included[e.to] === undefined) return;
      edges.push({
        from: e.from, to: e.to,
        cls: "hedge hedge-call",
        marker: "call",
        label: e.weight + " call" + (e.weight === 1 ? "" : "s"),
        weight: e.weight
      });
    });
    built.edges = edges;
    if(showExternal) addModuleCallExternals(built, maxDepth);
    return built;
  }

  // Same idea as addExternals, but sourcing node.calls_external — which,
  // unlike requires_external, can have several entries per module (one per
  // distinct member called), so weights are summed per (node, module) pair
  // before boxes/edges are built.
  function addModuleCallExternals(built, maxDepth){
    var idModuleWeight = {};
    Object.keys(built.included).forEach(function(id){
      if(id.indexOf("ext:") === 0) return;
      ((byId[id] || {}).calls_external || []).forEach(function(c){
        var byMod = idModuleWeight[id] || (idModuleWeight[id] = {});
        byMod[c.module] = (byMod[c.module] || 0) + c.count;
      });
    });

    var depthOf = {};
    Object.keys(idModuleWeight).forEach(function(id){
      Object.keys(idModuleWeight[id]).forEach(function(mod){
        var key = "ext:" + mod;
        var d = built.included[id] + 1;
        if(maxDepth > 0 && d > maxDepth) return;
        if(depthOf[key] === undefined || d > depthOf[key]) depthOf[key] = d;
      });
    });

    Object.keys(depthOf).sort().forEach(function(key){
      if(built.count >= MAX_HNODES){ built.truncated = true; return; }
      var d = depthOf[key];
      while(built.layers.length <= d) built.layers.push([]);
      built.layers[d].push(key);
      built.included[key] = d;
      built.count++;
    });

    Object.keys(idModuleWeight).forEach(function(id){
      Object.keys(idModuleWeight[id]).forEach(function(mod){
        var key = "ext:" + mod;
        if(built.included[key] === undefined) return;
        var weight = idModuleWeight[id][mod];
        built.edges.push({
          from: id, to: key,
          cls: "hedge hedge-call external",
          marker: "call",
          label: weight + " call" + (weight === 1 ? "" : "s") + " to " + mod + " (outside this map)",
          weight: weight
        });
      });
    });
  }

  function layerPositions(layers){
    var lr = isLR();
    // The extent of the widest layer, across the axis a layer spreads on.
    var span = 0;
    layers.forEach(function(layer){
      if(!layer) return;
      var n = layer.length;
      span = Math.max(span, lr
        ? n * BOX_H + (n - 1) * GAP_Y
        : n * BOX_W + (n - 1) * GAP_X);
    });
    var positions = {};
    layers.forEach(function(layer, d){
      if(!layer) return;
      var n = layer.length;
      var own = lr ? n * BOX_H + (n - 1) * GAP_Y : n * BOX_W + (n - 1) * GAP_X;
      // Layers are centred against the widest one, so the graph reads as a
      // shape rather than as a left-aligned staircase.
      var start = PAD + (span - own) / 2;
      layer.forEach(function(key, i){
        positions[key] = lr
          ? { x: PAD + d * (BOX_W + GAP_X), y: start + i * (BOX_H + GAP_Y) }
          : { x: start + i * (BOX_W + GAP_X), y: PAD + d * (BOX_H + GAP_Y) };
      });
    });
    return { positions: positions, maxRowWidth: span };
  }

  // =====================================================================
  // Box specs: one place that knows what a box in each view says. Returns a
  // class, its markup, a tooltip and the node the box ultimately belongs to
  // (a class box and a function box both resolve back to a node, which is
  // what click-to-select and the context menu act on).
  // =====================================================================
  function boxSpec(key, view){
    if(key.indexOf("ext:") === 0){
      var mod = key.slice(4);
      // Resolved through opts.tag_files (Doxygen TAGFILES equivalent) or
      // opts.external_repos (a guessed/verified GitHub link) — either way a
      // box that isn't part of *this* map stops being an inert dead end and
      // opens somewhere real.
      var link = (IR.tag_links || {})[mod];

      // "Why is this here" — every function of `mod` this tree actually
      // calls, not just the bare "X is required" fact `requires_external`
      // already drew before this existed. Absent (not empty) when nothing
      // resolved: a require kept purely for side effects, or a call shape
      // `core/calls.lua`'s four resolvable forms cannot see — a real
      // difference from "resolved and found zero calls", which cannot
      // happen (a module with a resolved call is why this entry exists).
      var byMember = getExternalCallTotals()[mod];
      var callTotal = 0;
      var callLines = [];
      if(byMember){
        var members = Object.keys(byMember);
        members.sort(function(a, b){
          if(byMember[a] !== byMember[b]) return byMember[b] - byMember[a];
          return a < b ? -1 : (a > b ? 1 : 0);
        });
        members.forEach(function(m){
          var n = byMember[m];
          callTotal += n;
          callLines.push((m ? mod + "." + m : mod) + " (" + n + "×)");
        });
      }

      var baseTitle = link
        ? mod + " — open " + link.title + " in its own map"
        : mod + " — required here but not part of this map";
      var title = callLines.length ? baseTitle + "\n" + callLines.join("\n") : baseTitle;

      return {
        cls: "hnode k-external" + (link ? " linked" : ""),
        title: title,
        html: '<div class="hnm">' + esc(mod) + '</div>' +
              '<div class="hkind">external' + (link ? " ↗" : "") +
              (callTotal ? "  ·  " + callTotal + " call" + (callTotal === 1 ? "" : "s") : "") +
              '</div>',
        nodeId: null, recenter: null, externalHtml: link && link.html
      };
    }
    // Both class-keyed views. Inheritance boxes carry the parent list as the
    // second line instead of the bare kind: in a diagram *about* inheritance,
    // "class" on every box says nothing, and the declared `: A, B` is exactly
    // what the reader is checking the arrows against.
    if(view === "types" || view === "inheritance"){
      var cls = classByName[key];
      if(!cls) return null;
      var sub = cls.info.kind;
      if(view === "inheritance"){
        var ps = cls.info.extends || [];
        sub = ps.length ? ": " + ps.join(", ") : "base";
      }
      return {
        cls: "hnode t-" + cls.info.kind,
        title: cls.info.desc || key,
        html: '<div class="hnm">' + esc(key) + '</div>' +
              '<div class="hkind">' + esc(sub) + '</div>',
        nodeId: cls.nodeId, recenter: cls.nodeId
      };
    }
    if(view === "calls"){
      var entry = fnByKey[key];
      if(!entry) return null;
      return {
        cls: "hnode k-fn",
        title: (entry.fn.summary || entry.fn.signature) + "\n" +
               (entry.node.module || entry.node.path),
        html: '<div class="hnm">' + esc(entry.fn.signature) + '</div>' +
              '<div class="hline">' + esc(entry.node.name) + ':' + entry.fn.line + '</div>',
        nodeId: entry.node.id, recenter: entry.node.id, fnKey: key
      };
    }
    var n = byId[key];
    if(!n) return null;
    // The Deps view labels boxes by module path rather than directory name:
    // a require graph is read in module terms, and half this tree's
    // directories are called `init`-shaped things that are ambiguous alone.
    var label = (view === "deps" || view === "modulecalls" || isMapView(view)) ? (n.module || n.name) : n.name;
    return {
      cls: "hnode k-" + n.kind,
      title: n.summary || n.name,
      html: '<div class="hnm">' + esc(label) + '</div>' +
            (n.summary ? '<div class="hsm">' + prose(n.summary) + '</div>' : ''),
      nodeId: n.id, recenter: n.id
    };
  }

  // =====================================================================
  // Keyed reconcile — the reason re-centering moves instead of cutting.
  //
  // Boxes are held in `hboxes` by key and reused across redraws, so a box
  // present before and after a re-center is the *same element* at a new
  // left/top, and the CSS transition on .hnode animates it there. Rebuilding
  // the subtree with innerHTML = "" (what this used to do) threw that
  // identity away every time, which is why every navigation was a hard cut
  // even though the two layouts often shared most of their boxes.
  //
  // Positions are still computed analytically from the IR, never measured off
  // the DOM — that is what lets the diagram be correct while the pane is
  // display:none, and animating does not change it.
  // =====================================================================
  var hboxes = {};
  var hpending = {};
  var ANIM_MS = 340;

  function reconcile(positions, view, centerKey){
    var moved = false;

    Object.keys(positions).forEach(function(key){
      var spec = boxSpec(key, view);
      if(!spec) return;
      var pos = positions[key];
      var el = hboxes[key];

      if(el){
        // A box that was mid-exit and is wanted again: cancel the removal
        // rather than let the timer delete a live element out from under us.
        if(hpending[key]){ clearTimeout(hpending[key]); delete hpending[key]; }
        if(parseFloat(el.style.left) !== pos.x || parseFloat(el.style.top) !== pos.y) moved = true;
      } else {
        el = document.createElement("div");
        el.dataset.key = key;
        el.style.left = pos.x + "px";
        el.style.top = pos.y + "px";
        el.classList.add("entering");
        hstage.appendChild(el);
        hboxes[key] = el;
      }

      var entering = el.classList.contains("entering");
      el.className = spec.cls + (key === centerKey ? " center" : "") + (entering ? " entering" : "");
      el.style.left = pos.x + "px";
      el.style.top = pos.y + "px";
      el.style.width = BOX_W + "px";
      el.title = spec.title;
      el.innerHTML = spec.html;
      el._spec = spec;
    });

    Object.keys(hboxes).forEach(function(key){
      if(positions[key] !== undefined || hpending[key]) return;
      var el = hboxes[key];
      el.classList.add("leaving");
      hpending[key] = setTimeout(function(){
        delete hpending[key];
        if(hboxes[key] === el){ delete hboxes[key]; }
        if(el.parentNode) el.parentNode.removeChild(el);
      }, ANIM_MS);
    });

    // Entering boxes need one frame at opacity 0 before the class comes off,
    // or the browser coalesces both styles into the final one and there is no
    // transition to run.
    requestAnimationFrame(function(){
      Object.keys(hboxes).forEach(function(key){
        hboxes[key].classList.remove("entering");
      });
    });

    return moved;
  }

  // Arrowheads: a tree needs none (the layout says which way is down), a
  // directed graph does — an edge between two boxes on the same layer, or a
  // backedge, is otherwise unreadable. One marker per edge colour, coloured
  // from CSS so the dark-mode palette applies to them too.
  function buildDefs(svgNS){
    var defs = document.createElementNS(svgNS, "defs");
    ["tree", "type", "ext", "dep", "call", "viol"].forEach(function(name){
      var m = document.createElementNS(svgNS, "marker");
      m.id = "m-" + name;
      m.setAttribute("viewBox", "0 0 8 8");
      m.setAttribute("refX", "7"); m.setAttribute("refY", "4");
      m.setAttribute("markerWidth", "7"); m.setAttribute("markerHeight", "7");
      m.setAttribute("orient", "auto-start-reverse");
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", "M0,0 L8,4 L0,8 z");
      m.appendChild(p);
      defs.appendChild(m);
    });
    return defs;
  }

  // Written as objects rather than nested arrays for a mundane reason worth
  // knowing before editing this file: the whole script lives inside a Lua
  // long string, and two adjacent closing square brackets terminate it —
  // which is exactly what an array of arrays ends with. The rest of the
  // script then parses as Lua source. Avoid that pair anywhere in here.
  function sw(mod, text){ return { sw: mod, text: text }; }
  var LEGEND = {
    modules: [ sw("", "contains"), sw("type", "type reference") ],
    types:   [ sw("type", "field references class") ],
    inheritance: [ sw("ext", "inherits from (arrow points at the base class)") ],
    deps:    [ sw("dep", "requires at load time"),
               sw("dep deferred", "lazy require (inside a function)") ],
    depsExt: [ sw("dep external", "requires something outside this map") ],
    calls:   [ sw("call", "calls"),
               sw("call weak", "guessed call (--calls-heuristic)") ]
  };

  function drawLegend(view){
    if(isMapView(view)){ hlegendEl.innerHTML = mapLegend(view); return; }
    var entries = (LEGEND[view] || []).slice();
    if(view === "deps" && state.ext) entries = entries.concat(LEGEND.depsExt);
    var items = entries.map(function(it){
      return '<span class="lg"><span class="sw ' + it.sw + '"></span>' + esc(it.text) + '</span>';
    });
    items = items.concat(tintLegend());
    items.push('<span class="lg">wheel zooms · shift+wheel pans · ' +
      (isGraphView(view) ? 'zoom past the edge changes depth' : 'zoom right in to open a module') +
      ' · right-click for more</span>');
    hlegendEl.innerHTML = items.join("");
  }

  function emptyMessage(view, center){
    if(view === "types"){
      return typeEdges.length
        ? '<p class="hmsg">' + esc(center.name) + ' has no <code>@class</code>/<code>@alias</code> of its own — pick a module with type definitions, or switch back to Modules.</p>'
        : '<p class="hmsg">No type data in this map — regenerate with <code>:DocMap full</code> (or <code>--full</code>) to include lua-language-server class/alias detail.</p>';
    }
    if(view === "inheritance"){
      if(!typeEdges.length && !extendsEdges.length){
        return '<p class="hmsg">No type data in this map — regenerate with <code>:DocMap full</code> (or <code>--full</code>) to include lua-language-server class detail.</p>';
      }
      return extendsEdges.length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s classes take part in an inheritance relation (<code>---@class Child : Parent</code>).</p>'
        : '<p class="hmsg">No class in this map declares a parent — nothing to draw an inheritance tree from.</p>';
    }
    if(view === "deps"){
      return '<p class="hmsg">' + esc(center.name) + ' neither requires nor is required by anything in this map.</p>';
    }
    if(view === "calls"){
      return (center.functions || []).length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s functions call — or are called by — anything the scanner could resolve. Dynamic dispatch is invisible to it; see the module README.</p>'
        : '<p class="hmsg">' + esc(center.name) + ' declares no functions.</p>';
    }
    if(view === "modulecalls"){
      return '<p class="hmsg">' + esc(center.name) + ' has no resolved call edges to or from another module — either it doesn’t call across module boundaries, or nothing else calls into it.</p>';
    }
    if(view === "layers"){
      return '<p class="hmsg">No layers are declared for this map. A rule in <code>.docmap.json</code> such as ' +
        '<code>"layers": [{ "from": "app.core", "to": "app.ui" }]</code> (the core may not require the UI) ' +
        'gives the tree bands, and this view draws them with every require that breaks a rule.</p>';
    }
    if(view === "rings"){
      return '<p class="hmsg">This map has no module to start from, so there is no distance to measure.</p>';
    }
    return '<p class="hmsg">Nothing to draw here.</p>';
  }

  function clearGraph(){
    Object.keys(hpending).forEach(function(k){ clearTimeout(hpending[k]); });
    hpending = {};
    hboxes = {};
    hstage.innerHTML = "";
    // The empty-state message hangs off #hgraph, outside the stage, so
    // clearing the stage alone would stack a second copy on the next empty
    // draw instead of replacing the first.
    var msg = hgraph.querySelector(".hmsg");
    if(msg) msg.remove();
  }

  var VIEWS = { modules: 1, types: 1, inheritance: 1, deps: 1, calls: 1, modulecalls: 1, tree: 1, treemap: 1,
                rings: 1, layers: 1, coupling: 1 };

  // =====================================================================
  // Notes tab: Doxygen's Deprecated / Todo / Bug / Test lists.
  //
  // Four aggregates over data the scan already has, in one tab rather than
  // four pages: three of these tags are usually unused in a given tree, and
  // four tabs that are empty most of the time would be four tabs of noise.
  // Sections with no entries say so instead of vanishing, so "nothing is
  // deprecated" is distinguishable from "this build forgot to collect it".
  //
  // Not a `check` finding, deliberately: none of these is drift or an error,
  // and routing them through findings would put author to-dos into an exit
  // code that CI fails on.
  // =====================================================================
  var NOTE_KINDS = [
    { key: "deprecated", title: "Deprecated", scalar: true,
      sub: "Functions marked ---@deprecated. The text is the migration hint the author left." },
    { key: "todo", title: "Todo",
      sub: "Open ---@todo entries, one line per occurrence." },
    { key: "bug", title: "Bug",
      sub: "Known defects recorded with ---@bug, still present in the code." },
    { key: "test", title: "Test",
      sub: "---@test notes: what covers this function, or what still needs covering." }
  ];

  function collectNotes(kind){
    var out = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        var v = fn[kind.key];
        if(kind.scalar){
          if(v) out.push({ node: n, fn: fn, text: v });
          return;
        }
        (v || []).forEach(function(entry){ out.push({ node: n, fn: fn, text: entry }); });
      });
    });
    // By where it lives, then by line: reading a list of todos is reading a
    // to-do list per module, not an alphabet of function names.
    out.sort(function(a, b){
      var am = a.node.module || a.node.path, bm = b.node.module || b.node.path;
      if(am !== bm) return am < bm ? -1 : 1;
      return a.fn.line - b.fn.line;
    });
    return out;
  }

  // =====================================================================
  // Marker comments — the other half of the Notes tab.
  //
  // The annotation sections above read `---@todo` and friends off function
  // doc blocks. These read `-- TODO:`, `// FIXME:`, `-- PERF:` off the
  // source text, wherever they sit. Two collectors and two section groups
  // rather than one merged list, because the two answer different
  // questions: an annotation is a claim about a function and is shown
  // beside its signature, a marker is a claim about a line and is shown
  // with its location. Merging them would produce rows whose function name
  // is a guess.
  //
  // `core/markers.lua` decided which keywords exist and what each means;
  // `IR.marker_kinds` carries that table so this code names none of them.
  // =====================================================================

  function collectMarkers(){
    var byKind = {};
    IR.nodes.forEach(function(n){
      (n.markers || []).forEach(function(m){
        (byKind[m.kind] = byKind[m.kind] || []).push({ node: n, m: m });
      });
    });
    // By file, then by line — the order they would be read in, not the
    // order the walk happened to produce them in.
    Object.keys(byKind).forEach(function(kind){
      byKind[kind].sort(function(a, b){
        var ap = a.node.source || a.node.path, bp = b.node.source || b.node.path;
        if(ap !== bp) return ap < bp ? -1 : 1;
        return a.m.line - b.m.line;
      });
    });
    return byKind;
  }

  function markerItem(it){
    var where = (it.node.source || it.node.path) + ":" + it.m.line;
    var bits = ['<li><a class="nfn" tabindex="0" role="button" data-node="' +
      esc(it.node.id) + '">' + esc(where) + "</a>"];
    // The spelling the author typed, shown only when it differs from the
    // section it landed in: a `BUG:` under the FIX heading needs saying, a
    // `TODO:` under TODO does not.
    if(it.m.word && it.m.word !== it.m.kind){
      bits.push('<span class="nword">' + esc(it.m.word) + "</span>");
    }
    if(it.m.author){
      // Prefixed and given its own class: beside a file path, a bare name
      // reads as another piece of the location.
      bits.push('<span class="nauthor">@' + esc(it.m.author) + "<\/span>");
    }
    bits.push('<div class="ntext">' + (it.m.text ? esc(it.m.text) : "&mdash;") + "</div></li>");
    return bits.join("");
  }

  function drawMarkers(parts){
    var kinds = IR.marker_kinds || [];
    var byKind = collectMarkers();
    var total = 0;
    kinds.forEach(function(k){ total += (byKind[k.name] || []).length; });

    parts.push('<h3 class="ngroup">Marker comments<span class="ncount">' +
      total + "</span></h3>");
    parts.push('<p class="nsub">Keywords written in ordinary comments — ' +
      '<code>-- TODO:</code>, <code>// FIXME:</code>, <code>-- PERF:</code> — ' +
      "read from the source text rather than from an annotation. The same " +
      "keyword set <code>todo-comments.nvim</code> highlights in the editor, " +
      "so what is coloured in the buffer is what is listed here.</p>");

    // An artifact generated before marker scanning existed carries no
    // `markers` key at all, and rendering that as "nothing to do" would be
    // the exact silent-degradation failure this page keeps being caught by.
    // Schema 4 is where the field arrived.
    if(!((IR.meta || {}).schema >= 4)){
      parts.push('<p class="ntext none">This map predates marker scanning. ' +
        "Regenerate it to list them.</p>");
      return;
    }

    var empty = [];
    kinds.forEach(function(k){
      var items = byKind[k.name] || [];
      if(items.length === 0){ empty.push(k.name); return; }
      parts.push("<h3>" + esc(k.name) +
        '<span class="ncount">' + items.length + "</span></h3>");
      parts.push('<p class="nsub">' + esc(k.sub) + "</p>");
      parts.push('<ul class="nlist">');
      items.forEach(function(it){ parts.push(markerItem(it)); });
      parts.push("</ul>");
    });

    // The keywords that found nothing get one line between them rather than
    // a heading each: seven empty sections is the whole tab, and this page's
    // rule is density on demand, never on screen.
    if(empty.length === kinds.length){
      parts.push('<p class="ntext none">No marker comments in this map.</p>');
    } else if(empty.length){
      parts.push('<p class="ntext none">Nothing marked ' +
        esc(empty.join(", ")) + ".</p>");
    }
  }

  var notesDrawn = false;
  function drawNotes(){
    if(notesDrawn) return; // static over one IR; nothing invalidates it
    notesDrawn = true;

    var host = document.getElementById("view-notes");
    var parts = [];

    // Named rather than implied. Before this heading existed the tab
    // opened straight into `Deprecated 0 / Todo 0 / Bug 0`, which reads as
    // "this repository has nothing outstanding" -- and was reported as
    // exactly that misreading by an author whose tree is full of
    // `-- TODO:`. Those four sections were never counting comments.
    parts.push('<h3 class="ngroup">Annotations<\/h3>');
    parts.push('<p class="nsub">Tags written in a documentation block, shown '
      + 'beside the function they describe. Comment markers such as '
      + '<code>-- TODO:<\/code> are a separate list, further down.<\/p>');
    NOTE_KINDS.forEach(function(kind){
      var items = collectNotes(kind);
      parts.push('<h3>' + esc(kind.title) +
        '<span class="ncount">' + items.length + '</span></h3>');
      parts.push('<p class="nsub">' + esc(kind.sub) + '</p>');
      if(items.length === 0){
        parts.push('<p class="ntext none">No function carries <code>---@' +
          esc(kind.key) + '<\/code>. Comment markers are listed under Marker comments below.<\/p>');
        return;
      }
      parts.push('<ul class="nlist">');
      items.forEach(function(it){
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(it.node.id) + '">' +
          esc(it.fn.signature) + '</a>' +
          sigTrigger(it.node.id, it.fn.name) + docTrigger(fnKey(it.node.id, it.fn.name)) +
          '<span class="nwhere">' + esc(it.node.module || it.node.path) +
          ':' + it.fn.line + '</span>' +
          '<div class="ntext">' + (it.text ? esc(it.text) : "&mdash;") + '</div></li>');
      });
      parts.push("</ul>");
    });
    drawMarkers(parts);

    host.innerHTML = parts.join("");

    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
  }

]]
