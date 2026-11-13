---@module 'docmap.core.render.html.js.10b_maps'
--- A slice of the page's script: the maps of the Hierarchy (the tint of the Modules view and its legend).
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

]]
