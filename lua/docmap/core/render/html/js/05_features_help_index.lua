---@module 'docmap.core.render.html.js.05_features_help_index'
--- A slice of the page's script: Features tab, promoted features, hover help, second level, Index tab.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Features tab: this repo's own docs/FEATURES/, read by
  // core/features.lua — see docs/features_format.md for the format.
  //
  // An index, not a Markdown viewer, the same shape the Plugins/Tools
  // Analysis panels already are: name, summary, metadata — never the full
  // prose that may follow a feature's bullets in its own file. That prose
  // stays exactly where the author put it; the card's own path links out to
  // it instead of re-rendering it here.
  //
  // A plain key/value list, not a table, because the metadata keys are not
  // fixed columns — one feature may carry Module/Keymaps/Config, another
  // Module/Command/Autocmd, and `docs/features_format.md` deliberately
  // never constrains the vocabulary (see that file's own header for why a
  // whitelist would reject real, working documentation).
  // =====================================================================

  // One line per bullet's first backtick-quoted token, matched against
  // every node's own `source`/`path` — the same "endswith" leniency
  // `tag_links` resolution already extends to stale cross-references
  // elsewhere on this page. `null` when nothing in `meta` names a `Module`
  // bullet, or nothing in the tree matches it; never thrown.
  //
  // The fallback only: `core/features.lua` resolves the same bullet while it
  // builds the reverse index and leaves the answer on the entry (`node`),
  // module names included. This runs for an entry that has none.
  function resolveModuleNode(meta){
    var mod = null;
    meta.forEach(function(m){
      if(!mod && /^module$/i.test(m.key)) mod = m.value;
    });
    if(!mod) return null;
    var token = (mod.match(/`([^`]+)`/) || [])[1];
    if(!token) return null;
    token = token.replace(/\\/g, "/");
    var found = null;
    IR.nodes.forEach(function(n){
      if(found) return;
      var p = (n.source || n.path || "").replace(/\\/g, "/");
      if(p && (p === token || p.slice(-token.length) === token)) found = n.id;
    });
    return found;
  }

  // A theme filename as the tab's own heading: an already-uppercase name
  // (`UI`, `PERFORMANCE`) is left alone but for its separators, since
  // title-casing it would just be re-uppercasing what is already upper;
  // anything else (`headings`, `editing-and-handlers`) is title-cased.
  function themeTitle(theme){
    var spaced = theme.replace(/[_-]+/g, " ");
    if(/^[A-Z0-9 ]+$/.test(spaced)) return spaced;
    return spaced.replace(/\b\w/g, function(c){ return c.toUpperCase(); });
  }

  // ---------------------------------------------------------------------
  // One sub-tab per theme file. The reader's order is the parser's
  // (`core.md` first, `FEATURES.md` second, the rest by name), so the first
  // file is the default: what the plugin exists for, before the overview.
  // A repository with one feature file gets no strip at all.
  //
  // The strip is the Analysis tab's toolbar (`.hview-toggle` holding
  // `.anview-btn`), the pattern this page already has for "several panels,
  // one tab". It is not the second-level tab strip: that one lists the
  // features promoted to a tab of their own (`Tab: true`), which is a
  // different question. See docs/features_format.md.
  // ---------------------------------------------------------------------

  // The theme a state shows: the one it names when that file exists, else
  // the first. A link to a theme that was renamed opens the default rather
  // than an empty tab.
  function featureTheme(s){
    var files = (IR.features && IR.features.files) || [];
    if(!files.length) return null;
    var want = s && s.ftheme;
    for(var i = 0; i < files.length; i++){
      if(files[i].theme === want) return want;
    }
    return files[0].theme;
  }

  function visibleFeatureCount(f){
    var n = 0;
    f.entries.forEach(function(e){ if(!e.tab) n++; });
    return n;
  }

  // What the line above the catalogue says. With one theme on screen the
  // total alone would describe cards the reader cannot see.
  function featureCountLine(feats, theme){
    var total = 0, shown = 0;
    feats.files.forEach(function(f){
      var n = visibleFeatureCount(f);
      total += n;
      if(f.theme === theme) shown = n;
    });
    var where = ' in <code>' + esc(feats.folder) + '</code>.';
    if(feats.files.length < 2){
      return total + ' feature' + (total === 1 ? '' : 's') + ' across 1 file' + where;
    }
    return esc(themeTitle(theme)) + ': ' + shown + ' of ' + total + ' feature' +
      (total === 1 ? '' : 's') + ' across ' + feats.files.length + ' files' + where;
  }

  // A card to scroll to once the tab is drawn: set by the feature popup,
  // which knows the card and not whether the tab exists yet.
  var pendingFeatureCard;

  // Show one theme, light its button, say what is shown. Runs on every
  // navigation; `drawFeatures` builds the DOM once and this only toggles it.
  function syncFeatureTheme(s){
    var host = document.getElementById("view-features");
    var feats = IR.features;
    if(!feats || !feats.files.length) return;
    var theme = featureTheme(s);
    host.querySelectorAll(".feat-group").forEach(function(g){
      g.hidden = g.dataset.ftheme !== theme;
    });
    host.querySelectorAll("#feattoggle .anview-btn").forEach(function(b){
      var on = b.dataset.ftheme === theme;
      b.classList.toggle("active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    });
    var line = host.querySelector(".feat-count");
    if(line) line.innerHTML = featureCountLine(feats, theme);

    if(pendingFeatureCard){
      var card = host.querySelector('.feat-card[data-feat-card="' +
        CSS.escape(pendingFeatureCard) + '"]');
      pendingFeatureCard = null;
      if(card){
        card.scrollIntoView({ block: "center" });
        card.classList.add("feat-flash");
        setTimeout(function(){ card.classList.remove("feat-flash"); }, 1600);
      }
    }
  }

  var featuresDrawn = false;
  function drawFeatures(){
    if(featuresDrawn){ syncFeatureTheme(state); return; } // static over one IR
    featuresDrawn = true;

    var host = document.getElementById("view-features");
    var feats = IR.features;
    var parts = ['<div class="feat-wrap">'];

    if(!feats){
      parts.push('<p class="ntext none">No <code>docs/FEATURES/</code> (or ' +
        '<code>docs/features/</code>) folder in this repo — see ' +
        '<code>docs/features_format.md</code> for the convention this tab reads.</p>');
      parts.push("</div>");
      host.innerHTML = parts.join("");
      return;
    }

    // The strip first: it is the navigation of this tab, and a folder intro
    // of a screen's length would otherwise push it out of sight.
    if(feats.files.length > 1){
      parts.push('<div class="hview-toggle feat-themes" id="feattoggle" role="tablist" ' +
        'aria-label="Feature themes">');
      feats.files.forEach(function(f){
        parts.push('<button class="anview-btn" role="tab" data-ftheme="' + esc(f.theme) +
          '" data-explain="feat.theme">' + esc(themeTitle(f.theme)) +
          '<span class="ncount">' + visibleFeatureCount(f) + '</span></button>');
      });
      parts.push('</div>');
    }

    if(feats.intro){
      // Through the same Markdown-subset renderer a promoted feature's body
      // uses, not `esc`. This text is the top of somebody's FEATURES.md and
      // is written as Markdown — escaping it printed `#`, `**` and
      // `[text](url)` literally and ran every heading, list and paragraph
      // together into one wall, which is what the folder's own intro looked
      // like in every generated map until now.
      parts.push('<div class="feat-intro">' + renderFeatureBody(feats.intro) + '</div>');
    }

    // A `Tab: true` feature has its own top-level tab (see
    // collectPromotedFeatures/drawFeatureTab below) and is left out of this
    // catalog entirely, counts included — showing it as both a card here
    // and a tab of its own would be the same feature listed twice for no
    // reason, and the whole point of promoting one is that it no longer
    // needs the card.
    parts.push('<p class="nsub feat-count"></p>');

    feats.files.forEach(function(f){
      var visible = f.entries.filter(function(e){ return !e.tab; });
      parts.push('<section class="feat-group" data-ftheme="' + esc(f.theme) + '">');
      parts.push('<h3 class="nhead">' + esc(themeTitle(f.theme)) +
        '<span class="ncount">' + visible.length + '</span></h3>');
      if(f.intro){
        // Same reason as the folder intro above: a file's own preamble is
        // Markdown too.
        parts.push('<div class="nsub feat-fileintro">' + renderFeatureBody(f.intro) + '</div>');
      }
      if(f.entries.length === 0){
        parts.push('<p class="ntext none">No <code>##</code> sections in this file.</p>');
        parts.push('</section>');
        return;
      }
      if(visible.length === 0){
        parts.push('<p class="ntext none">Every feature in this file is promoted to its ' +
          'own tab — see the tab bar.</p>');
        parts.push('</section>');
        return;
      }
      visible.forEach(function(e){
        var nodeId = e.node || resolveModuleNode(e.meta);
        parts.push('<div class="feat-card" data-feat-card="' + esc(featureKey(f.path, e.line)) + '">');
        parts.push('<div class="feat-name"' +
          (nodeId ? ' data-node="' + esc(nodeId) + '" tabindex="0" role="button"' : '') +
          '>' + esc(e.name) + '</div>');
        if(e.summary){
          parts.push('<div class="feat-summary">' + prose(e.summary) + '</div>');
        }
        if(e.meta.length){
          parts.push('<div class="feat-meta">');
          e.meta.forEach(function(m){
            parts.push('<div class="feat-meta-row"><b>' + esc(m.key) + ':</b> <span>' +
              esc(m.value) + '</span></div>');
          });
          parts.push("</div>");
        }
        parts.push('<div class="feat-src"><a href="#" data-src="' + esc(f.path) + '">' +
          esc(f.path) + ':' + e.line + '</a></div>');
        parts.push("</div>");
      });
      parts.push('</section>');
    });

    parts.push("</div>");
    host.innerHTML = parts.join("");

    host.querySelectorAll("#feattoggle .anview-btn").forEach(function(b){
      b.addEventListener("click", function(){
        navigate({ tab: "features", ftheme: b.dataset.ftheme });
      });
    });
    host.querySelectorAll(".feat-name[data-node]").forEach(function(el){
      el.addEventListener("click", function(){
        navigate({ tab: "tree", id: el.dataset.node });
      });
    });
    host.querySelectorAll(".feat-src a[data-src]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var u = srcUrl(a.dataset.src);
        window.open(u || rel(a.dataset.src), u ? "_blank" : "_self");
      });
    });
    syncFeatureTheme(state);
  }

  // =====================================================================
  // The way back: from a module or a function to the features that name it.
  //
  // `IR.features.refs` is the `Module:` bullets read backwards (built by
  // `core/features.lua`, keyed like the prose references: a node id, or
  // `nodeId#fnName`). One trigger, in one place: beside the module path and
  // beside each function in the Tree tab's detail pane, next to the prose
  // reference trigger it mirrors. Rendered only where a feature names the
  // thing, so its presence is the information.
  //
  // The card is the annotation popup (`sigOpen` in the popups slice): one
  // floating thing on the page, one set of rules for closing it.
  // =====================================================================

  function featureKey(path, line){ return path + ":" + line; }

  // `path:line` -> { entry, file }, built on first use. No initializer: this
  // slice's body runs after the boot sequence has already drawn a detail
  // pane, and an assignment here would throw the table away again.
  var featureByKey;
  function featureAt(path, line){
    if(!featureByKey){
      featureByKey = {};
      ((IR.features && IR.features.files) || []).forEach(function(f){
        f.entries.forEach(function(e){
          featureByKey[featureKey(f.path, e.line)] = { entry: e, file: f };
        });
      });
    }
    var key = featureKey(path, line);
    return Object.prototype.hasOwnProperty.call(featureByKey, key) ? featureByKey[key] : null;
  }

  function featureRefs(key){
    var refs = IR.features && IR.features.refs;
    if(!refs || !Object.prototype.hasOwnProperty.call(refs, key)) return [];
    return refs[key].filter(function(r){ return featureAt(r.file, r.line); });
  }

  function featTrigger(key){
    var n = featureRefs(key).length;
    if(!n) return "";
    return '<span class="feati" tabindex="0" role="button" data-feat="' + esc(key) +
      '" aria-label="Described by ' + n + ' feature' + (n === 1 ? '' : 's') +
      '" title="Features that describe this">&#9670;' +
      (n > 1 ? '<span class="docn">' + n + '</span>' : '') + '</span>';
  }

  function featRefsHTML(key){
    var refs = featureRefs(key);
    var h = ['<div class="fn-sig">Described by<span class="fn-badges">' +
      '<span class="bd">' + refs.length + ' feature' + (refs.length === 1 ? '' : 's') +
      '</span></span></div>'];
    refs.forEach(function(r){
      var hit = featureAt(r.file, r.line);
      h.push('<div class="docref featref">' +
        '<div class="docref-where"><a href="#" data-feat-goto="' +
        esc(featureKey(r.file, r.line)) + '">' + esc(hit.entry.name) + '</a>' +
        '<span class="bd">' + esc(themeTitle(hit.file.theme)) + '</span></div>' +
        (hit.entry.summary
          ? '<div class="docref-ctx">' + prose(hit.entry.summary) + '</div>' : '') +
        '</div>');
    });
    h.push('<div class="fn-desc fn-see"><a href="#" data-feat-goto="">' +
      'All features ↳</a></div>');
    return h.join("");
  }

  // To the feature itself: its own tab when it is promoted, else its card in
  // the catalogue, with the right theme showing. An empty key is the plain
  // "open the Features tab" link at the foot of the card.
  function gotoFeature(key){
    if(!key){ navigate({ tab: "features" }); return; }
    var cut = key.lastIndexOf(":");
    var hit = featureAt(key.slice(0, cut), key.slice(cut + 1));
    if(!hit) return;
    if(hit.entry.tab){
      var promoted = collectPromotedFeatures().filter(function(p){
        return p.entry === hit.entry;
      })[0];
      if(promoted){ navigate({ tab: promoted.slug }); return; }
    }
    pendingFeatureCard = key;
    navigate({ tab: "features", ftheme: hit.file.theme });
  }

  document.addEventListener("click", function(ev){
    var a = ev.target.closest && ev.target.closest("[data-feat-goto]");
    if(!a) return;
    ev.preventDefault();
    sigClose();
    gotoFeature(a.dataset.featGoto);
  });

  // =====================================================================
  // Promoted features: a `- **Tab:** true` bullet gets a feature its own
  // top-level tab instead of a card in the Features catalog above — see
  // docs/features_format.md "Promoting a feature to its own tab".
  // =====================================================================

  // Slugified once and cached, not recomputed per navigation: the tab
  // bar/view panels are built once at page load (buildPromotedTabs, called
  // from the boot sequence below), and every later lookup (applyState,
  // click handlers) needs the exact same slug that build produced.
  function featureSlug(name){
    return "feature-" + name.toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  // A tab label is a fixed, scarce surface — nine of them share one row —
  // and a promoted feature's name is a *heading*, written to be read in a
  // document. `The \`:Cmdlog <subcommand>\` command tree` is a good heading
  // and an unreadable tab: it crowds every other tab off the row and is
  // still too long to scan.
  //
  // Shortened rather than truncated where the name says how. A heading of
  // the form "The X …" is about X, and the backticked term in it is the
  // thing being named — so `:Cmdlog` survives and the sentence around it
  // does not. Only then does a hard cap apply, and the full name is always
  // in the tooltip.
  //
  // Deliberately not solved by asking authors to write shorter headings:
  // this page does not get to dictate how someone's FEATURES.md reads, and
  // a layout that only works for cooperative input is not a layout.
  function tabLabel(name){
    // Declared inside, not beside: `buildPromotedTabs` runs during boot,
    // which is before this point in the script body executes. A `var` at
    // file scope would be hoisted but still unassigned, and
    // `slice(0, undefined)` returns the whole string — so every label came
    // out full-length with an ellipsis glued on, which is the one outcome
    // worse than not shortening at all.
    var TAB_LABEL_MAX = 22;
    var s = String(name || "").trim();

    // A backticked term is the author naming the thing themselves; prefer it
    // over any guess this code could make.
    var quoted = s.match(/`([^`]+)`/);
    if(quoted && quoted[1].length <= TAB_LABEL_MAX) return quoted[1];

    s = s.replace(/^(The|A|An)\s+/i, "");
    if(s.length <= TAB_LABEL_MAX) return s;

    // Cut on a word boundary rather than mid-word: a label ending in "com…"
    // reads as broken, one ending in "command…" reads as shortened.
    var cut = s.slice(0, TAB_LABEL_MAX);
    var space = cut.lastIndexOf(" ");
    if(space > TAB_LABEL_MAX / 2) cut = cut.slice(0, space);
    return cut.replace(/[\s\-–—:,.]+$/, "") + "…";
  }

  // =====================================================================
  // "What is this?" — hover explanations for the page's own furniture
  //
  // Every tab, every mode inside one, and the findings disclosure says what
  // it *does* rather than repeating its label. A card that restates the
  // heading costs a hover and teaches nothing, so each text below is written
  // from what that view computes.
  //
  // One card, one attribute: anything carrying `data-explain` gets it. The
  // texts live in `EXPLAIN` keyed by the same value, in this file rather
  // than in the markup, because several of them are two sentences and
  // markup with prose in its attributes is markup nobody edits twice.
  //
  // **On the worry that a section means different things in different
  // tabs**: it was raised about "Drift findings", and that one turns out to
  // be a single element at the foot of the page shared by every tab — so
  // there is nothing to disambiguate there. Where a repeated heading *does*
  // mean different things, the key is what distinguishes them, not the
  // label: `index.functions` and `hierarchy.calls` are separate entries even
  // though both could be titled "functions".
  //
  // Reuses `.sigpop`'s styling the way the keyword card already does. A
  // third floating component with its own rules would be a third set of
  // rules to keep in step for no gain.
  // =====================================================================
  var EXPLAIN = {
    // ── The six graphs inside Hierarchy ──────────────────────────────
    //
    // Added because the outer tab explains the *tab* and each of these
    // computes something different from the same IR. Six of the controls
    // below used to carry a plain `title` instead, which this mechanism's
    // own `focusin` handler already argues against: a `title` never appears
    // on focus, so it left exactly the controls a keyboard user reaches as
    // the only ones with no explanation.
    "view.tree":
      "The same directory hierarchy as Modules, as a list you fold: a " +
      "level is a column of rows instead of a row of boxes, so a level with " +
      "two hundred modules stays readable. The filter keeps every match and " +
      "the path to it.",
    "view.treemap":
      "Everything under the center as nested areas, sized by lines of code " +
      "(or functions): where the weight of a wide level sits, at a glance. " +
      "Click to zoom in.",
    "view.coupling":
      "Every module as a dot: how many modules it requires across, how many " +
      "require it up. The corners have names (hubs, tangles, pass-throughs, " +
      "leaves) and say what would be expensive to change.",
    "hier.tint":
      "Tints the Modules boxes by one measure of everything below each box: " +
      "the share of functions that are documented or tested, or how many FIX " +
      "or TODO/HACK/PERF markers there are per 1,000 lines. A stronger tint means " +
      "look here first. The value is printed on each box and the legend names the steps.",
    "view.modules":
      "The directory hierarchy itself — every module and namespace, nested " +
      "the way the tree is. The one view with no direction, because " +
      "containment has none; the slider hides the top N levels instead.",
    "view.deps":
      "The require graph: an arrow means this module requires that one. " +
      "`+ external` adds the modules outside this map, each box naming the " +
      "functions actually called through it.",
    "view.calls":
      "Function-level callers and callees, resolved from real call sites " +
      "rather than guessed. A weak match is drawn dimmed rather than " +
      "hidden — see the Findings tab for what could not be resolved.",
    "view.modulecalls":
      "The same call graph collapsed module to module, with each edge " +
      "weighted by how many calls it carries. Answers which modules lean on " +
      "each other, where Calls answers which functions do.",
    "view.types":
      "How `@class` and `@alias` declarations reference each other through " +
      "their fields. Needs LuaLS enrichment (`:DocMap full`) — without it " +
      "this is empty rather than wrong.",
    "view.inheritance":
      "Only `@class Child : Parent` edges, drawn apart from Types because " +
      "inheritance is a different claim than collaboration and reading both " +
      "in one picture hides which is which.",

    // ── The tools inside Analysis ────────────────────────────────────
    //
    // Written from what each panel computes, per this table's own rule.
    // The `.plugin-gated` ones say what they need, because an empty panel
    // that cannot say why is the failure this whole card exists against.
    "atool.test":
      "Which functions a test suite mentions by name, per module, worst " +
      "first. A floor rather than a verdict: a name found under the tests " +
      "directory counts, and a function exercised only indirectly does not.",
    "atool.doc":
      "Which functions carry a summary and fully documented parameters, per " +
      "module, worst first. `@internal` functions are excluded — this is a " +
      "question about the published surface, not about helpers.",
    "atool.annotations":
      "Which annotation tags this tree actually uses, counted per function. " +
      "Generated, so unlike a hand-written inventory it cannot go stale.",
    "atool.api":
      "Every function this tree publishes, with its documentation state and " +
      "how many other modules here call it — the question asked every time a " +
      "module is extracted into its own plugin.",
    "atool.deps":
      "Fan-in and fan-out per module: how many modules it requires, and how " +
      "many require it. The second number is the one that decides how " +
      "expensive a rename is.",
    "atool.complexity":
      "Cyclomatic complexity per function, counted over its own subtree " +
      "including nested closures. A ranking of where the branching is, not " +
      "a threshold anything fails.",
    "atool.duplicates":
      "Functions whose parse-tree *shape* is identical, ignoring names and " +
      "literals — the one kind of drift the require graph cannot see, since " +
      "two modules that each grew their own `read(path)` do not require " +
      "each other.",
    "atool.lazy":
      "The Plugins question inverted: which plugins load on each event, " +
      "filetype, command and key, and which are paid for at startup " +
      "regardless. Answers what typing a command actually costs, and why " +
      "something is not loaded yet.",
    "atool.plugins":
      "Every lazy.nvim-shaped plugin spec in the tree. Matters when this is " +
      "pointed at a Neovim *config* rather than a plugin, where most files " +
      "are specs with no function in them and are invisible to every other " +
      "panel.",
    "atool.bindings":
      "Keymaps, user commands and autocommands registered in this tree. The " +
      "`vim.*` APIs are recognised unconditionally; a config binding through " +
      "its own wrapper needs `opts.bindings.wrappers` to declare it.",
    "atool.tools":
      "The CLI tools this repository declares it wants, from its own " +
      "`docs/install.json`. Declared only — a static page has no host to ask " +
      "whether any of them is installed here.",
    "atool.telemetry":
      "Call counts collected by runtime-analysis.nvim inside a real Neovim " +
      "session, joined onto this map. Needs `:DocMap serve`: counts change " +
      "between runs, so they are never baked into the committed page.",
    "atool.loaded":
      "A loaded-versus-declared comparison from a saved runtime-analysis " +
      "snapshot. Needs `:DocMap serve` and a named snapshot — the difference " +
      "is a property of one live session, never of a live aggregate.",
    "atool.startup":
      "Where startup time went, as a flamegraph: width is total time, depth " +
      "is require nesting. Measured by runtime-analysis.nvim and written by " +
      "`:RATelemetry flamegraph`, then baked into this page — unlike " +
      "Telemetry and Loaded it needs no `:DocMap serve`, because startup " +
      "happens once per session rather than accumulating.",
    "atool.checklist":
      "Hand-verified facts, each cited to the file it was read off. The " +
      "ledger is baked into this page; the changed-since-verified verdict " +
      "needs git, so it fills in under `:DocMap serve`.",
    "atool.hooks":
      "Functions named like a React hook (`^use[A-Z]`, the convention " +
      "eslint-plugin-react-hooks itself relies on). Only JavaScript, " +
      "TypeScript and TSX files are checked for this.",
    "atool.decorators":
      "Which decorators a Python tree uses, how often, and on which functions. " +
      "Only Python files are checked for this.",
    "atool.rust":
      "Which types implement which traits, and where `unsafe` lives: `unsafe fn` " +
      "and functions holding `unsafe` blocks. Only Rust files are checked for this.",
    "atool.docs":
      "Every Markdown file in the tree and how often the rest of the " +
      "documentation points at it — which pages are load-bearing, and which " +
      "nothing links to.",
    "atool.endpoints":
      "HTTP routes registered in the source, Express/Fastify/Koa-shaped. An " +
      "ecosystem convention rather than a language feature, so a tree " +
      "without one is empty here and that is a real answer.",

    "tab.hierarchy":
      "The dependency graph, drawn from one module outward. Boxes are modules " +
      "and namespaces, arrows are requires and calls; the slider decides how " +
      "far from the centre it reaches. Hovering a box lights it and its " +
      "neighbours; the first click holds that, so you can read it and follow " +
      "the edges without the pointer. Click the same box again to root the " +
      "graph there — or double-click, which is the same two clicks at once. " +
      "Escape, a click on empty space, or a click on another box lets go. " +
      "The path above the graph shows where you are, every level a way back. " +
      "The *Classic clicks* pill decides what that second click does: root " +
      "here, or open in the Tree. The one view that exports as an SVG.",
    "tab.index":
      "Flat lists of everything the map found, for when you know the name and " +
      "not the place. Three ways of listing the same repository — as a tree, " +
      "as functions, as modules.",
    "tab.analysis":
      "Aggregate numbers over the whole tree: how much is tested, how much is " +
      "documented, where dependencies concentrate. A palette of tools sharing " +
      "one panel, not a single report.",
    "tab.compare":
      "Two or more modules side by side, on the same rows, so a difference is " +
      "a difference in a column rather than something to remember between " +
      "scrolls.",
    "tab.features":
      "This repository's own `docs/FEATURES/` files, read as an index — name, " +
      "summary and metadata. Never the prose that follows them, which stays " +
      "in the file it was written in.",
    "tab.quicks":
      "The verdicts: what is notable about this tree stated in sentences, " +
      "good and bad, each with the count it is based on. Computed by the " +
      "engine, not by this page.",
    "tab.notes":
      "Everything the authors left behind. Annotations on functions " +
      "(`---@todo`, `---@bug`) and marker comments in the source " +
      "(`-- TODO:`, `// FIXME:`) — two lists, because one is attached to a " +
      "signature and the other to a line.",
    "tab.history":
      "This repository's git history, and what each commit did to the map. " +
      "Computed on demand from git, so it needs a host that can run it — a " +
      "map opened as a file says so instead of guessing.",

    "sub.tree":
      "The module tree as the scan walked it, with each node's own detail " +
      "beside it. The default place to start reading a repository you do not " +
      "know.",
    "sub.functions":
      "Every documented function in the map, alphabetically, with its " +
      "signature and where it lives.",
    "sub.modules":
      "Every module and namespace, alphabetically. The same set the tree " +
      "shows, without the nesting.",
    "feat.theme":
      "One feature file of this repository. The first is what the project " +
      "exists for, the second the overview, the rest one theme each.",
    "sub.features.all":
      "The index of every feature file, above the ones promoted to a tab of " +
      "their own.",

    "tab.findings":
      "Where the drift checks report. Each row is one check disagreeing " +
      "with the code — a doc reference to something that no longer exists, " +
      "an example that does not parse, a binding declared twice. The same " +
      "list that fails CI and lands on GitHub as SARIF. Its count stays in " +
      "the header rather than moving in here, because a number behind a " +
      "click is a number nobody reads.",
  };

  var explainpop = null;
  var explainAnchor = null;
  var explainTimer = null;

  function explainClose(){
    if(explainTimer){ clearTimeout(explainTimer); explainTimer = null; }
    if(explainpop) explainpop.classList.remove("on");
    // Removed with the card, not left behind: an `aria-describedby` pointing
    // at a hidden element describes nothing and is read as one anyway.
    if(explainAnchor) explainAnchor.removeAttribute("aria-describedby");
    explainAnchor = null;
  }

  function explainOpen(el){
    var text = EXPLAIN[el.dataset.explain];
    if(!text) return;
    if(!explainpop){
      explainpop = document.createElement("div");
      explainpop.className = "sigpop explainpop";
      explainpop.setAttribute("role", "tooltip");
      document.body.appendChild(explainpop);
    }
    explainAnchor = el;
    // **Associated, not merely positioned.** Six of these controls used to
    // carry a `title`, which a screen reader announces; replacing it with a
    // styled card would have taken that away from the readers least able to
    // spare it. `aria-describedby` is what puts it back, and it also gives
    // the nine tabs an association they never had.
    explainpop.id = explainpop.id || "explainpop";
    el.setAttribute("aria-describedby", explainpop.id);
    explainpop.innerHTML = '<div class="fn-desc"></div>';
    // `textContent`, not `innerHTML`: these strings carry backticks as
    // literal characters and nothing else, and a card that renders markup
    // is a card somebody eventually puts a link in.
    explainpop.querySelector(".fn-desc").textContent = text;
    explainpop.classList.add("on");

    // Under the control, flipped up when there is no room — the same rule
    // the annotation and keyword cards already follow.
    var r = el.getBoundingClientRect();
    var p = explainpop.getBoundingClientRect();
    var left = Math.min(r.left, window.innerWidth - p.width - 8);
    var top = r.bottom + 6;
    if(top + p.height > window.innerHeight - 8) top = r.top - p.height - 6;
    explainpop.style.left = Math.max(8, left) + "px";
    explainpop.style.top = Math.max(8, top) + "px";
  }

  // A deliberate dwell, not a pointer crossing the strip: eight tabs in a
  // row means a card per tab on the way to the one you wanted.
  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-explain]");
    if(!el){
      if(explainAnchor && !explainTimer) explainTimer = setTimeout(explainClose, 120);
      return;
    }
    if(explainTimer){ clearTimeout(explainTimer); explainTimer = null; }
    if(el === explainAnchor) return;
    explainClose();
    explainTimer = setTimeout(function(){
      explainTimer = null;
      explainOpen(el);
    }, 450);
  });

  // Keyboard focus opens it immediately. A `title` attribute would have been
  // free and never appears on focus, which would leave exactly the controls
  // a keyboard user reaches as the only ones with no explanation.
  document.addEventListener("focusin", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-explain]");
    if(el) explainOpen(el); else explainClose();
  });
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape") explainClose();
  });
  document.addEventListener("scroll", explainClose, true);
  window.addEventListener("blur", explainClose);

  // =====================================================================
  // The second level
  //
  // Two tabs own one: Index is three ways of listing the same repository
  // (Tree, Functions, Modules), and Features owns however many entries this
  // repository promotes with `Tab: true`.
  //
  // One strip rather than one per owner. Two strips in the same place that
  // are never both visible are one strip with extra code — and the promoted
  // features used to have no strip at all: each appended a button to the
  // *top* bar, so a repository documenting five features pushed the eight
  // permanent tabs onto a second row and buried them under five that are
  // particular to it.
  //
  // `state.tab` is unchanged by any of this. `tree` is still `tree` and a
  // promoted feature is still `feature-<slug>`, so every link ever shared
  // and every `#tab=` in anyone's history still lands where it did. What
  // changed is only which button lights up for them.
  // =====================================================================

  /// The top-level tab a state belongs to.
  ///
  /// `tree` lives under Index and `feature-x` under Features; everything
  /// else is its own group. This is the one place that mapping exists.
  function topTab(tab){
    if(tab === "tree") return "index";
    if(tab && tab.indexOf("feature-") === 0) return "features";
    return tab;
  }

  /// Entries for the strip, or `[]` when this group has no second level.
  function subTabs(tab){
    var group = topTab(tab);
    if(group === "index"){
      return [
        { tab: "tree", label: "Tree", explain: "sub.tree" },
        { tab: "index", iview: "functions", label: "Functions",
          explain: "sub.functions" },
        { tab: "index", iview: "modules", label: "Modules",
          explain: "sub.modules" }
      ];
    }
    if(group === "features"){
      // "All features" first: without it, opening a promoted feature would
      // leave no way back to the index of them except the browser's Back
      // button.
      var out = [{ tab: "features", label: "All features",
                   explain: "sub.features.all" }];
      collectPromotedFeatures().forEach(function(p){
        out.push({ tab: p.slug, label: tabLabel(p.entry.name), title: p.entry.name });
      });
      return out;
    }
    return [];
  }

  function renderSubTabs(s){
    var host = document.getElementById("subtabs");
    var entries = subTabs(s.tab);
    if(!entries.length){
      host.hidden = true;
      host.innerHTML = "";
      return;
    }
    host.hidden = false;
    host.innerHTML = "";
    entries.forEach(function(e){
      var b = document.createElement("button");
      b.className = "subtab-btn";
      // Active when both the tab and — where it matters — the mode match.
      // `Functions` and `Modules` are the same tab and differ only by
      // `iview`, so tab equality alone would light both.
      var on = e.tab === s.tab && (!e.iview || e.iview === (s.iview || "functions"));
      if(on) b.classList.add("active");
      b.textContent = e.label;
      if(e.title) b.title = e.title;
      if(e.explain) b.dataset.explain = e.explain;
      b.addEventListener("click", function(){
        navigate(e.iview ? { tab: e.tab, iview: e.iview } : { tab: e.tab });
      });
      host.append(b);
    });
  }

  var promotedFeatures = null;
  function collectPromotedFeatures(){
    if(promotedFeatures) return promotedFeatures;
    promotedFeatures = [];
    if(!IR.features) return promotedFeatures;
    // Two features can slugify to the same string (same name in different
    // theme files, or names differing only in punctuation) — disambiguated
    // with a numeric suffix rather than silently letting the second one's
    // tab button overwrite the first's in the DOM.
    var seen = {};
    IR.features.files.forEach(function(f){
      f.entries.forEach(function(e){
        if(!e.tab) return;
        var base = featureSlug(e.name);
        var slug = base, n = 2;
        while(seen[slug]){ slug = base + "-" + n; n++; }
        seen[slug] = true;
        promotedFeatures.push({ entry: e, file: f, slug: slug });
      });
    });
    return promotedFeatures;
  }

  // Inserted right after the static "Features" tab button/panel, each
  // subsequent one after the last — deterministic order (file order, then
  // entry order within a file, the same order `IR.features` already
  // carries), not something later re-sorts. Runs once at boot, before the
  // generic .tab-btn click-handler wiring picks up every button currently
  // in the DOM.
  function buildPromotedTabs(){
    var promoted = collectPromotedFeatures();
    if(!promoted.length) return;
    var afterView = document.getElementById("view-features");
    promoted.forEach(function(p){
      // Views only. The buttons are `renderSubTabs`'s now: appending them
      // to the top bar is what pushed the eight permanent tabs onto a
      // second row on any repository that promotes a few features.
      var view = document.createElement("div");
      view.id = "view-" + p.slug;
      view.className = "view";
      afterView.insertAdjacentElement("afterend", view);
      afterView = view;
    });
  }

  // Cheap Markdown-subset renderer for a promoted feature's body — the same
  // "cheap reliable reading beats a general one" discipline
  // core/features.lua's own parser follows, not a CommonMark
  // implementation. Understood: `#`.."######" headings, fenced ``` code
  // blocks, `-`/`*` bullet lists, paragraphs, and inline `` `code` ``/
  // **bold**/*italic*/[text](url). Not understood: tables, blockquotes,
  // images, nested/ordered lists, or raw HTML passthrough — anything else
  // renders as plain escaped text rather than being interpreted.
  function inlineMd(s){
    s = esc(s);
    s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
    s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    s = s.replace(/(^|[^*_])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
    // A hex escape for the closing bracket, not a backslash-escaped literal
    // one: two adjacent close-brackets anywhere in this file's embedded JS
    // would end the Lua long string this whole block lives inside early —
    // a sharp edge no other function here hit, since none needed a bracket
    // right next to the closing one of its own character class.
    s = s.replace(/\[([^\x5d]+)\]\(([^)]+)\)/g, function(m, text, url){
      // Only http(s)/relative-looking targets get linked — never a
      // `javascript:` URL smuggled through a docs/FEATURES/ file this
      // parser otherwise trusts as plain prose.
      if(/^(https?:)?\/\//.test(url) || /^[.\w#]/.test(url)){
        return '<a href="' + url + '" target="_blank" rel="noopener">' + text + '</a>';
      }
      return text;
    });
    return s;
  }

  function renderFeatureBody(raw){
    var lines = raw.split("\n");
    var out = [], para = [], list = null;

    function flushPara(){
      if(para.length){ out.push("<p>" + inlineMd(para.join(" ")) + "</p>"); para = []; }
    }
    function flushList(){
      if(list){ out.push("<ul>" + list.join("") + "</ul>"); list = null; }
    }

    var i = 0;
    while(i < lines.length){
      var trimmed = lines[i].replace(/^\s+|\s+$/g, "");

      if(/^```/.test(trimmed)){
        flushPara(); flushList();
        // The info string used to be matched and dropped: `/^```/` said "a
        // fence starts here" and nothing captured the `lua` after it, so the
        // one piece of information needed to highlight the block was thrown
        // away one character before it was used.
        var fenceLang = (/^```+\s*([A-Za-z0-9_+#.-]*)/.exec(trimmed) || [])[1] || "";
        var code = [];
        i++;
        while(i < lines.length && !/^```/.test(lines[i].replace(/^\s+|\s+$/g, ""))){
          code.push(lines[i]); i++;
        }
        i++; // skip the closing fence (or run off the end if one is missing)
        // Through the shared renderer rather than this function's own
        // `<pre><code>`: the Features tab and a module's `@description` show
        // the same languages, and two renderers would have given them two
        // looks on one page.
        out.push(fenceHTML(code.join("\n"), fenceLang));
        continue;
      }

      var heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
      if(heading){
        flushPara(); flushList();
        // A body's own headings sit under the tab's H2 (feature name) and
        // the theme label above it — h4 is the highest an author's `#`
        // should reach, capped at h6 so `######` doesn't overshoot into
        // nothing.
        var level = Math.min(heading[1].length + 3, 6);
        out.push("<h" + level + ">" + inlineMd(heading[2]) + "</h" + level + ">");
        i++; continue;
      }

      var item = trimmed.match(/^[-*]\s+(.+)$/);
      if(item){
        flushPara();
        list = list || [];
        list.push("<li>" + inlineMd(item[1]) + "</li>");
        i++; continue;
      }

      if(trimmed === ""){
        flushPara(); flushList();
        i++; continue;
      }

      flushList();
      para.push(trimmed);
      i++;
    }
    flushPara(); flushList();
    return out.join("\n");
  }

  var drawnFeatureTabs = {};
  function drawFeatureTab(slug){
    if(drawnFeatureTabs[slug]) return; // static over one IR, same as drawFeatures
    var promoted = collectPromotedFeatures().filter(function(p){ return p.slug === slug; })[0];
    var host = document.getElementById("view-" + slug);
    if(!promoted || !host) return;
    drawnFeatureTabs[slug] = true;

    var e = promoted.entry, f = promoted.file;
    var nodeId = e.node || resolveModuleNode(e.meta);
    var parts = ['<div class="feat-tab-wrap">'];
    parts.push('<div class="feat-tab-theme">' + esc(themeTitle(f.theme)) + '</div>');
    parts.push('<h2 class="feat-tab-name"' +
      (nodeId ? ' data-node="' + esc(nodeId) + '" tabindex="0" role="button"' : '') +
      '>' + esc(e.name) + '</h2>');
    if(e.summary){
      parts.push('<p class="feat-tab-summary">' + prose(e.summary) + '</p>');
    }
    if(e.meta.length){
      parts.push('<div class="feat-meta">');
      e.meta.forEach(function(m){
        parts.push('<div class="feat-meta-row"><b>' + esc(m.key) + ':</b> <span>' +
          esc(m.value) + '</span></div>');
      });
      parts.push("</div>");
    }
    if(e.body){
      parts.push('<div class="feat-tab-body">' + renderFeatureBody(e.body) + '</div>');
    }
    parts.push('<div class="feat-src"><a href="#" data-src="' + esc(f.path) + '">' +
      esc(f.path) + ':' + e.line + '</a></div>');
    parts.push("</div>");
    host.innerHTML = parts.join("");

    var nameEl = host.querySelector(".feat-tab-name[data-node]");
    if(nameEl){
      nameEl.addEventListener("click", function(){ navigate({ tab: "tree", id: nodeId }); });
    }
    host.querySelectorAll(".feat-src a[data-src]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var u = srcUrl(a.dataset.src);
        window.open(u || rel(a.dataset.src), u ? "_blank" : "_self");
      });
    });
  }

  // =====================================================================
  // Index tab: Doxygen's "File Members" — every documented function in the
  // tree, A–Z, without walking the module hierarchy to find it.
  //
  // Sorted on the *bare* name (`M.read` files under R, not M), because the
  // `M.` is this repo's local-table convention rather than part of what the
  // function is called — filing 900 functions under "M" would be an index in
  // name only. `calls.lua` needed the same reduction and its `bare()` is the
  // model here.
  //
  // The Tree tab already filters and the picker already fuzzy-matches; what
  // neither gives you is the flat alphabet, which is the one way to find
  // something whose module you do not know.
  // =====================================================================
  function bareName(name){ return (name.match(/[\w]+$/) || [name])[0]; }

  // Shared by both index views: letter buckets plus a jump bar, filed on
  // `entry.bare`. Ties broken by `entry.tie` so two entries with the same
  // bare name (`M.setup` everywhere; two modules named `init`) sort
  // deterministically instead of leaving it to the engine's discretion.
  function buildIndexBuckets(entries){
    entries.sort(function(a, b){
      var ab = a.bare.toLowerCase(), bb = b.bare.toLowerCase();
      if(ab !== bb) return ab < bb ? -1 : 1;
      return a.tie < b.tie ? -1 : (a.tie > b.tie ? 1 : 0);
    });
    var buckets = {}, order = [];
    entries.forEach(function(e){
      var c = e.bare.charAt(0).toUpperCase();
      if(!/[A-Z]/.test(c)) c = "#";
      if(!buckets[c]){ buckets[c] = []; order.push(c); }
      buckets[c].push(e);
    });
    order.sort();
    return { buckets: buckets, order: order };
  }

  function indexJumpBar(order){
    return '<div class="ixjump">' + order.map(function(c){
      return '<a data-jump="' + esc(c) + '">' + esc(c) + '</a>';
    }).join("") + "</div>";
  }

  function wireIndexBody(host){
    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
    host.querySelectorAll("[data-jump]").forEach(function(a){
      a.addEventListener("click", function(){
        var h = host.querySelector("#ix-" + CSS.escape(a.dataset.jump));
        if(h) h.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
  }

  // Doxygen's "File Members" — every documented function in the tree, A-Z,
  // without walking the module hierarchy to find it. Sorted on the *bare*
  // name (`M.read` files under R, not M): the `M.` is this repo's
  // local-table convention rather than part of what the function is
  // called, and filing 900 functions under "M" would be an index in name
  // only — `calls.lua` needed the same reduction and its `bare()` is the
  // model. The Tree tab already filters and the picker already
  // fuzzy-matches; what neither gives you is the flat alphabet, the one way
  // to find something whose module you do not already know.
  var indexFnHTML = null;
  function renderIndexFunctions(){
    if(indexFnHTML !== null) return indexFnHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        entries.push({ node: n, fn: fn, bare: bareName(fn.name), tie: n.module || n.path });
      });
    });

    if(entries.length === 0){
      indexFnHTML = '<p class="ntext none">This map contains no documented functions.</p>';
      return indexFnHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' documented functions, filed under the last segment of the declared name' +
      ' (<code>M.read</code> sorts under R).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(e.node.id) + '">' +
          esc(e.fn.signature) + '</a>' +
          sigTrigger(e.node.id, e.fn.name) + docTrigger(fnKey(e.node.id, e.fn.name)) +
          (e.fn.internal ? '<span class="ixtag">internal</span>' : '') +
          (e.fn.deprecated ? '<span class="ixtag dep">deprecated</span>' : '') +
          (e.fn.tested ? '<span class="ixtag tested">tested</span>' : '') +
          '<span class="nwhere">' + esc(e.node.module || e.node.path) +
          ':' + e.fn.line + '</span></li>');
      });
      parts.push("</ul>");
    });
    indexFnHTML = parts.join("");
    return indexFnHTML;
  }

  // R3: the same flat alphabet, one level up — every *module and namespace*
  // (not function, and deliberately not `file` nodes: a file is reached
  // through its module in the Tree, and this index exists for "I know the
  // module name, not where it lives", which a leaf file rarely is). Doxygen
  // keeps its File Index and Class Index as separate pages for the same
  // reason a flat function alphabet and a flat module alphabet answer two
  // different "I know the name, not the location" questions.
  var indexModHTML = null;
  function renderIndexModules(){
    if(indexModHTML !== null) return indexModHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      if(n.kind !== "module" && n.kind !== "namespace") return;
      var label = n.module || n.path;
      entries.push({ node: n, bare: bareName(label), label: label, tie: label });
    });

    if(entries.length === 0){
      indexModHTML = '<p class="ntext none">This map contains no modules.</p>';
      return indexModHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' modules and namespaces, filed under the last segment of the module path' +
      ' (<code>lib.nvim.fs</code> sorts under F).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        var fnCount = (e.node.functions || []).length;
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(e.node.id) + '">' +
          esc(e.label) + '</a>' + docTrigger(e.node.id) +
          '<span class="ixtag">' + esc(e.node.kind) + '</span>' +
          '<span class="nwhere">' + fnCount + (fnCount === 1 ? " function" : " functions") +
          '</span></li>');
      });
      parts.push("</ul>");
    });
    indexModHTML = parts.join("");
    return indexModHTML;
  }

  function drawIndex(){
    var host = document.getElementById("ixbody");
    var iview = state.iview === "modules" ? "modules" : "functions";
    host.innerHTML = iview === "modules" ? renderIndexModules() : renderIndexFunctions();
    wireIndexBody(host);
  }

]]
