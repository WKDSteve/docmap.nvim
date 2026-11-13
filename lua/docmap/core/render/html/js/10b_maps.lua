---@module 'docmap.core.render.html.js.10b_maps'
--- A slice of the page's script: the maps of the Hierarchy (the tint of the Modules view and its legend, the
--- Coupling plot).
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

]]
