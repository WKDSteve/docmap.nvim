---@module 'docmap.core.render.html.js.03_tree_findings_tabs_hierarchy'
--- A slice of the page's script: Tree tab, findings, tabs, the Hierarchy view.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Tree tab
  // =====================================================================
  var treeEl = document.getElementById("tree");
  var detailEl = document.getElementById("detail");
  var selectedRowId = null;

  function badges(n){
    var b = [];
    if(n.readme) b.push('<span class="bd rd">readme</span>');
    if(n.types && n.types.length) b.push('<span class="bd">types</span>');
    var f = findByNode[n.id] || [];
    if(f.some(function(x){return x.severity==="error";})) b.push('<span class="bd" style="color:var(--error);border-color:var(--error)">drift</span>');
    return b.length ? '<span class="badges">'+b.join("")+'</span>' : "";
  }

  // Functions hang under their node behind their own collapsed group rather
  // than being mixed into `children`. Two reasons: `children` is IR structure
  // and functions are not part of it, and this tree renders eagerly — folding
  // ~1500 function rows into the always-expanded default would bury the
  // module structure the tree exists to show. One extra row per node, opened
  // on demand, costs nothing until asked for.
  function renderFunctionGroup(n){
    var group = document.createElement("div");

    var head = document.createElement("div");
    head.className = "row fnhead";
    head.innerHTML = '<span class="tw">▸</span>' +
      '<span class="nm">ƒ ' + n.functions.length + ' function' +
      (n.functions.length === 1 ? '' : 's') + '</span>';

    var list = document.createElement("div");
    list.className = "kids fnkids hide";

    n.functions.forEach(function(fn){
      var key = fnKey(n.id, fn.name);
      var r = document.createElement("div");
      r.className = "row k-fn";
      r.dataset.fn = key;
      r.dataset.id = n.id;
      r.innerHTML = '<span class="tw"></span>' +
        '<span class="nm">' + esc(fn.signature) + '</span>' +
        '<span class="sm">' + prose(fn.summary || "") + '</span>';
      r.addEventListener("click", function(){
        navigate({ tab: "tree", id: n.id });
      });
      list.appendChild(r);
    });

    head.addEventListener("click", function(ev){
      ev.stopPropagation();
      list.classList.toggle("hide");
      head.querySelector(".tw").textContent = list.classList.contains("hide") ? "▸" : "▾";
    });

    group.appendChild(head);
    group.appendChild(list);
    return group;
  }

  function renderNode(n){
    var kids = (n.children||[]).map(function(id){ return byId[id]; }).filter(Boolean);
    var hasFns = (n.functions || []).length > 0;
    var hasKids = kids.length > 0 || hasFns;
    var row = document.createElement("div");
    row.className = "row k-" + n.kind;
    row.dataset.id = n.id;
    row.innerHTML =
      '<span class="tw">' + (hasKids ? "▾" : "") + '</span>' +
      '<span class="nm">' + esc(n.name) + '</span>' +
      badges(n) +
      '<span class="sm">' + prose(n.summary || "") + '</span>';

    var box = document.createElement("div");
    box.appendChild(row);

    if(hasKids){
      var kidsEl = document.createElement("div");
      kidsEl.className = "kids";
      kids.forEach(function(k){ kidsEl.appendChild(renderNode(k)); });
      if(hasFns) kidsEl.appendChild(renderFunctionGroup(n));
      box.appendChild(kidsEl);
      row.querySelector(".tw").addEventListener("click", function(ev){
        ev.stopPropagation();
        kidsEl.classList.toggle("hide");
        this.textContent = kidsEl.classList.contains("hide") ? "▸" : "▾";
      });
    }
    row.addEventListener("click", function(){ navigate({ tab: "tree", id: n.id }); });
    return box;
  }

  // DOM-only: row highlight + detail pane. No history side effects — that is
  // applyState's job, so this can be called from anywhere (including a
  // popstate restore) without ever touching the URL itself.
  function selectRow(id){
    var n = byId[id]; if(!n) return;
    if(selectedRowId){ var p = treeEl.querySelector('.row[data-id="'+CSS.escape(selectedRowId)+'"]');
      if(p) p.classList.remove("sel"); }
    selectedRowId = id;
    var cur = treeEl.querySelector('.row[data-id="'+CSS.escape(id)+'"]');
    if(cur) cur.classList.add("sel");
    renderDetail(n);
  }

  function renderDetail(n){
    var h = [];
    h.push('<h2>'+esc(n.name)+'</h2>');
    // A module has annotations but no signature, so there is no `sigTrigger`
    // here to carry the mark control along — it is rendered on its own. Marks
    // are not a function-only idea: "how do these three modules differ" is the
    // same question one scale up.
    h.push('<div class="mp">'+esc(n.module || n.path)+docTrigger(n.id)+featTrigger(n.id)+markTrigger(n.id)+'</div>');

    var links = [];
    if(n.readme) links.push('<a href="'+esc(rel(n.readme))+'">README</a>');
    if(n.source){ var u = srcUrl(n.source);
      links.push(u ? '<a href="'+esc(u)+'">source ↗</a>' : '<a href="'+esc(rel(n.source))+'">source</a>'); }
    (n.types||[]).forEach(function(t){
      var u2 = srcUrl(t);
      links.push(u2 ? '<a href="'+esc(u2)+'">types ↗</a>' : '<a href="'+esc(rel(t))+'">types</a>');
    });
    if(n.kind !== "file"){
      links.push('<a href="#" data-goto="hierarchy">Hierarchy ↳</a>');
    }
    if((n.requires||[]).length || (n.required_by||[]).length){
      links.push('<a href="#" data-goto="deps">Dependencies ↳</a>');
    }
    if((n.functions||[]).length){
      links.push('<a href="#" data-goto="calls">Calls ↳</a>');
      // No module-level Compiler Explorer link, deliberately — removed
      // rather than repaired, for two independent reasons.
      //
      // It could not work: the source travels base64-encoded in the URL and
      // godbolt.org rejects a request line over 8 KB, while this
      // repository's largest module came to 33,332 characters. A shortener
      // API exists and was verified to handle that size — but it uploads the
      // source and keeps it under a public short link, which is a different
      // act from opening a stateless URL.
      //
      // And it should not work: a module link concatenated every function's
      // snippet, which is an approximation of the file and not the file —
      // no requires, no comments, nothing at module scope. `luac` compiles
      // one real file and has no project mode to approximate. Making a
      // meaningless view work is not a fix.
      //
      // Per function it is exact and small (2,880 characters at this
      // repository's worst), and that link is rendered beside each function.
    }
    if(links.length) h.push('<div class="links">'+links.join("")+'</div>');

    if(n.summary || n.body){
      // `richText`, not `prose`: a module's `@description` is the one author
      // surface on this page that routinely runs to paragraphs, and a fenced
      // usage example is what people put in it. Single-line summaries are
      // unaffected — `richText` hands anything without a fence straight to
      // `prose`.
      h.push('<div class="prose">'+richText([n.summary, n.body].filter(Boolean).join("\n\n"))+'</div>');
    } else {
      h.push('<p class="empty">No description — this module has an @module tag but no prose.</p>');
    }

    var f = findByNode[n.id] || [];
    if(f.length){
      h.push('<div class="sec">Drift</div><ul class="lst">');
      f.forEach(function(x){ h.push('<li><span class="sev '+x.severity+'">'+x.severity+'</span> '+esc(x.message)+'</li>'); });
      h.push('</ul>');
    }

    // Stats before anything else in the body: "how big is this and what is in
    // it" is the question asked on arrival, and it is the one thing that was
    // impossible to answer from the map at all. Zero-valued entries are
    // dropped rather than shown as "0 markdown", which would be five sixths
    // noise on a leaf file.
    var st = n.stats || {};
    var cells = [
      ["modules", st.modules], ["namespaces", st.namespaces],
      ["lua files", st.files_lua], ["markdown", st.files_md],
      ["other files", st.files_other], ["lines of lua", st.lines],
      ["functions", st.functions], ["tables & values", st.symbols],
      ["types", st.types]
    ].filter(function(c){ return c[1]; });
    if(cells.length){
      h.push('<div class="sec">Stats' +
        (n.kind === "file" ? '' : ' <span class="sub">(this and everything below)</span>') +
        '</div><div class="stat-grid">');
      cells.forEach(function(c){
        h.push('<div class="stat"><b>' + c[1].toLocaleString() + '</b><span>' + esc(c[0]) + '</span></div>');
      });
      h.push('</div>');
    }

    // Dependencies as text, next to the diagram that draws the same thing:
    // the graph answers "what does this sit in the middle of", a list answers
    // "is X in there", and the second question is the more common one.
    function depList(title, ids){
      if(!ids || !ids.length) return;
      h.push('<div class="sec">'+title+' ('+ids.length+')</div><ul class="lst">');
      ids.forEach(function(id){
        var t = byId[id];
        if(!t) return;
        h.push('<li><a href="#" data-node-link="'+esc(id)+'">'+esc(t.module || t.path)+'</a></li>');
      });
      h.push('</ul>');
    }
    depList("Requires", n.requires);
    depList("Required by", n.required_by);

    // Opt-in (`spec_state`): the specs behind this module and how their last
    // run ended. Every value comes out of the embedded payload and goes through
    // `esc`; the status is additionally restricted to its known words.
    if(IR.spec_state && IR.spec_state.nodes && IR.spec_state.nodes[n.id]){
      var ss = IR.spec_state.nodes[n.id];
      var known = {pass:1, fail:1, error:1, skip:1, xfail:1, xpass:1, timeout:1, crash:1};
      h.push('<div class="sec">Specs</div><ul class="lst">');
      if(!ss.spec_count && !ss.indirect_count){
        h.push('<li><b>no specs</b> require this module, directly or through another one</li>');
      } else {
        (ss.specs || []).forEach(function(sp){ h.push('<li><code>'+esc(sp)+'</code></li>'); });
        if(ss.spec_count > (ss.specs || []).length){
          h.push('<li>… and '+(ss.spec_count - ss.specs.length)+' more</li>');
        }
        if(ss.indirect_count){
          h.push('<li>'+ss.indirect_count+' more spec'+(ss.indirect_count === 1 ? '' : 's')+' reach it only through other modules</li>');
        }
        if(ss.last_status && known[ss.last_status]){
          h.push('<li>last run: <b>'+esc(ss.last_status)+'</b></li>');
        }
      }
      h.push('</ul>');
    }

    // Stated even when it is zero: "nothing depends on this" is itself the
    // answer to "is this safe to change".
    if((n.requires || []).length || (n.required_by || []).length){
      var hull = impactOf(n.id);
      h.push('<div class="sec">Impact</div><ul class="lst"><li>' +
        '<b>' + hull.length + '</b> module' + (hull.length === 1 ? '' : 's') +
        ' would be affected by changing this — ' + (n.required_by || []).length +
        ' directly.</li></ul>');
    }

    if(n.types_detail && n.types_detail.length){
      h.push('<div class="sec">Types ('+n.types_detail.length+')</div><ul class="lst">');
      n.types_detail.forEach(function(t){
        h.push('<li>'+t.kind+' <code>'+esc(t.name)+'</code>'+(t.fields.length?' — '+t.fields.length+' field'+(t.fields.length===1?'':'s'):'')+'</li>');
      });
      h.push('</ul>');
    }

    if(n.functions && n.functions.length){
      // One function, rendered the same wherever it sits — the grouping
      // below decides *where*, never *how*.
      function pushFn(fn){
        var key = fnKey(n.id, fn.name);
        h.push('<div class="fn" data-fn="'+esc(key)+'">');
        h.push(fnAnnotationHTML(fn));
        // Prose references for this function, where the reader is already
        // looking at everything else known about it.
        var dref = docTrigger(key) + featTrigger(key);
        if(dref) h.push('<div class="fn-desc fn-see">' + dref + '</div>');

        // The per-function entry into the Calls view. Counts are shown up
        // front so a function with no edges either way does not offer a link
        // to an empty diagram — with no call data in the map at all (the
        // common case before `:DocMap` is re-run), this section simply is not
        // rendered, rather than every function sprouting two dead links.
        var outN = (callOut[key] || []).length, inN = (callIn[key] || []).length;
        if(outN || inN){
          var cl = [];
          if(outN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="out">calls '+outN+' ↓</a>');
          if(inN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="in">callers '+inN+' ↑</a>');
          h.push('<div class="fn-desc fn-see">'+cl.join(" · ")+'</div>');
        }
        var godboltFn = godboltTrigger("fn", key);
        if(godboltFn) h.push('<div class="fn-desc fn-see">'+godboltFn+'</div>');
        h.push('</div>');
      }

      var grouped = groupByOwner(n.functions);
      // The count line says how many scopes only when there are any: a Lua
      // or C module has none and would otherwise carry a permanent "in 0
      // scopes" that is true and reads like something is missing.
      h.push('<div class="sec">Functions ('+n.functions.length
        + (grouped.scopes.length
            ? ', ' + grouped.scopes.length + ' scope' + (grouped.scopes.length===1?'':'s')
            : '')
        + ')</div>');
      // Free functions first, then each scope with its own members. Twelve
      // sibling rows for three classes of four methods was the state this
      // replaces.
      grouped.free.forEach(pushFn);
      grouped.scopes.forEach(function(sc){
        h.push('<div class="scope"><div class="scope-head">'
          + '<span class="bd sk-table">'+esc(sc.kind)+'</span>'
          + esc(sc.name)
          + ' <span class="sdet">'+sc.functions.length+' function'
          + (sc.functions.length===1?'':'s')+'</span></div>');
        sc.functions.forEach(pushFn);
        h.push('</div>');
      });
    }

    // The half of a module's surface that is not callable: the lookup tables
    // it dispatches through, the constants that encode its thresholds, the
    // things it computes once at load time. Reading a module's source these
    // are usually the first thing you go looking for, and nothing generated
    // showed them before.
    if(n.symbols && n.symbols.length){
      h.push('<div class="sec">Tables &amp; values ('+n.symbols.length+')</div><ul class="lst syms">');
      n.symbols.forEach(function(sy){
        h.push('<li><span class="bd sk-'+sy.kind+'">'+sy.kind+'</span> <code>'+esc(sy.name)+'</code>'
          + (sy.detail ? ' <span class="sdet">'+esc(sy.detail)+'</span>' : '')
          + (sy.summary ? '<div class="fn-desc">'+prose(sy.summary)+'</div>' : '')
          + '</li>');
      });
      h.push('</ul>');
    }

    var kids = (n.children||[]).map(function(i){return byId[i];}).filter(Boolean);
    if(kids.length){
      h.push('<div class="sec">Contains ('+kids.length+')</div><ul class="lst">');
      kids.forEach(function(k){
        h.push('<li>'+esc(k.name)+(k.summary?' — <span style="font-family:inherit">'+prose(k.summary)+'</span>':'')+'</li>');
      });
      h.push('</ul>');
    }

    var meta = [];
    if(n.export) meta.push("exports: " + n.export);
    meta.push("kind: " + n.kind);
    h.push('<div class="sec">Meta</div><ul class="lst"><li>'+esc(meta.join("  ·  "))+'</li></ul>');

    detailEl.innerHTML = h.join("");

    // One handler per link family. `fn: null` on the Deps/Hierarchy hops is
    // not redundant: leaving a stale function centered would make a later
    // switch back to Calls open on whatever function was last looked at
    // several nodes ago, rather than on this node.
    detailEl.querySelectorAll("a[data-goto]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var to = a.dataset.goto;
        if(to === "hierarchy") navigate({ tab: "hierarchy", view: "modules", center: n.id, fn: null });
        else if(to === "deps") navigate({ tab: "hierarchy", view: "deps", center: n.id, fn: null });
        else navigate({ tab: "hierarchy", view: "calls", center: n.id, fn: null });
      });
    });

    detailEl.querySelectorAll("a[data-calls]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "hierarchy", view: "calls", center: n.id,
                   fn: a.dataset.calls, dir: a.dataset.dir });
      });
    });

    detailEl.querySelectorAll("a[data-node-link]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.nodeLink });
      });
    });

    detailEl.querySelectorAll("a[data-see-target]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.seeTarget });
      });
    });
  }

  treeEl.appendChild(renderNode(byId[IR.root]));

  document.getElementById("expand").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
    treeEl.querySelectorAll(".tw").forEach(function(t){ if(t.textContent) t.textContent = "▾"; });
  });
  document.getElementById("collapse").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k, i){ if(i) k.classList.add("hide"); });
    treeEl.querySelectorAll(".row").forEach(function(r){
      // The function-group header carries no node id, so the depth test below
      // skipped it and left a ▾ twisty over a collapsed group. It is always
      // collapsed by this button, so its arrow is unconditional.
      if(r.classList.contains("fnhead")){
        var ft = r.querySelector(".tw");
        if(ft) ft.textContent = "▸";
        return;
      }
      var n = byId[r.dataset.id];
      if(n && n.depth >= 1){ var t = r.querySelector(".tw"); if(t && t.textContent) t.textContent = "▸"; }
    });
  });

  // =====================================================================
  // Findings: clicking a row with a resolvable node id selects it. Rows for
  // findings whose node isn't a real IR node (a couple of repo-specific
  // checks report against synthetic paths) simply have no data-node
  // attribute and stay inert — see render/html.lua for why.
  // =====================================================================
  document.querySelectorAll("#findings tbody tr[data-node]").forEach(function(tr){
    var target = tr.dataset.node;
    if(!byId[target]) return;
    tr.addEventListener("click", function(){ navigate({ tab: "tree", id: target }); });
  });

  // =====================================================================
  // Header counts → the view that shows that set.
  //
  // Three of the five destinations were obvious and two were not, which was
  // the actual work:
  //
  //   modules     Hierarchy, Modules view — the graph of exactly those.
  //   files       the Tree tab, which is the file tree.
  //   namespaces  the Index tab's Modules view, which already lists "every
  //               module and namespace" filed under the last path segment.
  //               A dedicated namespace *view* was considered and rejected:
  //               namespaces are already drawn in the Hierarchy graph and
  //               already listed here, so a sixth tab would be a third
  //               rendering of a set that has two.
  //   errors      the findings disclosure at the foot of the page — which
  //   warnings    already existed, collapsed. These two are not navigations
  //               at all: they open it, scroll to the first row of that
  //               severity, and flash it.
  // =====================================================================
  /// The path from the root to whatever the graph is currently rooted at.
  ///
  /// `Up` and `Root` already existed and neither answers "where am I" —
  /// after two recentres a reader knows they moved and not from where. Each
  /// segment is also a way back to exactly that level, which `Up` only
  /// reaches one at a time.
  function renderCrumb(){
    var host = document.getElementById("hcrumb");
    if(!host) return;
    var chain = [];
    for(var id = hcenter; id && byId[id]; id = byId[id].parent){
      chain.unshift(byId[id]);
      // A malformed parent chain would spin here rather than fail; the
      // scan cannot produce one, and a loop that trusts that is a loop
      // that hangs the page if it is ever wrong.
      if(chain.length > 64) break;
    }
    host.innerHTML = "";
    // One level deep is the root itself, which `⌂ Root` already says. A
    // breadcrumb of one entry is a label pretending to be navigation.
    if(chain.length < 2){ host.hidden = true; return; }
    host.hidden = false;
    chain.forEach(function(n, i){
      if(i) host.appendChild(document.createTextNode(" / "));
      if(i === chain.length - 1){
        var here = document.createElement("span");
        here.className = "here";
        here.textContent = n.name;
        host.appendChild(here);
        return;
      }
      var a = document.createElement("button");
      a.type = "button";
      a.textContent = n.name;
      a.title = n.module || n.path;
      a.addEventListener("click", function(){ navigate({ center: n.id, fn: null }); });
      host.appendChild(a);
    });
  }

  function revealFinding(severity){
    var box = document.getElementById("findings");
    if(!box) return;
    // The list lives in its own tab now, so getting there is a navigation
    // rather than a scroll. The header count stays where it is: a number
    // behind a click is a number nobody reads, and that number is the
    // whole reason the check exists.
    navigate({ tab: "findings" });
    var details = box.querySelector("details");
    if(details) details.open = true;

    // By class, not by the cell's visible text: the severity is already
    // carried as `<span class="sev error">`, and matching the class keeps this
    // working if the label is ever rendered differently (capitalised,
    // translated, replaced with an icon).
    var marker = box.querySelector("tbody tr td .sev." + severity);
    var target = marker ? marker.closest("tr") : null;
    // No row of that severity should be unreachable: the button is rendered
    // disabled when the count is zero, so arriving here without a match means
    // the tally and the table disagree — scroll to the section anyway rather
    // than doing nothing visible.
    (target || box).scrollIntoView({ behavior: "smooth", block: "center" });
    if(target){
      target.classList.remove("flash");
      // Reflow between remove and add, or a second click on the same button
      // restarts nothing — the class never left the element as far as the
      // animation is concerned.
      void target.offsetWidth;
      target.classList.add("flash");
    }
  }

  document.querySelectorAll(".stat-link").forEach(function(b){
    b.addEventListener("click", function(){
      if(b.disabled) return;
      var to = b.dataset.goto;
      if(to === "modules"){
        navigate({ tab: "hierarchy", center: IR.root, view: "modules" });
      } else if(to === "files"){
        navigate({ tab: "tree" });
      } else if(to === "namespaces"){
        navigate({ tab: "index", iview: "modules" });
      } else if(to === "errors"){
        revealFinding("error");
      } else if(to === "warnings"){
        revealFinding("warn");
      }
    });
  });

  // =====================================================================
  // Tabs
  // =====================================================================
  // Promoted-feature tabs are inserted before the generic .tab-btn wiring
  // below runs, so a click on one goes through the exact same navigate()
  // path every static tab already uses — no separate listener to keep in
  // sync with the rest of the tab bar.
  buildPromotedTabs();
  document.querySelectorAll(".tab-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: b.dataset.tab }); });
  });

  // =====================================================================
  // Hierarchy view
  //
  // Two "aufbereitungen" of the same annotation data, toggled via
  // .hview-btn: "modules" draws the directory/module hierarchy (unchanged
  // from before); "types" draws the class/alias graph from LuaLS
  // enrichment — a materially different view of the same map, not just a
  // relabeling, since it walks ir.edges' from_class/to_class rather than
  // node.children.
  //
  // Node/class positions are computed analytically from IR data (layer =
  // BFS depth, position = index within the layer), not measured off the
  // DOM — this sidesteps "a box inside display:none has zero size" entirely
  // rather than working around it with a re-layout-on-show step, since the
  // math produces correct pixel coordinates regardless of visibility.
  // =====================================================================
  var hgraphWrap = document.getElementById("hgraph-wrap");
  var hgraph = document.getElementById("hgraph");
  var hstage = document.getElementById("hstage");
  var hpathEl = document.getElementById("hpath");
  var hlegendEl = document.getElementById("hlegend");
  // ---------------------------------------------------------------------
  // Middle-mouse panning.
  //
  // `#hgraph-wrap` is `overflow:auto`, so the graph has always scrolled — but
  // only through scrollbars and the wheel, one axis at a time. A wide graph is
  // the normal case here, and dragging it is the interaction every other graph
  // tool has.
  //
  // Middle button only. Left-drag is a text selection on this page — the boxes
  // carry module names people copy — and taking that away to gain a second way
  // to pan would be a bad trade.
  //
  // Three things have to be suppressed or the browser fights the drag:
  //   * `mousedown` default on button 1 starts Chrome/Firefox autoscroll (the
  //     four-way arrow cursor that then scrolls on its own);
  //   * `auxclick` fires on release and is what would open a link in a new tab
  //     had the drag ended over one;
  //   * text selection, once the pointer moves with a button held.
  //
  // Nothing here touches history or state: panning is a viewport change, the
  // same category as the scrollbar it replaces, and pushing a Back-stack entry
  // per drag would bury real navigation under it.
  // ---------------------------------------------------------------------
  var panning = null;

  hgraphWrap.addEventListener("mousedown", function(ev){
    if(ev.button !== 1) return;
    ev.preventDefault();
    panning = {
      x: ev.clientX, y: ev.clientY,
      left: hgraphWrap.scrollLeft, top: hgraphWrap.scrollTop
    };
    hgraphWrap.classList.add("panning");
  });

  // On `window`, not on the element: a drag that leaves the graph and comes
  // back should keep panning, and a release outside it must still end the
  // drag — otherwise the next click anywhere would resume it.
  window.addEventListener("mousemove", function(ev){
    if(!panning) return;
    ev.preventDefault();
    hgraphWrap.scrollLeft = panning.left - (ev.clientX - panning.x);
    hgraphWrap.scrollTop = panning.top - (ev.clientY - panning.y);
  });

  window.addEventListener("mouseup", function(ev){
    if(!panning || ev.button !== 1) return;
    panning = null;
    hgraphWrap.classList.remove("panning");
  });

  hgraphWrap.addEventListener("auxclick", function(ev){
    if(ev.button === 1) ev.preventDefault();
  });

  var hcenter = null;
  var MAX_HNODES = 90;
  var BOX_W = 168, BOX_H = 52, GAP_X = 16, GAP_Y = 44, PAD = 20;

  /// Whether the graph runs left-to-right instead of top-down.
  ///
  /// A layout choice, not a second layout: every view already produces
  /// *layers*, and an orientation is which axis a layer index becomes.
  /// Three places turn layers into geometry — positions, edges, canvas —
  /// and this is the only thing they consult.
  ///
  /// Worth having because module names are wide and shallow: a top-down
  /// graph of a deep tree is a tall column of half-empty rows, and the same
  /// tree sideways fills the screen it is on.
  function isLR(){ return state.hdir === "lr"; }

  // Downward edges keep the original S-curve between the boxes' facing sides.
  // Backedges — an edge to a box on the same layer or above — are a new
  // problem the tree views never had: a require or call graph has cycles, so
  // the BFS assigns a target its *first-seen* depth and any later edge into it
  // points sideways or up. Drawn with the same curve, those run straight
  // through every box in between; routed out of the side and back in, they
  // read as the loop they are.
  function edgePath(a, b){
    if(isLR()){
      // The same curve, a quarter turn round: forward edges leave the right
      // side and enter the left, and anything not going forward falls
      // through to the sideways route below, which already handles a graph
      // whose cycles point backwards.
      if(b.x > a.x){
        var lx1 = a.x + BOX_W, lx2 = b.x;
        var ly1 = a.y + BOX_H/2, ly2 = b.y + BOX_H/2;
        var midX = (lx1 + lx2) / 2;
        return "M" + lx1 + "," + ly1 + " C" + midX + "," + ly1 + " " +
          midX + "," + ly2 + " " + lx2 + "," + ly2;
      }
    }
    var x1 = a.x + BOX_W/2, x2 = b.x + BOX_W/2;
    if(!isLR() && b.y > a.y){
      var y1 = a.y + BOX_H, y2 = b.y;
      var midY = (y1 + y2) / 2;
      return "M" + x1 + "," + y1 + " C" + x1 + "," + midY + " " + x2 + "," + midY + " " + x2 + "," + y2;
    }
    var leftward = x2 <= x1;
    var sx = leftward ? a.x : a.x + BOX_W;
    var ex = leftward ? b.x + BOX_W : b.x;
    var sy = a.y + BOX_H/2, ey = b.y + BOX_H/2;
    var bulge = (leftward ? -1 : 1) * Math.max(38, Math.abs(sy - ey) * 0.45);
    return "M" + sx + "," + sy + " C" + (sx + bulge) + "," + sy + " " +
      (ex + bulge) + "," + ey + " " + ex + "," + ey;
  }

  // Edge readout on hover. The weighted Module Calls edges encode their count
  // as thickness, which ranks well and reads badly: "thicker than that one"
  // is not a number, and log scaling — the thing that stops one outlier
  // flattening everything else — deliberately compresses the difference the
  // eye is being asked to judge. So the number itself is one hover away.
  //
  // Shows the reverse direction too when the pair calls both ways. That is
  // the question thickness cannot express at all: two modules calling each
  // other draw two separate edges (`pairKey` is directional), and which of
  // them is under the cursor is otherwise guesswork.
  var edgeTip = null;
  function edgeHover(hit, path, e, weightByPair){
    function label(id){ var n = byId[id]; return (n && (n.module || n.name)) || id; }
    hit.addEventListener("mouseenter", function(){
      if(!edgeTip){
        edgeTip = document.createElement("div");
        edgeTip.className = "hedge-tip";
        document.body.appendChild(edgeTip);
      }
      var back = weightByPair[e.to + " " + e.from];
      var h = '<div class="et-row"><span class="et-n">' + e.weight + '</span> ' +
        (e.weight === 1 ? "call" : "calls") + " " + esc(label(e.from)) + " → " + esc(label(e.to)) + "</div>";
      if(back){
        h += '<div class="et-row et-back"><span class="et-n">' + back + '</span> ' +
          (back === 1 ? "call" : "calls") + " back</div>";
      }
      edgeTip.innerHTML = h;
      edgeTip.classList.add("on");
      // Widen the real edge while it is described, so it is unambiguous which
      // of several overlapping lines the readout belongs to. Set inline and
      // restored on leave: the weighted edges already carry an inline
      // `stroke-width`, which no class could override.
      path.dataset.w = path.style.strokeWidth || "";
      path.style.strokeWidth = String((parseFloat(path.style.strokeWidth) || 1.5) + 2.5);
      path.style.opacity = "1";
    });
    hit.addEventListener("mousemove", function(ev){
      if(!edgeTip) return;
      // Flip to the other side near the viewport edges rather than letting a
      // fixed-position card get clipped.
      var pad = 14, w = edgeTip.offsetWidth, hgt = edgeTip.offsetHeight;
      var x = ev.clientX + pad, y = ev.clientY + pad;
      if(x + w > window.innerWidth) x = ev.clientX - w - pad;
      if(y + hgt > window.innerHeight) y = ev.clientY - hgt - pad;
      edgeTip.style.left = Math.max(4, x) + "px";
      edgeTip.style.top = Math.max(4, y) + "px";
    });
    hit.addEventListener("mouseleave", function(){
      if(edgeTip) edgeTip.classList.remove("on");
      path.style.strokeWidth = path.dataset.w || "";
      path.style.opacity = "";
    });
  }

  // BFS over node.children from `startId`. Files count the same as modules/
  // namespaces — an earlier version excluded them as "just noise", which was
  // wrong in practice: centering on a module implemented as flat files with
  // no further subdirectories then drew almost nothing. MAX_HNODES already
  // bounds noise at any scope.
  // Every layout below returns the same shape, so drawHierarchy never asks
  // which view it is drawing:
  //   { layers: [[key,…],…], included: {key: layerIndex}, count, truncated,
  //     edges: [{from, to, cls, label}] }
  // Producing the edges here rather than in the drawing code is what keeps
  // four structurally different graphs — a tree, a class graph, a require
  // graph and a call graph — behind one renderer.
  // Shared by layoutModules (one seed, the ordinary case) and
  // layoutModulesRooted (several seeds at once, the hidden-root forest
  // case) — the BFS itself does not care how many roots it started from,
  // only layoutModules used to assume there was exactly one.
  function layoutModulesFrom(seeds){
    var layers = [], included = {}, count = 0, truncated = false;
    var queue = seeds.map(function(id){ return { id: id, d: 0 }; });
    while(queue.length){
      var item = queue.shift();
      if(included[item.id] !== undefined) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      var node = byId[item.id];
      if(!node) continue;
      included[item.id] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.id);
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(id){
      (byId[id].children || []).forEach(function(c){
        if(included[c] !== undefined) edges.push({ from: id, to: c, cls: "hedge", marker: "tree" });
      });
    });
    // Type-reference edges layered on top (dashed), node-granularity,
    // self-loops skipped — a field can reference a class anywhere in the whole
    // map, and pulling in out-of-view targets would break "scoped to one
    // subtree".
    typeEdges.forEach(function(e){
      if(e.from !== e.to && included[e.from] !== undefined && included[e.to] !== undefined){
        edges.push({ from: e.from, to: e.to, cls: "hedge hedge-type",
                     marker: "type", label: "." + e.via });
      }
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  function layoutModules(startId){
    return layoutModulesFrom([startId]);
  }

  // Every node at exactly `n` steps below the true IR.root via `children` —
  // the "peel off the top n layers" seed set the hidden-root slider needs.
  // n<=0 is the ordinary single-root case. Falls back to [IR.root] if `n`
  // overshoots the tree's real depth (a hand-edited URL hash, since the
  // slider's own `max` is bounded by maxRootDepth()) rather than laying out
  // nothing.
  function rootFrontier(n){
    if(n <= 0) return [IR.root];
    var frontier = [];
    var seen = {};
    var queue = [ { id: IR.root, d: 0 } ];
    while(queue.length){
      var item = queue.shift();
      if(seen[item.id]) continue;
      seen[item.id] = true;
      if(item.d === n){ frontier.push(item.id); continue; }
      var node = byId[item.id];
      if(!node) continue;
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }
    return frontier.length ? frontier : [IR.root];
  }

  // The tree's own real depth from IR.root, computed once and cached — the
  // slider's `max`, so it is structurally impossible to drag past the point
  // where there would be nothing left to show.
  var cachedMaxRootDepth = null;
  function maxRootDepth(){
    if(cachedMaxRootDepth !== null) return cachedMaxRootDepth;
    var max = 0;
    var seen = {};
    var queue = [ { id: IR.root, d: 0 } ];
    while(queue.length){
      var item = queue.shift();
      if(seen[item.id]) continue;
      seen[item.id] = true;
      if(item.d > max) max = item.d;
      var node = byId[item.id];
      if(!node) continue;
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }
    cachedMaxRootDepth = max;
    return max;
  }

  function layoutModulesRooted(n){
    return layoutModulesFrom(rootFrontier(Math.min(n, maxRootDepth())));
  }

  // BFS over ir.edges' from_class/to_class, seeded from the centered node's
  // own types_detail. A field can reference a class owned by any node in the
  // whole map, which is exactly the point of this view — unlike the Modules
  // view, edges are not required to stay within the laid-out subtree, they
  // define it.
  function layoutTypes(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || []).map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // `typeEdges`, not `IR.edges`: that array now also carries require and
    // call edges, whose `from_class` is undefined — keying an adjacency map on
    // it would file every one of them under the same bogus key.
    var adj = {};
    typeEdges.forEach(function(e){
      (adj[e.from_class] = adj[e.from_class] || []).push(e);
    });

    var layers = [], included = {}, count = 0, truncated = false;
    var queue = seeds.map(function(name){ return { name: name, d: 0 }; });
    while(queue.length){
      var item = queue.shift();
      if(included[item.name] !== undefined) continue;
      if(!classByName[item.name]) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      included[item.name] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.name);
      (adj[item.name] || []).forEach(function(e){
        if(classByName[e.to_class]) queue.push({ name: e.to_class, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(name){
      (adj[name] || []).forEach(function(e){
        if(included[e.to_class] !== undefined){
          edges.push({ from: name, to: e.to_class, cls: "hedge hedge-type",
                       marker: "type", label: "." + e.via });
        }
      });
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  // Inheritance: Doxygen's class-hierarchy diagram, centered the way every
  // other view here is centered rather than drawn as one global root-to-leaf
  // tree. Both directions at once, because for a class "what am I" and "who
  // inherits me" are equally the question.
  //
  // Deliberately *not* built on `walk()`, which the two directed views share.
  // `walk` puts every seed on layer 0 and measures distance from there — but a
  // module normally declares a base class and its subclasses together, so all
  // of them are seeds, and the whole hierarchy collapsed onto one row
  // (observed: Lib.Cache.Opts sat beside its own LoadOpts/SaveOpts). Depth
  // here has to come from the inheritance relation itself, not from distance
  // to whatever the reader happened to center on.
  //
  // So: take the connected component around the seeds, then layer it by
  // longest path from a root — depth(c) = 0 when c has no parent in the
  // component, else 1 + max(depth(parents)). Longest rather than shortest is
  // what guarantees a class always renders strictly below *every* one of its
  // parents, including in a diamond where one path is shorter than the other.
  function layoutInheritance(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || [])
      .filter(function(t){ return inInheritance[t.name]; })
      .map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // Connected component, walking parents and children alike.
    var inComp = {}, queue = seeds.slice(), qi = 0, truncated = false;
    seeds.forEach(function(s){ inComp[s] = true; });
    while(qi < queue.length){
      var cur = queue[qi++];
      var step = function(e, other){
        if(!classByName[other] || inComp[other]) return;
        if(Object.keys(inComp).length >= MAX_HNODES){ truncated = true; return; }
        inComp[other] = true;
        queue.push(other);
      };
      (extUp[cur] || []).forEach(function(e){ step(e, e.to_class); });
      (extDown[cur] || []).forEach(function(e){ step(e, e.from_class); });
    }

    // Longest-path depth, memoized. `state` also guards against a cycle:
    // `---@class A : B` plus `---@class B : A` is nonsense LuaLS would still
    // hand over, and without the guard this recursion would not terminate.
    var depth = {}, state = {};
    function depthOf(name){
      if(state[name] === 2) return depth[name];
      if(state[name] === 1) return 0; // cycle: stop contributing
      state[name] = 1;
      var d = 0;
      (extUp[name] || []).forEach(function(e){
        if(inComp[e.to_class]) d = Math.max(d, depthOf(e.to_class) + 1);
      });
      depth[name] = d; state[name] = 2;
      return d;
    }
    Object.keys(inComp).forEach(depthOf);

    var layers = [], included = {}, count = 0;
    Object.keys(inComp).sort().forEach(function(name){
      var d = depth[name];
      included[name] = d;
      (layers[d] = layers[d] || []).push(name);
      count++;
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    var edges = [];
    extendsEdges.forEach(function(e){
      if(included[e.from_class] !== undefined && included[e.to_class] !== undefined){
        edges.push({ from: e.from_class, to: e.to_class, cls: "hedge hedge-ext",
                     marker: "ext", label: "extends " + e.to_class });
      }
    });

    // Named explicitly rather than left to "first box of the first layer":
    // base classes occupy layer 0, so that shortcut (which the Types view can
    // rely on) would ring a parent instead of the class being looked at.
    return { layers: layers, included: included, count: count,
             truncated: truncated, edges: edges, centerKey: seeds[0] };
  }

]]
