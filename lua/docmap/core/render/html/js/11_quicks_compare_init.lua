---@module 'docmap.core.render.html.js.11_quicks_compare_init'
--- A slice of the page's script: Quicks, Compare, marked functions, roving tabindex, initial load.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Quicks — the tree's own state, in sentences.
  //
  // No computation here: `core/quicks.lua` produced the verdicts, including
  // the `basis` line under each one. That split is deliberate rather than
  // tidy — the same verdicts have to be reachable from the CLI and from a
  // spec, and a rule that lives in this file is a rule only the browser can
  // check.
  // =====================================================================
  var QUICKS = IR.quicks || { good: [], bad: [], total_good: 0, total_bad: 0 };

  function quickHTML(q){
    var h = ['<div class="qk ' + (q.polarity === "good" ? "good" : "bad") + '">'];
    h.push('<div class="qk-head"><span class="qk-line">' + esc(q.headline) + '</span>' +
      '<span class="qk-val">' + esc(q.detail) + '</span></div>');
    h.push('<div class="qk-basis">' + esc(q.basis) + '</div>');

    var acts = [];
    if(q.tab){
      acts.push('<button data-qgoto="' + esc(q.id) + '">Show the rows</button>');
    }
    // Only where the verdict actually carried evidence — an offer to mark
    // "the functions behind this" that silently marks nothing is worse than
    // no button. `quicks.lua` attaches evidence to negative verdicts only,
    // and caps the list, so this is bounded by construction.
    if(q.evidence && q.evidence.length){
      acts.push('<button data-qmark="' + esc(q.id) + '">Mark all ' +
        q.evidence.length + '</button>');
    }
    if(acts.length) h.push('<div class="qk-acts">' + acts.join("") + '</div>');
    h.push("</div>");
    return h.join("");
  }

  function quickById(id){
    var all = QUICKS.good.concat(QUICKS.bad);
    for(var i = 0; i < all.length; i++){ if(all[i].id === id) return all[i]; }
    return null;
  }

  function drawQuicks(){
    var el = document.getElementById("view-quicks");
    var h = ['<div class="qk-wrap">'];

    if(!QUICKS.good.length && !QUICKS.bad.length){
      // Three different situations, and telling them apart matters: an old
      // artifact, a tree too small to say anything about, or a genuinely
      // unremarkable one. Only the last is good news, so do not phrase all
      // three as if they were.
      h.push('<p class="ntext none">Nothing crossed a threshold in either direction. ' +
        'That is the normal reading for a tree that is doing fine — every measure ' +
        'landed in the unremarkable band between its two cut points. An artifact ' +
        'generated before Quicks existed also lands here; regenerate with ' +
        '<code>:DocMap</code> if this map is old.</p>');
      h.push("</div>");
      el.innerHTML = h.join("");
      return;
    }

    // Negatives first. The positives are the reward for reading, not the
    // headline — a page that opens with praise buries the one thing the
    // reader could act on today.
    if(QUICKS.bad.length){
      h.push('<div class="qk-col"><div class="qk-h">Worth fixing' +
        (QUICKS.total_bad > QUICKS.bad.length
          ? ' — ' + QUICKS.bad.length + ' of ' + QUICKS.total_bad + ' shown'
          : '') + '</div>');
      QUICKS.bad.forEach(function(q){ h.push(quickHTML(q)); });
      h.push("</div>");
    }
    if(QUICKS.good.length){
      h.push('<div class="qk-col"><div class="qk-h">Going well' +
        (QUICKS.total_good > QUICKS.good.length
          ? ' — ' + QUICKS.good.length + ' of ' + QUICKS.total_good + ' shown'
          : '') + '</div>');
      QUICKS.good.forEach(function(q){ h.push(quickHTML(q)); });
      h.push("</div>");
    }
    h.push("</div>");
    el.innerHTML = h.join("");
  }

  document.addEventListener("click", function(ev){
    var goto = ev.target.closest && ev.target.closest("[data-qgoto]");
    if(goto){
      var q = quickById(goto.dataset.qgoto);
      if(q) navigate(q.atool ? { tab: q.tab, atool: q.atool } : { tab: q.tab });
      return;
    }
    var mk = ev.target.closest && ev.target.closest("[data-qmark]");
    if(mk){
      var qq = quickById(mk.dataset.qmark);
      if(qq && qq.evidence) addMarks(qq.evidence);
      return;
    }
  });

  // =====================================================================
  // Compare — the marked objects, next to each other.
  //
  // Three layouts, and they are not three skins of one thing. Columns and
  // Stacked render the annotation card this page already has, which is worth
  // having but is also roughly what two browser windows do. Matrix is the
  // layout that earns the tab: attributes down the side, marked objects
  // across, and every row where they disagree lit up. "Where do these four
  // differ" has no other answer here.
  // =====================================================================
  function markEntry(key){
    var fn = fnByKey[key];
    if(fn) return { kind: "fn", key: key, fn: fn.fn, node: fn.node };
    var n = byId[key];
    if(n) return { kind: "node", key: key, node: n };
    return null;
  }

  function markTitle(e){
    if(e.kind === "fn") return e.fn.name;
    return e.node.module || e.node.name;
  }

  function markWhere(e){
    if(e.kind === "fn") return (e.node.module || e.node.path) + ":" + e.fn.line;
    return e.node.path;
  }

  // One row of the matrix. `get` returns a display string; rows where every
  // marked object returns the same string are not what the reader came for.
  var CMP_ROWS = [
    { label: "Kind", get: function(e){ return e.kind === "fn" ? "function" : e.node.kind; } },
    { label: "Where", get: function(e){ return markWhere(e); } },
    { label: "Summary", get: function(e){
      return (e.kind === "fn" ? e.fn.summary : e.node.summary) || "—"; } },
    { label: "Signature", get: function(e){
      return e.kind === "fn" ? (e.fn.signature || "—") : "—"; } },
    { label: "Params", get: function(e){
      return e.kind === "fn" ? String((e.fn.params || []).length) : "—"; } },
    { label: "Returns", get: function(e){
      return e.kind === "fn" ? String((e.fn.returns || []).length) : "—"; } },
    { label: "Complexity", get: function(e){
      return e.kind === "fn" ? String(e.fn.complexity || 1) : "—"; } },
    { label: "Lines", get: function(e){
      if(e.kind !== "fn") return String((e.node.stats && e.node.stats.lines) || 0);
      return (e.fn.line_end && e.fn.line) ? String(e.fn.line_end - e.fn.line + 1) : "—"; } },
    { label: "Tested", get: function(e){
      return e.kind === "fn" ? (e.fn.tested ? "yes" : "no") : "—"; } },
    { label: "Documented", get: function(e){
      return e.kind === "fn" ? (e.fn.documented ? "yes" : "no") : "—"; } },
    { label: "Internal", get: function(e){
      return e.kind === "fn" ? (e.fn.internal ? "yes" : "no") : "—"; } },
    { label: "Deprecated", get: function(e){
      if(e.kind !== "fn") return "—";
      return e.fn.deprecated !== undefined ? (e.fn.deprecated || "yes") : "no"; } },
    { label: "Example", get: function(e){
      return e.kind === "fn" ? (e.fn.example ? "yes" : "no") : "—"; } },
    { label: "Requires", get: function(e){
      return String(((e.kind === "fn" ? e.node : e.node).requires || []).length); } },
    { label: "Required by", get: function(e){
      return String(((e.kind === "fn" ? e.node : e.node).required_by || []).length); } }
  ];

  function cmpMatrixHTML(entries){
    var h = ['<div class="cmp-scroll"><table class="cmptable"><thead><tr><th></th>'];
    entries.forEach(function(e){
      h.push('<th>' + esc(markTitle(e)) +
        '<button class="cmp-drop" data-unmark="' + esc(e.key) +
        '" title="Drop this one">&times;</button></th>');
    });
    h.push("</tr></thead><tbody>");
    CMP_ROWS.forEach(function(row){
      var vals = entries.map(row.get);
      var differs = false;
      for(var i = 1; i < vals.length; i++){ if(vals[i] !== vals[0]){ differs = true; break; } }
      h.push('<tr class="' + (differs ? "differs" : "") + '"><th>' + esc(row.label) + '</th>');
      vals.forEach(function(v){ h.push('<td>' + esc(v) + '</td>'); });
      h.push("</tr>");
    });
    h.push("</tbody></table></div>");
    return h.join("");
  }

  function cmpCardHTML(e){
    var h = ['<div class="cmp-card">'];
    h.push('<div class="cmp-card-h"><span class="cmp-where">' + esc(markWhere(e)) + '</span>' +
      '<button class="cmp-drop" data-unmark="' + esc(e.key) + '" title="Drop this one">&times;</button></div>');
    if(e.kind === "fn"){
      // The same renderer the detail pane and the popup use. A third copy of
      // "how a function's annotations look" is exactly the drift this plugin
      // exists to detect.
      h.push(fnAnnotationHTML(e.fn) + snippetHTML(e.fn, e.node));
    } else {
      h.push('<div class="fn-sig">' + esc(e.node.module || e.node.name) + '</div>');
      if(e.node.summary) h.push('<div class="fn-desc">' + prose(e.node.summary) + '</div>');
    }
    h.push("</div>");
    return h.join("");
  }

  function drawCompare(){
    var body = document.getElementById("cmpbody");
    var view = state.cview || "matrix";
    document.querySelectorAll("#cmptoggle .cmpview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.cview === view);
    });

    var entries = state.marks.map(markEntry).filter(Boolean);

    if(!entries.length){
      body.innerHTML = '<p class="ntext none">Nothing marked yet. The <code>+</code> ' +
        'beside any function or module adds it here — mark two or more and this tab ' +
        'shows them next to each other. Marks survive a reload and travel in the URL, ' +
        'so a comparison is shareable.</p>';
      return;
    }
    if(view === "matrix" && entries.length === 1){
      body.innerHTML = '<p class="nsub">One object marked — a matrix needs a second ' +
        'to compare against. Shown as a card until then.</p>' +
        '<div class="cmp-stack">' + cmpCardHTML(entries[0]) + '</div>';
      return;
    }

    if(view === "matrix"){ body.innerHTML = ceBarHTML(entries) + cmpMatrixHTML(entries); return; }

    var cls = view === "columns" ? "cmp-cols" : "cmp-stack";
    body.innerHTML = ceBarHTML(entries) + '<div class="' + cls + '">' +
      entries.map(cmpCardHTML).join("") + "</div>";
  }

  // =====================================================================
  // Marked functions, side by side, in one Compiler Explorer
  //
  // The Duplicates panel raises a question it cannot answer: two functions
  // have the same shape, so do they compile to the same thing? Marking both
  // and opening them in one `clientstate` answers it — Compiler Explorer's
  // own format is an array of sessions, so this is the documented shape
  // used as documented, not a trick.
  //
  // **Why marks rather than a button in the Duplicates panel.** The marks
  // mechanism, the key scheme and the Compare tab all already exist, and
  // marks are not limited to one group: the comparison worth making is
  // often between a duplicate and the thing it *should* have been, which
  // lives in some other group or in no group at all.
  //
  // Modules are skipped rather than refused. A module's "source" is its
  // functions concatenated, which is already an approximation, and mixing
  // one into a comparison of two functions would put a session in there
  // that answers a different question. The bar says how many it took.
  // =====================================================================
  function ceSources(entries){
    return entries.filter(function(e){
      return e.kind === "fn" && e.fn && e.fn.snippet;
    });
  }

  function ceBarHTML(entries){
    if(!IR.meta.godbolt) return "";
    var usable = ceSources(entries);
    var base = ceBase();
    var local = ceIsLocal();

    var h = ['<div class="cebar">'];
    if(usable.length >= 2){
      h.push('<button type="button" class="cebtn" id="cego">⚙ Compile all ' +
        usable.length + ' together ↗</button>');
      h.push('<span class="cenote">' +
        (local
          ? 'Opens ' + esc(base) + ' with one editor per function.'
          : 'Opens godbolt.org with one editor per function — their source ' +
            'travels inside the link, and it is still someone else’s server.') +
        '</span>');
    } else {
      h.push('<span class="cenote">Mark two or more <em>functions</em> to compile ' +
        'them side by side. ' +
        (entries.length > usable.length
          ? 'Modules are left out: a module’s source here is its functions ' +
            'concatenated, which answers a different question.'
          : '') +
        '</span>');
    }

    // The setting lives here rather than in a preferences panel the page
    // does not have. It is also where it is most wanted: this is the view
    // that builds the longest URLs, and the 8 KB ceiling is godbolt.org's
    // alone.
    h.push('<details class="cehost"' + (local ? " open" : "") + '>');
    h.push('<summary>' + (local ? esc(base) : "godbolt.org") + '</summary>');
    h.push('<p class="cenote">Point this at a Compiler Explorer you run ' +
      'yourself and nothing leaves your machine. Stored in this browser only ' +
      '— never written into the generated page, because a committed map ' +
      'that hard-wired one machine’s address would be a broken link for ' +
      'everyone else who opens it.</p>');
    h.push('<input type="url" id="cehostin" class="cehostin" spellcheck="false" ' +
      'placeholder="http://localhost:10240" value="' + (local ? esc(base) : "") + '">');
    h.push('<button type="button" class="cebtn" id="cehostsave">Use this</button>');
    h.push('<button type="button" class="cebtn" id="cehostreset">Back to godbolt.org</button>');
    h.push("</details></div>");
    return h.join("");
  }

  document.querySelectorAll("#cmptoggle .cmpview-btn").forEach(function(b){
    b.addEventListener("click", function(){
      navigate({ tab: "compare", cview: b.dataset.cview });
    });
  });
  // Delegated, because `#cego` and the host controls are rebuilt by every
  // `drawCompare` — binding them per draw is how a handler ends up attached
  // three times to the same button.
  document.addEventListener("click", function(ev){
    var t = ev.target;
    if(!t || !t.id) return;

    if(t.id === "cego"){
      var usable = ceSources(state.marks.map(markEntry).filter(Boolean));
      if(usable.length < 2) return;
      var url = godboltUrl(usable.map(function(e){ return e.fn.snippet; }));
      if(ceTooLong(url)){
        // Said in the bar rather than in a new tab: godbolt.org answers an
        // over-long request line with an unexplained `414` page, and the
        // reader would have no way to connect it to the number of marks.
        var note = document.querySelector(".cebar .cenote");
        if(note){
          note.textContent = "Too large for godbolt.org: " +
            Math.round(url.length / 1024) + " KB of URL against their 8 KB " +
            "limit. Unmark a few, or point this at a Compiler Explorer you " +
            "run yourself — that limit is their front end's, not the tool's.";
        }
        return;
      }
      window.open(url, "_blank");
      return;
    }

    if(t.id === "cehostsave"){
      var input = document.getElementById("cehostin");
      var v = (input && input.value || "").trim().replace(/\/+$/, "");
      // Refused rather than stored-and-ignored. A value that silently does
      // nothing is worse than one that says why: `ceBase` would fall back to
      // godbolt.org and the reader would think they had switched.
      if(!/^https?:\/\//.test(v)){
        if(input) input.setCustomValidity("Needs to start with http:// or https://");
        if(input) input.reportValidity();
        return;
      }
      try { localStorage.setItem(CE_LS_KEY, v); } catch(e){ void 0; }
      drawCompare();
      return;
    }

    if(t.id === "cehostreset"){
      try { localStorage.removeItem(CE_LS_KEY); } catch(e){ void 0; }
      drawCompare();
      return;
    }
  });

  document.getElementById("cmpclear").addEventListener("click", clearMarks);
  document.getElementById("markbar").addEventListener("click", function(){
    navigate({ tab: "compare" });
  });
  // Unlike #markbar, no tab to open — the pill's only job is showing how many
  // boxes are dimmed and clearing all of them in one click.
  document.getElementById("hiddenbar").addEventListener("click", clearHidden);

  document.addEventListener("click", function(ev){
    var un = ev.target.closest && ev.target.closest("[data-unmark]");
    if(un){ toggleMark(un.dataset.unmark); return; }
    var mk = ev.target.closest && ev.target.closest("[data-mark]");
    if(mk){
      // Stops the row's own click handler from also firing: every list that
      // renders a mark trigger renders it inside a row that navigates when
      // clicked, and marking something must not also move the page away from
      // the list being scanned.
      ev.preventDefault();
      ev.stopPropagation();
      toggleMark(mk.dataset.mark);
      return;
    }
  }, true);

  // Keyboard parity, same as the `ⓘ` trigger has.
  document.addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !el.dataset.mark) return;
    ev.preventDefault();
    toggleMark(el.dataset.mark);
  });

  // Keyboard parity for the third affordance on those same rows: the link
  // itself. `.marki` and `.sigi` above each got a tabindex and their own
  // Enter/Space handler; the `data-node` element they decorate did not, so
  // tabbing the Index reached all 456 "mark" toggles and all 456 `ⓘ`
  // triggers and none of the 456 function links they belong to — every
  // accessory keyboard-operable, the primary action not.
  //
  // One delegated listener rather than a per-element one at each of the
  // render sites, for the reason the graph's own click handler gives: these
  // lists are rebuilt wholesale on every redraw, and re-binding per element
  // would stack duplicates on whatever survives.
  //
  // Disjoint from the two handlers above by construction — they key on
  // `data-mark`/`data-sig`/`data-doc`, this on `data-node`, and no element
  // carries both. `.feat-name`/`.feat-tab-name` are covered by the same
  // listener: they already shipped `tabindex="0" role="button"` but had only
  // a click listener, so they took a tab stop and announced themselves as
  // buttons while doing nothing when operated — `role="button"` does not
  // make a non-button activate on Enter, which was measured rather than
  // assumed before this was written.
  document.addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !el.dataset.node) return;
    // A real <input>/<textarea> that happened to carry data-node keeps its
    // own meaning for Space; nothing renders that today, and guarding costs
    // one test.
    if(/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) return;
    ev.preventDefault();
    navigate({ tab: "tree", id: el.dataset.node });
  });

  // =====================================================================
  // =====================================================================
  // Roving tabindex for the long lists.
  //
  // Slice 5 gave the Index's 456 links a tabindex each, which is right for a
  // list of links but wrong at this scale: the Tree carries 169 rows, the
  // Analysis panels up to 79, History 100. Stamping each one a tab stop
  // would put ~440 presses between the tab bar and the page's own content,
  // which is not "accessible", just unusable in a different way.
  //
  // So: one tab stop per list, on the container, and the arrows move within
  // it — the roving-tabindex pattern. Exactly one element in each list is
  // focusable at any moment, which is what makes it "roving".
  //
  // Delegated on a container that exists in the initial HTML and is never
  // replaced (`#tree`, `#hist-list`, `#anbody`), never bound per item, for
  // the reason the graph's click handler already states: these bodies are
  // rebuilt wholesale on redraw and per-item binding stacks duplicates.
  // Items therefore carry no tabindex attribute at rest; `tabIndex = -1` is
  // set on one lazily, immediately before focusing it. That is also what
  // makes this survive a redraw with no re-wiring: nothing is remembered
  // about the old DOM.
  //
  // `offsetParent === null` is the visibility test, and it is doing real
  // work rather than being a formality: it excludes rows inside a collapsed
  // `.kids` (`display:none`) *and* rows the search box hid via
  // `style.display`, so the arrows walk exactly what the eye sees.
  // =====================================================================
  function rovingList(containerId, itemSelector, activate, hooks){
    var container = document.getElementById(containerId);
    if(!container) return;
    // The container is the single tab stop. Items are reached with arrows
    // once focus is inside it.
    if(!container.hasAttribute("tabindex")) container.tabIndex = 0;

    function items(){
      return Array.prototype.slice.call(container.querySelectorAll(itemSelector))
        .filter(function(el){ return el.offsetParent !== null; });
    }
    function itemOf(target){
      var el = target;
      while(el && el !== container){
        if(el.matches && el.matches(itemSelector)) return el;
        el = el.parentNode;
      }
      return null;
    }
    function focusItem(el){
      if(!el) return;
      el.tabIndex = -1;
      el.focus();
      // `nearest` so arrowing does not yank a list that is already in view.
      if(el.scrollIntoView) el.scrollIntoView({ block: "nearest" });
    }

    container.addEventListener("keydown", function(ev){
      if(ev.ctrlKey || ev.metaKey || ev.altKey) return;
      // A search box or any other real input inside the list keeps its own
      // arrow-key meaning.
      if(/^(INPUT|TEXTAREA|SELECT)$/.test(ev.target.tagName)) return;

      var list = items();
      if(!list.length) return;
      var cur = itemOf(ev.target);
      var i = cur ? list.indexOf(cur) : -1;

      if(ev.key === "ArrowDown"){
        ev.preventDefault();
        focusItem(list[i < 0 ? 0 : Math.min(i + 1, list.length - 1)]);
      } else if(ev.key === "ArrowUp"){
        ev.preventDefault();
        focusItem(list[i <= 0 ? 0 : i - 1]);
      } else if(ev.key === "Home"){
        ev.preventDefault(); focusItem(list[0]);
      } else if(ev.key === "End"){
        ev.preventDefault(); focusItem(list[list.length - 1]);
      } else if(ev.key === "Enter" || ev.key === " "){
        if(!cur) return;
        ev.preventDefault();
        activate(cur);
      } else if(hooks && hooks.horizontal && (ev.key === "ArrowRight" || ev.key === "ArrowLeft")){
        if(!cur) return;
        ev.preventDefault();
        hooks.horizontal(cur, ev.key === "ArrowRight", focusItem, list, i);
      }
    });
  }

  // The Tree is a tree, not a flat list, so Right/Left expand and collapse
  // the way every other tree widget does. Reusing the twisty's own click
  // handler rather than re-implementing the toggle keeps one source of truth
  // for what expanding means — including the arrow glyph it swaps.
  function treeKidsOf(row){
    var box = row.parentNode;
    return box ? box.querySelector(".kids") : null;
  }
  rovingList("tree", ".row", function(row){
    if(row.dataset.id) navigate({ tab: "tree", id: row.dataset.id });
  }, {
    horizontal: function(row, isRight, focusItem, list, i){
      var kids = treeKidsOf(row);
      var tw = row.querySelector(".tw");
      if(isRight){
        // Collapsed: open it. Already open (or a leaf): step into the first
        // child, which is what Right does in a tree that is already expanded.
        if(kids && kids.classList.contains("hide")){ tw && tw.click(); return; }
        if(i >= 0 && i + 1 < list.length) focusItem(list[i + 1]);
        return;
      }
      // Left: close an open node, else go to the parent row.
      if(kids && !kids.classList.contains("hide")){ tw && tw.click(); return; }
      var parentBox = row.parentNode && row.parentNode.parentNode;
      var parentRow = parentBox && parentBox.parentNode
        ? parentBox.parentNode.querySelector(":scope > .row") : null;
      if(parentRow && parentRow !== row) focusItem(parentRow);
    }
  });

  rovingList("hist-list", ".crow", function(row){
    if(row.dataset.sha) navigate({ tab: "history", sha: row.dataset.sha });
  });

  // The Analysis body holds a real <table>. Its rows get roving focus, but
  // deliberately no listbox/option roles: a table already carries correct
  // semantics, and overriding them with list roles would throw away the row
  // and column relationships a screen reader otherwise gets for free.
  rovingList("anbody", "tr.anrow", function(row){
    if(row.dataset.node) navigate({ tab: "tree", id: row.dataset.node });
  });

  // `aria-expanded` on the rows that have something to expand. Stamped after
  // every tree redraw and every toggle rather than at render time, because
  // the twisty's own click handler is what changes the state and it lives in
  // renderNode. Measurable and unambiguous, unlike the fuller tree/treeitem
  // role taxonomy, which is deliberately not attempted here: getting it
  // half-right is worse than leaving native semantics alone, and this
  // session has no screen reader to verify it against.
  function syncTreeExpanded(){
    var treeEl2 = document.getElementById("tree");
    if(!treeEl2) return;
    treeEl2.querySelectorAll(".row").forEach(function(row){
      var kids = treeKidsOf(row);
      if(kids) row.setAttribute("aria-expanded", kids.classList.contains("hide") ? "false" : "true");
      else row.removeAttribute("aria-expanded");
    });
  }
  // Capture phase, deliberately: the twisty's own click handler calls
  // `ev.stopPropagation()` (so that expanding a node does not also select
  // it), which means a bubble-phase listener on `#tree` never sees the one
  // click that actually changes expanded state. Measured, not reasoned about
  // — the first version of this used the bubble phase and left
  // `aria-expanded` reading "true" on a collapsed node, for keyboard and
  // mouse alike. Capture runs on the way down, before that stop; the
  // `setTimeout` then reads the state after the toggle has applied.
  document.getElementById("tree").addEventListener("click", function(){
    setTimeout(syncTreeExpanded, 0);
  }, true);

  // Keyboard parity for the sort headers, same shape as `data-node`'s above:
  // they are rendered fresh with every panel redraw, so this is delegated on
  // `#anbody` and keyed on `data-sort`, and it simply replays the click the
  // pointer would have produced rather than duplicating the direction logic
  // that decides ascending from descending.
  document.getElementById("anbody").addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || el.dataset.sort === undefined) return;
    ev.preventDefault();
    el.click();
  });

  // =====================================================================
  // Initial load: parse whatever hash the page was opened with (a bare
  // #<id> from an old-style/shared link, a full serialized state from
  // Back/Forward, or nothing) and apply it as a *replace*, not a push — the
  // very first state should not itself create a Back-stack entry.
  // =====================================================================
  var initial = parseState(location.hash);
  if(!initial.id && !initial.center) initial.id = IR.root;
  // A link that carries marks wins — it is an explicit statement about which
  // set to look at, and silently unioning it with whatever this browser had
  // lying around would make a shared comparison show things the sender never
  // marked. Only a hash with no `marks` at all falls back to the stored set,
  // which is the "I marked these yesterday, then regenerated" case.
  if(!initial.marks.length) initial.marks = loadMarks();
  // Same precedence, same reasoning: a shared Hierarchy link that dims a
  // specific set of boxes should show exactly that set, not that set unioned
  // with whatever this browser had dimmed from an earlier session.
  if(!initial.hidden.length) initial.hidden = loadHidden();
  applyState(initial, false);
  syncTreeExpanded();
})();
]]
