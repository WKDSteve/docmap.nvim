---@module 'docmap.core.render.html.js.09_zoom_graph_export'
--- A slice of the page's script: Zoom, graph interaction and toolbar, SVG export, inbound channel.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Zoom — two mechanisms that must stay separate in the code, or both end
  // up half-done:
  //
  //   geometric  the same diagram, larger. A CSS transform on #hstage.
  //              No relayout, no redraw, nothing in the URL — it is comfort,
  //              not state.
  //   semantic   past a threshold, a *different* excerpt: one level down into
  //              the module under the cursor, or one level up. That is
  //              exactly the navigate({center}) double-click already does.
  //
  // The geometric zoom is the feel between two levels; the semantic one is
  // the jump. Only the jump touches history — the same rule the search
  // preview had to learn, for the same reason.
  //
  // Positions stay analytic. The transform sits on a layer *above* the
  // computed pixel coordinates, so `positions`, reconcile() and the SVG paths
  // are all unaware a zoom exists.
  // =====================================================================
  var Z_MIN = 0.35, Z_MAX = 2.40;
  var DRILL_IN = 1.80, DRILL_OUT = 0.55;
  var AFTER_IN = 0.90, AFTER_OUT = 1.15;
  var COOLDOWN_MS = 260;
  var LOD_MIN = 0.65;

  var hzoom = 1;
  var stageExtent = { w: 0, h: 0 };
  var lastJump = 0;
  var suppressAutoScroll = false;
  var zoomLabel;

  function clampZoom(z){ return Math.min(Z_MAX, Math.max(Z_MIN, z)); }

  // #hgraph is sized to the scaled extent because a transform leaves layout
  // size alone; without this the scroll area would not grow on zoom-in and
  // half the diagram would be unreachable.
  function applyZoom(){
    hstage.style.transform = "scale(" + hzoom + ")";
    hgraph.style.width = Math.round(stageExtent.w * hzoom) + "px";
    hgraph.style.height = Math.round(stageExtent.h * hzoom) + "px";
    hstage.classList.toggle("lod-min", hzoom < LOD_MIN);
    if(zoomLabel) zoomLabel.textContent = Math.round(hzoom * 100) + "%";
  }

  // Keeps the graph point under the cursor fixed while scaling around it —
  // without this the diagram slides out from under the pointer and zooming
  // feels like it is fighting you.
  function zoomAt(clientX, clientY, factor){
    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var before = hzoom;
    hzoom = clampZoom(hzoom * factor);
    if(hzoom === before) return false;
    applyZoom();
    hgraphWrap.scrollLeft = gx * hzoom - (clientX - r.left);
    hgraphWrap.scrollTop = gy * hzoom - (clientY - r.top);
    return true;
  }

  function setZoom(z){
    hzoom = clampZoom(z);
    applyZoom();
  }

  // The box under the cursor, or — when the pointer sits in empty space —
  // the nearest one, measured from `positions` rather than from the DOM, so
  // this keeps working at any scale and never triggers a layout read.
  function boxNear(clientX, clientY){
    var direct = boxOf(document.elementFromPoint(clientX, clientY));
    if(direct) return direct;

    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var best = null, bestD = Infinity;
    Object.keys(hboxes).forEach(function(k){
      var el = hboxes[k];
      if(el.classList.contains("leaving")) return;
      var dx = parseFloat(el.style.left) + BOX_W / 2 - gx;
      var dy = parseFloat(el.style.top) + BOX_H / 2 - gy;
      var d = dx * dx + dy * dy;
      if(d < bestD){ bestD = d; best = el; }
    });
    return best;
  }

  // A jump that cannot happen — a leaf with no children, the root on the way
  // out, an external box that stands for nothing — pulses the box instead of
  // silently doing nothing, which reads as a bug. The zoom is deliberately
  // left where it is: on a leaf, zooming further in to read the box is a
  // reasonable thing to want, and crossing-based triggering means it will not
  // re-fire on every further notch.
  function refuseJump(box){
    if(box && !reducedMotion()){
      box.classList.remove("pulse");
      void box.offsetWidth;
      box.classList.add("pulse");
    }
  }

  // In Deps and Calls "one level deeper" is not defined — a require graph is
  // not a containment hierarchy. Depth is the axis that means "show more"
  // there, and it already exists as state and as a toolbar control, so the
  // threshold binds to it instead.
  function drill(dir, clientX, clientY){
    var now = Date.now();
    // One flick of the wheel must not fall three levels. Blocked by the
    // cooldown, the zoom is pulled back just inside the threshold so the next
    // notch crosses it again — left where it was, the gesture would have to
    // be wound all the way back before it could retry.
    if(now - lastJump < COOLDOWN_MS){
      setZoom(dir > 0 ? DRILL_IN - 0.02 : DRILL_OUT + 0.02);
      return;
    }

    if(isGraphView(state.view)){
      var d = state.depth === 0 ? 0 : (state.depth || 2);
      var next = dir > 0 ? (d === 0 ? 0 : d + 1) : (d <= 1 ? 1 : d - 1);
      if(next === d){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(dir > 0 ? AFTER_IN : AFTER_OUT);
      navigate({ depth: next });
      return;
    }

    if(dir > 0){
      var box = boxNear(clientX, clientY);
      var target = box && box._spec && box._spec.recenter;
      // Three refusals, all of which would otherwise reset the zoom for no
      // visible reason: nothing under the cursor, a leaf with no level below
      // it, and — the easy one to miss — the box that is *already* the
      // center, whose children are what the view is showing right now.
      if(!target || target === hcenter || !((byId[target] || {}).children || []).length){
        refuseJump(box);
        return;
      }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_IN);
      navigate({ center: target, fn: null });
    } else {
      var parent = (byId[hcenter] || {}).parent;
      if(!parent){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_OUT);
      navigate({ center: parent, fn: null });
    }
  }

  hgraphWrap.addEventListener("wheel", function(ev){
    // Shift keeps a way to pan horizontally, which is what the wheel would
    // otherwise have done here.
    if(ev.shiftKey){
      ev.preventDefault();
      hgraphWrap.scrollLeft += ev.deltaY;
      return;
    }
    ev.preventDefault();

    // Exponential so each notch feels the same at any scale, and so a
    // trackpad's small deltas do not crawl. ctrl+wheel is what a pinch
    // gesture arrives as, and it means the same thing here.
    var before = hzoom;
    var factor = Math.exp(-ev.deltaY * 0.0015);
    zoomAt(ev.clientX, ev.clientY, factor);

    // Fires on *crossing* the threshold, not on being past it. Two things
    // depend on that: a refused jump (a leaf, the root) leaves the zoom above
    // the line without re-firing on every further notch, and — the bug this
    // replaced — a zoom that came to rest above DRILL_IN no longer drills
    // *in* when the next notch is a zoom-*out*.
    if(before < DRILL_IN && hzoom >= DRILL_IN) drill(1, ev.clientX, ev.clientY);
    else if(before > DRILL_OUT && hzoom <= DRILL_OUT) drill(-1, ev.clientX, ev.clientY);
  }, { passive: false });

  // Keyboard equivalents, so the view is not mouse-only.
  document.addEventListener("keydown", function(ev){
    if(state.tab !== "hierarchy") return;
    // Tree and Treemap hide the zoom controls; the keys would otherwise
    // change the zoom of the diagram that is not on screen.
    if(isAltView(state.view)) return;
    if(ev.target && /^(INPUT|TEXTAREA)$/.test(ev.target.tagName)) return;
    if(ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if(ev.key === "+" || ev.key === "="){ ev.preventDefault(); setZoom(hzoom * 1.2); }
    else if(ev.key === "-"){ ev.preventDefault(); setZoom(hzoom / 1.2); }
    else if(ev.key === "0"){ ev.preventDefault(); setZoom(1); }
  });

  // =====================================================================
  // Graph interaction. Delegated from #hgraph rather than bound per box:
  // reconcile() reuses boxes across redraws, and re-adding listeners on every
  // draw would stack duplicates on exactly the boxes that survive longest.
  // =====================================================================
  var hgraphNeighbours = {};

  function boxOf(target){
    var el = target;
    while(el && el !== hgraph){
      if(el.classList && el.classList.contains("hnode")) return el;
      el = el.parentNode;
    }
    return null;
  }

  // =====================================================================
  // Which click does what.
  //
  // **The default swapped on 2026-08-20**, deliberately. Before, a single
  // click left the Hierarchy for the Tree view and a double click recentred
  // — which meant the cheapest, most reflexive gesture did the one thing
  // that abandons the view you are working in, and the deliberate gesture
  // did the thing the view exists for. `WORKPLAN.md` §9.2 named it "the most
  // surprising thing in the view" and left the swap as an open decision
  // precisely because existing muscle memory is a real cost.
  //
  // So the swap ships with a way back rather than as a fait accompli. It now
  // follows the convention every file manager and tree widget uses: a single
  // click selects and stays, a double click commits and opens.
  //
  // The preference is stored **unscoped**, unlike marks and hidden boxes,
  // which key on `location.pathname`. Those are facts about one project's
  // map; this is a fact about the person's hands, and it would be absurd to
  // relearn the gesture per repository.
  var GESTURE_LS_KEY = "docmap:classic-clicks";
  var classicClicks = false;
  try { classicClicks = localStorage.getItem(GESTURE_LS_KEY) === "1"; } catch(e){ void 0; }

  function leaveForTree(box){
    // A tag_files-resolved external box has no node in *this* map — nothing
    // to navigate to here — but does have another project's own generated
    // page to open, in a new tab so the current map's state is not lost.
    if(box._spec.externalHtml){ window.open(box._spec.externalHtml, "_blank"); return; }
    // An unresolved external box has no node behind it at all — no id to
    // select, nothing to re-center on. Inert rather than navigating
    // somewhere arbitrary.
    if(!box._spec.nodeId) return;
    navigate({ tab: "tree", id: box._spec.nodeId });
  }

  function recentreOn(box){
    if(!box._spec.recenter) return;
    // In the Calls view a re-center lands on the function itself, which is
    // the whole point of the view; elsewhere there is no finer object than
    // the node.
    if(box._spec.fnKey) navigate({ center: box._spec.recenter, fn: box._spec.fnKey });
    else navigate({ center: box._spec.recenter, fn: null });
  }

  // What a click on a box actually does.
  //
  // **First click pins, second click acts** — added 2026-08-20, on top of the
  // gesture swap above. Hovering already lights a box and its direct
  // neighbours and dims everything else, and all of it vanished the moment
  // the pointer moved, so the highlighted subgraph could not be read, traced
  // or followed. Freezing it is what makes the view legible; the action is
  // one click further on.
  //
  // **A double click is that sequence, only fast**, which is why there is no
  // `dblclick` handler any more. The two `click` events a double click emits
  // already pin and then act, so a reader who knows where they are going
  // pays nothing for the pin and never sees it. A third handler on top would
  // have fired *in addition* to those two and acted twice.
  //
  // The `classicClicks` pill keeps its meaning unchanged: it decides what the
  // *second* click does — root the graph here, or open the module in Tree.
  function actOn(box){
    if(classicClicks){ leaveForTree(box); return; }
    // An external box has nothing in this map to recentre on, so it keeps
    // its old meaning under either setting rather than becoming inert.
    if(box._spec.externalHtml || !box._spec.recenter){ leaveForTree(box); return; }
    recentreOn(box);
  }

  hgraph.addEventListener("click", function(ev){
    var box = boxOf(ev.target);
    // A click on the graph's own background releases the pin. The gesture
    // everybody tries reflexively to drop a selection, so it should not need
    // discovering.
    if(!box || !box._spec){ unpin(); return; }
    var key = box.dataset.key;
    if(pinnedKey === key){ actOn(box); return; }
    // A different box re-pins there rather than releasing first. Without
    // that, following a chain — the one thing this exists for — would be the
    // most tedious way to use it.
    pin(key);
  });

  document.getElementById("hgest").addEventListener("click", function(){
    classicClicks = !classicClicks;
    try {
      if(classicClicks) localStorage.setItem(GESTURE_LS_KEY, "1");
      else localStorage.removeItem(GESTURE_LS_KEY);
    } catch(e){ void 0; }
    this.classList.toggle("active", classicClicks);
  });

  // Focus: dim everything that is not a direct neighbour of one box. Pure
  // class toggling — on a dense require graph this is the difference between
  // a readable diagram and a spider's web, and it costs no relayout.
  //
  // Driven by the pointer *or* by a pin, which is why it is a function of a
  // key rather than of an event.
  function focusOn(key){
    var near = hgraphNeighbours[key] || {};
    hgraph.classList.add("focusing");
    Object.keys(hboxes).forEach(function(k){
      hboxes[k].classList.toggle("near", k === key || near[k]);
      hboxes[k].classList.toggle("pinned", k === pinnedKey);
    });
    var svg = document.getElementById("hsvg");
    if(svg) svg.querySelectorAll(".hedge").forEach(function(p){
      p.classList.toggle("near", p.dataset.from === key || p.dataset.to === key);
    });
  }

  function clearFocus(){
    hgraph.classList.remove("focusing");
    Object.keys(hboxes).forEach(function(k){ hboxes[k].classList.remove("pinned"); });
  }

  // The pinned box, or null. Held here rather than in `state`: a pin is a
  // way of looking at the graph, not a place in it, so it never rides in the
  // URL and pressing Back does not undo one.
  var pinnedKey = null;

  function pin(key){
    pinnedKey = key;
    focusOn(key);
  }

  function unpin(){
    if(pinnedKey === null) return;
    pinnedKey = null;
    clearFocus();
  }

  hgraph.addEventListener("mouseover", function(ev){
    // A pin holds against the pointer — that is the entire point of it.
    // Hover behaves exactly as before whenever nothing is pinned.
    if(pinnedKey !== null) return;
    var box = boxOf(ev.target);
    // Moving off a box onto the graph's own background has to un-focus:
    // mouseleave only fires when the pointer leaves #hgraph entirely, so
    // without this the last box hovered stayed lit while the cursor sat in
    // empty space next to it.
    if(!box){ clearFocus(); return; }
    focusOn(box.dataset.key);
  });

  hgraph.addEventListener("mouseleave", function(){
    if(pinnedKey !== null) return;
    clearFocus();
  });

  // Escape releases, the same meaning it already carries for this page's
  // popups — a further place for one gesture rather than a new gesture.
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape" && pinnedKey !== null){ unpin(); }
  });

  // =====================================================================
  // Graph toolbar. Direction and depth only apply to the directed views, so
  // their controls are hidden elsewhere rather than sitting there inert.
  // =====================================================================
  function syncGraphControls(s){
    document.querySelectorAll(".hview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.view === (s.view || "modules"));
    });
    document.querySelectorAll(".hdir-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.dir === (s.dir || "out"));
    });
    document.querySelectorAll(".hdepth-btn").forEach(function(b){
      b.classList.toggle("active", parseInt(b.dataset.depth, 10) === (s.depth === 0 ? 0 : (s.depth || 2)));
    });
    var show = isGraphView(s.view) ? "" : "none";
    // Orientation, gestures, zoom and the SVG export belong to the drawn
    // diagram; Tree and Treemap are not one.
    var diag = isAltView(s.view) ? "none" : "";
    ["hlr", "hgest", "hzoomreset", "hzoomlabel", "hexport"].forEach(function(id){
      var el = document.getElementById(id);
      if(el) el.style.display = diag;
    });
    document.getElementById("hdir").style.display = show;
    document.getElementById("hdepth").style.display = show;
    // External requires/calls exist only in Deps and Module Calls; the
    // per-function Calls view has no equivalent, since a call into a module
    // the map never scanned leaves no resolvable name behind to draw.
    var hext = document.getElementById("hext");
    hext.style.display = (s.view === "deps" || s.view === "modulecalls") ? "" : "none";
    hext.classList.toggle("active", !!s.ext);

    // Not part of `state`: a gesture preference is the reader's, not the
    // map's, so it never rides in the URL hash and never goes through
    // `navigate`. Reflected here only so the pill agrees with what the
    // handlers will actually do.
    document.getElementById("hgest").classList.toggle("active", classicClicks);

    // Modules only — Deps/Calls/Module Calls/Types/Inheritance have no
    // directory root to peel layers off of.
    var slider = document.getElementById("hrootslider");
    slider.classList.toggle("on", (s.view || "modules") === "modules");
    var max = maxRootDepth();
    var val = Math.min(s.hideroot || 0, max);
    var range = document.getElementById("hrootrange");
    range.max = String(max);
    range.value = String(val);
    document.getElementById("hrootplus").disabled = val >= max;
    document.getElementById("hrootminus").disabled = val <= 0;
  }

  document.getElementById("hup").addEventListener("click", function(){
    // Hidden-root mode has no single center to walk up from — "Up" peels
    // back one hidden level instead, the same direction the slider's own
    // "-" end moves in.
    if(state.view === "modules" && (state.hideroot || 0) > 0){
      navigate({ hideroot: state.hideroot - 1 });
      return;
    }
    var center = byId[hcenter || IR.root];
    if(center && center.parent) navigate({ center: center.parent, fn: null });
  });
  document.getElementById("hroot").addEventListener("click", function(){
    navigate({ center: IR.root, fn: null, hideroot: 0 });
  });
  document.getElementById("hrootplus").addEventListener("click", function(){
    navigate({ hideroot: Math.min((state.hideroot || 0) + 1, maxRootDepth()) });
  });
  document.getElementById("hrootminus").addEventListener("click", function(){
    navigate({ hideroot: Math.max((state.hideroot || 0) - 1, 0) });
  });
  document.getElementById("hrootrange").addEventListener("input", function(ev){
    var n = parseInt(ev.target.value, 10);
    navigate({ hideroot: isNaN(n) ? 0 : n });
  });
  document.getElementById("hlr").addEventListener("click", function(){
    navigate({ hdir: isLR() ? null : "lr" });
  });

  document.querySelectorAll(".hview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ view: b.dataset.view }); });
  });
  document.querySelectorAll(".anview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: "analysis", atool: b.dataset.atool }); });
  });
  document.querySelectorAll(".hdir-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ dir: b.dataset.dir }); });
  });
  document.querySelectorAll(".hdepth-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ depth: parseInt(b.dataset.depth, 10) }); });
  });
  document.getElementById("hext").addEventListener("click", function(){
    navigate({ ext: !state.ext });
  });

  // =====================================================================
  // SVG export
  //
  // The diagram on screen is half SVG (the edges) and half absolutely
  // positioned HTML (the boxes), which is the right trade for an interactive
  // page and useless as a file. Rather than wrapping the boxes in
  // <foreignObject> — which Inkscape and most converters do not render — the
  // export redraws them as plain <rect>/<text>, so the result opens anywhere.
  //
  // Colours are read back off the live DOM instead of being hardcoded, so the
  // exported file matches the theme it was exported from rather than always
  // being the light one.
  // =====================================================================
  /// The diagram as a standalone SVG string, or `null` when none is drawn.
  ///
  /// Split out from `exportSvg` so a host can ask for the bytes without a
  /// download happening: an embedded page's `<a download>` lands wherever
  /// the embedder decides, which is not a place anybody chose.
  function buildSvg(){
    // Only while the diagram is the thing on screen. `#hsvg` is hidden by
    // CSS on every other tab rather than removed, so without this check a
    // host asking from the Notes tab got the last hierarchy that happened
    // to be drawn — exported under the name "current view", which it was
    // not. Found by asking from Notes, not by reading this function.
    if(state.tab !== "hierarchy") return null;
    var svg = document.getElementById("hsvg");
    if(!svg) return null;
    var w = svg.getAttribute("width"), h = svg.getAttribute("height");
    var cs = getComputedStyle(document.body);
    var parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="'+h+'" '+
      'viewBox="0 0 '+w+' '+h+'" font-family="monospace">'];
    parts.push('<rect width="100%" height="100%" fill="'+cs.backgroundColor+'"/>');

    // Markers first: the paths below reference them by id.
    parts.push('<defs>');
    ["tree","type","ext","dep","call"].forEach(function(name){
      var probe = document.querySelector("#m-" + name + " path");
      var fill = probe ? getComputedStyle(probe).fill : cs.color;
      parts.push('<marker id="x-'+name+'" viewBox="0 0 8 8" refX="7" refY="4" '+
        'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'+
        '<path d="M0,0 L8,4 L0,8 z" fill="'+fill+'"/></marker>');
    });
    parts.push('</defs>');

    svg.querySelectorAll(".hedge").forEach(function(p){
      var st = getComputedStyle(p);
      var marker = (p.getAttribute("marker-end") || "").replace("url(#m-", "").replace(")", "");
      parts.push('<path d="'+esc(p.getAttribute("d"))+'" fill="none" stroke="'+st.stroke+'" '+
        'stroke-width="'+st.strokeWidth+'" stroke-dasharray="'+
        (st.strokeDasharray === "none" ? "" : st.strokeDasharray)+'" opacity="'+st.opacity+'" '+
        'marker-end="url(#x-'+marker+')"/>');
    });

    Object.keys(hboxes).forEach(function(key){
      var el = hboxes[key];
      if(el.classList.contains("leaving")) return;
      var x = parseFloat(el.style.left), y = parseFloat(el.style.top);
      var st = getComputedStyle(el);
      parts.push('<rect x="'+x+'" y="'+y+'" width="'+BOX_W+'" height="'+BOX_H+'" rx="7" '+
        'fill="'+st.backgroundColor+'" stroke="'+st.borderTopColor+'"/>');
      var nm = el.querySelector(".hnm"), sub = el.querySelector(".hsm, .hkind, .hline");
      if(nm){
        parts.push('<text x="'+(x+9)+'" y="'+(y+19)+'" font-size="11" font-weight="600" '+
          'fill="'+getComputedStyle(nm).color+'">'+esc(clip(nm.textContent, 22))+'</text>');
      }
      if(sub){
        parts.push('<text x="'+(x+9)+'" y="'+(y+35)+'" font-size="9.5" '+
          'fill="'+getComputedStyle(sub).color+'">'+esc(clip(sub.textContent, 26))+'</text>');
      }
    });

    parts.push('</svg>');
    return parts.join("\n");
  }

  /// The name this diagram would be saved under.
  function svgName(){
    return (state.view || "modules") + "-" +
      (hcenter || "map").replace(/[^\w.-]+/g, "_") + ".svg";
  }

  function exportSvg(){
    var text = buildSvg();
    if(!text) return;
    var blob = new Blob([text], { type: "image/svg+xml" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = svgName();
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function(){ URL.revokeObjectURL(a.href); }, 1000);
  }

  // SVG <text> does not wrap or ellipsize; the HTML boxes rely on CSS
  // overflow for that, so the export has to truncate itself.
  function clip(s, n){
    s = (s || "").trim();
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  document.getElementById("hexport").addEventListener("click", exportSvg);

  // =====================================================================
  // The inbound channel — questions only
  //
  // This page has always spoken to a host and never listened. Opening that
  // direction is a change of security posture, so the shape is chosen to
  // give away as little of it as possible:
  //
  // **It answers questions about itself. It does not take instructions.**
  // There is no "go to this tab", no "run this", no "set this value" — a
  // host that wants the page somewhere navigates the frame's own URL, which
  // it already controls and which the page already validates on the way in.
  // What a host cannot do from outside is *read* a cross-origin document,
  // and that is exactly what the one verb below exists for.
  //
  // Consequences of that choice, stated so a later verb has to argue against
  // them rather than quietly break them:
  //
  //   * A malicious embedder gains nothing it did not have. Everything
  //     answerable here is already rendered on the page it embedded.
  //   * A fixed vocabulary, not a dispatch table keyed by whatever arrived.
  //     An unknown verb is answered with silence, not with an error echoing
  //     the input back.
  //   * Replies go to the asker's own origin, never to `"*"`. An `opener`
  //     that is not the embedder therefore learns nothing by listening.
  //
  // The theme deliberately does *not* come through here: `?theme=` is read
  // from the URL instead, because it has to apply before first paint and a
  // message cannot arrive that early.
  // =====================================================================
  window.addEventListener("message", function(ev){
    var msg = ev.data;
    if(!msg || typeof msg !== "object" || msg.source !== "docmap-host") return;

    var reply = null;
    if(msg.ask === "export-svg"){
      // `null` when no diagram is drawn — a real answer, and the one the
      // host needs in order to say "there is nothing to export" rather than
      // writing an empty file.
      var text = (typeof buildSvg === "function") ? buildSvg() : null;
      reply = text
        ? { ok: true, kind: "svg", name: svgName(), data: text }
        : { ok: false, reason: "no-diagram" };
    }else if(msg.ask === "counts"){
      // What the header shows, for a host that has a place to show it and
      // cannot read this document. Everything here is already on the page:
      // the three structural counts come from the artifact, the two
      // finding counts from `FIND`, which is why this needs no new payload
      // and cannot drift from the header beside it.
      var sev = { error: 0, warn: 0 };
      FIND.forEach(function(f){
        if(sev[f.severity] !== undefined) sev[f.severity]++;
      });
      var c = (IR.meta && IR.meta.counts) || {};
      reply = { ok: true, kind: "counts", modules: c.module || 0,
                namespaces: c.namespace || 0, files: c.file || 0,
                errors: sev.error, warnings: sev.warn };
    }
    // **There was a third question, `state`, and it was removed rather than
    // kept.** It answered with the same coarse context this page already
    // volunteers on every navigation, added on the reasoning that asking is
    // cheaper than waiting. A round later nothing had ever asked it — the
    // one host there is reads the volunteered message, because by the time
    // it has a reason to care the message has already arrived. A question
    // nobody asks is not free: it is a branch in a published channel that
    // every generated artifact carries and that any future change to
    // `state` has to keep answering correctly.
    if(!reply) return;

    reply.source = "docmap";
    reply.replyTo = msg.id;
    try {
      // `ev.origin` is `"null"` for a sandboxed or file: embedder, and
      // `postMessage` rejects that as a target — those hosts get no answer,
      // which is the correct outcome rather than a broadcast.
      if(ev.origin && ev.origin !== "null" && ev.source){
        ev.source.postMessage(reply, ev.origin);
      }
    } catch(e) { /* a host that went away mid-question is not an error here */ }
  });

  zoomLabel = document.getElementById("hzoomlabel");
  document.getElementById("hzoomreset").addEventListener("click", function(){ setZoom(1); });
  applyZoom();


]]
