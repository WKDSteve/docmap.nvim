---@module 'docmap.core.render.html.js.10_search_menus_popups'
--- A slice of the page's script: Search, legend, tree/hierarchy sync, copy link, context menu, keyword and annotation cards.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Search — one input, two behaviors depending on the active tab: filters
  // visible rows in the Tree tab (unchanged), re-centers the Hierarchy view
  // on the best-matching node as you type in the Hierarchy tab. Typing
  // updates live via a replaced (not pushed) history entry — five keystrokes
  // finding the same module should not become five Back-button stops — and
  // Enter commits the current match as a real, pushed navigation.
  // =====================================================================
  function findBestMatch(query){
    var q = query.toLowerCase().trim();
    if(!q) return null;
    var starts = null, contains = null;
    for(var i = 0; i < IR.nodes.length; i++){
      var n = IR.nodes[i];
      var name = (n.name || "").toLowerCase();
      var mod = (n.module || "").toLowerCase();
      if(name === q || mod === q) return n.id;
      if(!starts && (name.indexOf(q) === 0 || mod.indexOf(q) === 0)) starts = n.id;
      if(!contains && (name.indexOf(q) >= 0 || mod.indexOf(q) >= 0 || (n.summary||"").toLowerCase().indexOf(q) >= 0)) contains = n.id;
    }
    return starts || contains;
  }

  var q = document.getElementById("q");

  // One input, one contract *per tab* — not one matcher over the whole page.
  //
  // The tabs list genuinely different things (modules, aggregate rows,
  // commits, a flat alphabet), and a single matcher over all of them would be
  // vaguer than any of the four. What is shared is the placeholder, which has
  // to say what the current tab will match, and the fragment state, so a
  // filtered view is linkable.
  //
  // The two tabs that do nothing say so in the placeholder rather than
  // sitting there with a stale prompt — a box that invites typing and then
  // ignores it reads as broken, which is what this used to do on four tabs.
  var PLACEHOLDERS = {
    tree: "Filter modules, paths, descriptions…",
    hierarchy: "Jump to a module — Enter commits",
    analysis: "Filter this panel's rows…",
    notes: "Filter is not used on Notes",
    index: "Filter is not used on the Index",
    history: "Filter is not used on History"
  };
  var FILTERING_TABS = { tree: true, hierarchy: true, analysis: true };

  // The box's contents belong to the *active* tab, so they are reset when the
  // tab changes and left alone otherwise. Resetting on every applyState would
  // wipe a Tree filter the moment a row in it was clicked; never resetting
  // would carry an Analysis query into the Tree tab, where it sits in the box
  // looking applied while filtering nothing.
  var lastSearchTab = null;

  function syncSearchBox(s){
    q.placeholder = PLACEHOLDERS[s.tab] || PLACEHOLDERS.tree;
    q.disabled = !FILTERING_TABS[s.tab];

    if(s.tab !== lastSearchTab){
      // The Analysis filter lives in the URL, so a Back button or a shared
      // link has to put it back in the box. The Tree and Hierarchy filters
      // deliberately do not — both are transient views over rows that are all
      // still there, and persisting them would make a shared link arrive
      // pre-narrowed for no reason the recipient can see.
      q.value = (s.tab === "analysis") ? (s.q || "") : "";
      if(s.tab === "tree") showAllTreeRows();
      lastSearchTab = s.tab;
    } else if(s.tab === "analysis" && q.value !== (s.q || "")){
      // Same tab, but the state changed underneath the box — a popstate, or a
      // link followed within Analysis. Typing does not take this path: there
      // the box is already the source of the value.
      q.value = s.q || "";
    }
  }

  ///Undo the Tree tab's row hiding.
  function showAllTreeRows(){
    treeEl.querySelectorAll(".row").forEach(function(r){ r.style.display = ""; });
  }

  // =====================================================================
  // Language legend
  //
  // A map can hold more than one language since `opts.source` became a list,
  // and until now nothing on screen said which node was which. `n.language`
  // (schema 3) is the backend that read it.
  //
  // **Drawn only when there is more than one.** A legend over a single-
  // language tree is a row of permanent chrome restating what the repository
  // already is — and single-language is nearly every repository, so the
  // common case gets nothing at all. This is the same rule the keyword card
  // follows: depth where there is depth, silence where there is not.
  //
  // No per-row language badge either, for the same reason. The question
  // "which language is this node" is asked about a handful of nodes in a
  // polyglot tree and never in any other tree; a filter answers it without
  // putting a marker on all ninety of them.
  // =====================================================================
  // Two elements, one state. The Tree and the Hierarchy live in separate
  // view containers, so a single shared bar would either sit above every
  // tab (including the ones it means nothing for) or be absent from one of
  // the two. Two elements painted by one function keeps the filter itself
  // single -- switching tabs never changes what is filtered.
  var langBars = [document.getElementById("langbar"), document.getElementById("langbar-h")];
  var activeLangs = null; // null = no filter; otherwise a set of names

  function languageCounts(){
    var counts = {}, order = [];
    IR.nodes.forEach(function(n){
      if(!n.language) return;
      if(counts[n.language] === undefined){ counts[n.language] = 0; order.push(n.language); }
      counts[n.language]++;
    });
    order.sort(function(a, b){ return counts[b] - counts[a] || (a < b ? -1 : 1); });
    return { counts: counts, order: order };
  }

  // Does this node, or anything below it, belong to an active language?
  //
  // Ancestors have to survive the filter or the nodes it selects become
  // unreachable — a `src/util.js` whose parent `src` is hidden is a row with
  // no path to it. A namespace has no language of its own by construction
  // (see scan.lua), so without this it would always be filtered out.
  var langSubtree = {};
  function subtreeLanguages(id){
    if(langSubtree[id]) return langSubtree[id];
    var n = byId[id], set = {};
    if(!n) return set;
    langSubtree[id] = set; // set first: a cycle would otherwise recurse forever
    if(n.language) set[n.language] = true;
    (n.children || []).forEach(function(kid){
      var sub = subtreeLanguages(kid);
      for(var k in sub) set[k] = true;
    });
    return set;
  }

  function rowMatchesLanguage(r){
    if(!activeLangs) return true;
    // Function rows and the group header follow the module they sit under,
    // which the DOM already expresses: they have no id of their own.
    var id = r.dataset.id;
    if(!id) return true;
    var sub = subtreeLanguages(id);
    for(var k in sub) if(activeLangs[k]) return true;
    return false;
  }

  // One pass for both filters.
  //
  // The search box and the legend both decide row visibility through
  // `style.display`, and two independent handlers writing that property make
  // the second one to run silently undo the first. Deciding once, from both
  // inputs, is the only version that cannot drift.
  function applyTreeFilter(){
    var v = (q.value || "").toLowerCase().trim();
    treeEl.querySelectorAll(".row").forEach(function(r){
      var hit;
      if(r.dataset.fn){
        var entry = fnByKey[r.dataset.fn];
        hit = !v || !entry ||
          (entry.fn.signature + " " + (entry.fn.summary || "")).toLowerCase().indexOf(v) >= 0;
      } else if(r.classList.contains("fnhead")){
        hit = !v;
      } else {
        var n = byId[r.dataset.id];
        hit = !v || !n ||
          (n.name + " " + (n.module || "") + " " + (n.summary || "")).toLowerCase().indexOf(v) >= 0;
      }
      r.style.display = (hit && rowMatchesLanguage(r)) ? "" : "none";
    });
    if(v) treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
  }

  // Which language a Hierarchy box belongs to, or `null` for "cannot say".
  //
  // `hboxes` keys are not all node ids — `boxSpec` resolves four kinds: a
  // node id, an `ext:<module>` box for something outside this map, a class
  // name (Types/Inheritance), and an `fnKey` (Calls). Only two of the four
  // can answer, and the other two are answered honestly rather than guessed:
  //
  //   * `ext:` is by definition not part of this map, so it has no language
  //     *here*, whatever it is written in.
  //   * A class name comes from LuaLS enrichment, which is Lua-only today —
  //     but saying "therefore Lua" would be inferring a fact from the
  //     limitations of a tool rather than from the tree.
  //
  // A box that cannot say is never filtered out. Hiding boxes on the strength
  // of a guess is how a graph starts lying about its own shape.
  function languagesOfBoxKey(key){
    if(key.indexOf("ext:") === 0) return null;
    if(byId[key]) return subtreeLanguages(key);
    var entry = fnByKey[key];
    if(entry && entry.node && entry.node.language){
      var one = {};
      one[entry.node.language] = true;
      return one;
    }
    return null;
  }

  // Dim, never remove.
  //
  // The Tree view hides filtered rows because a list with gaps is still a
  // list. A graph is not: taking boxes out re-flows every remaining one and
  // can disconnect the picture, so the reader loses the shape they were
  // looking at in order to ask a question about part of it. This is the same
  // reasoning — and deliberately the same opacity — as the right-click
  // hide/dim above, kept on its own class so the two never fight over one:
  // a box the reader dimmed by hand must stay dimmed when the language
  // filter clears, and vice versa.
  function syncLangFilter(){
    Object.keys(hboxes).forEach(function(key){
      var off = false;
      if(activeLangs){
        var langs = languagesOfBoxKey(key);
        if(langs){
          off = true;
          for(var k in langs){ if(activeLangs[k]){ off = false; break; } }
        }
      }
      hboxes[key].classList.toggle("langoff", off);
    });
  }

  function renderLangBar(){
    var info = languageCounts();
    if(info.order.length < 2){
      langBars.forEach(function(bar){ if(bar) bar.hidden = true; });
      return;
    }

    var h = ['<span class="lb-label">Languages</span>'];
    info.order.forEach(function(name){
      var on = !activeLangs || activeLangs[name];
      h.push('<button type="button" class="lb-chip' + (on ? " on" : "") +
        '" data-lang="' + esc(name) + '" aria-pressed="' + (on ? "true" : "false") + '">' +
        esc(name) + '<span class="lb-n">' + info.counts[name] + '</span></button>');
    });
    if(activeLangs){
      h.push('<button type="button" class="lb-clear" data-lang-clear="1">show all</button>');
    }
    langBars.forEach(function(bar){
      if(!bar) return;
      bar.innerHTML = h.join("");
      bar.hidden = false;
    });
  }

  langBars.forEach(function(bar){ if(bar) bar.addEventListener("click", onLangBarClick); });

  function onLangBarClick(ev){
    var clear = ev.target.closest && ev.target.closest("[data-lang-clear]");
    if(clear){ activeLangs = null; renderLangBar(); applyLangFilter(); return; }
    var chip = ev.target.closest && ev.target.closest("[data-lang]");
    if(!chip) return;
    var name = chip.dataset.lang;
    // First click on an unfiltered bar selects *only* that language rather
    // than deselecting it. "Show me the TypeScript" is the thing a reader
    // wants from a legend; "show me everything except TypeScript" is not,
    // and starting from all-on makes the first click do the useless one.
    if(!activeLangs){
      activeLangs = {};
      activeLangs[name] = true;
    } else if(activeLangs[name]){
      delete activeLangs[name];
      // Emptied by unticking the last one: that is "show nothing", which is
      // never what was meant, so it means "show all" instead.
      var any = false;
      for(var k in activeLangs){ any = true; break; }
      if(!any) activeLangs = null;
    } else {
      activeLangs[name] = true;
    }
    renderLangBar();
    applyLangFilter();
  }

  ///Both surfaces the filter reaches, in one call, so a chip click cannot
  ///update one and leave the other showing a stale selection.
  function applyLangFilter(){
    applyTreeFilter();
    syncLangFilter();
  }

  // Drawn at load, not on first interaction: the legend's whole job is to
  // tell a reader the map holds more than one language before they wonder.
  renderLangBar();

  // =====================================================================
  // Copy link
  //
  // The whole page state already lives in the URL fragment -- that is what
  // `:DocMap graph` and `gO` exploit, and what every `navigate()` call
  // maintains. What was missing is any way for a reader to *get* it: the
  // address bar shows it, but a map opened from a file:// path or inside an
  // iframe (docmap-desktop) has no address bar to select from.
  //
  // Reads `location.href` rather than rebuilding the URL from `state`: the
  // hash is written by `applyState` on every navigation, so the address is
  // already correct by construction, and a second serializer here would be a
  // second answer to "what is this view called" that could drift from the
  // first.
  // =====================================================================
  var copyBtn = document.getElementById("copylink");
  var copyTimer = null;

  function flashCopy(text){
    if(copyTimer) clearTimeout(copyTimer);
    copyBtn.textContent = text;
    copyTimer = setTimeout(function(){ copyBtn.textContent = "Copy link"; copyTimer = null; }, 1400);
  }

  copyBtn.addEventListener("click", function(){
    var url = location.href;
    // `navigator.clipboard` is unavailable on an insecure origin, which
    // includes the `file://` case this page is most often opened as. The
    // fallback is the old `execCommand` route, and if even that fails the
    // reader is told rather than left looking at a button that did nothing.
    var done = function(){ flashCopy("Copied"); };
    var failed = function(){
      try {
        var ta = document.createElement("textarea");
        ta.value = url;
        ta.setAttribute("readonly", "");
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        var okExec = document.execCommand && document.execCommand("copy");
        document.body.removeChild(ta);
        flashCopy(okExec ? "Copied" : "Press Ctrl+C");
      } catch(e){
        flashCopy("Press Ctrl+C");
      }
    };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(url).then(done, failed);
    } else {
      failed();
    }
  });

  q.addEventListener("input", function(){
    var v = this.value.toLowerCase().trim();

    if(state.tab === "analysis"){
      // Replaces rather than pushes, for the same reason the Hierarchy
      // preview does not push: five keystrokes narrowing to one module should
      // not become five Back-button stops. Unlike Hierarchy this *does* go
      // through navigate(), because the result is a re-render from state and
      // there is no separate draw path to call.
      navigate({ q: v || null }, { push: false });
      return;
    }

    if(state.tab === "hierarchy"){
      // Live preview only — draws directly, deliberately bypassing
      // navigate()/history entirely rather than replacing on every
      // keystroke. An earlier version used navigate(patch, {push:false}),
      // which calls history.replaceState on the *current top entry* — right
      // after switching to the Hierarchy tab, that entry is the tab-switch
      // itself, so the first keystroke overwrote it. Enter's subsequent
      // pushState then pushed a duplicate of that already-overwritten entry
      // instead of a distinct new stop, so Back from the committed search
      // landed on an indistinguishable copy of itself instead of the
      // pre-search tab state. Not writing to history at all while typing
      // avoids the clobber; drawHierarchy still keeps its own `hcenter`
      // current, so Up/Root/double-click after a preview (without ever
      // pressing Enter) act on what's actually on screen.
      var match = findBestMatch(this.value);
      // forceCenter: a typed match always wins over a root-hidden forest
      // view, the same way Enter's real navigate({center}) would clear
      // hideroot — see drawHierarchy's own note on why this path needs it
      // spelled out explicitly instead of getting it for free.
      if(match) drawHierarchy(match, state.view, true);
      return;
    }
    // Three row shapes share this list -- node rows, function rows (which
    // match on their own signature, not their module's summary) and the
    // function-group header, which has no data at all -- and the language
    // legend filters the same rows. `applyTreeFilter` owns all of it, so the
    // two inputs cannot take turns undoing each other's `display`.
    applyTreeFilter();
  });
  q.addEventListener("keydown", function(ev){
    if(ev.key === "Enter" && state.tab === "hierarchy"){
      var match = findBestMatch(this.value);
      if(match) navigate({ center: match });
    }
  });

  // =====================================================================
  // Context menu
  //
  // Every clickable object in the page — a tree row, a function row, a graph
  // box, a type or function entry in the detail pane — resolves through one
  // describeTarget() into { kind, nodeId, fnKey, className, label }, and the
  // menu is built from that. One resolver instead of four menus is what keeps
  // "right-click anything, get the same verbs" true as views are added.
  //
  // preventDefault only fires when the target actually resolves: selecting a
  // paragraph of documentation and reaching for the browser's own Copy has to
  // keep working, so unrecognised targets are left entirely alone.
  // =====================================================================
  var ctx = document.getElementById("ctx");
  var ctxItems = [];
  var ctxHi = -1;

  function describeTarget(el){
    while(el && el !== document.body){
      if(el.dataset){
        if(el.classList.contains("hnode") && el._spec){
          // `hkey` is the box's own key into `hboxes`/`state.hidden` — the
          // only place this is available, since a tree row or detail-pane
          // reference (the branches below) has no Hierarchy box behind it to
          // dim. `buildMenu` gates the hide/dim entry on this field alone.
          return { kind: el._spec.fnKey ? "function" : (classByName[el.dataset.key] ? "class" : "node"),
                   nodeId: el._spec.nodeId, fnKey: el._spec.fnKey,
                   className: classByName[el.dataset.key] ? el.dataset.key : null,
                   label: el.dataset.key, hkey: el.dataset.key };
        }
        if(el.dataset.fn && fnByKey[el.dataset.fn]){
          var e = fnByKey[el.dataset.fn];
          return { kind: "function", nodeId: e.node.id, fnKey: el.dataset.fn, label: e.fn.signature };
        }
        if(el.dataset.id && byId[el.dataset.id]){
          var n = byId[el.dataset.id];
          return { kind: "node", nodeId: n.id, label: n.module || n.path };
        }
      }
      el = el.parentNode;
    }
    return null;
  }

  function ctxClose(){ ctx.classList.remove("open"); ctxItems = []; ctxHi = -1; }

  function buildMenu(t){
    var n = byId[t.nodeId];
    var items = [];
    var fnEntry = t.fnKey ? fnByKey[t.fnKey] : null;

    items.push({ label: "Show in tree", run: function(){ navigate({ tab: "tree", id: t.nodeId }); } });
    items.push({ sep: true });

    items.push({ label: "Hierarchy", hint: "structure",
      run: function(){ navigate({ tab: "hierarchy", view: "modules", center: t.nodeId, fn: null }); } });

    var hasDeps = ((n.requires || []).length + (n.required_by || []).length) > 0;
    items.push({ label: "Dependencies — needs", hint: (n.requires || []).length || "0",
      disabled: !(n.requires || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "out", fn: null }); } });
    items.push({ label: "Dependencies — needed by", hint: (n.required_by || []).length || "0",
      disabled: !(n.required_by || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "in", fn: null }); } });
    items.push({ label: "Dependencies — both ways", disabled: !hasDeps,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "both", fn: null }); } });

    // Counts come from the same adjacency the view walks, so a menu entry is
    // only offered when it leads somewhere — an enabled item that opens an
    // empty diagram teaches people to distrust the menu.
    var outN = fnEntry ? (callOut[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callOut[fnKey(n.id, f.name)] || []).length; }, 0);
    var inN = fnEntry ? (callIn[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callIn[fnKey(n.id, f.name)] || []).length; }, 0);

    items.push({ sep: true });
    items.push({ label: fnEntry ? "Calls — callees" : "Calls — what it calls", hint: outN || "0",
      disabled: !outN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "out" }); } });
    items.push({ label: fnEntry ? "Calls — callers" : "Calls — what calls it", hint: inN || "0",
      disabled: !inN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "in" }); } });
    items.push({ label: "Calls — both ways", disabled: !(outN || inN),
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "both" }); } });

    items.push({ label: "Types", disabled: !(n.types_detail || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "types", center: t.nodeId, fn: null }); } });

    // Enabled only when this node actually owns a class that inherits or is
    // inherited from — the view would otherwise open on its own empty state,
    // and "greyed out with a reason" beats "opens and says nothing here".
    var inhN = (n.types_detail || []).filter(function(ty){ return inInheritance[ty.name]; }).length;
    items.push({ label: "Inheritance", hint: inhN || "0", disabled: !inhN,
      run: function(){ navigate({ tab: "hierarchy", view: "inheritance", center: t.nodeId, fn: null }); } });

    items.push({ sep: true });
    if(n.source){
      var u = srcUrl(n.source);
      var frag = fnEntry ? "#L" + fnEntry.fn.line : "";
      items.push({ label: u ? "Open source ↗" : "Open source",
        run: function(){ window.open(u ? u + frag : rel(n.source), u ? "_blank" : "_self"); } });
      // Open it in an editor — only when something is embedding this page.
      // A browser cannot start an editor, so in a plain tab this item would
      // be a menu entry that does nothing, which is worse than an absent
      // one. `window.parent !== window` is the whole test: a host that
      // embeds this is a host that can be told, and one that ignores the
      // message leaves the item doing what it appears to do — nothing —
      // rather than lying about it.
      if(window.parent !== window){
        items.push({ label: "Open in editor", run: function(){
          try {
            window.parent.postMessage({
              source: "docmap", kind: "open-file",
              path: n.source,
              line: fnEntry ? fnEntry.fn.line : null
            }, "*");
          } catch(e){ /* no host, same as no item */ }
        } });
      }
    }
    if(n.readme){
      items.push({ label: "Open README", run: function(){ window.open(rel(n.readme), "_self"); } });
    }

    // Only offered when the menu was opened on an actual Hierarchy box
    // (`t.hkey`, set by describeTarget only in that branch) — right-clicking
    // this same node's tree row or a reference in a detail pane has nothing
    // to dim, since neither one has a box on screen.
    if(t.hkey){
      items.push({ sep: true });
      items.push({
        label: isHidden(t.hkey) ? "Show this box" : "Dim this box",
        hint: "hierarchy",
        run: function(){ toggleHidden(t.hkey); }
      });
    }

    items.push({ sep: true });
    items.push({ label: "Copy module path", run: function(){ copy(n.module || n.path); } });
    items.push({ label: "Copy link to this view", run: function(){
      copy(location.origin + location.pathname + serializeState(state));
    } });

    return items;
  }

  // clipboard.writeText is unavailable on a file:// page in some browsers,
  // which is exactly how this artifact is most often opened. The textarea
  // fallback is not legacy cruft here, it is the primary path.
  function copy(text){
    if(navigator.clipboard && window.isSecureContext){
      navigator.clipboard.writeText(text);
      return;
    }
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch(e) {}
    document.body.removeChild(ta);
  }

  function openMenu(x, y, t){
    var items = buildMenu(t);
    var html = ['<div class="hdr">' + esc(t.label || "") + '</div>'];
    items.forEach(function(it, i){
      if(it.sep){ html.push('<div class="sep"></div>'); return; }
      html.push('<div class="ci' + (it.disabled ? " disabled" : "") + '" data-i="' + i + '">' +
        esc(it.label) + (it.hint !== undefined ? '<span class="hint">' + esc(String(it.hint)) + '</span>' : '') +
        '</div>');
    });
    ctx.innerHTML = html.join("");
    ctxItems = items;
    ctxHi = -1;
    ctx.classList.add("open");

    // Positioned after the menu is measurable, clamped so a right-click near
    // the bottom or right edge does not open a menu that runs off-screen.
    var r = ctx.getBoundingClientRect();
    ctx.style.left = Math.min(x, window.innerWidth - r.width - 8) + "px";
    ctx.style.top = Math.min(y, window.innerHeight - r.height - 8) + "px";

    ctx.querySelectorAll(".ci").forEach(function(el){
      el.addEventListener("click", function(){
        var it = ctxItems[parseInt(el.dataset.i, 10)];
        if(!it || it.disabled) return;
        ctxClose();
        it.run();
      });
    });
  }

  document.addEventListener("contextmenu", function(ev){
    var t = describeTarget(ev.target);
    if(!t || !byId[t.nodeId]) return;
    ev.preventDefault();
    openMenu(ev.clientX, ev.clientY, t);
  });

  document.addEventListener("click", function(ev){
    if(ctx.classList.contains("open") && !ctx.contains(ev.target)) ctxClose();
  });
  window.addEventListener("blur", ctxClose);
  window.addEventListener("resize", ctxClose);
  document.addEventListener("scroll", ctxClose, true);

  document.addEventListener("keydown", function(ev){
    if(!ctx.classList.contains("open")) return;
    if(ev.key === "Escape"){ ctxClose(); return; }
    if(ev.key !== "ArrowDown" && ev.key !== "ArrowUp" && ev.key !== "Enter") return;
    ev.preventDefault();
    var els = Array.prototype.slice.call(ctx.querySelectorAll(".ci:not(.disabled)"));
    if(!els.length) return;
    if(ev.key === "Enter"){
      if(ctxHi >= 0) els[ctxHi].click();
      return;
    }
    els.forEach(function(e){ e.classList.remove("hi"); });
    ctxHi = ev.key === "ArrowDown"
      ? (ctxHi + 1) % els.length
      : (ctxHi <= 0 ? els.length - 1 : ctxHi - 1);
    els[ctxHi].classList.add("hi");
  });


  // =====================================================================
  // Keyword card
  //
  // A second floating layer, which the governing rule for this feature
  // ("one card component, one card at a time") would normally forbid — and
  // the exception is structural rather than a concession. A snippet is
  // rendered *inside* the annotation popup, so a keyword trigger lives
  // inside the very card that would otherwise have to display its answer;
  // reusing `sigpop` would mean a keyword hover destroying the function
  // card the reader opened to look at. Two layers is what the nesting
  // actually is.
  //
  // What the rule still buys, and what is kept: the same visual component
  // (`.sigpop` styling), the same positioning and flip logic, the same
  // dismissal rules. Only the content and the nesting differ.
  //
  // Opens on a dwell, never on hover-through: a card that appears while the
  // pointer merely crosses a word is chrome nobody asked for, and a snippet
  // is full of words a pointer crosses on the way somewhere else.
  // =====================================================================
  var kwpop = document.getElementById("kwpop");
  var kwAnchor = null, kwOpenTimer = null, kwCloseTimer = null;
  // Focusing a keyword by keyboard scrolls it into view; that scroll arrives AFTER the
  // card opened and must not take it down again (a wheel or touch scroll still does).
  var kwFocusScrollUntil = 0;
  var KW_DWELL = 260;

  function kwClearTimers(){
    if(kwOpenTimer){ clearTimeout(kwOpenTimer); kwOpenTimer = null; }
    if(kwCloseTimer){ clearTimeout(kwCloseTimer); kwCloseTimer = null; }
  }

  function kwClose(){
    kwClearTimers();
    kwpop.classList.remove("on");
    kwAnchor = null;
  }

  // Positioned exactly like the annotation popup, including the flip: a card
  // pinned below the viewport edge would cover the line the reader is
  // pointing at. Extracted when the tag card became a second caller -- two
  // copies of a flip rule is two chances to flip one of them the wrong way.
  function kwPlace(el){
    var a = el.getBoundingClientRect();
    var r = kwpop.getBoundingClientRect();
    kwpop.style.left = Math.max(8, Math.min(a.left, window.innerWidth - r.width - 8)) + "px";
    kwpop.style.top = ((a.bottom + r.height + 8 <= window.innerHeight)
      ? a.bottom + 6
      : Math.max(8, a.top - r.height - 6)) + "px";
  }

  // The tag catalogue as a lookup table, built once. Keyed by name without
  // the `@`, which is how the badges and the parser both spell it.
  var tagByName = null;
  function tagEntry(name){
    if(tagByName === null){
      tagByName = {};
      (IR.tags || []).forEach(function(t){ tagByName[t.name] = t; });
    }
    return Object.prototype.hasOwnProperty.call(tagByName, name) ? tagByName[name] : null;
  }

  function kwOpen(el){
    // The third kind. Unlike keywords and stdlib names it has no snippet
    // behind it and therefore no per-language glossary: an annotation means
    // the same thing wherever it is written, which is exactly why the
    // catalogue is one table and the glossaries are one per language.
    if(el.dataset.kwkind === "tag"){
      var tag = tagEntry(el.dataset.kw);
      if(!tag) return;
      var th = '<div class="kw-word">@' + esc(tag.name) + '</div>' +
        '<div class="kw-sum">' + prose(tag.summary) + '</div>' +
        '<div class="kw-origin">' + (tag.origin === "luals"
          ? "LuaCATS annotation" : "this project's own convention") + '</div>';
      // Only where the origin publishes one. A LuaLS link for `@todo` would
      // load, look authoritative and not contain the answer -- the same rule
      // that withholds the Lua-manual link from `vim.*` below.
      if(tag.url){
        th += '<div class="kw-ref"><a href="' + esc(tag.url) +
          '" target="_blank" rel="noreferrer noopener">LuaLS reference &#8599;</a></div>';
      }
      kwAnchor = el;
      kwpop.innerHTML = th;
      kwpop.classList.add("on");
      kwPlace(el);
      return;
    }

    // `[data-path]` rather than `.fn-snip`, which is what `snippetHTML`'s own
    // comment already describes ("the path rides on the container ... and the
    // lookup walks up to it"). Written as a class name it silently meant "and
    // only snippets"; a keyword decorated inside a fenced block would have
    // found no container, read no glossary, and shown nothing on click.
    var snip = el.closest && el.closest("[data-path]");
    var gl = glossaryForPath(snip && snip.dataset.path);
    var table = el.dataset.kwkind === "std" ? (gl && gl.stdlib) : (gl && gl.keywords);
    var entry = table && Object.prototype.hasOwnProperty.call(table, el.dataset.kw)
      ? table[el.dataset.kw]
      : null;
    // Nothing behind the trigger is a bug in whatever decorated it, not
    // something to show an empty card for.
    if(!entry) return;

    var h = '<div class="kw-word">' + esc(el.dataset.kw) + '</div>' +
      '<div class="kw-sum">' + prose(entry.summary) + '</div>';
    if(entry.note) h += '<div class="kw-note">' + esc(entry.note) + '</div>';
    // Where the name comes from, when it is not the language itself. The
    // distinction is the whole reason `vim.*` entries can sit in a Lua
    // glossary without pretending to be Lua: a reader is told the difference
    // rather than left to infer it.
    if(entry.origin) h += '<div class="kw-origin">' + esc(entry.origin) + '</div>';
    // Only for entries that *are* the language. A `vim.*` name is not in the
    // Lua manual, and sending a reader there would be a link that looks
    // right and answers nothing.
    if(!entry.origin && gl.reference && gl.reference.url){
      // The one link, per language, that this feature is allowed to depend
      // on nothing for: every sentence above it is already the answer. There
      // is one base URL rather than one URL per keyword.
      h += '<div class="kw-ref"><a href="' + esc(gl.reference.url + (entry.anchor || "")) +
        '" target="_blank" rel="noreferrer noopener">' + esc(gl.reference.label) + ' &#8599;</a></div>';
    }

    kwAnchor = el;
    kwpop.innerHTML = h;
    kwpop.classList.add("on");
    kwPlace(el);
  }

  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-kw]");
    if(el){
      kwClearTimers();
      if(el !== kwAnchor) kwOpenTimer = setTimeout(function(){ kwOpen(el); }, KW_DWELL);
      return;
    }
    if(!kwAnchor && !kwOpenTimer) return;
    // The content scrolled under a resting pointer (the focus scrolled its keyword into view): the
    // browser reports a mouseover on whatever is under it now, which is not the reader leaving.
    if(Date.now() < kwFocusScrollUntil) return;
    // Same grace period on the way out as the annotation popup, and for the
    // same reason: the pointer has to be able to travel into the card to
    // reach the reference link.
    if(ev.target.closest && ev.target.closest("#kwpop")){ kwClearTimers(); return; }
    kwClearTimers();
    kwCloseTimer = setTimeout(kwClose, 180);
  });

  // Keyboard parity. The spans are focusable, so a reader who never touches
  // a pointer still reaches every explanation -- the same reason `.sigi`
  // above is kept at full opacity while focused.
  document.addEventListener("focusin", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-kw]");
    if(el){ kwClearTimers(); kwFocusScrollUntil = Date.now() + 500; kwOpen(el); }
    else if(!(ev.target.closest && ev.target.closest("#kwpop"))) kwClose();
  });

  document.addEventListener("keydown", function(ev){ if(ev.key === "Escape") kwClose(); });
  // Same exemption as the annotation popup below: the keyword card is short
  // today, but it lives *inside* that card, so a scroll gesture aimed at the
  // snippet behind it must not take it down either.
  window.addEventListener("scroll", function(ev){
    if(ev.target && ev.target.nodeType === 1 && ev.target.closest &&
       (ev.target.closest("#kwpop") || ev.target.closest("#sigpop"))) return;
    // the scroll the focus itself caused: keep the card, follow its keyword
    if(kwAnchor && Date.now() < kwFocusScrollUntil){ kwPlace(kwAnchor); return; }
    kwClose();
  }, true);
  window.addEventListener("resize", kwClose);

  // =====================================================================
  // Annotation popup
  //
  // Every list in this map — Index, Notes, Complexity, Hooks, Duplicates —
  // shows a function as its signature and nothing else. The params, returns,
  // deprecation and prose were all parsed and are all already in this page;
  // they were simply one navigation away, in the Tree tab's detail pane.
  // This surfaces them where the reader already is.
  //
  // No new data: `fnByKey` and `fnAnnotationHTML` both already exist, which
  // is why this costs a popup and not an extraction.
  //
  // Lifecycle deliberately mirrors the context menu above (close on
  // click-outside, blur, resize, scroll, Escape) rather than inventing a
  // second set of rules for a second floating thing on the same page.
  // =====================================================================
  var sigpop = document.getElementById("sigpop");
  var sigAnchor = null, sigPinned = false, sigTimer = null;

  function sigClose(){
    if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
    sigpop.classList.remove("on");
    if(sigAnchor) sigAnchor.classList.remove("on");
    sigAnchor = null;
    sigPinned = false;
  }

  function sigOpen(el){
    // Two kinds of trigger, one card: `data-sig` shows what the annotations
    // say, `data-doc` shows where the prose mentions it. Sharing the element
    // is not just economy — two independently-positioned cards that can both
    // be open would have to negotiate overlap, focus and Escape between
    // them, and there is no reading task that wants both at once.
    var html;
    if(el.dataset.doc){
      html = docRefsHTML(el.dataset.doc);
    } else {
      var entry = fnByKey[el.dataset.sig];
      // A key with no entry is a bug in whatever rendered the trigger, not
      // something to paper over with an empty card — say nothing at all.
      if(!entry) return;
      html = fnAnnotationHTML(entry.fn) + snippetHTML(entry.fn, entry.node) +
        '<div class="fn-desc fn-see"><a href="#" data-sig-goto="' +
        esc(entry.node.id) + '">' + esc(entry.node.module || entry.node.path) +
        ':' + entry.fn.line + '</a></div>';
    }

    if(sigAnchor && sigAnchor !== el) sigAnchor.classList.remove("on");
    sigAnchor = el;
    el.classList.add("on");
    sigpop.innerHTML = html;
    sigpop.classList.add("on");

    // Measured after it is in the DOM, then flipped rather than clamped
    // vertically: a card pinned to the bottom edge would cover the very row
    // the reader is pointing at, which a menu (positioned at the cursor)
    // does not have to worry about.
    var a = el.getBoundingClientRect();
    var r = sigpop.getBoundingClientRect();
    var left = Math.max(8, Math.min(a.left, window.innerWidth - r.width - 8));
    var top = (a.bottom + r.height + 8 <= window.innerHeight)
      ? a.bottom + 6
      : Math.max(8, a.top - r.height - 6);
    sigpop.style.left = left + "px";
    sigpop.style.top = top + "px";
  }

  // Hover opens, but with a grace period on the way out so the pointer can
  // travel into the card to scroll it or select text. Click pins, which is
  // what makes the card usable at all for a long `@example` block.
  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-sig],[data-doc]");
    if(el){
      if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
      if(el !== sigAnchor) sigOpen(el);
      return;
    }
    if(sigPinned || !sigAnchor) return;
    if(ev.target.closest && ev.target.closest("#sigpop")){
      if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
      return;
    }
    if(!sigTimer) sigTimer = setTimeout(sigClose, 180);
  });

  document.addEventListener("click", function(ev){
    var goto = ev.target.closest && ev.target.closest("[data-sig-goto]");
    if(goto){
      ev.preventDefault();
      var id = goto.dataset.sigGoto;
      sigClose();
      navigate({ tab: "tree", id: id });
      return;
    }
    var el = ev.target.closest && ev.target.closest("[data-sig],[data-doc]");
    if(el){
      ev.preventDefault();
      if(sigPinned && sigAnchor === el){ sigClose(); return; }
      sigOpen(el);
      sigPinned = true;
      return;
    }
    if(sigAnchor && !(ev.target.closest && ev.target.closest("#sigpop"))) sigClose();
  });

  // A separate listener rather than folded into the one above: this one
  // never opens an in-page popup, only ever a new tab, so it has none of
  // sigOpen/sigClose's own state to coordinate with.
  document.addEventListener("click", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-godbolt]");
    if(!el) return;
    ev.preventDefault();
    var key = el.dataset.godboltKey;
    var entry = fnByKey[key];
    var source = entry && entry.fn.snippet;
    if(!source) return; // no snippet to show — a trigger with nothing behind it is inert, not a dead link to godbolt.org with an empty editor

    // The whole source travels in the URL, base64-encoded, and godbolt.org
    // sits behind a front end that rejects a request line over 8 KB with a
    // bare `414`. Measured against this repository's own map: the longest
    // single function comes to 2,880 characters and is fine, while the
    // largest module — 37 functions concatenated — comes to 33,332, four
    // times over. So a module trigger did not *sometimes* fail; on anything
    // past a handful of functions it could never have worked, and it failed
    // as an unexplained CloudFront error page in a new tab.
    //
    // Refuse locally instead. Saying why, in the page, beats opening a tab
    // that says `414 ERROR` and nothing else — and the alternative is real:
    // the per-function triggers on the same page do work.
    var url = godboltUrl(source);
    if(ceTooLong(url)){
      godboltTooLong(el, url.length);
      return;
    }
    window.open(url, "_blank");
  });

  // The 8 KB ceiling belongs to **godbolt.org's front end**, not to Compiler
  // Explorer: it is CloudFront refusing a long request line with a bare
  // `414`. A locally-run instance has no such thing in front of it, so
  // applying the limit there would be this page inventing a restriction its
  // target does not have — and refusing a link that would have worked.
  function ceTooLong(url){ return !ceIsLocal() && url.length > 8000; }

  // Explain a refusal where the reader clicked, and leave it explained: the
  // trigger keeps the message as its title afterwards, so the same link does
  // not invite the same click again.
  function godboltTooLong(el, len){
    var msg = "Too large for godbolt.org: this would be a " +
      Math.round(len / 1024) + " KB URL and their front end rejects anything " +
      "over 8 KB with a 414. Open a single function instead — those fit. " +
      "A Compiler Explorer you run yourself has no such limit; the Compare " +
      "tab is where you point this page at one.";
    el.classList.add("godi-off");
    el.title = msg;
    var note = el.parentNode && el.parentNode.querySelector(".godi-note");
    if(!note){
      note = document.createElement("div");
      note.className = "godi-note";
      el.parentNode.appendChild(note);
    }
    note.textContent = msg;
  }

  // Keyboard parity: the trigger is focusable, so tabbing a list reaches it
  // and Enter/Space opens the same card the pointer would.
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape" && sigAnchor){ sigClose(); return; }
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !(el.dataset.sig || el.dataset.doc)) return;
    ev.preventDefault();
    if(sigPinned && sigAnchor === el){ sigClose(); return; }
    sigOpen(el);
    sigPinned = true;
  });

  window.addEventListener("blur", sigClose);
  window.addEventListener("resize", sigClose);
  // Capture phase, so a scroll anywhere on the page reaches this — the card
  // is `position:fixed` against an anchor that scrolls away, so it has to go
  // when the page moves under it.
  //
  // But **not when the scroll is the card's own**. It is `max-height:60vh;
  // overflow-y:auto` on purpose: a forty-line snippet is meant to be
  // scrolled inside it. Without this test the card showed a scrollbar and
  // shut the instant anyone used it — an affordance that advertised
  // something it then refused to do, which is worse than not offering it.
  document.addEventListener("scroll", function(ev){
    if(ev.target && ev.target.nodeType === 1 && ev.target.closest &&
       ev.target.closest("#sigpop")) return;
    sigClose();
  }, true);

]]
