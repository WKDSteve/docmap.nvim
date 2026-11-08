---@module 'docmap.core.render.html.js.06_analysis_tools'
--- A slice of the page's script: Analysis tab: the tool palette (first part).
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Analysis tab: a tool palette, not a diagram — the same "toolbar
  // switches what a shared panel shows" shape the Hierarchy view buttons
  // and the Index Functions/Modules toggle already use, applied to
  // aggregate numbers instead of boxes or a flat alphabet.
  //
  // Each tool reads a boolean docmap already stamped onto every function
  // during scan_full() (`fn.tested`, R2; `fn.documented`, R4) rather than
  // recomputing anything here — `doccoverage.is_documented`'s param-name
  // comparison in particular is not something this file should ever
  // reimplement in JS, where it would inevitably drift from check.lua's
  // own logic the moment either side changed.
  //
  // First two tools only, deliberately: R6 (fan-in/fan-out hotspots) and
  // beyond are real candidates but have no data stamped into the IR yet —
  // adding their buttons here before their data exists would be a menu
  // entry that opens an empty panel, exactly what the context menu's
  // "disabled with count shown" rule exists to avoid elsewhere.
  // =====================================================================

  // `excludeInternal` matters for the Documentation panel specifically:
  // `doccoverage.summary`'s own definition of "total" already excludes
  // `@internal` functions (an internal function's documentation bar is the
  // author's own, not part of a "published API" number), and this panel
  // must count the same way or its 65% would quietly disagree with the
  // number `:DocMap`/the CLI prints for the same tree. The Test-coverage
  // panel passes false: `coverage.resolve` stamps `fn.tested` on every
  // function regardless of `@internal`, so its total is every function.
  // ---------------------------------------------------------------------
  // Sortable Analysis tables.
  //
  // Three pieces shared by every panel so the behaviour cannot differ between
  // them: a header renderer, a sorter, and a filter. Each panel declares its
  // columns as `{ label, key, get, initial }` and gets clickable headers, the
  // arrow, the URL round-trip and the text filter for free.
  //
  // `key == null` means an unsortable column — the bar graphics, which are a
  // rendering of a column already in the table and would sort by nothing.
  //
  // The panel's own default order survives: with no `asort` the caller's
  // `fallback` comparator runs, tiebreaks included. That matters because
  // "worst first, then most functions affected, then id" is an editorial
  // judgement about where to look, and collapsing it to "sorted by pct desc"
  // would quietly change what the panel recommends.
  // ---------------------------------------------------------------------

  ///Render a `<thead>` from a column spec, marking the active sort.
  function anHead(cols){
    var out = ['<thead><tr>'];
    cols.forEach(function(c){
      if(!c.key){ out.push('<th>' + (c.label || "") + '</th>'); return; }
      var active = state.asort === c.key;
      // The arrow is on the active column only. An idle arrow on every header
      // reads as "these are all sorted", which is exactly backwards.
      var arrow = active ? (state.adir === "asc" ? " ▲" : " ▼") : "";
      // A sort control is a control: focusable in its own right, and few
      // enough (three per table) that it is a tab stop rather than another
      // roving list. `aria-sort` is the one ARIA property a sortable column
      // header genuinely owns, and it is derivable from state already here.
      out.push('<th class="ansort' + (active ? " active" : "") + '" data-sort="' +
        esc(c.key) + '" data-initial="' + (c.initial === "asc" ? "asc" : "desc") +
        '" tabindex="0" role="button" aria-sort="' +
        (active ? (state.adir === "asc" ? "ascending" : "descending") : "none") +
        '" title="Sort by ' + esc(c.label) + '">' + c.label + arrow + '</th>');
    });
    out.push('</tr></thead>');
    return out.join("");
  }

  ///Sort `rows` per the active column, or by `fallback` when none is active.
  function anSort(rows, cols, fallback){
    var col = null;
    for(var i = 0; i < cols.length; i++){
      if(cols[i].key && cols[i].key === state.asort) col = cols[i];
    }
    if(!col || !col.get){
      rows.sort(fallback);
      return rows;
    }
    var dir = state.adir === "asc" ? 1 : -1;
    rows.sort(function(a, b){
      var av = col.get(a), bv = col.get(b);
      if(av !== bv) return (av < bv ? -1 : 1) * dir;
      // Always the same tiebreak, independent of direction: without it, two
      // rows with equal values swap places on every re-render, which looks
      // like the table is unstable.
      var ak = a.sortkey || "", bk = b.sortkey || "";
      return ak < bk ? -1 : (ak > bk ? 1 : 0);
    });
    return rows;
  }

  ///Keep only rows whose `haystack` contains the active query.
  ///
  ///Substring, case-insensitive, no fuzzy matching. The Tree tab's filter and
  ///the Hierarchy jump already offer richer matching; what this answers is
  ///"show me only this module", where a fuzzy match that also returns four
  ///near-misses is worse than an exact one.
  function anFilter(rows){
    var q = (state.q || "").toLowerCase().trim();
    if(!q) return rows;
    return rows.filter(function(r){
      return (r.haystack || "").toLowerCase().indexOf(q) >= 0;
    });
  }

  ///The "N hidden by the filter" line, or "" when nothing is filtered.
  ///
  ///Said out loud rather than left implicit: a panel that silently shows three
  ///of forty rows looks like a map with three modules in it.
  function anFilterNote(shown, total){
    if(shown === total) return "";
    return ' <strong>' + shown + ' of ' + total + '</strong> shown, filtered by "' +
      esc(state.q) + '".';
  }

  function renderAnalysisPanel(label, sub, pick, excludeInternal){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fns = (n.functions || []).filter(function(fn){
        return !(excludeInternal && fn.internal);
      });
      if(fns.length === 0) return;
      var hit = 0;
      fns.forEach(function(fn){ if(pick(fn)) hit++; });
      var name = n.module || n.path;
      rows.push({
        node: n, hit: hit, total: fns.length, pct: hit / fns.length,
        name: name, haystack: name + " " + n.id, sortkey: n.id
      });
    });

    // Totals over *everything*, before the filter: the headline percentage is
    // a property of the map, not of what is currently on screen, and a number
    // that moved when you typed would be actively misleading.
    var totalHit = 0, totalAll = 0;
    rows.forEach(function(r){ totalHit += r.hit; totalAll += r.total; });
    var overallPct = totalAll > 0 ? Math.round(100 * totalHit / totalAll) : 0;
    var totalRows = rows.length;

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    // Worst-first: the module that needs attention most belongs at the top
    // of a panel meant to answer "where should I look", not filed
    // alphabetically where that answer is buried. Fewer functions is not
    // itself worse, so the tiebreak is functions-affected (a 0% module with
    // 20 functions matters more than one with 1), then module id for a
    // stable order once both numbers tie exactly.
    var cols = [
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: label, key: "pct", get: function(r){ return r.pct; }, initial: "asc" },
      { label: "Functions", key: "total", get: function(r){ return r.total; }, initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      // The default: worst first. The module that needs attention most belongs
      // at the top of a panel meant to answer "where should I look", not filed
      // alphabetically where that answer is buried. Fewer functions is not
      // itself worse, so the tiebreak is functions-affected (a 0% module with
      // 20 functions matters more than one with 1), then module id for a
      // stable order once both numbers tie exactly.
      if(a.pct !== b.pct) return a.pct - b.pct;
      if(a.total !== b.total) return b.total - a.total;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + label + ': <strong>' + totalHit + '/' + totalAll +
      '</strong> functions (' + overallPct + '%). ' + sub +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No module matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var pct = Math.round(r.pct * 100);
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.hit + '/' + r.total + ' (' + pct + '%)</td>' +
        '<td>' + r.total + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + pct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // R6: fan-in/fan-out per module, read straight off `n.requires`/
  // `n.required_by` — both already sorted, deduplicated indexes into
  // `ir.edges`'s require edges (see `Docmap.Node` in @types/init.lua),
  // so this is JS-side aggregation only, no new Lua extraction. Distinct
  // from `renderAnalysisPanel`: that one counts a boolean over a node's
  // *functions*, this counts edges over the *node itself*, so it is its
  // own small render function rather than a third `pick` callback bent
  // into the same shape.
  function renderAnalysisDeps(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fanIn = (n.required_by || []).length;
      var fanOut = (n.requires || []).length;
      if(fanIn === 0 && fanOut === 0) return;
      var name = n.module || n.path;
      rows.push({
        node: n, fanIn: fanIn, fanOut: fanOut,
        name: name, haystack: name + " " + n.id, sortkey: n.id
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no require edges.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Fan-in", key: "fanIn", get: function(r){ return r.fanIn; }, initial: "desc" },
      { label: "Fan-out", key: "fanOut", get: function(r){ return r.fanOut; }, initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      // Highest fan-in first: the module most other modules depend on is the
      // one whose blast radius matters most, the same "most consequential
      // first" rule the coverage panels already follow with their pct sort.
      // Fan-out is the tiebreak, not an equal-weight second key — a module
      // nothing depends on but that itself pulls in a lot is a different
      // smell (the roadmap's "God module" idea), worth seeing but not at the
      // cost of burying real fan-in leaders under it.
      if(a.fanIn !== b.fanIn) return b.fanIn - a.fanIn;
      if(a.fanOut !== b.fanOut) return b.fanOut - a.fanOut;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    // Over the filtered set on purpose, unlike the coverage panels' headline
    // percentage: this is a *scale* for the bars beside it, so it has to match
    // the rows actually drawn or the longest visible bar stops being full.
    var maxFanIn = rows.reduce(function(m, r){ return Math.max(m, r.fanIn); }, 0);

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' modules with at least one require ' +
      'edge. Fan-in is how many other modules require this one — the blast radius if it ' +
      'changes. Fan-out is how many modules it requires itself.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No module matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = maxFanIn > 0 ? Math.round(100 * r.fanIn / maxFanIn) : 0;
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.fanIn + '</td>' +
        '<td>' + r.fanOut + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Cyclomatic complexity (McCabe): `fn.complexity`, computed unconditionally
  // by docmap.functions during the scan itself (unlike tested/documented,
  // there is no IR-only "resolve" step that could derive it later — it
  // needs the treesitter node, which only exists during that same pass).
  // Ranked by function, not rolled up per module: "longest/most tangled
  // function" is a property of one function, and averaging it into a
  // per-module score would bury the one function that actually needs
  // attention under a healthy module's mean.
  // The published surface: every function this tree exposes, with whether it
  // is documented and whether anything outside its own module calls it.
  //
  // Three places already hold a third of this each -- Index has the names,
  // Documentation has the state, Deps has the edges -- and none of them
  // answers "what does this plugin actually expose". The question is asked
  // every time a module is extracted into its own plugin, which this
  // ecosystem has now done twice, by hand both times.
  //
  // **`internal` is read, never guessed.** It is a contract field the backend
  // fills from the language itself in nineteen of the backend files -- Zig's
  // `pub`, Java's `public`, C's `static`, Lua's `@internal` tag -- so the
  // surface is *declared* rather than inferred from a naming convention.
  // That is also why this panel was cheap: the hard half was paid for by the
  // visibility work.
  //
  // **"No caller here" is not "unused", and the panel says so.** A plugin's
  // published API is consumed by *other repositories* by definition; a
  // function with no in-tree caller outside its own module is exactly what an
  // exported entry point looks like from inside. So the column counts what it
  // can see, is named for that, and the sub-line states what it cannot.
  // Which annotation tags this tree actually uses, generated.
  //
  // `docs/annotations.md` is this analysis done by hand, for one repository,
  // once — which `IDEAS.md` §2.1 calls what it is: a plugin whose entire
  // purpose is detecting drift shipping a hand-maintained inventory of its
  // own tag usage is drift, structurally. The last time that document was
  // recounted, `@nodiscard` had gone from 112 occurrences to zero and nothing
  // had noticed.
  //
  // **Adoption per function, not occurrences.** The hand-written table counts
  // how many times a tag appears in the source; this counts how many
  // functions carry it at least once. They answer different questions and the
  // panel says which one it answers: eleven hundred `@param` lines is a fact
  // about typing effort, "84% of functions document a parameter" is a fact
  // about the tree.
  //
  // **The tag -> field mapping comes from the catalogue**, not from here.
  // `param` lands in `params` and `return` in `returns`, which is not
  // derivable from the name, so the alternative is this panel keeping its own
  // copy of a table `core/tags.lua` already has — and a copy that drifts
  // reports zero adoption for a tag the tree uses everywhere, which looks
  // exactly like a true answer.
  function renderAnalysisAnnotations(){
    var catalogue = IR.tags || [];
    if(!catalogue.length){
      return '<p class="ntext none">This map was generated before the annotation ' +
        'catalogue existed, so there is nothing to report adoption against.</p>';
    }

    // Only function-scope tags: a module tag lives on the file and a class
    // tag on a type, and folding three denominators into one column would
    // produce a percentage of nothing in particular.
    var fnTags = catalogue.filter(function(t){ return t.scope === "function" && t.field; });

    var total = 0;
    var counts = {};
    fnTags.forEach(function(t){ counts[t.name] = { n: 0, nodes: {} }; });

    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        total++;
        fnTags.forEach(function(t){
          var v = fn[t.field];
          // Three shapes behind one question: a list with something in it, a
          // string with something in it, a flag that is set. `false` and `[]`
          // and `""` all mean the same thing here and none of them counts.
          var has = Array.isArray(v) ? v.length > 0 : (typeof v === "string" ? v.length > 0 : !!v);
          if(has){
            counts[t.name].n++;
            counts[t.name].nodes[n.id] = true;
          }
        });
      });
    });

    if(total === 0){
      return '<p class="ntext none">This map contains no functions to report adoption over.</p>';
    }

    var rows = fnTags.map(function(t){
      var c = counts[t.name];
      var files = 0;
      for(var k in c.nodes){ if(c.nodes.hasOwnProperty(k)) files++; }
      return {
        tag: "@" + t.name,
        name: t.name,
        origin: t.origin === "luals" ? "LuaCATS" : "docmap",
        summary: t.summary,
        url: t.url || null,
        n: c.n,
        files: files,
        pct: Math.round(1000 * c.n / total) / 10,
        haystack: "@" + t.name + " " + t.summary,
        sortkey: t.name
      };
    });

    var cols = [
      { label: "Tag", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "From", key: "origin", get: function(r){ return r.origin; }, initial: "asc" },
      { label: "Functions", key: "n", get: function(r){ return r.n; }, initial: "desc" },
      { label: "Files", key: "files", get: function(r){ return r.files; }, initial: "desc" },
      { label: "", key: null }
    ];

    var totalRows = rows.length;
    var unused = rows.reduce(function(a, r){ return a + (r.n === 0 ? 1 : 0); }, 0);
    rows = anFilter(rows);
    // Most-used first, and an unused tag sinks to the bottom where it reads
    // as what it is: a convention this tree does not follow. That is the row
    // the hand-written table got wrong for months.
    anSort(rows, cols, function(a, b){
      if(a.n !== b.n) return b.n - a.n;
      return a.sortkey < b.sortkey ? -1 : 1;
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' function-scope tag' +
      (totalRows === 1 ? "" : "s") + ' this pipeline reads, against ' + total +
      ' function' + (total === 1 ? "" : "s") + ' in this map' +
      (unused ? ' - ' + unused + ' of them used nowhere here' : '') +
      '. Counted per <em>function that carries the tag at least once</em>, not ' +
      'per occurrence: eleven hundred <code>@param</code> lines is a fact about ' +
      'typing effort, "most functions document a parameter" is a fact about the ' +
      'tree. Module-scope and type-scope tags are left out rather than folded ' +
      'in, because their denominator is files and types rather than functions.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No tag matches that filter.</p>';
    }

    var maxN = rows.reduce(function(m, r){ return Math.max(m, r.n); }, 1);
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = Math.round(100 * r.n / maxN);
      parts.push('<tr class="anrow">' +
        '<td><code>' + esc(r.tag) + '</code><div class="ntext">' + prose(r.summary) + '</div></td>' +
        '<td>' + esc(r.origin) + '</td>' +
        '<td>' + r.n + (r.n ? ' <span class="ntext">(' + r.pct + '%)</span>' : '') + '</td>' +
        '<td>' + (r.files || "none") + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisApi(){
    // Call edges into a `<node>#<fn>` key, keeping only callers from a
    // *different* module. A module calling itself says nothing about what it
    // exposes.
    var external = {};
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "call") return;
      if(!e.to || !e.to_fn) return;
      if(e.from === e.to) return;
      var k = fnKey(e.to, e.to_fn);
      if(!external[k]) external[k] = {};
      external[k][e.from] = true;
    });

    var rows = [];
    var marked = 0;
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        if(fn.internal){ marked++; return; }
        var callers = external[fnKey(n.id, fn.name)];
        var count = 0;
        if(callers){
          for(var k in callers){ if(callers.hasOwnProperty(k)) count++; }
        }
        rows.push({
          node: n, fn: fn, name: name,
          sig: fn.signature || fn.name,
          documented: !!fn.documented,
          callers: count,
          haystack: (fn.signature || fn.name) + " " + name,
          sortkey: name + "#" + (fn.signature || fn.name)
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map exposes no functions - everything ' +
        'it declares is marked internal, or nothing was extracted.</p>';
    }

    var totalRows = rows.length;
    var documented = rows.reduce(function(a, r){ return a + (r.documented ? 1 : 0); }, 0);
    var unreached = rows.reduce(function(a, r){ return a + (r.callers === 0 ? 1 : 0); }, 0);

    var cols = [
      { label: "Function", key: "sig", get: function(r){ return r.sig; }, initial: "asc" },
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Documented", key: "documented",
        get: function(r){ return r.documented ? 1 : 0; }, initial: "asc" },
      { label: "Callers here", key: "callers",
        get: function(r){ return r.callers; }, initial: "desc" }
    ];

    rows = anFilter(rows);
    // Least-reached first: the rows worth opening this panel for are the ones
    // nothing here calls. Each is either a real entry point or an export
    // nobody meant to make, and telling those two apart is the whole job.
    anSort(rows, cols, function(a, b){
      if(a.callers !== b.callers) return a.callers - b.callers;
      if(a.documented !== b.documented) return a.documented ? 1 : -1;
      return a.sortkey < b.sortkey ? -1 : 1;
    });

    var parts = [];
    // **Whether this is a surface at all depends on the language.** Zig's
    // `pub`, Java's `public` and C's `static` are keywords, so `internal`
    // arrives from the code and the list below is the real published API. Lua
    // and the ECMA family have no keyword at this granularity, so `internal`
    // arrives from an `@internal` tag somebody had to write -- and in a tree
    // where nobody wrote one, an unmarked file-local helper is
    // indistinguishable from an entry point. Measured on this repository the
    // day the panel was built: `norm(p)`, a local in `bindings/usrcmds`, sat
    // in the list beside `M.render()`. Saying so is the fix; guessing from a
    // `M.` prefix would be exactly the naming-convention inference the rest
    // of this panel refuses.
    // Always both halves, rather than a caveat above some threshold: the
    // count says how much was excluded, and the sentence after it says what
    // being excluded depended on. A tree with two marked functions out of
    // 776 -- this repository, measured -- is nearer to the zero case than to
    // a curated surface, and no cut-off would have said so honestly.
    var caveat = ' ' + (marked === 0
      ? '<strong>Nothing here is marked internal.</strong>'
      : marked + ' function' + (marked === 1 ? " is" : "s are") +
        ' marked internal and excluded.') +
      ' Internal is declared, never inferred - a keyword in Zig, Java and C, ' +
      'an <code>@internal</code> tag in Lua and JS/TS. In a tag language ' +
      'that means an untagged file-local helper reads the same here as an ' +
      'entry point, so the list is the surface only as far as the tree ' +
      'bothered to say.';
    parts.push('<p class="nsub">' + totalRows + ' published function' +
      (totalRows === 1 ? "" : "s") + ' - ' + documented + ' documented, ' +
      unreached + ' with no caller inside this repository.' + caveat +
      ' <strong>No caller here does not mean unused</strong> - a published API ' +
      'is consumed by other repositories by definition, and that is what an ' +
      'entry point looks like from inside. The column counts call edges from ' +
      'a different module of this tree, so a dynamically dispatched call is ' +
      'invisible to it, the same blind spot the Calls view has.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No function matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.sig) + sigTrigger(r.node.id, r.fn.name) +
          docTrigger(fnKey(r.node.id, r.fn.name)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + (r.documented ? "yes" : "no") + '</td>' +
        '<td>' + (r.callers === 0 ? "none" : r.callers) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisComplexity(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        rows.push({
          node: n, fn: fn, complexity: fn.complexity || 1,
          name: name, sig: fn.signature || "",
          // Both, so "which of this module's functions are the tangled ones"
          // and "where is `parse_header`" are the same box.
          haystack: (fn.signature || "") + " " + name,
          sortkey: name + "#" + (fn.signature || "")
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Function", key: "sig", get: function(r){ return r.sig; }, initial: "asc" },
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Complexity", key: "complexity", get: function(r){ return r.complexity; },
        initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.complexity !== b.complexity) return b.complexity - a.complexity;
      return a.fn.signature < b.fn.signature ? -1 : 1;
    });
    // Scale for the bars, so over the filtered set — same reasoning as the
    // deps panel's `maxFanIn`.
    var maxC = rows.reduce(function(m, r){ return Math.max(m, r.complexity); }, 1);

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' documented functions, ranked by ' +
      'cyclomatic complexity (McCabe) — one point per if/elseif/while/for/repeat/and/or, ' +
      'plus a base of 1. Highest first.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No function matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = Math.round(100 * r.complexity / maxC);
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.fn.signature) + sigTrigger(r.node.id, r.fn.name) +
          docTrigger(fnKey(r.node.id, r.fn.name)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.complexity + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // The Duplicates panel as a list or as clusters. Not in the URL: a way of looking
  // at the same groups, not a place.
  var dupView = "list";

  // The members of one duplicate group by module, largest first, ties by name.
  function duplicateClusterModules(g){
    var by = {}, order = [];
    g.members.forEach(function(m){
      var name = m.module || m.node;
      if(!by[name]){ by[name] = []; order.push(name); }
      by[name].push(m);
    });
    order.sort(function(a, b){
      if(by[a].length !== by[b].length) return by[b].length - by[a].length;
      return a < b ? -1 : (a > b ? 1 : 0);
    });
    return order.map(function(name){ return { module: name, members: by[name] }; });
  }

  // One group as a cluster: a box per module, wide by how many of the members it
  // holds, so one missing abstraction (many copies across modules) can be told
  // from a coincidence at a glance. The rows are the same as in the list: a click
  // goes to the module, and `sigTrigger` carries the mark for Compare.
  function renderDuplicateCluster(g){
    var mods = duplicateClusterModules(g);
    var html = ['<section class="dupcl"><h3 class="nhead">' + g.members.length +
      ' functions in ' + mods.length + ' module' + (mods.length === 1 ? '' : 's') + ', ' +
      g.size + ' nodes</h3><div class="dupcl-mods">'];
    mods.forEach(function(mod){
      html.push('<div class="dupcl-mod" style="flex-grow:' + mod.members.length + '">' +
        '<div class="dupcl-name">' + esc(mod.module) + '</div>');
      mod.members.forEach(function(m){
        html.push('<div class="anrow dupcl-fn" data-node="' + esc(m.node) + '">' +
          esc(m.signature || m.name) + sigTrigger(m.node, m.name) +
          ' <span class="dupcl-line">:' + m.line + '</span></div>');
      });
      html.push('</div>');
    });
    html.push('</div></section>');
    return html.join("");
  }

  // Structural duplicates, straight off `ir.duplicates` — computed in Lua by
  // duplicates.lua rather than here, unlike the fan-in/fan-out panel. That one
  // is an aggregation over data already serialised; this one needs the parse
  // tree, which does not survive into the artifact, so the grouping has to
  // happen where the tree existed.
  function renderAnalysisDuplicates(){
    var dup = IR.duplicates;
    if(!dup){
      return '<p class="ntext none">This map was generated before duplicate ' +
        'detection existed. Regenerate it to see this panel.</p>';
    }

    var parts = [];
    if(!dup.groups || dup.groups.length === 0){
      parts.push('<p class="nsub">No two functions in this tree share a structure. ' +
        dup.considered + ' functions were large enough to compare (at least ' +
        dup.min_size + ' syntax nodes); anything smaller is excluded, because ' +
        'every tree has a dozen one-line accessors that match each other and ' +
        'mean nothing.</p>');
      parts.push('<p class="ntext none">Nothing to report.</p>');
      return parts.join("");
    }

    parts.push('<p class="nsub">' + dup.groups.length + ' group' +
      (dup.groups.length === 1 ? '' : 's') + ' of structurally identical functions, ' +
      'covering ' + dup.functions + ' of the ' + dup.considered + ' functions large ' +
      'enough to compare (at least ' + dup.min_size + ' syntax nodes). Identifier and ' +
      'literal names are ignored, so a renamed copy still matches — but a single ' +
      'edited line does not. Largest group first.</p>');
    parts.push('<p class="nsub">Sharing a shape is not by itself a defect: two ' +
      'adapters around different APIs can be the same five lines of plumbing. ' +
      'This is a ranking to read, never a check that fails.</p>');

    // Filtered by *group*, not by member: a duplicate group with its matching
    // members removed is no longer a duplicate group, and showing "3
    // identical" above one row would be a lie. So a group survives if any
    // member matches, and then survives whole.
    var query = (state.q || "").toLowerCase().trim();
    var groups = dup.groups;
    if(query){
      groups = groups.filter(function(g){
        return g.members.some(function(m){
          return ((m.signature || m.name || "") + " " + (m.module || m.node || ""))
            .toLowerCase().indexOf(query) >= 0;
        });
      });
      parts.push('<p class="nsub"><strong>' + groups.length + ' of ' +
        dup.groups.length + '</strong> groups shown, filtered by "' + esc(state.q) +
        '". A group matches when any of its members does, and is then shown whole — ' +
        'a group with members removed would no longer be one.</p>');
      if(groups.length === 0){
        return parts.join("") + '<p class="ntext none">No group matches that filter.</p>';
      }
    }

    parts.push('<p class="dupview" role="group" aria-label="How to show the groups">' +
      '<button class="dupview-btn' + (dupView === "list" ? ' active' : '') + '" data-dupview="list">List</button>' +
      '<button class="dupview-btn' + (dupView === "clusters" ? ' active' : '') + '" data-dupview="clusters">Clusters</button>' +
      '</p>');
    if(dupView === "clusters"){
      groups.forEach(function(g){ parts.push(renderDuplicateCluster(g)); });
      return parts.join("");
    }

    groups.forEach(function(g){
      parts.push('<h3 class="nhead">' + g.members.length + ' identical, ' +
        g.size + ' nodes</h3>');
      parts.push('<table class="antable"><thead><tr><th>Function</th><th>Module</th>' +
        '<th>Line</th></tr></thead><tbody>');
      g.members.forEach(function(m){
        parts.push('<tr class="anrow" data-node="' + esc(m.node) + '">' +
          '<td>' + esc(m.signature || m.name) + sigTrigger(m.node, m.name) + '</td>' +
          '<td>' + esc(m.module || m.node) + '</td>' +
          '<td>' + m.line + '</td>' +
          '</tr>');
      });
      parts.push("</tbody></table>");
    });
    return parts.join("");
  }

  // One line per trigger kind actually present on a spec — mirrors
  // bindings/usrcmds/plugins.lua's `traits()` in Lua exactly, kept in sync by
  // hand because the two run in different languages and read the same
  // `Docmap.PluginSpec` shape for two different surfaces (this panel,
  // that command's quickfix list).
  // Whether anything in this spec defers the load.
  function pluginHasTrigger(spec){
    return ((spec.event || []).length + (spec.cmd || []).length +
            (spec.keys || []).length + (spec.ft || []).length) > 0;
  }

  // **When this plugin is actually loaded — four states, not two.**
  //
  // This used to answer "no trigger — loads at startup" for every spec with
  // no `event`/`cmd`/`ft`/`keys`, and that is wrong for one of them in a way
  // that matters. `lazy = true` with no trigger does *not* load at startup:
  // it loads when another plugin `require`s it, or on `:Lazy load`. Telling
  // its author it costs them startup time is the opposite of the truth, and
  // it is the state a dependency-only plugin is normally in.
  //
  // Measured before being called a defect: against a real 52-entry config,
  // **seven** specs were in exactly that state and every one was labelled
  // "loads at startup".
  //
  // `lazy` is `null` when unstated, which lazy.nvim resolves by looking at
  // the triggers — the same rule applied here, and the one place this file
  // re-derives a default the extractor deliberately did not.
  function pluginLoad(spec){
    if(spec.lazy === false) return "startup";
    if(pluginHasTrigger(spec)) return "trigger";
    if(spec.lazy === true) return "ondemand";
    return "startup";
  }

  function pluginTraits(spec){
    var bits = [];
    var load = pluginLoad(spec);
    if(spec.lazy === false) bits.push("eager");
    if((spec.event || []).length) bits.push("event:" + spec.event.join(","));
    if((spec.cmd || []).length) bits.push("cmd:" + spec.cmd.join(","));
    if((spec.keys || []).length) bits.push("keys:" + spec.keys.join(","));
    if((spec.ft || []).length) bits.push("ft:" + spec.ft.join(","));
    if(spec.enabled === false) bits.push("disabled");
    if(load === "ondemand"){
      bits.push("lazy = true, no trigger — loads only when required");
    }else if(bits.length === 0){
      bits.push("no trigger — loads at startup");
    }
    return bits.join("  ");
  }

  // lazy.nvim spec entries, straight off `n.plugins` — JS-side aggregation
  // only, no new Lua extraction, the same shape as the fan-in/fan-out panel:
  // the data already sits per-node in the serialised IR (`core/plugins.lua`
  // extracts it during the scan, where the parse tree exists; this only
  // walks what is already JSON).
  //
  // Sorted by repo, ascending, by default — unlike every other panel here.
  // The others rank a health metric worst-first; this is an inventory, and
  // "what do I have installed" is read alphabetically, not by severity.
  // The lazy-load inventory: the Plugins panel's question, inverted.
  //
  // Plugins answers "what does this plugin load on"; every row already says
  // so. What it cannot answer without reading every row is the other
  // direction — *which* plugins load on `VeryLazy`, what typing `:Neogit`
  // actually costs, and what is paid for unconditionally at startup. That is
  // the question "why is this not loaded yet" is really asking, and it is a
  // different index over the same data rather than new data.
  //
  // No new Lua extraction: `core/plugins.lua` already stamps `event`, `cmd`,
  // `ft` and `keys` per spec during the scan. This walks the serialised IR,
  // the same way the fan-in panel does.
  function renderAnalysisLazy(){
    // trigger identity -> row. Keyed by kind *and* value: an `ft` named
    // `lua` and a `cmd` named `lua` would otherwise share a row and claim
    // each other's plugins.
    var byTrigger = {};
    var total = 0;

    function bucket(kind, value){
      var key = kind + "\u0000" + value;
      if(!byTrigger[key]){
        byTrigger[key] = { kind: kind, value: value, repos: [], seen: {} };
      }
      return byTrigger[key];
    }

    IR.nodes.forEach(function(n){
      (n.plugins || []).forEach(function(spec){
        total++;
        var load = pluginLoad(spec);
        // The two trigger-less states get a bucket of their own rather than
        // being left out. "What loads at startup" is the most expensive
        // answer on this panel, and a panel about load timing that omitted
        // it would be answering the easy half.
        if(load === "startup"){
          var st = bucket("startup", "");
          if(!st.seen[spec.repo]){ st.seen[spec.repo] = true; st.repos.push(spec.repo); }
          return;
        }
        if(load === "ondemand"){
          var od = bucket("ondemand", "");
          if(!od.seen[spec.repo]){ od.seen[spec.repo] = true; od.repos.push(spec.repo); }
          return;
        }
        ["event", "cmd", "ft", "keys"].forEach(function(kind){
          (spec[kind] || []).forEach(function(v){
            var b = bucket(kind, String(v));
            if(!b.seen[spec.repo]){ b.seen[spec.repo] = true; b.repos.push(spec.repo); }
          });
        });
      });
    });

    var rows = Object.keys(byTrigger).map(function(k){
      var b = byTrigger[k];
      b.repos.sort();
      return {
        kind: b.kind,
        value: b.value,
        label: b.kind === "startup" ? "at startup"
          : b.kind === "ondemand" ? "when required by something else"
          : b.kind + ": " + b.value,
        count: b.repos.length,
        repos: b.repos.join(", "),
        haystack: b.kind + " " + b.value + " " + b.repos.join(" "),
        sortkey: b.kind + "#" + b.value
      };
    });

    if(total === 0){
      return '<p class="ntext none">No lazy.nvim-shaped plugin spec found in this tree, ' +
        'so there is nothing to say about when anything loads. ' +
        'See <code>core/plugins.lua</code> for what is recognized.</p>';
    }

    var cols = [
      { label: "Loads", key: "label", get: function(r){ return r.label; }, initial: "asc" },
      { label: "Plugins", key: "count", get: function(r){ return r.count; }, initial: "desc" },
      { label: "Which", key: "repos", get: function(r){ return r.repos; }, initial: "asc" }
    ];

    var totalRows = rows.length;
    rows = anFilter(rows);
    // **Startup first, then the biggest groups**, unlike the alphabetical
    // Plugins inventory next door. This panel is read for cost: what is paid
    // unconditionally comes first, and after that a trigger carrying seven
    // plugins matters more than one carrying a single plugin. `ondemand`
    // sorts last because it is the one state that costs nothing until
    // something asks.
    var ORDER = { startup: 0, event: 1, ft: 2, cmd: 3, keys: 4, ondemand: 5 };
    anSort(rows, cols, function(a, b){
      if(ORDER[a.kind] !== ORDER[b.kind]) return ORDER[a.kind] - ORDER[b.kind];
      if(a.count !== b.count) return b.count - a.count;
      return a.value < b.value ? -1 : (a.value > b.value ? 1 : 0);
    });

    var startup = byTrigger["startup\u0000"];
    var nstartup = startup ? startup.repos.length : 0;

    var parts = [];
    parts.push('<p class="nsub">' + total + ' plugin spec entr' +
      (total === 1 ? 'y' : 'ies') + ' across ' + totalRows + ' distinct load point' +
      (totalRows === 1 ? '' : 's') + '. <strong>' + nstartup + '</strong> load' +
      (nstartup === 1 ? 's' : '') + ' at startup — everything else is deferred.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No load point matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr><td>' + esc(r.label) + '</td><td class="num">' + r.count +
        '</td><td class="dim">' + esc(r.repos) + '</td></tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisPlugins(){
    var rows = [];
    var seen = {};
    IR.nodes.forEach(function(n){
      (n.plugins || []).forEach(function(spec){
        seen[spec.repo] = (seen[spec.repo] || 0) + 1;
      });
    });
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.plugins || []).forEach(function(spec){
        var traits = pluginTraits(spec);
        rows.push({
          node: n, spec: spec, repo: spec.repo, traits: traits,
          dup: seen[spec.repo] > 1, name: name,
          haystack: spec.repo + " " + traits + " " + name,
          sortkey: spec.repo + "#" + n.id
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No lazy.nvim-shaped plugin spec found in this tree. ' +
        'See <code>core/plugins.lua</code> for what is recognized — packer.nvim and ' +
        'vim-plug specs look different and are not.</p>';
    }

    var totalRows = rows.length;
    var ndup = 0;
    Object.keys(seen).forEach(function(r){ if(seen[r] > 1) ndup++; });

    var cols = [
      { label: "Repo", key: "repo", get: function(r){ return r.repo; }, initial: "asc" },
      { label: "Triggers", key: "traits", get: function(r){ return r.traits; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.repo !== b.repo) return a.repo < b.repo ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' plugin spec entr' +
      (totalRows === 1 ? 'y' : 'ies') + '.' +
      (ndup > 0 ? ' <strong>' + ndup + '</strong> repo' + (ndup === 1 ? '' : 's') +
        ' declared more than once — in a config split across files, the last one ' +
        'lazy.nvim imports silently wins.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No spec matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.repo) + (r.dup ? ' <span class="anflag">⚠ duplicate</span>' : '') + '</td>' +
        '<td>' + esc(r.traits) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Keymaps / user commands / autocmds, straight off `n.bindings` — the same
  // JS-side-aggregation-only shape as the Plugins panel above: `core/
  // bindings.lua` did the extraction during the scan, where the parse tree
  // exists, and this only walks the serialised IR.
  //
  // Sorted by the identifying text (kind, then lhs/name/event) rather than
  // worst-first, for the reason `renderAnalysisPlugins` states — an
  // inventory is read alphabetically. That sort is also what makes
  // collisions visible: two rows for the same lhs land adjacent.
  function bindingLabel(b){
    if(b.kind === "keymap"){
      var modes = (b.modes || []).length ? b.modes.join("/") : "?";
      return "[" + modes + "] " + (b.lhs || "?");
    }
    if(b.kind === "usercmd") return ":" + (b.name || "?");
    return (b.events || []).join(",");
  }

  // Keymap collisions are per (mode, lhs); a user command's name is global.
  // Buffer-local registrations never collide — shadowing a global mapping
  // inside an ftplugin is the intended idiom, not a clash. Autocmds do not
  // collide at all: many handlers per event is the normal shape.
  // Built with fromCharCode rather than an escape: this whole script is a
  // Lua long string, so a literal control character here would be at the
  // mercy of any retab/whitespace pass that ever touches the file.
  var BSEP = String.fromCharCode(1);

  function bindingCollisionKey(b){
    if(b.kind === "keymap" && b.lhs && !b.buffer){
      var modes = (b.modes || []).length ? b.modes.join(",") : "?";
      return "keymap" + BSEP + modes + BSEP + b.lhs;
    }
    if(b.kind === "usercmd" && b.name) return "usercmd" + BSEP + b.name;
    return null;
  }

  function renderAnalysisBindings(){
    var rows = [];
    var seen = {};
    IR.nodes.forEach(function(n){
      (n.bindings || []).forEach(function(b){
        var key = bindingCollisionKey(b);
        if(key) seen[key] = (seen[key] || 0) + 1;
      });
    });
    var counts = { keymap: 0, usercmd: 0, autocmd: 0 };
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.bindings || []).forEach(function(b){
        var key = bindingCollisionKey(b);
        var label = bindingLabel(b);
        var desc = b.desc || "";
        counts[b.kind] = (counts[b.kind] || 0) + 1;
        var kindRank = b.kind === "keymap" ? "1" : (b.kind === "usercmd" ? "2" : "3");
        rows.push({
          node: n, kind: b.kind, label: label, desc: desc, name: name,
          via: b.callee, buffer: b.buffer === true,
          dup: key !== null && seen[key] > 1,
          haystack: label + " " + desc + " " + name + " " + b.callee,
          sortkey: kindRank + BSEP + label
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No keymap, user command or autocmd found. ' +
        'The <code>vim.*</code> APIs are always recognized; a config that binds ' +
        'through its own helper — <code>map(...)</code>, ' +
        '<code>usercmd.create(...)</code> — must declare it in ' +
        '<code>opts.bindings.wrappers</code>. See <code>core/bindings.lua</code>.</p>';
    }

    var totalRows = rows.length;
    var ndup = 0;
    Object.keys(seen).forEach(function(k){ if(seen[k] > 1) ndup++; });

    var cols = [
      { label: "Binding", key: "label", get: function(r){ return r.sortkey; }, initial: "asc" },
      { label: "Kind", key: "kind", get: function(r){ return r.kind; }, initial: "asc" },
      { label: "Description", key: "desc", get: function(r){ return r.desc; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.sortkey !== b.sortkey) return a.sortkey < b.sortkey ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + counts.keymap + ' keymap' +
      (counts.keymap === 1 ? '' : 's') + ', ' + counts.usercmd + ' command' +
      (counts.usercmd === 1 ? '' : 's') + ', ' + counts.autocmd + ' autocmd' +
      (counts.autocmd === 1 ? '' : 's') + '.' +
      (ndup > 0 ? ' <strong>' + ndup + '</strong> bound more than once — ' +
        'whichever module loads last silently wins.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No binding matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td><code>' + esc(r.label) + '</code>' +
        (r.dup ? ' <span class="anflag">⚠ duplicate</span>' : '') +
        (r.buffer ? ' <span class="anflag">buf</span>' : '') + '</td>' +
        '<td>' + esc(r.kind) + '</td>' +
        '<td>' + esc(r.desc || ("via " + r.via)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Call-based route registrations, straight off `n.endpoints` — JS-side
  // aggregation only, no new extraction: `core/endpoints.lua` already
  // recognizes these during the scan, the same shape `n.plugins` already
  // is. See that module's own header for what counts as a route
  // (Express/Fastify/Koa-shaped `app.get(path, handler)`) and what does
  // not — `docs/ecosystem.md` §3.1 puts file-based routing
  // (Next.js/SvelteKit/Nuxt/Remix) in a Hierarchy view instead, not here.
  //
  // Sorted by path, ascending, by default — the same reasoning
  // `renderAnalysisPlugins` gives for repo: an inventory ("what routes does
  // this codebase have"), not a ranked health metric.
  function renderAnalysisEndpoints(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      var fnByName = {};
      (n.functions || []).forEach(function(fn){ fnByName[fn.name] = fn; });
      (n.endpoints || []).forEach(function(spec){
        var handlerFn = spec.handler ? fnByName[spec.handler] : null;
        rows.push({
          node: n, spec: spec, method: spec.method.toUpperCase(),
          path: spec.path, handler: spec.handler || "(inline handler)",
          handlerFn: handlerFn, framework: spec.framework || "", name: name,
          documented: !!spec.documented, line: spec.line,
          haystack: spec.method + " " + spec.path + " " + (spec.handler || "") +
            " " + (spec.framework || "") + " " + name,
          sortkey: spec.path + "#" + spec.method
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No call-based route registration found in this ' +
        'tree. See <code>core/endpoints.lua</code> for what is recognized — file-based ' +
        'routing (Next.js and similar) is a separate, unbuilt concept, not this.</p>';
    }

    var totalRows = rows.length;
    var ndoc = 0;
    rows.forEach(function(r){ if(r.documented) ndoc++; });

    var cols = [
      { label: "Method", key: "method", get: function(r){ return r.method; }, initial: "asc" },
      { label: "Path", key: "path", get: function(r){ return r.path; }, initial: "asc" },
      { label: "Handler", key: "handler", get: function(r){ return r.handler; }, initial: "asc" },
      { label: "Framework", key: "framework", get: function(r){ return r.framework; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.path !== b.path) return a.path < b.path ? -1 : 1;
      return a.method < b.method ? -1 : (a.method > b.method ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' route' + (totalRows === 1 ? '' : 's') +
      ' found. <strong>' + ndoc + '</strong> of ' + totalRows +
      ' handler' + (totalRows === 1 ? '' : 's') + ' documented.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No route matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var handlerCell = esc(r.handler);
      if(r.handlerFn){
        handlerCell += sigTrigger(r.node.id, r.handlerFn.name) +
          docTrigger(fnKey(r.node.id, r.handlerFn.name));
      }
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.method) + '</td>' +
        '<td>' + esc(r.path) + '</td>' +
        '<td>' + handlerCell + '</td>' +
        '<td>' + esc(r.framework) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // React hooks, straight off `fn.is_hook` — JS-side aggregation only, no new
  // extraction: `core/lang/ecma.lua` already tags this per function at scan
  // time, the same shape as `n.plugins` above. A tree with no JS/TS backend
  // registered (this repository's own map, today) simply has no function
  // with the field set, which reads as "no hooks" rather than an error —
  // the panel does not need to know which languages exist.
  //
  // Sorted by name, ascending, by default — an inventory ("what hooks does
  // this codebase have"), not a ranked health metric, the same reasoning
  // `renderAnalysisPlugins` gives for sorting by repo instead of worst-first.
  function renderAnalysisHooks(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        if(!fn.is_hook) return;
        rows.push({
          node: n, fn: fn, name: fn.name, module: name,
          signature: fn.signature || fn.name, summary: fn.summary || "",
          line: fn.line,
          haystack: fn.name + " " + (fn.signature || "") + " " + name,
          sortkey: fn.name + "#" + n.id
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No function named like a React hook ' +
        '(<code>^use[A-Z]</code> — the same convention ' +
        '<code>eslint-plugin-react-hooks</code> itself relies on) was found. ' +
        'Only JavaScript/TypeScript/TSX files are checked for this — see ' +
        '<code>core/lang/ecma.lua</code>.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Hook", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Signature", key: "signature", get: function(r){ return r.signature; }, initial: "asc" },
      { label: "Declared in", key: "module", get: function(r){ return r.module; }, initial: "asc" },
      { label: "Line", key: "line", get: function(r){ return r.line; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.name !== b.name) return a.name < b.name ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' hook' + (totalRows === 1 ? '' : 's') +
      ' found by name.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No hook matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + esc(r.signature) + sigTrigger(r.node.id, r.fn.name) + '</td>' +
        '<td>' + esc(r.module) + '</td>' +
        '<td>' + r.line + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // A panel of one row per finding, straight off fields a backend set per
  // function, in the shape of `renderAnalysisHooks`. The empty state names the
  // language: a tree without it has none, which is not the same as "none used".
  function renderLanguageRows(rows, cols, words){
    if(rows.length === 0) return '<p class="ntext none">' + words.empty + '</p>';
    var totalRows = rows.length;
    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.name !== b.name) return a.name < b.name ? -1 : 1;
      if(a.node.id !== b.node.id) return a.node.id < b.node.id ? -1 : 1;
      return a.line - b.line;
    });
    var parts = [];
    parts.push('<p class="nsub">' + words.summary(totalRows) +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">Nothing matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var cells = cols.map(function(c){
        var text = c.get(r);
        var mark = c.key === "fname" ? sigTrigger(r.node.id, r.fn.name) : "";
        return '<td>' + esc(String(text)) + mark + '</td>';
      });
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' + cells.join("") + '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Python decorators, off `fn.decorators`: what a tree decorates with and where.
  // One row per use, with how often that name occurs: sorted by name the uses of
  // one decorator stand together, sorted by Uses the most common comes first.
  function renderAnalysisDecorators(){
    var rows = [], uses = {};
    IR.nodes.forEach(function(n){
      var module = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        (fn.decorators || []).forEach(function(d){
          uses[d] = (uses[d] || 0) + 1;
          rows.push({
            node: n, fn: fn, name: d, fname: fn.name, module: module, line: fn.line,
            haystack: d + " " + fn.name + " " + module
          });
        });
      });
    });
    rows.forEach(function(r){ r.uses = uses[r.name]; });
    return renderLanguageRows(rows, [
      { label: "Decorator", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Uses", key: "uses", get: function(r){ return r.uses; }, initial: "desc" },
      { label: "Function", key: "fname", get: function(r){ return r.fname; }, initial: "asc" },
      { label: "Declared in", key: "module", get: function(r){ return r.module; }, initial: "asc" },
      { label: "Line", key: "line", get: function(r){ return r.line; }, initial: "asc" }
    ], {
      empty: "No function with a decorator was found. Only Python files are " +
        "checked for this, so a tree without Python has none.",
      summary: function(total){
        return total + " use" + (total === 1 ? "" : "s") + " of " +
          Object.keys(uses).length + " decorator" + (Object.keys(uses).length === 1 ? "" : "s") + ".";
      }
    });
  }

  // Rust structure, off `fn.impl_trait`, `fn.is_unsafe` and `fn.unsafe_blocks`. It
  // answers two questions: which types implement which traits, and where `unsafe`
  // lives. A trait impl without a method (`impl Send for T {}`) is no row: the
  // field sits on the method, and the map records functions.
  function renderAnalysisRust(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var module = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        function row(kind, name, detail){
          rows.push({
            node: n, fn: fn, kind: kind, name: name, detail: detail, fname: fn.name,
            module: module, line: fn.line,
            haystack: kind + " " + name + " " + fn.name + " " + module
          });
        }
        if(fn.impl_trait) row("impl", fn.impl_trait + " for " + fn.owner, "");
        if(fn.is_unsafe) row("unsafe", "unsafe fn", "");
        if(fn.unsafe_blocks) row("unsafe", "unsafe block",
          fn.unsafe_blocks + " block" + (fn.unsafe_blocks === 1 ? "" : "s"));
      });
    });
    return renderLanguageRows(rows, [
      { label: "Kind", key: "kind", get: function(r){ return r.kind; }, initial: "asc" },
      { label: "What", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Function", key: "fname", get: function(r){ return r.fname; }, initial: "asc" },
      { label: "Detail", key: "detail", get: function(r){ return r.detail; }, initial: "asc" },
      { label: "Declared in", key: "module", get: function(r){ return r.module; }, initial: "asc" },
      { label: "Line", key: "line", get: function(r){ return r.line; }, initial: "asc" }
    ], {
      empty: "No trait implementation and no <code>unsafe</code> was found. Only " +
        "Rust files are checked for this, so a tree without Rust has none.",
      summary: function(total){
        var impl = rows.filter(function(r){ return r.kind === "impl"; }).length;
        return impl + " trait method" + (impl === 1 ? "" : "s") + ", " +
          (total - impl) + " place" + (total - impl === 1 ? "" : "s") + " with <code>unsafe</code>.";
      }
    });
  }

  // The documentation corpus itself (`ir.docs.files`) — every `.md` file
  // `core/docs.lua` scanned, with how many code-span mentions it made.
  // ecosystem.md §3.4 calls this "cheap, once the corpus scan exists": no
  // new extraction, just the same `anFilter`/`anSort`/`anHead` plumbing
  // every other panel already uses, over data `docs.lua` already collected.
  //
  // Rows carry no `data-node` and are not `.anrow`-classed: a doc file is
  // not a `Docmap.Node`, so there is nowhere in the Tree tab for a
  // click to land — giving these rows the hover/click affordance every
  // other panel's clickable rows have would be a false promise. Where a
  // reference actually resolves to a function or module is the marker
  // beside that entity (`sigTrigger`/the docs-reference popup), not this
  // overview.
  //
  // `doc-references-missing` (`ir.docs.missing`) is deliberately not
  // repeated here — it is already a `check.lua` finding, in the Notes tab,
  // and belongs to "what is wrong" rather than "what documentation exists".
  function renderAnalysisDocs(){
    var files = (IR.docs && IR.docs.files) || [];

    if(files.length === 0){
      return '<p class="ntext none">No <code>.md</code> file was found under this ' +
        'tree (see <code>core/docs.lua</code> for what counts as the corpus), or this ' +
        'map was generated before the docs corpus scan existed.</p>';
    }

    var rows = files.map(function(f){
      return {
        path: f.path, title: f.title || f.path, refs: f.refs || 0,
        haystack: f.path + " " + (f.title || ""), sortkey: f.path
      };
    });
    var totalRows = rows.length;
    var totalRefs = 0;
    rows.forEach(function(r){ totalRefs += r.refs; });

    var cols = [
      { label: "Path", key: "path", get: function(r){ return r.path; }, initial: "asc" },
      { label: "Title", key: "title", get: function(r){ return r.title; }, initial: "asc" },
      { label: "References", key: "refs", get: function(r){ return r.refs; }, initial: "desc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' documentation file' +
      (totalRows === 1 ? '' : 's') + ', ' + totalRefs + ' code-span reference' +
      (totalRefs === 1 ? '' : 's') + ' resolved in total.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No file matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr>' +
        '<td>' + esc(r.path) + '</td>' +
        '<td>' + esc(r.title) + '</td>' +
        '<td>' + r.refs + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // This repo's own `lib.nvim.deps` manifest — `IR.tools`, a repo-level
  // object rather than a per-node array (there is exactly one
  // docs/install.json or docs/INSTALL.md per repo, not one per file), same
  // shape `IR.docs`/`IR.duplicates` already are. Declared tools only: never
  // a live "is this installed on my machine" check, which a static page
  // read on GitHub Pages has no host to ask anyway — see `core/tools.lua`'s
  // header for why that stays out of the artifact entirely, not just this
  // panel.
  function renderAnalysisTools(){
    var spec = IR.tools;
    var tools = (spec && spec.tools) || [];
    var errors = (spec && spec.errors) || [];

    if(!spec){
      return '<p class="ntext none">No <code>docs/install.json</code> or ' +
        '<code>docs/INSTALL.md</code> found in this repo (or lib.nvim.deps was not ' +
        'available when this map was generated) — see <code>core/tools.lua</code>, or ' +
        'lib.nvim\'s <code>:help lib.nvim-deps-declaring</code>.</p>';
    }
    if(tools.length === 0 && errors.length === 0){
      return '<p class="ntext none">' + esc(spec.source) + ' declares no tools.</p>';
    }

    var rows = tools.map(function(t){
      var pkgs = Object.keys(t.pkg || {}).sort();
      return {
        bin: t.bin, required: !!t.required, why: t.why, pkg: pkgs.join(", "),
        haystack: t.bin + " " + t.why + " " + pkgs.join(" "), sortkey: t.bin
      };
    });
    var totalRows = rows.length;
    var nrequired = 0;
    rows.forEach(function(r){ if(r.required) nrequired++; });

    var cols = [
      { label: "Tool", key: "bin", get: function(r){ return r.bin; }, initial: "asc" },
      { label: "Required", key: "required", get: function(r){ return r.required ? 1 : 0; }, initial: "desc" },
      { label: "Why", key: "why", get: function(r){ return r.why; }, initial: "asc" },
      { label: "Packages", key: "pkg", get: function(r){ return r.pkg; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      return a.bin < b.bin ? -1 : (a.bin > b.bin ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' tool' + (totalRows === 1 ? '' : 's') +
      ' declared in ' + esc(spec.source) + ', ' + nrequired + ' required.' +
      (errors.length > 0 ? ' <strong>' + errors.length + '</strong> invalid entr' +
        (errors.length === 1 ? 'y' : 'ies') + ' — see the drift findings below.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No tool matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr>' +
        '<td><code>' + esc(r.bin) + '</code></td>' +
        '<td>' + (r.required ? 'required' : 'optional') + '</td>' +
        '<td>' + esc(r.why) + '</td>' +
        '<td>' + esc(r.pkg) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Rendered panels, memoised per *rendering* rather than per panel.
  //
  // One variable per panel was correct while a panel had exactly one
  // rendering. Sorting and filtering give it many, so the key carries them —
  // otherwise clicking a column re-serves the previous order out of the cache
  // and the header arrow moves while the rows do not.
  //
  // Unbounded on purpose: the key space is (9 panels x ~4 columns x 2
  // directions x the queries actually typed), every entry is a string already
  // built once, and the alternative — evicting — would re-render on a Back
  // button press, which is the one moment the cache exists for.
  var analysisCache = {};

  function anCacheKey(atool){
    return atool + "|" + (state.asort || "") + "|" + (state.adir || "") + "|" + (state.q || "") +
      "|" + dupView;
  }

  ///Render one panel from scratch. Sort and filter come from `state`.
  function renderAnalysis(atool){
    if(atool === "test"){
      return renderAnalysisPanel(
        "Tested",
        "A function counts as tested when its bare name is found somewhere " +
        "under the configured tests directory — see docmap's coverage.lua " +
        "for what that heuristic can and cannot see.",
        function(fn){ return !!fn.tested; },
        false
      );
    }
    if(atool === "doc"){
      return renderAnalysisPanel(
        "Documented",
        "A function counts as documented when it has a summary and its " +
        "parameters are fully and correctly named — @internal functions " +
        "are excluded entirely, not counted as undocumented.",
        function(fn){ return !!fn.documented; },
        true
      );
    }
    if(atool === "annotations") return renderAnalysisAnnotations();
    if(atool === "api") return renderAnalysisApi();
    if(atool === "deps") return renderAnalysisDeps();
    if(atool === "complexity") return renderAnalysisComplexity();
    if(atool === "duplicates") return renderAnalysisDuplicates();
    if(atool === "hooks") return renderAnalysisHooks();
    if(atool === "decorators") return renderAnalysisDecorators();
    if(atool === "rust") return renderAnalysisRust();
    if(atool === "lazy") return renderAnalysisLazy();
    if(atool === "docs") return renderAnalysisDocs();
    if(atool === "endpoints") return renderAnalysisEndpoints();
    if(atool === "tools") return renderAnalysisTools();
    if(atool === "bindings") return renderAnalysisBindings();
    return renderAnalysisPlugins();
  }

  function drawAnalysis(){
    var atool = (state.atool === "doc" || state.atool === "deps" ||
      state.atool === "complexity" || state.atool === "duplicates" ||
      state.atool === "plugins" || state.atool === "lazy" ||
      state.atool === "tools" || state.atool === "hooks" ||
      state.atool === "decorators" || state.atool === "rust" ||
      state.atool === "docs" || state.atool === "endpoints" || state.atool === "telemetry" ||
      state.atool === "loaded" || state.atool === "checklist" ||
      state.atool === "api" || state.atool === "annotations" ||
      state.atool === "startup" ||
      state.atool === "bindings")
      ? state.atool : "test";

    document.querySelectorAll("#antoggle .anview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.atool === atool);
    });

    // Telemetry/Loaded are not computed from the embedded IR and cannot
    // be — see each draw function's own header for why. They get a
    // separate path rather than a branch inside `renderAnalysis`, the
    // same reason History is a sibling of this whole function rather than
    // a case in it: the cache below is for synchronous, IR-only renders,
    // and a fetch does not fit that shape.
    if(atool === "telemetry"){
      drawAnalysisTelemetry();
      return;
    }
    if(atool === "loaded"){
      drawAnalysisLoaded();
      return;
    }
    // Unlike Telemetry and Loaded above, this one is not fetch-*dependent*:
    // the ledger is baked into the page and renders completely from
    // `IR.checklist`. The fetch only adds the staleness verdict, so the
    // panel is fully useful from `file://` and merely gains a column under
    // `:DocMap serve`. It still takes the separate path rather than a case
    // in `renderAnalysis`, for the same reason those two do — the cache
    // below is for synchronous renders, and an enrichment that arrives
    // later does not fit it.
    if(atool === "checklist"){
      drawAnalysisChecklist();
      return;
    }
    // Baked in like Checklist, not fetched like the two above it — see
    // `core/startup_graph.lua` for why startup attribution is the one
    // runtime measurement that belongs in a committed artifact. Its own
    // path for a third reason on top of theirs: it inserts a *node* rather
    // than a string, and the cache stores strings.
    if(atool === "startup"){
      drawAnalysisStartup();
      return;
    }

    var host = document.getElementById("anbody");
    var key = anCacheKey(atool);
    if(analysisCache[key] === undefined) analysisCache[key] = renderAnalysis(atool);
    host.innerHTML = analysisCache[key];

    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });

    host.querySelectorAll(".dupview-btn").forEach(function(b){
      b.addEventListener("click", function(){
        dupView = b.dataset.dupview;
        drawAnalysis();
      });
    });

    // Sortable headers. Clicking the active column flips direction; clicking a
    // new one starts at that column's natural direction — descending for a
    // number (largest first is what a ranking means), ascending for a name.
    host.querySelectorAll("th.ansort").forEach(function(th){
      th.addEventListener("click", function(){
        var key2 = th.dataset.sort;
        var dir;
        if(state.asort === key2){
          dir = state.adir === "asc" ? "desc" : "asc";
        } else {
          dir = th.dataset.initial === "asc" ? "asc" : "desc";
        }
        navigate({ tab: "analysis", atool: atool, asort: key2, adir: dir });
      });
    });
  }

]]
