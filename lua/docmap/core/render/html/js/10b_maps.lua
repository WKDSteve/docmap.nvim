---@module 'docmap.core.render.html.js.10b_maps'
--- A slice of the page's script: the maps of the Hierarchy (the tint of the Modules view and its legend, the
--- Coupling plot, the Rings and the Layers).
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Tint: one more encoding on the Modules view.
  //
  // A percentage in a panel is a number; "where is this repository weakest,
  // and is the weakness in one corner or everywhere?" is a question about
  // shape, and the Modules view already has the shape. So the boxes are
  // tinted, and nothing is laid out again.
  //
  // One switch, four readings:
  //   doc   share of the functions that are documented (`fn.documented`;
  //         `@internal` functions are left out, as in the Documentation panel)
  //   test  share of the functions a spec names (`fn.tested`)
  //   fix   `FIX`-family markers (FIXME, BUG, ISSUE) per 1,000 lines
  //   debt  TODO, HACK and PERF markers per 1,000 lines
  // `fix` and `debt` stay apart on purpose: a FIX marker is the author's
  // claim that a line is wrong, the other three are scheduled work (the
  // same line the Quicks verdict draws).
  //
  // Everything is computed here from what the payload already carries
  // (`functions`, `markers`, `stats.lines`); a box stands for its whole
  // subtree. A stronger tint always means "look here": a low share, a high
  // density.
  //
  // Never colour alone: each box prints its value, the legend names the
  // steps, the tooltip gives the counts, and the steps differ in lightness,
  // which survives every form of colour blindness.
  // =====================================================================
  var TINT_MODES = {
    doc:  { name: "documented", share: true, unit: "documented" },
    test: { name: "tested", share: true, unit: "tested" },
    fix:  { name: "FIX markers", share: false, unit: "FIX" },
    debt: { name: "TODO, HACK and PERF markers", share: false, unit: "TODO/HACK/PERF" }
  };
  // The stated thresholds. A share below the bound of a step lands in it;
  // a density (markers per 1,000 lines) above it does.
  var TINT_SHARE_STEPS = [ 0.8, 0.6, 0.4, 0.2 ];
  var TINT_DENSITY_STEPS = [ 0, 1, 3, 6 ];
  var TINT_SHARE_LABELS = [ "80% and more", "60–79%", "40–59%", "20–39%", "under 20%" ];
  var TINT_DENSITY_LABELS = [ "none", "under 1", "1 to 3", "3 to 6", "6 and more" ];

  function tintMode(){
    return (state.tab === "hierarchy" && (state.view || "modules") === "modules" && TINT_MODES[state.tint])
      ? state.tint : null;
  }

  // What a node and everything below it adds up to. Memoised: the tree does
  // not change while the page is open.
  var tintTotalsCache = {};
  function tintTotals(id){
    if(tintTotalsCache[id]) return tintTotalsCache[id];
    var t = { fns: 0, pub: 0, doc: 0, test: 0, fix: 0, debt: 0 };
    // Stored before the walk, so a `children` cycle in a damaged artifact
    // ends instead of recursing forever.
    tintTotalsCache[id] = t;
    var n = byId[id];
    if(!n) return t;
    (n.functions || []).forEach(function(fn){
      t.fns++;
      if(fn.tested) t.test++;
      if(!fn.internal){ t.pub++; if(fn.documented) t.doc++; }
    });
    (n.markers || []).forEach(function(m){
      if(m.kind === "FIX") t.fix++;
      else if(m.kind === "TODO" || m.kind === "HACK" || m.kind === "PERF") t.debt++;
    });
    (n.children || []).forEach(function(c){
      if(!byId[c]) return;
      var k = tintTotals(c);
      t.fns += k.fns; t.pub += k.pub; t.doc += k.doc; t.test += k.test;
      t.fix += k.fix; t.debt += k.debt;
    });
    return t;
  }

  // One box's reading in one mode: the step (0 = no tint, 4 = strongest, null =
  // nothing to measure), the short value printed on the box and the sentence
  // of the tooltip.
  function tintOf(id, mode){
    var t = tintTotals(id), spec = TINT_MODES[mode];
    if(spec.share){
      var have = mode === "doc" ? t.doc : t.test;
      var total = mode === "doc" ? t.pub : t.fns;
      if(!total) return { level: null, text: "–", tip: "no functions to measure" };
      var share = have / total, level = 4;
      for(var i = 0; i < TINT_SHARE_STEPS.length; i++){
        if(share >= TINT_SHARE_STEPS[i]){ level = i; break; }
      }
      var pct = Math.floor(share * 100);
      return { level: level, text: pct + "%",
               tip: have + " of " + total + " functions " + spec.unit + " (" + pct + "%)" };
    }
    var count = mode === "fix" ? t.fix : t.debt;
    var lines = ((byId[id] || {}).stats || {}).lines || 0;
    if(!lines) return { level: null, text: "–", tip: "no lines to measure" };
    var per = count * 1000 / lines, lvl = 0;
    if(count > 0){
      lvl = 1;
      for(var j = TINT_DENSITY_STEPS.length - 1; j >= 1; j--){
        if(per >= TINT_DENSITY_STEPS[j]){ lvl = j + 1; break; }
      }
    }
    return { level: lvl, text: String(count),
             tip: count + " " + spec.unit + " marker" + (count === 1 ? "" : "s") + " in " + lines +
                  " lines (" + per.toFixed(1) + " per 1,000)" };
  }

  // Paints the current tint onto the boxes `reconcile()` just wrote. Called
  // at the end of every draw: reconcile resets a box's class and markup, so
  // a tint set once would not survive a re-centre. Hide, dim and the
  // language legend work on opacity and their own classes; none of them
  // touches what is set here, and this touches none of theirs.
  function applyTint(){
    var mode = tintMode();
    hstage.classList.toggle("tinted", !!mode);
    Object.keys(hboxes).forEach(function(key){
      var el = hboxes[key];
      for(var i = 1; i <= 4; i++) el.classList.remove("tint-" + i);
      el.classList.remove("tint-na");
      delete el.dataset.tint;
      delete el.dataset.tintText;
      var old = el.querySelector(".htv");
      if(old) old.remove();
      if(!mode || !byId[key]) return;
      var r = tintOf(key, mode);
      if(r.level === null) el.classList.add("tint-na");
      else if(r.level > 0) el.classList.add("tint-" + r.level);
      el.dataset.tint = r.level === null ? "na" : String(r.level);
      el.dataset.tintText = r.text;
      var badge = document.createElement("span");
      badge.className = "htv";
      badge.textContent = r.text;
      el.appendChild(badge);
      el.title = (el._spec ? el._spec.title : el.title) + "\n" + TINT_MODES[mode].name + ": " + r.tip;
    });
  }

  // The legend entries of the current tint, for `drawLegend`: the steps with
  // their bounds, strongest last, and what a box without a value means.
  function tintLegend(){
    var mode = tintMode();
    if(!mode) return [];
    var spec = TINT_MODES[mode];
    var labels = spec.share ? TINT_SHARE_LABELS : TINT_DENSITY_LABELS;
    var items = ['<span class="lg lg-tint"><b>Tint: ' + esc(spec.name) +
      (spec.share ? " (share of the functions below a box)" : " per 1,000 lines") + "</b></span>"];
    labels.forEach(function(text, i){
      items.push('<span class="lg lg-tint"><span class="bx' + (i ? " tint-" + i : "") + '"></span>' +
        esc(text) + "</span>");
    });
    items.push('<span class="lg lg-tint"><span class="bx tint-na"></span>nothing to measure</span>');
    items.push('<span class="lg lg-tint">stronger tint = look here first · the value is on each box, the counts in its tooltip</span>');
    return items;
  }

  // The same legend as one line of text, for the SVG export.
  function tintLegendText(){
    var mode = tintMode();
    if(!mode) return "";
    var spec = TINT_MODES[mode];
    var labels = spec.share ? TINT_SHARE_LABELS : TINT_DENSITY_LABELS;
    return "Tint: " + spec.name + (spec.share ? "" : " per 1,000 lines") + " — weakest to strongest tint: " +
      labels.join(" · ") + " · dashed: nothing to measure";
  }

  // The colour and the opacity of one step, read off the stylesheet so the
  // export matches the theme on screen. `--tint` is three numbers ("200,100,0").
  function tintPaint(level){
    var cs = getComputedStyle(document.documentElement);
    return { rgb: "rgb(" + cs.getPropertyValue("--tint").trim() + ")",
             opacity: cs.getPropertyValue("--ta" + level).trim() };
  }

  document.getElementById("htint").addEventListener("change", function(ev){
    navigate({ tint: TINT_MODES[ev.target.value] ? ev.target.value : null });
  });

  // =====================================================================
  // Coupling: the modules as a scatter plot, fan-out across, fan-in up.
  //
  // Not a graph. The Analysis tab's Dependencies panel lists the same two
  // numbers per module; "what would be expensive to change?" is a question
  // about where a module sits among the others, and a table sorted by one
  // column cannot show two. The plot has four corners with names:
  //
  //   hub           many modules require it, it requires few: a change
  //                 reaches far, and little can break it from below
  //   tangle        many require it and it requires many: a change reaches
  //                 far and it is exposed to every change below it
  //   pass-through  few require it, it requires many: wiring, cheap to
  //                 change, the first to notice a change elsewhere
  //   leaf          few either way
  //
  // "Many" is a fixed number (COUPLING_HIGH), printed in the bar and drawn as
  // the two lines of the plot. Fixed, not the median of what is shown: a
  // relative line would call the busiest module of a three-file tree a hub
  // and would move every time the center does.
  //
  // The numbers are the ones the payload already carries (`requires`,
  // `required_by`, over the whole tree); the plot shows the modules at and
  // below the center that have at least one of the two. It draws into #halt
  // like Tree and Treemap: it is not a diagram to zoom or to lay out again.
  // =====================================================================
  var COUPLING_HIGH = 5;
  var COUPLING_CORNERS = {
    hub: { label: "Hubs", one: "hub", hint: "many require it, it requires few" },
    tangle: { label: "Tangles", one: "tangle", hint: "many require it, it requires many" },
    pass: { label: "Pass-throughs", one: "pass-through", hint: "few require it, it requires many" },
    leaf: { label: "Leaves", one: "leaf", hint: "few either way" }
  };

  function couplingCorner(fanIn, fanOut){
    var hi = fanIn >= COUPLING_HIGH, ho = fanOut >= COUPLING_HIGH;
    return hi ? (ho ? "tangle" : "hub") : (ho ? "pass" : "leaf");
  }

  // The modules at and below `centerId` with at least one require edge,
  // sorted the way the keyboard walks them: by corner (the expensive ones
  // first), then by the larger number, then by id.
  function couplingRows(centerId){
    var rows = [], order = { tangle: 0, hub: 1, pass: 2, leaf: 3 };
    (function walk(id){
      var n = byId[id];
      if(!n) return;
      var fanIn = (n.required_by || []).length, fanOut = (n.requires || []).length;
      if(fanIn || fanOut){
        rows.push({ id: id, name: n.module || n.path || id, fanIn: fanIn, fanOut: fanOut,
                    corner: couplingCorner(fanIn, fanOut) });
      }
      (n.children || []).forEach(walk);
    })(centerId);
    rows.sort(function(a, b){
      if(a.corner !== b.corner) return order[a.corner] - order[b.corner];
      var wa = Math.max(a.fanIn, a.fanOut), wb = Math.max(b.fanIn, b.fanOut);
      if(wa !== wb) return wb - wa;
      return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
    });
    return rows;
  }

  // The ticks of an axis that runs to `max`: the small numbers, where nearly
  // every module sits, and then steps that keep the labels apart.
  function couplingTicks(max){
    var out = [];
    [0, 1, 2, 5, 10, 20, 50, 100, 200, 500].forEach(function(t){ if(t <= max) out.push(t); });
    return out;
  }

  // Where every row is drawn. A square-root scale: most modules have one,
  // two or three edges, and a linear axis that reaches the one module with
  // forty would stack them all in a corner. Modules with the same two
  // numbers share a point of the grid; they are laid around it in a spiral
  // (in the order of `rows`), so each keeps a dot of its own.
  function couplingLayout(rows, W, H){
    var PAD_L = 46, PAD_B = 34, PAD_T = 14, PAD_R = 16, STEP = 5.2;
    var maxIn = COUPLING_HIGH, maxOut = COUPLING_HIGH;
    rows.forEach(function(r){ maxIn = Math.max(maxIn, r.fanIn); maxOut = Math.max(maxOut, r.fanOut); });
    // Zero sits GAP inside the frame: the modules at 0 and 1 are the most
    // numerous, and their spirals would otherwise cover the tick labels.
    var GAP = 34;
    var w = W - PAD_L - PAD_R - GAP, h = H - PAD_T - PAD_B - GAP;
    function x(v){ return PAD_L + GAP + Math.sqrt(v / maxOut) * w; }
    function y(v){ return PAD_T + h - Math.sqrt(v / maxIn) * h; }
    var seen = {}, dots = [];
    rows.forEach(function(r){
      var key = r.fanIn + "/" + r.fanOut;
      var k = seen[key] || 0;
      seen[key] = k + 1;
      var rad = STEP * Math.sqrt(k), ang = k * 2.399963;
      dots.push({ row: r, x: x(r.fanOut) + rad * Math.cos(ang), y: y(r.fanIn) - rad * Math.sin(ang) });
    });
    return { dots: dots, x: x, y: y, maxIn: maxIn, maxOut: maxOut,
             left: PAD_L, right: W - PAD_R, top: PAD_T, bottom: H - PAD_B };
  }

  function couplingText(r){
    return r.name + " · required by " + r.fanIn + " · requires " + r.fanOut + " · " +
      COUPLING_CORNERS[r.corner].one;
  }

  function couplingReadout(r){
    var el = document.getElementById("cq-read");
    if(!el) return;
    el.textContent = r ? couplingText(r)
      : "point at a module, or move through them with the arrow keys · Enter opens it";
  }

  var couplingShown = [];
  function drawCoupling(centerId){
    var rows = couplingRows(centerId);
    couplingShown = rows;
    haltBar.innerHTML =
      '<span class="hmuted">fan-out across, fan-in up · the lines are at ' + COUPLING_HIGH +
      ': a module is a hub, tangle or pass-through from ' + COUPLING_HIGH + ' on</span>' +
      '<span class="cq-read" id="cq-read" aria-live="polite"></span>';
    haltBody.removeAttribute("role");
    if(!rows.length){
      haltBody.innerHTML = '<p class="hmsg">No module at or under ' +
        esc(byId[centerId].name || centerId) + ' requires another or is required by one.</p>';
      couplingReadout(null);
      return;
    }
    // Narrower than the pane by a scroll bar's width: the pane grows one
    // when the plot is taller than the window, and must not grow a second.
    var W = Math.max(haltBody.clientWidth - 28, 320);
    var H = Math.max(Math.min(Math.round(window.innerHeight - haltBody.getBoundingClientRect().top - 56),
      Math.round(W * 0.72)), 320);
    var L = couplingLayout(rows, W, H);
    var s = ['<svg class="cq" width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + " " + H +
      '" role="group" aria-label="Coupling: ' + rows.length + ' modules by fan-in and fan-out">'];

    // The two lines, and the four corners they make.
    var tx = L.x(COUPLING_HIGH), ty = L.y(COUPLING_HIGH);
    s.push('<line class="cq-split" x1="' + tx.toFixed(1) + '" y1="' + L.top + '" x2="' + tx.toFixed(1) +
      '" y2="' + L.bottom + '"/>');
    s.push('<line class="cq-split" x1="' + L.left + '" y1="' + ty.toFixed(1) + '" x2="' + L.right +
      '" y2="' + ty.toFixed(1) + '"/>');
    var count = { hub: 0, tangle: 0, pass: 0, leaf: 0 };
    rows.forEach(function(r){ count[r.corner]++; });
    function corner(key, cx, cy, anchor){
      var c = COUPLING_CORNERS[key];
      s.push('<text class="cq-corner" x="' + cx + '" y="' + cy + '" text-anchor="' + anchor + '">' +
        c.label + ' <tspan class="cq-n">' + count[key] + '</tspan><title>' + c.hint + '</title></text>');
    }
    corner("hub", L.left + 6, L.top + 12, "start");
    corner("tangle", L.right - 6, L.top + 12, "end");
    corner("leaf", L.left + 6, L.bottom - 6, "start");
    corner("pass", L.right - 6, L.bottom - 6, "end");

    // Axes: a frame, the ticks, what each axis counts.
    s.push('<path class="cq-axis" d="M' + L.left + " " + L.top + "V" + L.bottom + "H" + L.right + '"/>');
    couplingTicks(L.maxOut).forEach(function(t){
      var px = L.x(t).toFixed(1);
      s.push('<text class="cq-tick" x="' + px + '" y="' + (L.bottom + 14) + '" text-anchor="middle">' + t + '</text>');
    });
    couplingTicks(L.maxIn).forEach(function(t){
      var py = (L.y(t) + 3.5).toFixed(1);
      s.push('<text class="cq-tick" x="' + (L.left - 6) + '" y="' + py + '" text-anchor="end">' + t + '</text>');
    });
    s.push('<text class="cq-label" x="' + ((L.left + L.right) / 2) + '" y="' + (L.bottom + 29) +
      '" text-anchor="middle">modules it requires (fan-out)</text>');
    s.push('<text class="cq-label" transform="translate(12 ' + ((L.top + L.bottom) / 2) +
      ') rotate(-90)" text-anchor="middle">modules that require it (fan-in)</text>');

    L.dots.forEach(function(d, i){
      var r = d.row;
      s.push('<circle class="cq-dot cq-' + r.corner + (isHidden(r.id) ? " dim" : "") + '" cx="' + d.x.toFixed(1) +
        '" cy="' + d.y.toFixed(1) + '" r="4" tabindex="' + (i === 0 ? 0 : -1) + '" role="button" data-id="' +
        esc(r.id) + '" data-i="' + i + '" aria-label="' + esc(couplingText(r)) + '"><title>' +
        esc(couplingText(r)) + '</title></circle>');
    });
    s.push('</svg>');
    haltBody.innerHTML = s.join("");
    couplingReadout(null);
  }

  function couplingDot(ev){
    if(state.view !== "coupling" || !ev.target.closest) return null;
    return ev.target.closest(".cq-dot");
  }
  haltBody.addEventListener("click", function(ev){
    var dot = couplingDot(ev);
    if(dot && byId[dot.dataset.id]) navigate({ tab: "tree", id: dot.dataset.id });
  });
  haltBody.addEventListener("mouseover", function(ev){
    var dot = couplingDot(ev);
    if(dot) couplingReadout(couplingShown[+dot.dataset.i]);
  });
  haltBody.addEventListener("focusin", function(ev){
    var dot = couplingDot(ev);
    if(dot) couplingReadout(couplingShown[+dot.dataset.i]);
  });
  // One tab stop for the whole plot; the arrows walk the modules in the
  // order of `couplingRows` (the expensive corners first).
  haltBody.addEventListener("keydown", function(ev){
    var dot = couplingDot(ev);
    if(!dot) return;
    var all = Array.prototype.slice.call(haltBody.querySelectorAll(".cq-dot"));
    var i = all.indexOf(dot), to = null;
    if(ev.key === "ArrowRight" || ev.key === "ArrowDown") to = all[i + 1];
    else if(ev.key === "ArrowLeft" || ev.key === "ArrowUp") to = all[i - 1];
    else if(ev.key === "Home") to = all[0];
    else if(ev.key === "End") to = all[all.length - 1];
    else if(ev.key === "Enter" || ev.key === " "){
      ev.preventDefault();
      if(byId[dot.dataset.id]) navigate({ tab: "tree", id: dot.dataset.id });
      return;
    }
    if(!to) return;
    ev.preventDefault();
    all.forEach(function(x){ x.setAttribute("tabindex", "-1"); });
    to.setAttribute("tabindex", "0");
    to.focus();
  });

  // =====================================================================
  // Rings: the require graph laid out by distance from an entry module.
  //
  // "How deep is this, and what is reachable at all?" The Deps view shows a
  // neighbourhood; this one shows every module once, on the ring of its
  // shortest require chain from the entry: ring 1 is what the entry requires
  // itself, ring 2 what those require, and so on. Whatever no chain reaches
  // sits in a last, dashed ring. That ring is `unreferenced-module` as a
  // picture: the modules that carry the finding are marked in it, and the
  // others in it are required only by modules that are unreachable too.
  //
  // The entry is the center of the Hierarchy when that is a module, so a
  // click on a box, the search box and a link all pick it. When the center is
  // a folder the rings start at the default entry (`ringDefaultEntry`), and
  // the Entry select in the toolbar offers every root of the require graph:
  // a tree with several entries, or with no `init.lua`, has no single answer.
  //
  // It draws into the zooming stage like the box views, with positions of its
  // own, so zoom, pan, dimming, the context menu and the SVG export work on it
  // unchanged. The arrows are the require that first reaches each module;
  // they are shown for the box under the pointer or the pin only, where they
  // read as the chain from the entry. All 300 at once would be a disc of ink.
  // Lazy requires count like any other: reachable is reachable.
  //
  // A ring is an ellipse, twice as wide as high, because a box is three times
  // as wide as high; a ring too long for one row takes several.
  // =====================================================================
  var RING_AX = 184, RING_AY = 80;   // one unit of the layout in pixels, across and down
  var RING_SPACE = 1.25;             // along a row, between two boxes (units)
  var RING_STEP = 1.15;              // between two rows of one ring
  var RING_GAP = 1.3;                // between two rings
  var RING_MAX = 400;

  function isMapView(v){ return v === "rings" || v === "layers"; }

  function ringModule(id){
    var n = byId[id];
    return !!(n && n.module && n.kind !== "namespace");
  }

  function ringName(id){
    var n = byId[id] || {};
    return n.module || n.name || id;
  }

  // A module path without the prefix its surroundings already state (the
  // layer a box sits in, the root module of the map): on a box 168 pixels
  // wide, forty modules that all begin `app.bindings.` read as one name.
  function mapShortName(id, prefix){
    var name = ringName(id);
    if(!prefix || name === prefix) return name;
    return name.indexOf(prefix + ".") === 0 ? name.slice(prefix.length + 1) : name;
  }
  function mapRename(el, id, prefix){
    var nm = el.querySelector(".hnm");
    if(nm) nm.textContent = mapShortName(id, prefix);
  }

  // Breadth first along the requires: the distance of every module `entry`
  // reaches, the require that reached it first, and the order they were found
  // in (which keeps the modules one module requires next to each other).
  function ringDistances(entry){
    var dist = {}, via = {}, order = [entry];
    dist[entry] = 0;
    for(var i = 0; i < order.length; i++){
      var id = order[i];
      (depOut[id] || []).forEach(function(e){
        if(dist[e.to] !== undefined || !ringModule(e.to)) return;
        dist[e.to] = dist[id] + 1;
        via[e.to] = e;
        order.push(e.to);
      });
    }
    return { dist: dist, via: via, order: order };
  }

  function ringByDepth(a, b){
    var da = (byId[a].depth || 0), db = (byId[b].depth || 0);
    if(da !== db) return da - db;
    var na = ringName(a), nb = ringName(b);
    return na < nb ? -1 : (na > nb ? 1 : (a < b ? -1 : (a > b ? 1 : 0)));
  }

  // The roots of the require graph: modules that require something and that
  // nothing requires (the root of the map counts when it is a module, whoever
  // requires it). Shallowest first.
  function ringEntries(){
    var out = [];
    IR.nodes.forEach(function(n){
      if(!ringModule(n.id) || !(depOut[n.id] || []).length) return;
      if(n.id === IR.root || !(depIn[n.id] || []).length) out.push(n.id);
    });
    return out.sort(ringByDepth);
  }

  // Where the rings start when nobody chose: the root of the map when it is a
  // module that requires something (a Lua plugin's `init.lua`). Else the
  // module that reaches the most, looked for among the roots of the require
  // graph and the modules of the topmost level: an entry that its own
  // children require back (`require("app")` for the config) is no root, and
  // it is still where the tree starts. Ties go to the shallower, then to the
  // name, so one map always opens on the same module.
  var ringDefault;
  function ringDefaultEntry(){
    if(ringDefault !== undefined) return ringDefault;
    ringDefault = null;
    if(ringModule(IR.root) && (depOut[IR.root] || []).length){ ringDefault = IR.root; return ringDefault; }
    var mods = [];
    IR.nodes.forEach(function(n){ if(ringModule(n.id)) mods.push(n.id); });
    if(!mods.length) return null;
    var requiring = mods.filter(function(id){ return (depOut[id] || []).length; }).sort(ringByDepth);
    // Nothing requires anything: any module is as good, the first by depth and name.
    if(!requiring.length){ ringDefault = mods.sort(ringByDepth)[0]; return ringDefault; }
    var top = byId[requiring[0] ].depth || 0, pool = ringEntries(), seen = {};
    requiring.forEach(function(id){ if((byId[id].depth || 0) === top) pool.push(id); });
    var bestReach = -1;
    pool.sort(ringByDepth).slice(0, 200).forEach(function(id){
      if(seen[id]) return;
      seen[id] = true;
      var reach = ringDistances(id).order.length;
      if(reach > bestReach){ ringDefault = id; bestReach = reach; }
    });
    return ringDefault;
  }

  function ringUnreferenced(id){
    return (findByNode[id] || []).some(function(f){ return f.check === "unreferenced-module"; });
  }

  // Where the boxes of the rings go, in units around 0/0. `bands` is a list of
  // id lists, innermost first. A row holds what its circumference has room
  // for; what is left goes on the next row of the same band.
  function ringPlace(bands){
    var pos = {}, out = [], r = 0;
    bands.forEach(function(ids){
      r += RING_GAP;
      var band = { inner: r, outer: r, rows: 0 };
      var i = 0;
      while(i < ids.length){
        if(band.rows) r += RING_STEP;
        var n = Math.min(Math.max(1, Math.floor(2 * Math.PI * r / RING_SPACE)), ids.length - i);
        // Every second row starts half a step on, so the rows do not line up
        // into spokes.
        var shift = (band.rows % 2) ? Math.PI / n : 0;
        for(var k = 0; k < n; k++){
          var ang = -Math.PI / 2 + shift + 2 * Math.PI * k / n;
          pos[ids[i++] ] = { ux: r * Math.cos(ang), uy: r * Math.sin(ang) };
        }
        band.rows++;
      }
      band.outer = r;
      out.push(band);
    });
    return { pos: pos, bands: out, radius: r };
  }

  // A straight line between two boxes, from border to border: the boxes of a
  // ring lie in every direction from each other, so no side is the facing one.
  function ringEdge(a, b){
    var ax = a.x + BOX_W / 2, ay = a.y + BOX_H / 2, bx = b.x + BOX_W / 2, by = b.y + BOX_H / 2;
    var dx = bx - ax, dy = by - ay;
    if(!dx && !dy) return "M" + ax + "," + ay;
    var t = Math.min(dx ? (BOX_W / 2) / Math.abs(dx) : Infinity, dy ? (BOX_H / 2) / Math.abs(dy) : Infinity, 0.5);
    return "M" + (ax + dx * t).toFixed(1) + "," + (ay + dy * t).toFixed(1) +
      " L" + (bx - dx * t).toFixed(1) + "," + (by - dy * t).toFixed(1);
  }

  function ringPlural(n, one){ return n + " " + one + (n === 1 ? "" : "s"); }

  // The whole view for `drawHierarchy`: the same shape every layout returns,
  // plus positions of its own and what only this view draws.
  var ringShown = null;
  function layoutRings(centerId){
    var entry = ringModule(centerId) ? centerId : ringDefaultEntry();
    ringShown = null;
    if(!entry) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };
    var walk = ringDistances(entry);

    var rings = [];
    walk.order.forEach(function(id){
      var d = walk.dist[id];
      if(d > 0) (rings[d - 1] = rings[d - 1] || []).push(id);
    });
    var outside = [];
    IR.nodes.forEach(function(n){
      if(ringModule(n.id) && walk.dist[n.id] === undefined) outside.push(n.id);
    });
    var unref = {};
    outside.forEach(function(id){ if(ringUnreferenced(id)) unref[id] = true; });
    // The findings first: they are why the others are out here.
    outside.sort(function(a, b){
      if(!!unref[a] !== !!unref[b]) return unref[a] ? -1 : 1;
      return ringByDepth(a, b);
    });
    var total = walk.order.length + outside.length, reached = walk.order.length;
    var unrefCount = Object.keys(unref).length, outsideCount = outside.length;

    // The cap takes from the outside in: the unreachable ring first, then the
    // deepest rings.
    var room = RING_MAX - 1, truncated = false;
    var bands = [], kinds = [];
    rings.forEach(function(ids, i){
      if(room <= 0){ truncated = true; return; }
      if(ids.length > room){ ids = ids.slice(0, room); truncated = true; }
      room -= ids.length;
      bands.push(ids); kinds.push(i + 1);
    });
    if(outside.length){
      if(outside.length > room){ outside = outside.slice(0, room); truncated = true; }
      if(outside.length){ bands.push(outside); kinds.push("out"); }
    }

    var placed = ringPlace(bands);
    var cx = PAD + placed.radius * RING_AX + BOX_W / 2;
    var cy = PAD + placed.radius * RING_AY + BOX_H / 2;
    var positions = {}, included = {}, count = 1;
    positions[entry] = { x: Math.round(cx - BOX_W / 2), y: Math.round(cy - BOX_H / 2) };
    included[entry] = 0;
    bands.forEach(function(ids, i){
      ids.forEach(function(id){
        var p = placed.pos[id];
        positions[id] = { x: Math.round(cx + p.ux * RING_AX - BOX_W / 2),
                          y: Math.round(cy + p.uy * RING_AY - BOX_H / 2) };
        included[id] = i + 1;
        count++;
      });
    });

    var edges = [];
    Object.keys(walk.via).forEach(function(id){
      var e = walk.via[id];
      if(positions[id] === undefined || positions[e.from] === undefined) return;
      edges.push({ from: e.from, to: id, cls: "hedge hedge-dep hedge-quiet" + (e.deferred ? " deferred" : ""),
                   marker: "dep",
                   label: (e.deferred ? "lazy require " : "require ") + e.to_module + ":" + e.line });
    });

    // Pointing at a box lights its chain back to the entry and what is first
    // reached through it.
    var near = {};
    Object.keys(positions).forEach(function(id){
      var set = {};
      for(var at = id; walk.via[at]; at = walk.via[at].from) set[walk.via[at].from] = true;
      near[id] = set;
    });
    edges.forEach(function(e){ near[e.from][e.to] = true; });

    function chain(id){
      var names = [ringName(id)];
      for(var at = id; walk.via[at]; at = walk.via[at].from) names.unshift(ringName(walk.via[at].from));
      return names.join(" → ");
    }
    function why(id){
      if(id === entry) return "the entry: the rings count the requires from here";
      var d = walk.dist[id];
      if(d !== undefined) return ringPlural(d, "require") + " from the entry: " + chain(id);
      if(unref[id]) return "not reachable from " + ringName(entry) + ": nothing in this map requires it (unreferenced-module)";
      var by = (depIn[id] || []).map(function(e){ return ringName(e.from); });
      if(!by.length) return "not reachable from " + ringName(entry) + ": nothing in this map requires it";
      return "not reachable from " + ringName(entry) + ": required only by " + by.slice(0, 3).join(", ") +
        (by.length > 3 ? " and " + (by.length - 3) + " more" : "") + ", which the entry does not reach either";
    }

    ringShown = { entry: entry, picked: centerId === entry, total: total, reached: reached,
                  depth: rings.length, outside: outsideCount, unref: unrefCount };

    return {
      layers: [ [entry] ].concat(bands), included: included, count: count, truncated: truncated, edges: edges,
      positions: positions, extent: { w: Math.round(cx * 2), h: Math.round(cy * 2) },
      centerKey: entry, edgePath: ringEdge, neighbours: near, tip: why,
      edgeNear: function(key, from, to){ return to === key || !!near[key][to] && !!near[key][from] || from === key; },
      truncNote: "Showing " + count + " of " + total + " modules: the unreachable ring and the deepest rings are cut first.",
      // The rings themselves, drawn below the edges and the boxes.
      decor: function(svg, svgNS){
        placed.bands.forEach(function(band, i){
          var out = kinds[i] === "out";
          var rb = band.inner - RING_GAP / 2;
          var el = document.createElementNS(svgNS, "ellipse");
          el.setAttribute("class", "hring" + (out ? " hring-out" : ""));
          el.setAttribute("cx", cx); el.setAttribute("cy", cy);
          el.setAttribute("rx", (rb * RING_AX).toFixed(1)); el.setAttribute("ry", (rb * RING_AY).toFixed(1));
          svg.appendChild(el);
        });
      },
      // What each ring is, written over the edges: an arrow of the chain may
      // cross a name, and the name has to stay readable.
      overlay: function(svg, svgNS){
        placed.bands.forEach(function(band, i){
          var out = kinds[i] === "out";
          var rb = band.inner - RING_GAP / 2;
          var label = document.createElementNS(svgNS, "text");
          label.setAttribute("class", "hring-label" + (out ? " hring-out" : ""));
          label.setAttribute("x", cx); label.setAttribute("y", (cy - rb * RING_AY - 6).toFixed(1));
          label.setAttribute("text-anchor", "middle");
          label.textContent = out
            ? "not reachable from " + ringName(entry) + " · " + ringPlural(outsideCount, "module") +
              (unrefCount ? " · " + unrefCount + " unreferenced-module" : "")
            : ringPlural(kinds[i], "require") + " away · " + ringPlural(bands[i].length, "module");
          svg.appendChild(label);
        });
      },
      // Runs after `reconcile`, which resets a box's class and markup on
      // every draw: what a box is in this view, said on it and in its tooltip.
      paint: function(){
        Object.keys(positions).forEach(function(id){
          var el = hboxes[id];
          if(!el) return;
          var d = walk.dist[id];
          mapRename(el, id, (byId[IR.root] || {}).module);
          el.dataset.ring = d === undefined ? "out" : String(d);
          var tag = id === entry ? "entry" : (d === undefined ? (unref[id] ? "unreferenced-module" : "not reachable") : "");
          if(d === undefined) el.classList.add("ring-out");
          if(unref[id]) el.classList.add("ring-unref");
          if(tag){
            var sm = el.querySelector(".hsm");
            if(sm) sm.remove();
            var k = document.createElement("div");
            k.className = "hkind";
            k.textContent = tag;
            el.appendChild(k);
          }
          el.title = (el._spec ? el._spec.title : el.title) + "\n" + why(id);
        });
        ringControls();
      }
    };
  }

  // The Entry select: the roots of the require graph with how much each
  // reaches, and the entry on screen when it is none of them.
  function ringControls(){
    var sel = document.getElementById("hentry");
    if(!sel || !ringShown) return;
    var ids = ringEntries().slice(0, 60);
    var first = ringDefaultEntry();
    [first, ringShown.entry].forEach(function(id){ if(id && ids.indexOf(id) === -1) ids.unshift(id); });
    var all = 0;
    IR.nodes.forEach(function(n){ if(ringModule(n.id)) all++; });
    sel.innerHTML = ids.map(function(id){
      return '<option value="' + esc(id) + '"' + (id === ringShown.entry ? " selected" : "") + ">" +
        esc(ringName(id)) + " · reaches " + ringDistances(id).order.length + " of " + all + "</option>";
    }).join("");
  }

  // What stands under the diagram: the two numbers the view is for, and the
  // way from the unreachable ring to the finding it shows.
  function ringNote(){
    var s = ringShown;
    if(!s) return null;
    var box = document.createElement("div");
    box.className = "htrunc hauto hring-note";
    var text = (s.picked ? "" : "Started at " + ringName(s.entry) + ", the entry of this map (the center is a folder). ") +
      ringName(s.entry) + " reaches " + s.reached + " of " + ringPlural(s.total, "module") + ", the farthest " +
      ringPlural(s.depth, "require") + " away.";
    if(s.outside){
      text += " " + ringPlural(s.outside, "module") + " " + (s.outside === 1 ? "is" : "are") +
        " not reachable from it";
      if(!s.unref) text += ".";
      else if(s.outside === 1) text += " and carries the unreferenced-module finding: nothing requires it.";
      else if(s.unref === s.outside) text += ", and all of them carry the unreferenced-module finding: nothing requires them.";
      else text += ": " + s.unref + " carr" + (s.unref === 1 ? "ies" : "y") +
        " the unreferenced-module finding (nothing requires " + (s.unref === 1 ? "it" : "them") +
        "), the others are required only by unreachable modules or are exempt from that check.";
    }
    box.appendChild(document.createTextNode(text + " "));
    if(s.unref){
      var b = document.createElement("button");
      b.type = "button";
      b.id = "hring-findings";
      b.textContent = "Show the findings";
      b.addEventListener("click", function(){ navigate({ tab: "findings" }); });
      box.appendChild(b);
    }
    return box;
  }

  // =====================================================================
  // Layers: the tree in the bands its layering rules imply.
  //
  // "Does this tree have the shape I claim it has?" The rules of `layers`
  // (in `.docmap.json`) each forbid one direction: modules under `from` may
  // not require modules under `to`. `core/layers.lua` turns them into a
  // picture and ships it as `IR.layers`: every prefix a rule names is a
  // layer, a module belongs to the layer with the longest prefix it sits
  // under, and a layer that may not reach another sits below it, because the
  // forbidden direction is up. Layers that forbid each other in a circle
  // have no order; they share a band and the note says so.
  //
  // What is drawn: a frame per layer with its modules, the frames in bands
  // (the base at the bottom), and below them the modules no rule names. A
  // require that breaks a rule is a red arrow, drawn over the boxes, always
  // visible; it is the `layer-violation` finding as a line you can point at.
  // Every other require is shown for the box under the pointer or the pin
  // only. Which edge breaks a rule is decided in Lua by the function the
  // check uses, not here.
  //
  // It draws in the zooming stage, like the Rings, with positions of its own.
  // =====================================================================
  var LAYER_CELL_W = 184, LAYER_CELL_H = 74;   // a box and the gap after it
  var LAYER_PAD = 14, LAYER_HEAD = 30;          // inside a layer's frame
  var LAYER_GAP = 28, LAYER_BAND_PAD = 18, LAYER_BAND_HEAD = 22, LAYER_BAND_GAP = 26;
  var LAYER_MAX = 600;

  // How many boxes a layer puts in a row: about twice as wide as high.
  function layerCols(n){ return Math.max(1, Math.min(10, Math.ceil(Math.sqrt(0.72 * n)))); }

  function layerViolationText(L, v){
    var rule = (L.rules || [])[v.rule - 1] || {};
    return ringName(v.from) + " requires " + ringName(v.to) + ", but " + v.from_layer +
      " must not reach into " + v.to_layer + (rule.why ? " (" + rule.why + ")" : "");
  }

  var layerShown = null;
  function layoutLayers(){
    var L = IR.layers;
    layerShown = null;
    var none = { layers: [], included: {}, count: 0, truncated: false, edges: [] };
    if(!L || !(L.units || []).length) return none;

    // The rows of the picture, from the top: the bands, highest first, then
    // what no rule names.
    var rows = [];
    for(var b = L.bands - 1; b >= 0; b--){
      rows.push({ band: b, units: L.units.filter(function(u){ return u.band === b; }) });
    }
    var loose = (L.unassigned || []).filter(function(id){ return !!byId[id]; });
    if(loose.length) rows.push({ band: null, units: [{ id: null, modules: loose }] });

    // A module in a broken rule is never the one the cap drops.
    var hot = {};
    (L.violations || []).forEach(function(v){ hot[v.from] = true; hot[v.to] = true; });
    var total = 0, unitCount = 0;
    rows.forEach(function(row){ row.units.forEach(function(u){
      u.all = (u.modules || []).filter(function(id){ return !!byId[id]; });
      total += u.all.length; unitCount++;
    }); });
    var per = total > LAYER_MAX ? Math.max(12, Math.floor(LAYER_MAX / unitCount)) : Infinity;
    var truncated = false, count = 0;

    var positions = {}, included = {}, unitOf = {}, frames = [], y = PAD, width = 0;
    rows.forEach(function(row){
      row.units.forEach(function(u){
        u.shown = u.all;
        if(u.all.length > per){
          truncated = true;
          u.shown = u.all.filter(function(id){ return hot[id]; })
            .concat(u.all.filter(function(id){ return !hot[id]; })).slice(0, per);
        }
        u.cols = layerCols(u.shown.length);
        u.lines = Math.ceil(u.shown.length / u.cols);
        u.w = u.cols * LAYER_CELL_W - GAP_X + 2 * LAYER_PAD;
        u.h = LAYER_HEAD + Math.max(u.lines, 1) * LAYER_CELL_H - (LAYER_CELL_H - BOX_H) + LAYER_PAD;
      });
      row.w = row.units.reduce(function(a, u){ return a + u.w; }, 0) + (row.units.length - 1) * LAYER_GAP;
      row.h = row.units.reduce(function(a, u){ return Math.max(a, u.h); }, 0);
      width = Math.max(width, row.w);
    });
    var W = width + 2 * LAYER_BAND_PAD + 2 * PAD;
    rows.forEach(function(row, ri){
      row.y = y;
      row.bh = LAYER_BAND_HEAD + row.h + 2 * LAYER_BAND_PAD;
      var x = PAD + LAYER_BAND_PAD + (width - row.w) / 2;
      row.units.forEach(function(u){
        u.x = Math.round(x);
        u.y = y + LAYER_BAND_HEAD + LAYER_BAND_PAD;
        u.shown.forEach(function(id, i){
          positions[id] = { x: u.x + LAYER_PAD + (i % u.cols) * LAYER_CELL_W,
                            y: u.y + LAYER_HEAD + Math.floor(i / u.cols) * LAYER_CELL_H };
          included[id] = ri;
          unitOf[id] = u.id;
          count++;
        });
        frames.push(u);
        x += u.w + LAYER_GAP;
      });
      y += row.bh + LAYER_BAND_GAP;
    });
    var H = y - LAYER_BAND_GAP + PAD;

    // One arrow per pair of modules, however many rules it breaks.
    var broken = {}, brokenList = [];
    (L.violations || []).forEach(function(v){
      var key = v.from + " " + v.to;
      if(!broken[key]){ broken[key] = { from: v.from, to: v.to, texts: [] }; brokenList.push(broken[key]); }
      broken[key].texts.push(layerViolationText(L, v));
    });
    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "require" || e.from === e.to) return;
      if(positions[e.from] === undefined || positions[e.to] === undefined) return;
      if(broken[e.from + " " + e.to]) return;
      edges.push({ from: e.from, to: e.to,
                   cls: "hedge hedge-dep hedge-quiet" + (e.deferred ? " deferred" : ""), marker: "dep",
                   label: (e.deferred ? "lazy require " : "require ") + e.to_module + ":" + e.line });
    });
    brokenList.forEach(function(v){
      if(positions[v.from] === undefined || positions[v.to] === undefined) return;
      edges.push({ from: v.from, to: v.to, cls: "hedge hedge-viol", marker: "viol", top: true,
                   label: v.texts.join("\n") });
    });

    var shared = {};
    (L.shared || []).forEach(function(id){ shared[id] = true; });
    var bySource = {}, byTarget = {};
    brokenList.forEach(function(v){
      (bySource[v.from] = bySource[v.from] || []).push(v);
      (byTarget[v.to] = byTarget[v.to] || []).push(v);
    });

    var layered = total - loose.length;
    layerShown = { rules: (L.rules || []).length, bands: L.bands, layers: L.units.length, layered: layered,
                   loose: loose.length, broken: brokenList.length, loops: L.loops || [] };

    function label(svg, svgNS, cls, x, yy, text){
      var t = document.createElementNS(svgNS, "text");
      t.setAttribute("class", "hmap-label " + cls);
      t.setAttribute("x", x); t.setAttribute("y", yy);
      t.textContent = text;
      svg.appendChild(t);
    }
    function rect(svg, svgNS, cls, x, yy, w, h, r){
      var el = document.createElementNS(svgNS, "rect");
      el.setAttribute("class", cls);
      el.setAttribute("x", x); el.setAttribute("y", yy);
      el.setAttribute("width", w); el.setAttribute("height", h); el.setAttribute("rx", r);
      svg.appendChild(el);
    }

    return {
      layers: [Object.keys(positions)], included: included, count: count, truncated: truncated, edges: edges,
      positions: positions, extent: { w: W, h: H }, edgePath: ringEdge,
      path: ringPlural(layerShown.rules, "rule") + " · layers",
      truncNote: "Showing " + count + " of " + total + " modules: a layer shows its first " + per +
        ", the ones in a broken rule first.",
      decor: function(svg, svgNS){
        rows.forEach(function(row){
          rect(svg, svgNS, "hband" + (row.band === null ? " hband-loose" : ""), PAD, row.y, W - 2 * PAD, row.bh, 10);
        });
        frames.forEach(function(u){
          if(u.id !== null) rect(svg, svgNS, "hunit" + (u.siblings ? " hunit-sib" : ""), u.x, u.y, u.w, u.h, 8);
        });
      },
      overlay: function(svg, svgNS){
        rows.forEach(function(row){
          label(svg, svgNS, "hband-name", PAD + 12, row.y + 16, row.band === null
            ? "named by no rule · " + ringPlural(loose.length, "module")
            : "band " + (row.band + 1) + " of " + L.bands +
              (row.band === 0 ? " · the base: no rule forbids anything to require it"
                              : " · a rule forbids a band below to require it"));
        });
        frames.forEach(function(u){
          if(u.id === null) return;
          label(svg, svgNS, "hunit-name", u.x + LAYER_PAD, u.y + 19,
            u.id + " · " + (u.shown.length < u.all.length ? u.shown.length + " of " : "") +
            ringPlural(u.all.length, "module") + (u.siblings ? " · siblings" : ""));
        });
      },
      paint: function(){
        Object.keys(positions).forEach(function(id){
          var el = hboxes[id];
          if(!el) return;
          var out = bySource[id] || [], into = byTarget[id] || [], tips = [], tag = "";
          mapRename(el, id, unitOf[id]);
          el.dataset.layer = unitOf[id] || "";
          out.forEach(function(v){ tips = tips.concat(v.texts); });
          into.forEach(function(v){ tips.push("required against a rule by " + ringName(v.from)); });
          if(out.length){
            el.classList.add("lv-from");
            tag = "breaks a rule · " + ringPlural(out.length, "require");
          } else if(shared[id]) tag = "shared target";
          if(into.length) el.classList.add("lv-to");
          if(shared[id]) tips.push("a rule's allow list exempts it as a target");
          if(tag){
            var sm = el.querySelector(".hsm");
            if(sm) sm.remove();
            var k = document.createElement("div");
            k.className = "hkind";
            k.textContent = tag;
            el.appendChild(k);
          }
          if(tips.length) el.title = (el._spec ? el._spec.title : el.title) + "\n" + tips.join("\n");
        });
      }
    };
  }

  function layerNote(){
    var s = layerShown;
    if(!s) return null;
    var box = document.createElement("div");
    box.className = "htrunc hauto hmap-note";
    var text = ringPlural(s.rules, "rule") + " put " + ringPlural(s.layered, "module") + " into " +
      ringPlural(s.layers, "layer") + " on " + ringPlural(s.bands, "band") + ". " +
      (s.loose ? ringPlural(s.loose, "module") + " " + (s.loose === 1 ? "is" : "are") + " named by no rule. " : "") +
      (s.broken ? ringPlural(s.broken, "require") + " break" + (s.broken === 1 ? "s" : "") + " a rule (the red arrow" +
                  (s.broken === 1 ? "" : "s") + ")."
                : "No require breaks a rule.");
    s.loops.forEach(function(group){
      text += " No order holds among " + group.join(", ") +
        ": they forbid each other in a circle, so they share a band.";
    });
    box.appendChild(document.createTextNode(text + " "));
    if(s.broken){
      var b = document.createElement("button");
      b.type = "button";
      b.id = "hmap-findings";
      b.textContent = "Show the findings";
      b.addEventListener("click", function(){ navigate({ tab: "findings" }); });
      box.appendChild(b);
    }
    return box;
  }

  function mapNote(view){ return view === "layers" ? layerNote() : ringNote(); }

  function mapLegend(view){
    if(view === "layers"){
      return '<span class="lg"><span class="sw viol"></span>a require that breaks a rule</span>' +
        '<span class="lg"><span class="bx lv-from"></span>the module that requires against a rule</span>' +
        '<span class="lg"><span class="sw dep"></span>any other require (shown for the box you point at)</span>' +
        '<span class="lg">a band is above another because a rule forbids the lower one to require it</span>' +
        '<span class="lg">wheel zooms · shift+wheel pans · click pins a box, a second click opens it in the Tree tab · right-click for more</span>';
    }
    return '<span class="lg"><span class="bx ring-entry"></span>the entry</span>' +
      '<span class="lg"><span class="bx ring-out"></span>not reachable from the entry</span>' +
      '<span class="lg"><span class="bx ring-out ring-unref"></span>… and an unreferenced-module finding</span>' +
      '<span class="lg"><span class="sw dep"></span>the require that first reaches a module (shown for the box you point at)</span>' +
      '<span class="lg">wheel zooms · shift+wheel pans · click pins a box, a second click makes it the entry · right-click for more</span>';
  }

  document.getElementById("hentry").addEventListener("change", function(ev){
    if(byId[ev.target.value]) navigate({ center: ev.target.value, fn: null });
  });

]]
