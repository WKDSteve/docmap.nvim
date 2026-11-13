---@module 'docmap.core.render.html.js.01_marks_and_dimming'
--- A slice of the page's script: Compare marks, hierarchy hide/dim.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
(function(){
  var IR = JSON.parse(document.getElementById("ir").textContent);
  var FIND = JSON.parse(document.getElementById("findings-data").textContent);
  var byId = {}; IR.nodes.forEach(function(n){ byId[n.id] = n; });

  var findByNode = {};
  FIND.forEach(function(f){ if(!f.node) return;
    (findByNode[f.node] = findByNode[f.node] || []).push(f); });

  // className -> { info: Docmap.TypeInfo, nodeId: owning node id }. Built
  // once so the Types hierarchy view and any class lookup can go straight to
  // a class by name instead of re-scanning every node's types_detail.
  var classByName = {};
  IR.nodes.forEach(function(n){
    (n.types_detail || []).forEach(function(t){ classByName[t.name] = { info: t, nodeId: n.id }; });
  });

  // ---------------------------------------------------------------------
  // Functions as first-class, addressable objects.
  //
  // "<node id>#<declared name>" — derivable from data already in the IR, so
  // no id has to be generated and serialized, and stable across regenerations
  // as long as the function keeps its name. This is what makes a function
  // something the URL can point at, the Calls view can center on, and the
  // context menu can act on; before it, a function existed only as a block of
  // text inside one node's detail pane.
  // ---------------------------------------------------------------------
  function fnKey(nodeId, name){ return nodeId + "#" + name; }

  var fnByKey = {};
  IR.nodes.forEach(function(n){
    (n.functions || []).forEach(function(fn){
      fnByKey[fnKey(n.id, fn.name)] = { node: n, fn: fn, key: fnKey(n.id, fn.name) };
    });
  });

  // =====================================================================
  // Compare marks
  //
  // A mark is a key — a node id, or `fnKey(nodeId, name)` — the reader has
  // set aside to look at next to others. Deliberately the *same* key scheme
  // `sigTrigger`, the context menu and `quicks.evidence` already speak, which
  // is what makes "mark every function behind this verdict" a one-liner
  // instead of a translation layer.
  //
  // The trigger is its own control beside the `ⓘ`, not a new meaning for
  // clicking it. That click already pins the annotation popup open, which is
  // the thing that makes a long `@example` readable at all; taking it over
  // would have traded one affordance for another and called it a feature.
  // =====================================================================
  function markExists(key){ return !!(fnByKey[key] || byId[key]); }

  // Scoped to this artifact's own path. Two projects' maps open in the same
  // browser are two different trees, and a shared key would leak one's marks
  // into the other's page.
  var MARKS_LS_KEY = "docmap:marks:" + location.pathname;

  function loadMarks(){
    try {
      var raw = localStorage.getItem(MARKS_LS_KEY);
      if(!raw) return [];
      return JSON.parse(raw).filter(markExists);
    } catch(e){
      // Private-mode localStorage throws on read in some browsers, and a
      // corrupt value is not worth a broken page over a convenience feature.
      return [];
    }
  }

  function saveMarks(list){
    try { localStorage.setItem(MARKS_LS_KEY, JSON.stringify(list)); } catch(e){ void 0; }
  }

  function isMarked(key){ return state.marks.indexOf(key) !== -1; }

  // Marks do not go through `navigate`: toggling one is not a navigation, and
  // pushing a history entry per mark would bury the actual navigation the
  // reader wants Back to return to under a stack of selection noise. The hash
  // is still updated — in place — so the link in the address bar is always
  // shareable and always current.
  function toggleMark(key){
    if(!markExists(key)) return;
    var i = state.marks.indexOf(key);
    if(i === -1) state.marks.push(key); else state.marks.splice(i, 1);
    state.marks.sort();
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
    if(state.tab === "compare") drawCompare();
  }

  function addMarks(keys){
    var changed = false;
    keys.forEach(function(k){
      if(markExists(k) && state.marks.indexOf(k) === -1){ state.marks.push(k); changed = true; }
    });
    if(!changed) return;
    state.marks.sort();
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
  }

  function clearMarks(){
    if(!state.marks.length) return;
    state.marks = [];
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
    if(state.tab === "compare") drawCompare();
  }

  // The affordance itself. Rendered beside every `sigTrigger`, and on its own
  // for a module (which has annotations but no signature to hang a `ⓘ` off).
  function markTrigger(key){
    return '<span class="marki" tabindex="0" role="button" data-mark="' + esc(key) +
      '" aria-label="Mark for comparison" title="Mark for comparison">&#43;</span>';
  }

  // Paints mark state onto whatever is currently in the DOM, and keeps the
  // toolbar counter honest. Called after every redraw rather than having each
  // renderer remember to emit an `on` class — one place to be right.
  function syncMarks(){
    document.querySelectorAll("[data-mark]").forEach(function(el){
      el.classList.toggle("on", isMarked(el.dataset.mark));
    });
    var bar = document.getElementById("markbar");
    if(!bar) return;
    var n = state.marks.length;
    bar.hidden = n === 0;
    bar.classList.toggle("has", n > 0);
    bar.textContent = "Compare (" + n + ")";
    bar.title = n + " marked object" + (n === 1 ? "" : "s") + " — open the Compare tab";
  }

  // Same "paint whatever is on screen" role as syncMarks, over `hboxes`
  // instead of a `[data-mark]` query — a Hierarchy box's key already sits on
  // its own element (`el.dataset.key`, set by reconcile()), so iterating
  // `hboxes` directly reaches every box without a second lookup. A no-op
  // on every tab but Hierarchy (`hboxes` is empty until drawHierarchy runs
  // at least once), which is why this is safe to call unconditionally from
  // applyState alongside syncMarks rather than gated on `state.tab`.
  // Boxes are created and destroyed by `reconcile()` on every redraw, so a
  // class set once does not survive a view switch or a re-centre. Painted
  // alongside `syncHidden` for exactly that reason -- same problem, same
  // solution, same call sites.
  function syncHidden(){
    Object.keys(hboxes).forEach(function(key){
      hboxes[key].classList.toggle("hidden", isHidden(key));
    });
    // Tree rows, Treemap areas and the dots of the Coupling plot dim by
    // node id too; "show all" has to reach them without waiting for the
    // next redraw.
    var alt = document.getElementById("halt-body");
    if(alt) alt.querySelectorAll(".ht-row[data-id], .tm-group[data-id], .tm-tile[data-id], .cq-dot[data-id]").forEach(function(el){
      el.classList.toggle("dim", isHidden(el.dataset.id));
    });
    var bar = document.getElementById("hiddenbar");
    if(!bar) return;
    var n = state.hidden.length;
    bar.hidden = n === 0;
    bar.classList.toggle("has", n > 0);
    bar.textContent = "Hidden (" + n + ") — show all";
    bar.title = n + " box" + (n === 1 ? "" : "es") +
      " dimmed in the Hierarchy view — click to show them again";
  }

  // =====================================================================
  // Hierarchy hide/dim
  //
  // A box in the Hierarchy graph, set aside so it stops competing for
  // attention in a large tree — never removed from the layout (that would
  // mean re-flowing the tree's remaining boxes, and possibly reparenting
  // its children, every time one is toggled), just dimmed to near-zero
  // opacity and taken out of pointer interaction. "Ausblenden/abdunkeln"
  // in the roadmap item this ships — reads as fully hidden, implemented as
  // a strong dim, so a reader who forgot what was under a dimmed box can
  // still make out its outline rather than wondering what used to be there.
  //
  // Keyed the same as `hboxes`/`positions`/`boxSpec` — a node id, a class
  // name (Types/Inheritance), or an `fnKey` (Calls) — so one mechanism
  // covers all five Hierarchy views without a per-view special case.
  //
  // State shape and persistence deliberately mirror Compare marks above:
  // same array-of-keys shape, same per-path localStorage scoping, same
  // hash-wins-over-localStorage precedence on initial load (see the load
  // at the bottom of this script). Not unified into one mechanism with
  // marks, because the two answer different questions — "compare these"
  // vs. "stop showing me that" — and a reader marking a function for
  // comparison has no reason to expect it to also disappear from a graph.
  // =====================================================================
  function hiddenKeyExists(key){
    return !!(byId[key] || classByName[key] || fnByKey[key]);
  }

  var HIDDEN_LS_KEY = "docmap:hidden:" + location.pathname;

  function loadHidden(){
    try {
      var raw = localStorage.getItem(HIDDEN_LS_KEY);
      if(!raw) return [];
      return JSON.parse(raw).filter(hiddenKeyExists);
    } catch(e){
      return [];
    }
  }

  function saveHidden(list){
    try { localStorage.setItem(HIDDEN_LS_KEY, JSON.stringify(list)); } catch(e){ void 0; }
  }

  function isHidden(key){ return state.hidden.indexOf(key) !== -1; }

  // Same "not a navigation" reasoning as toggleMark: updates the hash in
  // place via replaceState rather than pushState, so dimming ten boxes
  // while decluttering a tree does not bury the navigation the reader
  // actually wants Back to return to under ten selection-noise entries.
  function toggleHidden(key){
    if(!hiddenKeyExists(key)) return;
    var i = state.hidden.indexOf(key);
    if(i === -1) state.hidden.push(key); else state.hidden.splice(i, 1);
    state.hidden.sort();
    saveHidden(state.hidden);
    syncHidden();
    syncLangFilter();
    history.replaceState(state, "", serializeState(state));
  }

  function clearHidden(){
    if(!state.hidden.length) return;
    state.hidden = [];
    saveHidden(state.hidden);
    syncHidden();
    syncLangFilter();
    history.replaceState(state, "", serializeState(state));
  }

  // Blast radius: the transitive closure of `required_by`. Already implied
  // by the edges and visible nowhere, and it is the number that says how
  // risky a change to a module is — the same measurement before and after a
  // refactor is evidence that the refactor decoupled something.
  var impactCache = {};
  function impactOf(id){
    if(impactCache[id]) return impactCache[id];
    var seen = {}, queue = [id], qi = 0, out = [];
    seen[id] = true;
    while(qi < queue.length){
      var cur = queue[qi++];
      ((byId[cur] || {}).required_by || []).forEach(function(dep){
        if(seen[dep]) return;
        seen[dep] = true;
        out.push(dep);
        queue.push(dep);
      });
    }
    impactCache[id] = out;
    return out;
  }

  // Tree-wide, not scoped to whatever subgraph the Deps view currently has
  // centered — an external box means the same thing regardless of which
  // node you walked in from, and a count that changed as you re-centered
  // would read as a bug, not a feature. Computed once, lazily, off
  // `n.calls_external` (per-node, from `core/calls.lua`) rather than a
  // second pass over anything — the counting already happened in Lua.
  var externalCallTotals = null;
  function getExternalCallTotals(){
    if(externalCallTotals) return externalCallTotals;
    externalCallTotals = {};
    IR.nodes.forEach(function(n){
      (n.calls_external || []).forEach(function(c){
        var byMember = externalCallTotals[c.module] || (externalCallTotals[c.module] = {});
        var mkey = c.member || "";
        byMember[mkey] = (byMember[mkey] || 0) + c.count;
      });
    });
    return externalCallTotals;
  }

  // Edges arrive as one array with a `kind` discriminator; every consumer
  // wants one kind at a time, and both directions of it. Built once here
  // rather than filtered per redraw — a re-center at depth 3 would otherwise
  // walk all ~1300 edges once per layer.
  var depOut = {}, depIn = {}, callOut = {}, callIn = {}, typeEdges = [];
  // Inheritance, keyed both ways by class name: `extUp` answers "who are my
  // parents", `extDown` "who inherits me". An edge is stored as written
  // (from_class = the child, to_class = the parent), so which end is "next"
  // depends on which map you came in through — see layoutInheritance.
  var extUp = {}, extDown = {}, extendsEdges = [];
  // Module Calls view: the same "call" edges above, collapsed from
  // function-to-function to module-to-module and counted, so five call
  // sites between two modules draw one weighted edge, not five overlapping
  // ones. Built by reference: `moduleCallOut[id]` and `moduleCallIn[id]`
  // for a given pair share the *same* edge object, so incrementing
  // `.weight` once updates whichever side a walk finds it from. Self-edges
  // (two functions in the same file calling each other) are dropped — a
  // module graph has nothing to say about a module calling itself.
  var moduleCallOut = {}, moduleCallIn = {}, moduleCallEdgeByPair = {};
  function push(map, key, val){ (map[key] = map[key] || []).push(val); }
  (IR.edges || []).forEach(function(e){
    if(e.kind === "require"){
      push(depOut, e.from, e); push(depIn, e.to, e);
    } else if(e.kind === "call"){
      push(callOut, fnKey(e.from, e.from_fn), e);
      push(callIn, fnKey(e.to, e.to_fn), e);
      if(e.from !== e.to){
        var pairKey = e.from + " " + e.to;
        var mcEdge = moduleCallEdgeByPair[pairKey];
        if(!mcEdge){
          mcEdge = { from: e.from, to: e.to, weight: 0 };
          moduleCallEdgeByPair[pairKey] = mcEdge;
          push(moduleCallOut, e.from, mcEdge);
          push(moduleCallIn, e.to, mcEdge);
        }
        mcEdge.weight++;
      }
    } else if(e.kind === "type"){
      typeEdges.push(e);
    } else if(e.kind === "extends"){
      extendsEdges.push(e);
      push(extUp, e.from_class, e);
      push(extDown, e.to_class, e);
    }
  });

  // Classes that take part in at least one inheritance relation. The
  // Inheritance view seeds from these rather than from every class the
  // centered node declares: a class with no parent and no subclass is an
  // isolated box in a view that exists to show relationships, and most nodes
  // declare several of those — they would crowd out the handful of boxes that
  // actually connect.
  var inInheritance = {};
  extendsEdges.forEach(function(e){
    inInheritance[e.from_class] = true;
    inInheritance[e.to_class] = true;
  });

  // @see target -> owning node id. Same three resolution shapes as
  // docmap.check's check_see_targets, kept in sync deliberately: a bare
  // module path, "module.bareName" (the qualified form a reader would
  // actually write), and the raw declared name (e.g. "M.scan_full") as a
  // fallback for targets copy-pasted straight from source.
  var seeIndex = {};
  IR.nodes.forEach(function(n){
    if(n.module) seeIndex[n.module] = n.id;
    (n.functions || []).forEach(function(fn){
      seeIndex[fn.name] = n.id;
      if(n.module){
        var bare = fn.name.replace(/^[A-Z][\w]*\./, "");
        seeIndex[n.module + "." + bare] = n.id;
      }
    });
  });

  var repo = IR.meta.repo_url, branch = IR.meta.branch || "main";
  function srcUrl(p){ return repo ? repo + "/blob/" + branch + "/" + p : null; }

  function esc(s){ return (s||"").replace(/[&<>"]/g, function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }

  // Prose from a doc-comment, with its inline code rendered.
  //
  // **The doc-comments have always been markdown; this page was the one
  // output that showed it as text.** A summary reading "Registers the single
  // `:Debug` user command" arrived in the Hierarchy boxes with the backticks
  // visible. Measured on this repository: **432 summaries carry backticks**
  // — the rule rather than an edge. `overview.md` renders them correctly and
  // always has, because markdown does it natively, so the page was behind
  // its own sibling output.
  //
  // **Escaping first is not a detail, it is the whole safety argument.** A
  // summary is author-controlled text that ends up as innerHTML. `esc` runs
  // over the entire string before a single tag is introduced, and the only
  // tags this can then produce are the `<code>` pair it writes itself —
  // there is no path from source text to markup, because by the time the
  // backtick scan runs, every `<` in the input is already `&lt;`.
  //
  // Double backticks first, so ``a ` b`` — markdown's way of putting a
  // backtick inside code — is not read as two separate single-backtick
  // spans. **Non-greedy and character-agnostic**, because the first attempt
  // was neither and got the one case it exists for wrong: `[^`]+` forbids
  // the very character the double-backtick form is for, so this tree's own
  // "``\`[text](url)\``` in \`features_format.md\`" came out as `<code>`
  // wrapped around the spaces between the ticks. Found by reading the
  // rendered DOM, not the regex.
  //
  // **One pass, not two**, and that is the second thing rendering caught.
  // Run separately, the single-backtick pass reads the double-backtick
  // pass's own output and turns the ticks it deliberately preserved into a
  // nested `<code><code>…</code></code>`. One alternation consumes each
  // position exactly once, so the scanner never re-reads what it wrote.
  //
  // One leading and one trailing space are dropped when both are there,
  // which is what CommonMark does and what makes ``\`x\`` render as the
  // backticked text rather than as a space-padded one.
  //
  // Unpaired backticks are left exactly as written: half a code span is a
  // typo in the source, and silently swallowing the character would hide it.
  // Eleven of this tree's 432 have an odd count, every one of them a summary
  // the scanner truncated mid-span — visible now, which is the point.
  //
  // Fenced blocks are deliberately not handled here. A summary is one line;
  // the multi-line case is `@example`, which is a different surface with a
  // different shape, and doing both in one regex is how you get a renderer
  // nobody can reason about.
  function prose(s){
    var out = esc(s);
    out = out.replace(/``([\s\S]+?)``|`([^`\n]+)`/g, function(_, dbl, single){
      if(dbl === undefined){ return "<code>" + single + "</code>"; }
      var code = dbl;
      if(code.length > 2 && code[0] === " " && code[code.length - 1] === " "){
        code = code.slice(1, -1);
      }
      return "<code>" + code + "</code>";
    });
    return out;
  }

  // =====================================================================
  // The lookup layer
  //
  // Every place the page shows notation a reader may not recognise wants
  // the same thing: a short answer, in place, behind a deliberate gesture.
  // `lookup(kind, key, ctx)` is the one question, a kind is registered from
  // where its data lives (`lookupRegister`), and `lookupCardHTML` is the one
  // card. A trigger is any element carrying `data-kw` (the key) and
  // `data-kwkind` (the kind); the keyword card of the popups slice opens it
  // on a dwell, on focus and on a click, and closes it the same way for all.
  //
  // A kind answers with a card, with `null` (the trigger has nothing behind
  // it, which is a bug in whatever decorated it: no card at all), or with a
  // card whose `unknown` says why the data is not here. "Not known" is an
  // answer; an empty card is not.
  //
  // A card:
  //   word     what was asked about            kind    a small label beside it
  //   summary  prose (backticks rendered)      note    the surprising fact, verbatim
  //   lines    labelled one-liners: { label, text }
  //   rows     { title, items: { code, text, count }, total }, cut to LOOKUP_ROWS
  //            with the omitted amount stated
  //   unknown  why the data is missing         origin  where the answer comes from
  //   link     { href, label }, leaves the page
  //   nav      { label, to }, a state patch for navigate()
  // =====================================================================
  var LOOKUP = {};
  var LOOKUP_ROWS = 8;
  var LOOKUP_TEXT = 180;

  function own(obj, key){ return !!obj && Object.prototype.hasOwnProperty.call(obj, key); }

  function lookupRegister(kind, answer){ LOOKUP[kind] = answer; }

  function lookup(kind, key, ctx){
    if(!own(LOOKUP, kind)) return null;
    return LOOKUP[kind](key, ctx || {});
  }

  function lookupClip(text){
    text = String(text == null ? "" : text);
    return text.length > LOOKUP_TEXT ? text.slice(0, LOOKUP_TEXT - 1) + "…" : text;
  }

  function lookupCardHTML(card){
    var h = '<div class="kw-word">' + esc(card.word) +
      (card.kind ? '<span class="kw-kind">' + esc(card.kind) + '</span>' : '') + '</div>';
    if(card.summary) h += '<div class="kw-sum">' + prose(card.summary) + '</div>';
    if(card.unknown) h += '<div class="kw-unknown">Not known: ' + prose(card.unknown) + '</div>';
    if(card.note) h += '<div class="kw-note">' + esc(card.note) + '</div>';
    (card.lines || []).forEach(function(l){
      h += '<div class="kw-line"><span class="kw-label">' + esc(l.label) + '</span> ' +
        prose(l.text) + '</div>';
    });
    var rows = card.rows;
    if(rows && rows.items && rows.items.length){
      var total = rows.total || rows.items.length;
      var shown = rows.items.slice(0, LOOKUP_ROWS);
      if(rows.title) h += '<div class="kw-rows-title">' + esc(rows.title) + '</div>';
      h += '<ul class="kw-rows">';
      shown.forEach(function(r){
        h += '<li>' + (r.code ? '<code>' + esc(r.code) + '</code> ' : '') +
          (r.text ? prose(lookupClip(r.text)) : '') +
          (r.count ? ' <span class="kw-n">' + r.count + '×</span>' : '') + '</li>';
      });
      h += '</ul>';
      if(total > shown.length){
        h += '<div class="kw-more">… and ' + (total - shown.length) + ' more</div>';
      }
    }
    if(card.origin) h += '<div class="kw-origin">' + esc(card.origin) + '</div>';
    if(card.nav){
      h += '<div class="kw-ref"><a href="#" data-kw-nav="' + esc(JSON.stringify(card.nav.to)) +
        '">' + esc(card.nav.label) + '</a></div>';
    }
    if(card.link){
      h += '<div class="kw-ref"><a href="' + esc(card.link.href) +
        '" target="_blank" rel="noreferrer noopener">' + esc(card.link.label) + ' &#8599;</a></div>';
    }
    return h;
  }

  // ---------------------------------------------------------------------
  // The kinds the IR answers. No scanner work behind any of them: the data
  // is in the artifact already and was one navigation away.
  // ---------------------------------------------------------------------

  // Which languages of this map have call edges at all. A function of a
  // language without them has no callers the map could know of, and "0" would
  // be a number where "not known" is the answer.
  var callLangs = null;
  function hasCallEdges(node){
    if(callLangs === null){
      callLangs = {};
      (IR.edges || []).forEach(function(e){
        if(e.kind === "call" && byId[e.from] && byId[e.from].language){
          callLangs[byId[e.from].language] = true;
        }
      });
    }
    return !!(node && node.language && callLangs[node.language]);
  }

  // The distinct functions on the other end of a function's call edges.
  function callPeers(key, incoming){
    var seen = {}, out = [];
    ((incoming ? callIn : callOut)[key] || []).forEach(function(e){
      var k = incoming ? fnKey(e.from, e.from_fn) : fnKey(e.to, e.to_fn);
      if(seen[k]) return;
      seen[k] = true;
      out.push(k);
    });
    return out;
  }

  function lookupPlural(n, word){ return n + " " + word + (n === 1 ? "" : "s"); }

  // A call in a snippet that resolves in the tree: what the callee is, where
  // it lives, and the way there.
  lookupRegister("call", function(key){
    var e = own(fnByKey, key) ? fnByKey[key] : null;
    if(!e){
      return { word: key.replace(/^.*#/, ""), kind: "call",
        unknown: "the map has an edge to this function and no entry for it." };
    }
    return {
      word: e.fn.signature || e.fn.name, kind: "call",
      summary: e.fn.summary || null,
      unknown: e.fn.summary ? null : "it has no summary line.",
      origin: e.node.module || e.node.path,
      nav: { label: (e.node.module || e.node.path) + ":" + e.fn.line, to: { tab: "tree", id: e.node.id } }
    };
  });

  // A function's own name in its snippet: the numbers the Analysis tab holds
  // about it, where the reader is looking at it.
  lookupRegister("fn", function(key){
    var e = own(fnByKey, key) ? fnByKey[key] : null;
    if(!e) return { word: key.replace(/^.*#/, ""), kind: "function", unknown: "the map has no such function." };
    var edges = hasCallEdges(e.node);
    var inN = callPeers(key, true).length, outN = callPeers(key, false).length;
    var noEdges = "not known (the map has no call edges for " + (e.node.language || "this language") + ")";
    return {
      word: e.fn.name, kind: "function",
      lines: [
        { label: "Complexity", text: e.fn.complexity === undefined
          ? "not known (the map predates it)" : e.fn.complexity + " (cyclomatic)" },
        { label: "Called by", text: edges ? lookupPlural(inN, "function") + " of this tree" : noEdges },
        { label: "Calls", text: edges ? lookupPlural(outN, "function") + " of this tree" : noEdges },
        { label: "Tests", text: e.fn.tested === undefined
          ? "not known (the map predates it)"
          : (e.fn.tested ? "a spec names it" : "no spec names it") }
      ],
      nav: (inN || outN)
        ? { label: "Callers and callees", to: { tab: "hierarchy", view: "calls", center: e.node.id, fn: key, dir: "both" } }
        : null
    };
  });

  // A type name in a rendered annotation: its fields and where it is declared.
  // `types_detail` is there only when the map was generated with LuaLS
  // enrichment (`--full`); a map without it says so instead of guessing.
  var mapHasTypes = null;
  function hasTypeDetail(){
    if(mapHasTypes === null){
      mapHasTypes = IR.nodes.some(function(n){ return !!(n.types_detail && n.types_detail.length); });
    }
    return mapHasTypes;
  }

  lookupRegister("type", function(key){
    var c = own(classByName, key) ? classByName[key] : null;
    if(!c){
      return { word: key, kind: "type", unknown: hasTypeDetail()
        ? "no `@class` or `@alias` of this name is declared in the tree."
        : "this map carries no class details. They are read through `lua-language-server` when the map is generated with `--full`." };
    }
    var info = c.info, fields = info.fields || [];
    var parents = (info.extends || []).join(", ");
    return {
      word: info.name, kind: info.kind + (parents ? " : " + parents : ""),
      summary: info.desc || null,
      note: (!fields.length && info.kind === "class") ? "No fields declared." : null,
      rows: { title: "Fields", items: fields.map(function(f){
        return { code: f.name, text: f.view + (f.desc ? " — " + f.desc : "") };
      }) },
      origin: info.file,
      nav: { label: "Types view", to: { tab: "hierarchy", view: "types", center: c.nodeId, fn: null } }
    };
  });

  // Module name -> node id, for a `require` path. Built on first use.
  var nodeByModule = null;
  function moduleNode(name){
    if(nodeByModule === null){
      nodeByModule = {};
      IR.nodes.forEach(function(n){ if(n.module && !own(nodeByModule, n.module)) nodeByModule[n.module] = n.id; });
    }
    if(!own(nodeByModule, name)) return null;
    var id = nodeByModule[name];
    return byId[id] || null;
  }

  // What this file (or, without one, the whole tree) calls on an external
  // module, most called first: the shape the `+ external` boxes of the Deps
  // view break down into, where the name is written.
  function externalRows(module, node){
    var items = [];
    if(node){
      (node.calls_external || []).forEach(function(c){
        if(c.module === module) items.push({ code: c.member || module, count: c.count });
      });
    } else {
      var totals = getExternalCallTotals()[module] || {};
      Object.keys(totals).forEach(function(m){ items.push({ code: m || module, count: totals[m] }); });
    }
    items.sort(function(a, b){ return b.count - a.count || (a.code < b.code ? -1 : 1); });
    return items;
  }

  function externalCard(module, node, kind){
    var items = externalRows(module, node);
    return {
      word: module, kind: kind,
      note: items.length ? null
        : "Required here, and no call into it that the map can see.",
      rows: { title: node ? "This file calls" : "This tree calls", items: items },
      origin: "external: outside this map"
    };
  }

  function nodeOfCtx(ctx){
    var e = ctx.fnKey && own(fnByKey, ctx.fnKey) ? fnByKey[ctx.fnKey] : null;
    return e ? e.node : null;
  }

  // Is `name` under a prefix this tree owns (the first segment of one of its
  // module names)? The scan files a require that resolves to nothing under
  // `requires_external` whatever its name; one under the tree's own prefix
  // is not another project's module, it is a module that is missing.
  var treePrefixes = null;
  function firstSegment(name){ return String(name).replace(/\..*$/, ""); }
  function underOwnPrefix(name){
    if(treePrefixes === null){
      treePrefixes = {};
      IR.nodes.forEach(function(n){ if(n.module) treePrefixes[firstSegment(n.module)] = true; });
    }
    return own(treePrefixes, firstSegment(name));
  }

  // Is `module` one of the external modules of this file?
  function isExternalOf(node, module){
    if(!node || underOwnPrefix(module)) return false;
    if((node.requires_external || []).indexOf(module) !== -1) return true;
    return (node.calls_external || []).some(function(c){ return c.module === module; });
  }

  // An external module written in a snippet.
  lookupRegister("ext", function(key, ctx){
    var node = nodeOfCtx(ctx);
    if(node && !isExternalOf(node, key)){
      return { word: key, kind: "external module",
        unknown: "the map records no external require of this name for this file." };
    }
    return externalCard(key, node, "external module");
  });

  // A `require`/`import` path: three answers that look the same in the source.
  lookupRegister("req", function(key, ctx){
    var node = nodeOfCtx(ctx), target = null;
    if(node){
      (depOut[node.id] || []).forEach(function(d){ if(d.to_module === key && byId[d.to]) target = byId[d.to]; });
    }
    if(!target) target = moduleNode(key);
    if(target){
      return {
        word: key, kind: "require",
        summary: target.summary || null,
        unknown: target.summary ? null : "the module has no summary line.",
        origin: "in this tree: " + target.path,
        nav: { label: target.module || target.path, to: { tab: "tree", id: target.id } }
      };
    }
    if(isExternalOf(node, key)) return externalCard(key, node, "require");
    return { word: key, kind: "require",
      unknown: underOwnPrefix(key)
        ? "unresolved. The name is under this tree's own prefix and no file of the tree declares it."
        : "unresolved. It is neither a module of this tree nor an external require the map recorded for this file; the name may be built at run time." };
  });

  // A check id in a findings view: what the check compares and why it exists.
  // The catalogue is `core/findings.lua`'s, next to the sentences themselves.
  var checkByName = null;
  function checkEntry(name){
    if(checkByName === null){
      checkByName = {};
      (IR.checks || []).forEach(function(c){ checkByName[c.name] = c; });
    }
    return own(checkByName, name) ? checkByName[name] : null;
  }

  lookupRegister("check", function(key){
    var c = checkEntry(key);
    var n = FIND.filter(function(f){ return f.check === key; }).length;
    if(!c){
      return { word: key, kind: "check",
        unknown: "this page has no explanation for the check. It is one of the project's own `extra_checks`, or the page predates the catalogue.",
        origin: lookupPlural(n, "finding") + " here" };
    }
    return {
      word: c.name, kind: "check",
      summary: c.compares,
      lines: [{ label: "Why", text: c.why }],
      rows: { title: "A finding reads", items: (c.templates || []).map(function(t){ return { text: t }; }) },
      origin: "severity " + c.severity + " by default · " + lookupPlural(n, "finding") + " here"
    };
  });

  // Markdown info strings that are not the file extension the glossaries are
  // keyed by. Only the ones that actually differ from a *declared* extension
  // (`lang_registry.glossaries()` keys on `backend.extensions`), so this
  // table stays a list of spelling differences rather than a second language
  // registry that drifts from the first. An info string with no entry and no
  // matching extension gets no decoration at all, which is the same honest
  // degradation `snipBodyHTML` already applies to a backend that ships no
  // glossary.
  var FENCE_EXT = {
    assembly: "asm", assembler: "asm",
    "c#": "cs", csharp: "cs",
    elixir: "ex",
    erlang: "erl",
    haskell: "hs",
    kotlin: "kt",
    ocaml: "ml",
    python: "py",
    ruby: "rb",
    rust: "rs",
    shell: "sh", bash: "sh", sh: "sh"
  };

  // One fenced block, rendered.
  //
  // The single place on this page that turns fenced source into markup. It is
  // one place on purpose: the Features tab already split fences before this
  // existed (`renderFeatureBody`), and a second renderer beside it would have
  // given the same Lua two different looks on the same page, which is the
  // failure `prose()`'s own comment warns about one screen up.
  //
  // Highlighting reuses `snipBodyHTML` — the tokenizer the source snippets
  // already use — by handing it a synthetic path whose extension is the
  // fence's language. Reusing it is the whole point: a `lua` fence and a Lua
  // snippet then decorate identically, share the keyword card, and gain any
  // future language for free the moment a backend declares it. A fence with
  // no language, or one nothing knows, falls through to plain escaped text.
  function fenceHTML(src, lang){
    var info = (lang || "").toLowerCase();
    var ext = FENCE_EXT[info] || info;
    var path = ext ? ("fence." + ext) : "";
    var body = (path && glossaryForPath(path)) ? snipBodyHTML(src, path) : esc(src);
    return '<pre class="fence"' +
      (info ? ' data-lang="' + esc(info) + '"' : '') +
      (path ? ' data-path="' + esc(path) + '"' : '') +
      '>' + body + '</pre>';
  }

  // Author prose that may run to several lines, with fenced blocks in it.
  //
  // `prose()` deliberately stops at inline code because a summary is one
  // line; this is the other half it names. The split is line-based rather
  // than a second alternation inside that regex, for exactly the reason
  // stated there — both in one expression is how you get a renderer nobody
  // can reason about. Here a fence marker owns its line, which is what makes
  // the two rules independent: an inline span never starts a block, and a
  // block never eats a span.
  //
  // Text outside the fences still goes through `prose()`, so a paragraph
  // around a code block keeps its inline code.
  function richText(s){
    if(s === undefined || s === null) return "";
    var text = String(s);
    // Nothing to split and nothing to pay for: the overwhelming majority of
    // prose in any tree has no fence in it at all.
    if(text.indexOf("```") < 0) return prose(text);

    var lines = text.split("\n"), out = [], buf = [];
    var code = null, lang = "", openRaw = "";

    function flushProse(){
      if(!buf.length) return;
      out.push(prose(buf.join("\n")));
      buf = [];
    }

    for(var i = 0; i < lines.length; i++){
      var line = lines[i];
      if(code === null){
        var open = /^\s*```+\s*([A-Za-z0-9_+#.-]*)\s*$/.exec(line);
        if(open){
          flushProse();
          code = []; lang = open[1] || ""; openRaw = line;
          continue;
        }
        buf.push(line);
      } else if(/^\s*```+\s*$/.test(line)){
        out.push(fenceHTML(code.join("\n"), lang));
        code = null; lang = ""; openRaw = "";
      } else {
        code.push(line);
      }
    }

    // An unclosed fence goes back exactly as written, opening line included.
    // The same stance `prose()` takes on an unpaired backtick, for the same
    // reason: half a block is a typo in the source, and swallowing it would
    // hide the one thing the author needs to see.
    if(code !== null){
      buf.push(openRaw);
      buf = buf.concat(code);
    }
    flushProse();
    return out.join("");
  }

  // `@example` is code, not prose.
  //
  // Without a fence it stays exactly what it has always been — escaped and
  // nothing else — because a backtick inside an example is a backtick, and
  // running `prose()` over it would turn a shell command into markup. A fence
  // is an author saying "this part is <language>", and only then does the
  // block get what any other fence gets.
  function exampleHTML(s){
    if(s === undefined || s === null) return "";
    var text = String(s);
    return text.indexOf("```") < 0 ? esc(text) : richText(text);
  }

  // The affordance that opens the annotation popup, for any list that shows
  // a function. `tabindex` because a keyboard reader must be able to reach
  // it; `aria-label` rather than `title` because a native tooltip would open
  // *beside* the card this control exists to open, saying less.
  // Emits the mark trigger alongside, rather than making six call sites
  // remember to render both. The two controls are a pair — "tell me about
  // this" and "set this aside" — and a list that grew one without the other
  // would be a list the compare tab silently cannot reach.
  function sigTrigger(nodeId, fnName){
    var key = fnKey(nodeId, fnName);
    return '<span class="sigi" tabindex="0" role="button" aria-label="Annotations"' +
      ' data-sig="' + esc(key) + '">&#9432;</span>' + markTrigger(key);
  }

  var DOCREFS = (IR.docs && IR.docs.refs) || {};

  // The same affordance for prose references, and deliberately **only
  // rendered when there are some**. An always-present icon that is usually
  // empty trains the reader to ignore it; one that appears exactly when a
  // document mentions this thing is itself the signal, before it is clicked.
  // `key` is a node id for a module or `nodeId#fnName` for a function — the
  // shape `docs.lua` files references under.
  function docTrigger(key){
    var refs = DOCREFS[key];
    if(!refs || !refs.length) return "";
    return '<span class="doci" tabindex="0" role="button" data-doc="' + esc(key) +
      '" aria-label="Mentioned in ' + refs.length + ' place' +
      (refs.length === 1 ? '' : 's') + ' in the docs">&#182;' +
      (refs.length > 1 ? '<span class="docn">' + refs.length + '</span>' : '') + '</span>';
  }

]]
