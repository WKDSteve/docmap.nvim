---@module 'docmap.core.render.html.js.08_history_tree_treemap'
--- A slice of the page's script: History tab, Tree and Treemap.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // History tab: where each commit's diff radiates to.
  //
  // The only tab that is not computed from the embedded IR, and cannot be.
  // The analysis needs git and the *historical* artifacts, which means it
  // needs a server — a page opened as `file://` gets an opaque origin and
  // `fetch()` refuses the `file:` scheme outright, so "load it when clicked"
  // is only possible over http. `:DocMap serve` provides that.
  //
  // Opened from `file://` the tab must therefore explain itself rather than
  // fail: the committed map is the common case (it is what is in the repo),
  // and a tab that silently does nothing there would read as a bug. Same
  // treatment the class-based Hierarchy views give a map generated without
  // LuaLS.
  // =====================================================================
  var histLoaded = false, histCommits = null, histSelected = null;

  function historyAvailable(){ return location.protocol === "http:" || location.protocol === "https:"; }

  // Why a *served* page and a *published* one are not the same thing.
  //
  // `historyAvailable()` above tests the protocol, which answers "can this
  // page fetch at all" and nothing more. That was enough while the only two
  // cases were `file://` (cannot fetch) and `:DocMap serve` (a real docmap
  // server). Publishing the map to a static host adds a third: `https:`,
  // fetching works, and there is no server behind it. The four server-backed
  // panels then reported "Could not reach the map server — is it still
  // running? `:DocMap serve` starts it", which on a published page is advice
  // for a problem the reader does not have.
  //
  // Asked only on the failure path, so the normal case pays nothing: by the
  // time this runs a request has already failed, and one more tells the
  // reader which of the two situations they are in. `/api/ping` answers
  // `{"docmap":true}`; a static host answers its own 404, and any other
  // origin answers something that is not that.
  function explainFetchFailure(e, what){
    var detail = esc(String(e));
    return fetch("/api/ping", { cache: "no-store" })
      .then(function(r){ return r.ok ? r.json() : null; })
      .then(function(d){
        if(d && d.docmap === true){
          // A docmap server is there; this particular request still failed.
          return '<p class="hmsg">The map server is running, but ' + what +
            ' failed: ' + detail + '</p>';
        }
        return null;
      })
      .catch(function(){ return null; })
      .then(function(msg){
        if(msg) return msg;
        return '<p class="hmsg">This is a published copy of the map, so ' + what +
          ' has nothing to ask.<br><br>' + what.charAt(0).toUpperCase() + what.slice(1) +
          ' is computed on demand by a local server — it reads your working tree, your ' +
          'git history and your runtime data, none of which exist here.<br><br>' +
          'Run <code>:DocMap serve</code> in the repository and open the URL it prints.</p>';
      });
  }

  function histOffline(msg){
    document.getElementById("hist-list").innerHTML = "";
    document.getElementById("hist-detail").innerHTML = msg;
  }

  function drawHistory(sha){
    if(!historyAvailable()){
      histOffline(
        '<p class="hmsg">This page was opened from a file, so the History tab has nothing to ask.<br><br>' +
        'The commit analysis is computed on demand from <code>git</code> and the map committed at each ' +
        'revision — that needs a server, because a <code>file://</code> page is not allowed to fetch ' +
        'anything.<br><br>Run <code>:DocMap serve</code> and open the URL it prints ' +
        '(or <code>:DocMap open</code> while it runs).</p>'
      );
      return;
    }
    if(!histLoaded){
      histLoaded = true;
      document.getElementById("hist-list").innerHTML = '<p class="hmsg">Loading commits…</p>';
      fetch("/api/commits?n=100")
        .then(function(r){ return r.json(); })
        .then(function(d){
          histCommits = d.commits || [];
          renderHistList();
          if(state.sha) loadCommit(state.sha);
        })
        .catch(function(e){
          histLoaded = false;
          explainFetchFailure(e, "the History tab").then(histOffline);
        });
      return;
    }
    renderHistList();
    if(sha) loadCommit(sha);
  }

  function renderHistList(){
    var host = document.getElementById("hist-list");
    if(!histCommits || histCommits.length === 0){
      host.innerHTML = '<p class="hmsg">No commits.</p>';
      return;
    }
    host.innerHTML = histCommits.map(function(c){
      return '<div class="crow' + (c.sha === histSelected ? " sel" : "") +
        '" data-sha="' + esc(c.sha) + '">' +
        '<div class="csub">' + esc(c.subject) + "</div>" +
        '<div class="cmeta">' + esc(c.short) + " · " + esc(c.date) + " · " + esc(c.author) +
        "</div></div>";
    }).join("");
    host.querySelectorAll(".crow").forEach(function(row){
      row.addEventListener("click", function(){
        navigate({ tab: "history", sha: row.dataset.sha });
      });
    });
  }

  function loadCommit(sha){
    if(histSelected === sha && document.getElementById("hist-detail").dataset.sha === sha) return;
    histSelected = sha;
    renderHistList();
    var det = document.getElementById("hist-detail");
    det.innerHTML = '<p class="hmsg">Analysing ' + esc(sha.slice(0, 8)) + "…</p>";
    fetch("/api/commit/" + encodeURIComponent(sha))
      .then(function(r){ return r.json(); })
      .then(function(d){
        if(d.error){ det.innerHTML = '<p class="hmsg">' + esc(d.error) + "</p>"; return; }
        det.dataset.sha = sha;
        det.innerHTML = renderCommitDetail(d);
        wireCommitDetail(det);
      })
      .catch(function(e){
        explainFetchFailure(e, "the History tab").then(function(msg){ det.innerHTML = msg; });
      });
  }

  // Module chips link into the rest of the page like any other cross-
  // reference — but only when the node still exists in the *current* map. A
  // commit can name a module that has since been renamed or deleted, and a
  // link that navigates nowhere is worse than plain text saying so.
  function modChips(ids, names){
    if(!ids || ids.length === 0) return '<p class="ntext none">None.</p>';
    return '<div class="hist-mods">' + ids.map(function(id){
      var label = esc((names && names[id]) || id);
      return byId[id]
        ? '<a data-node="' + esc(id) + '">' + label + "</a>"
        : '<span class="gone" title="not in the current map">' + label + "</span>";
    }).join("") + "</div>";
  }

  function renderCommitDetail(d){
    var c = d.commit, im = d.impact, names = d.names || {};
    var out = [];

    out.push("<h2>" + esc(c.subject) + "</h2>");
    out.push('<div class="mp">' + esc(c.short) + " · " + esc(c.date) + " · " + esc(c.author) + "</div>");
    if(c.body) out.push('<div class="prose">' + esc(c.body) + "</div>");

    if(!d.has_map){
      out.push('<div class="hist-approx">This revision predates the committed map, so nothing ' +
        "could be attributed to functions — only the changed files are known.</div>");
    } else if(im.approximate){
      out.push('<div class="hist-approx">Function spans were <b>approximated</b> for at least one ' +
        "file: the map at this revision predates <code>line_end</code>, so a function's extent was " +
        "taken as \"up to the next one\". Attribution errs toward over-reaching into the gaps " +
        "between functions.</div>");
    }

    out.push('<div class="sec">Touched functions <span class="sub">' + im.touched.length + "</span></div>");
    if(im.touched.length === 0){
      out.push('<p class="ntext none">No scanned function contains any of the changed lines.</p>');
    } else {
      im.touched.forEach(function(t){
        var callers = (im.callers || {})[t.node + "#" + t.fn] || [];
        out.push('<div class="hist-fn">' + esc(t.signature || t.fn) +
          '  <span class="cmeta">' + esc(names[t.node] || t.node) + ":" + t.line + "</span></div>");
        if(callers.length === 0){
          out.push('<ul class="hist-callers"><li>no resolved caller in the tree</li></ul>');
        } else {
          out.push('<ul class="hist-callers">' + callers.map(function(x){
            return "<li>← " + esc(x.fn || "?") + "  (" + esc(names[x.node] || x.node) + ")</li>";
          }).join("") + "</ul>");
        }
      });
    }

    out.push('<div class="sec">Calling modules <span class="sub">precise — they hold a call site</span></div>');
    out.push(modChips(im.calling_modules, names));
    out.push('<div class="sec">Impacted modules <span class="sub">transitive, via required_by</span></div>');
    out.push(modChips(im.impacted_modules, names));

    if(im.unattributed && im.unattributed.length){
      out.push('<div class="sec">Changed, nothing to trace <span class="sub">' +
        im.unattributed.length + "</span></div>");
      out.push('<ul class="lst">' + im.unattributed.map(function(p){
        return "<li>" + esc(p) + "</li>";
      }).join("") + "</ul>");
    }

    out.push('<div class="sec">Diff <span class="sub">generated map excluded</span></div>');
    out.push('<div class="hist-diff">' + colorDiff(d.diff || "") + "</div>");
    return out.join("");
  }

  // Minimal diff colouring: enough to read, and done by line prefix rather
  // than by parsing, because the only thing that matters visually here is
  // added / removed / hunk header.
  function colorDiff(text){
    if(!text) return '<span class="dm">(empty)</span>';
    return text.split("\n").map(function(l){
      var cls = "";
      if(l.charAt(0) === "+") cls = "da";
      else if(l.charAt(0) === "-") cls = "dd";
      else if(l.slice(0, 2) === "@@") cls = "dh";
      else if(l.slice(0, 4) === "diff" || l.slice(0, 5) === "index") cls = "dm";
      return cls ? '<span class="' + cls + '">' + esc(l) + "</span>" : esc(l);
    }).join("\n");
  }

  function wireCommitDetail(det){
    det.querySelectorAll(".hist-mods a[data-node]").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
  }

  // `forceCenter`: used only by the search box's live-typing preview below,
  // which calls this directly rather than through navigate() (see that
  // handler's own comment for why) and so never goes through navigate()'s
  // own center-clears-hideroot logic. Without it, live-typing a match while
  // a root-hidden forest view was up would silently keep drawing the
  // forest — `state.hideroot` unchanged, the typed match completely
  // ignored — until Enter's real navigate({center}) finally cleared it.
  // =====================================================================
  // Tree and Treemap: the Hierarchy for wide levels.
  //
  // The box views lay every level out as one row. A config with 300
  // namespaces gives rows wider than any window (bindings.mappings alone
  // requires a dozen modules side by side) and the Modules view hits the
  // 90-box cap. These two views read the same `children` tree without
  // layers: Tree turns a level into a list (folding, a filter, the
  // keyboard), Treemap turns it into an area and shows where the weight is.
  // Both draw into #halt, outside #hgraph-wrap, whose wheel zooms the
  // diagram - a list has to scroll. Rows and tiles carry `data-id`, so the
  // context menu (describeTarget) works on them unchanged.
  // =====================================================================
  var halt = document.getElementById("halt");
  var haltBar = document.getElementById("halt-bar");
  var haltBody = document.getElementById("halt-body");
  function isAltView(v){ return v === "tree" || v === "treemap" || v === "coupling"; }

  // Which rows are open, by node id. The reader's, not the map's: it does
  // not ride in the URL (a link carries the center and the filter, which is
  // what it takes to show the same thing).
  var treeOpen = {};

  // Folders first, then by name: the order a file tree has.
  function kidsOf(id){
    var n = byId[id];
    return ((n && n.children) || []).filter(function(c){ return !!byId[c]; })
      .sort(function(a, b){
        var na = byId[a], nb = byId[b];
        var ga = (na.children && na.children.length) ? 0 : 1;
        var gb = (nb.children && nb.children.length) ? 0 : 1;
        if(ga !== gb) return ga - gb;
        var la = (na.name || a).toLowerCase(), lb = (nb.name || b).toLowerCase();
        return la < lb ? -1 : (la > lb ? 1 : 0);
      });
  }

  function statOf(n, metric){
    var s = n.stats || {};
    return metric === "functions" ? (s.functions || 0) : (s.lines || 0);
  }

  // The filter matches name, module and summary; a match keeps every
  // ancestor up to the center, so the reader sees where it sits.
  function treeMatches(rootId, q){
    var keep = {}, hit = {};
    q = q.toLowerCase();
    (function walk(id){
      var n = byId[id];
      var self = ((n.name || "") + " " + (n.module || "") + " " + (n.summary || "")).toLowerCase().indexOf(q) !== -1;
      var any = false;
      kidsOf(id).forEach(function(c){ if(walk(c)) any = true; });
      if(self) hit[id] = true;
      if(self || any) keep[id] = true;
      return self || any;
    })(rootId);
    return { keep: keep, hit: hit };
  }

  function cssEsc(s){
    return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\]/g, "\\$&");
  }

  function treeBar(){
    if(haltBar.querySelector("#htq")) return;
    haltBar.innerHTML =
      '<input id="htq" type="search" placeholder="Filter by name, module or summary" aria-label="Filter the tree">' +
      '<button id="htopen" type="button">Expand all</button><button id="htclose" type="button">Collapse</button>' +
      '<span id="htcount" class="hmuted"></span>';
    var input = haltBar.querySelector("#htq");
    input.addEventListener("input", function(){
      // Replaces the history entry instead of pushing one per keystroke, and
      // redraws only the list: the input keeps its focus and caret.
      state.tq = input.value || null;
      history.replaceState(state, "", serializeState(state));
      drawTree(hcenter);
    });
    input.addEventListener("keydown", function(ev){
      if(ev.key !== "ArrowDown") return;
      var first = haltBody.querySelector(".ht-row");
      if(first){ ev.preventDefault(); first.focus(); }
    });
    haltBar.querySelector("#htopen").addEventListener("click", function(){
      (function all(id){ treeOpen[id] = true; kidsOf(id).forEach(all); })(hcenter);
      drawTree(hcenter);
    });
    haltBar.querySelector("#htclose").addEventListener("click", function(){
      treeOpen = {};
      drawTree(hcenter);
    });
  }

  function drawTree(centerId){
    treeBar();
    var q = state.tq || "";
    var inputEl = haltBar.querySelector("#htq");
    if(document.activeElement !== inputEl) inputEl.value = q;

    var m = q ? treeMatches(centerId, q) : null;
    var rows = [], shown = 0;
    (function row(id, depth){
      if(m && !m.keep[id]) return;
      var n = byId[id];
      var kids = kidsOf(id);
      // The center is always open; with a filter every kept row is, or a
      // match three levels down would hide behind closed parents.
      var open = id === centerId || !!m || !!treeOpen[id];
      shown++;
      var st = n.stats || {};
      var nums = (st.lines ? st.lines + " lines" : "") + (st.functions ? " · " + st.functions + " fn" : "");
      rows.push(
        '<div class="ht-row' + (isHidden(id) ? " dim" : "") + (m && m.hit[id] ? " hit" : "") +
          '" role="treeitem" tabindex="-1" data-id="' + esc(id) + '"' +
          (kids.length ? ' aria-expanded="' + open + '"' : "") +
          ' aria-level="' + (depth + 1) + '" style="padding-left:' + (8 + depth * 18) + 'px">' +
        '<span class="ht-tw">' + (kids.length ? (open ? "▾" : "▸") : "") + "</span>" +
        '<span class="ht-name">' + esc(n.name || id) + "</span>" +
        '<span class="ht-kind">' + esc(n.kind || "") + (kids.length ? " · " + kids.length : "") + "</span>" +
        '<span class="ht-num">' + nums + "</span>" +
        (n.summary ? '<span class="ht-sum">' + prose(n.summary) + "</span>" : "") +
        "</div>"
      );
      if(open) kids.forEach(function(c){ row(c, depth + 1); });
    })(centerId, 0);

    haltBody.setAttribute("role", "tree");
    haltBody.innerHTML = rows.length ? rows.join("")
      : '<p class="hmsg">Nothing under ' + esc(byId[centerId].name || centerId) + " matches “" + esc(q) + "”.</p>";
    var first = haltBody.querySelector(".ht-row");
    if(first) first.tabIndex = 0;
    haltBar.querySelector("#htcount").textContent = q ? shown + " shown" : "";
  }

  function treeToggle(id, open){
    if(!kidsOf(id).length) return;
    treeOpen[id] = open === undefined ? !treeOpen[id] : open;
    drawTree(hcenter);
    var el = haltBody.querySelector('.ht-row[data-id="' + cssEsc(id) + '"]');
    if(el){ el.tabIndex = 0; el.focus(); }
  }

  haltBody.addEventListener("click", function(ev){
    if(!ev.target.closest) return;
    if(state.view === "tree"){
      var r = ev.target.closest(".ht-row");
      if(!r) return;
      // The triangle folds; the name re-roots the tree there, the same thing
      // a click on a box does in the other views.
      if(ev.target.closest(".ht-tw") || r.dataset.id === hcenter) treeToggle(r.dataset.id);
      else navigate({ center: r.dataset.id, fn: null });
      return;
    }
    var hit = ev.target.closest(".tm-tile, .tm-head");
    if(!hit) return;
    var id = hit.dataset.id || hit.parentNode.dataset.id;
    if(!byId[id]) return;
    // Zoom into anything that has children; a leaf opens where its detail
    // is, the Tree tab.
    if(kidsOf(id).length) navigate({ center: id, fn: null });
    else navigate({ tab: "tree", id: id });
  });

  haltBody.addEventListener("keydown", function(ev){
    if(state.view !== "tree" || !ev.target.closest) return;
    var r = ev.target.closest(".ht-row");
    if(!r) return;
    var all = Array.prototype.slice.call(haltBody.querySelectorAll(".ht-row"));
    var i = all.indexOf(r);
    var id = r.dataset.id;
    function go(el){
      if(!el) return;
      ev.preventDefault();
      all.forEach(function(x){ x.tabIndex = -1; });
      el.tabIndex = 0;
      el.focus();
    }
    if(ev.key === "ArrowDown") go(all[i + 1]);
    else if(ev.key === "ArrowUp"){
      if(i > 0) go(all[i - 1]);
      else { ev.preventDefault(); haltBar.querySelector("#htq").focus(); }
    }
    else if(ev.key === "Home") go(all[0]);
    else if(ev.key === "End") go(all[all.length - 1]);
    else if(ev.key === "ArrowRight"){
      ev.preventDefault();
      if(r.getAttribute("aria-expanded") === "false") treeToggle(id, true);
      else go(all[i + 1]);
    } else if(ev.key === "ArrowLeft"){
      ev.preventDefault();
      if(r.getAttribute("aria-expanded") === "true" && id !== hcenter && !state.tq) treeToggle(id, false);
      else {
        var p = byId[id] && byId[id].parent;
        if(p) go(haltBody.querySelector('.ht-row[data-id="' + cssEsc(p) + '"]'));
      }
    } else if(ev.key === "Enter"){
      ev.preventDefault();
      navigate({ center: id, fn: null });
    }
  });

  // Squarified treemap (Bruls, Huizing, van Wijk 2000): fill along the
  // shorter side, growing a row while that keeps its worst aspect ratio from
  // getting worse. `items` must be sorted largest first, values > 0.
  function squarify(items, x, y, w, h){
    var out = [];
    var total = items.reduce(function(a, it){ return a + it.v; }, 0);
    if(total <= 0 || w <= 0 || h <= 0) return out;
    var scale = (w * h) / total;
    var rest = items.map(function(it){ return { it: it, a: it.v * scale }; });
    function worst(row, side){
      var s = 0, mx = 0, mn = Infinity;
      row.forEach(function(r){ s += r.a; mx = Math.max(mx, r.a); mn = Math.min(mn, r.a); });
      return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn));
    }
    while(rest.length){
      // Written without two closing brackets in a row: anywhere in this page
      // they would end the Lua long string the script lives in.
      var side = Math.min(w, h), first = rest[0], row = [first], k = 1;
      while(k < rest.length){
        var next = rest[k];
        if(worst(row.concat([next]), side) > worst(row, side)) break;
        row.push(next); k++;
      }
      rest = rest.slice(k);
      var sum = row.reduce(function(a, r){ return a + r.a; }, 0);
      if(w >= h){
        var cw = sum / h, cy = y;
        row.forEach(function(r){ var rh = r.a / cw; out.push({ it: r.it, x: x, y: cy, w: cw, h: rh }); cy += rh; });
        x += cw; w -= cw;
      } else {
        var ch = sum / w, cx = x;
        row.forEach(function(r){ var rw = r.a / ch; out.push({ it: r.it, x: cx, y: y, w: rw, h: ch }); cx += rw; });
        y += ch; h -= ch;
      }
    }
    return out;
  }

  function weighed(id, metric){
    return kidsOf(id).map(function(c){ return { id: c, v: statOf(byId[c], metric) }; })
      .filter(function(it){ return it.v > 0; })
      .sort(function(a, b){ return b.v - a.v; });
  }

  // A tile's tooltip: name, weight and summary as plain text. esc, not
  // prose: a `title` attribute shows markup as markup.
  function titleOf(n, id, v, unit){ return esc(n.name || id) + " · " + v + unit + (n.summary ? " — " + esc(n.summary) : ""); }

  function tmBox(cls, id, r, label, inner){
    return '<div class="' + cls + (isHidden(id) ? " dim" : "") + '" data-id="' + esc(id) + '" title="' + label +
      '" style="left:' + r.x.toFixed(1) + "px;top:" + r.y.toFixed(1) + "px;width:" + r.w.toFixed(1) +
      "px;height:" + r.h.toFixed(1) + 'px">' + inner + "</div>";
  }

  function drawTreemap(centerId){
    var metric = state.tm === "functions" ? "functions" : "lines";
    var unit = metric === "lines" ? " lines" : " fn";
    haltBar.innerHTML =
      '<span class="hmuted">Area</span><div class="hview-toggle">' +
      '<button type="button" class="tm-metric' + (metric === "lines" ? " active" : "") + '" data-tm="lines">Lines</button>' +
      '<button type="button" class="tm-metric' + (metric === "functions" ? " active" : "") + '" data-tm="functions">Functions</button></div>' +
      '<span class="hmuted">click a group or tile to zoom in, a leaf opens in Tree · ▲ Up and the path go back</span>';
    haltBar.querySelectorAll(".tm-metric").forEach(function(b){
      b.addEventListener("click", function(){ navigate({ tm: b.dataset.tm === "functions" ? "functions" : null }); });
    });

    var kids = weighed(centerId, metric);
    if(!kids.length){
      haltBody.innerHTML = '<p class="hmsg">Nothing under ' + esc(byId[centerId].name || centerId) +
        " has any" + unit + " to weigh.</p>";
      return;
    }
    var W = Math.max(haltBody.clientWidth - 10, 320);
    var H = Math.max(Math.round(window.innerHeight - haltBody.getBoundingClientRect().top - 40), 360);
    var HEAD = 18, html = [];
    squarify(kids, 0, 0, W, H).forEach(function(r){
      var n = byId[r.it.id];
      var label = titleOf(n, r.it.id, r.it.v, unit);
      var name = esc(n.name || r.it.id);
      var sub = weighed(r.it.id, metric);
      // One nested level where there is room for it: the groups of the
      // center and what each is made of. Deeper is a click away.
      if(sub.length && r.w > 60 && r.h > HEAD + 24){
        var inner = '<div class="tm-head">' + name + " · " + r.it.v + unit + "</div>";
        squarify(sub, 2, HEAD, r.w - 6, r.h - HEAD - 4).forEach(function(c){
          var cn = byId[c.it.id];
          var cl = titleOf(cn, c.it.id, c.it.v, unit);
          inner += tmBox("tm-tile", c.it.id, c, cl, (c.w > 46 && c.h > 16) ? esc(cn.name || c.it.id) : "");
        });
        html.push(tmBox("tm-group", r.it.id, r, label, inner));
      } else {
        html.push(tmBox("tm-tile tm-solo", r.it.id, r, label, (r.w > 46 && r.h > 16) ? name : ""));
      }
    });
    haltBody.removeAttribute("role");
    haltBody.innerHTML = '<div class="tm" style="width:' + W + "px;height:" + H + 'px">' + html.join("") + "</div>";
  }

  function drawAltView(view){
    var center = byId[hcenter];
    hgraphWrap.style.display = "none";
    halt.hidden = false;
    clearGraph();
    hgraphWrap.parentNode.querySelectorAll(".htrunc").forEach(function(el){ el.remove(); });
    hlegendEl.innerHTML = view === "tree"
      ? '<span class="lg">click a name to root the tree there · ▸ folds · arrows, Enter, Home and End work · right-click for more</span>'
      : view === "coupling"
      ? '<span class="lg">a dot is a module at or below the center · the numbers count the whole tree · ' +
        'click or Enter opens it in the Tree tab · right-click for more</span>'
      : '<span class="lg">area = ' + (state.tm === "functions" ? "functions" : "lines of code") +
        ' · one level nested · right-click for more</span>';
    hpathEl.textContent = (center.module || center.path) + " · " + view;
    if(haltBar.dataset.view !== view) haltBar.innerHTML = "";
    haltBar.dataset.view = view;
    if(view === "tree") drawTree(hcenter);
    else if(view === "coupling") drawCoupling(hcenter);
    else drawTreemap(hcenter);
  }

  // How many edges of a graph view touch one node: requires for Deps, call
  // sites for Calls, calling module pairs for Module Calls.
  function graphDegree(view, id){
    if(view === "deps") return (depOut[id] || []).length + (depIn[id] || []).length;
    if(view === "modulecalls") return (moduleCallOut[id] || []).length + (moduleCallIn[id] || []).length;
    if(view === "calls"){
      var n = byId[id], d = 0;
      ((n && n.functions) || []).forEach(function(fn){
        var k = fnKey(id, fn.name);
        d += (callOut[k] || []).length + (callIn[k] || []).length;
      });
      return d;
    }
    return 0;
  }

  // The node a graph view starts on when nobody picked one. The root is a
  // folder: it requires nothing, declares no functions and calls nothing, so
  // Deps, Calls and Module Calls centered on it drew one lonely box (or "X
  // declares no functions") for every project, data or not - which read as
  // "these views are broken" on a map with a thousand edges in it. Ties go
  // to the id, so the same map always opens on the same node.
  function busiestFor(view){
    var best = null, bestDeg = 0;
    IR.nodes.forEach(function(n){
      var d = graphDegree(view, n.id);
      if(d > bestDeg || (d === bestDeg && d > 0 && best !== null && n.id < best)){
        best = n.id; bestDeg = d;
      }
    });
    return best;
  }

  // `implicitCenter`: the URL names no center, so the view may pick a better
  // one than the root (see busiestFor). A center somebody chose - a click, a
  // link, the search box - is always kept, empty or not.
  function drawHierarchy(centerId, view, forceCenter, implicitCenter){
    view = VIEWS[view] ? view : "modules";
    hcenter = (centerId && byId[centerId]) ? centerId : (hcenter && byId[hcenter] ? hcenter : IR.root);
    var autoCentered = false;
    if(implicitCenter && isGraphView(view) && graphDegree(view, hcenter) === 0){
      var busiest = busiestFor(view);
      if(busiest && busiest !== hcenter){ hcenter = busiest; autoCentered = true; }
    }
    var center = byId[hcenter];

    if(isAltView(view)){ drawAltView(view); return; }
    halt.hidden = true;
    hgraphWrap.style.display = "";

    hgraphWrap.parentNode.querySelectorAll(".htrunc").forEach(function(el){ el.remove(); });
    drawLegend(view);

    var depth = state.depth === 0 ? 0 : (state.depth || 2);

    // A centered function only applies while the center is still its own
    // node. The search box re-centers live as you type without touching the
    // rest of the state, so without this the Calls view would keep drawing
    // the previously focused function and quietly ignore what was typed.
    var wantFn = (state.fn && fnByKey[state.fn] && fnByKey[state.fn].node.id === hcenter)
      ? state.fn : null;

    var hidingRoot = !forceCenter && view === "modules" && (state.hideroot || 0) > 0;

    var built;
    if(view === "types") built = layoutTypes(hcenter);
    else if(view === "inheritance") built = layoutInheritance(hcenter);
    else if(view === "deps") built = layoutDeps(hcenter, state.dir || "out", depth, !!state.ext);
    else if(view === "calls") built = layoutCalls(hcenter, wantFn, state.dir || "out", depth);
    else if(view === "modulecalls") built = layoutModuleCalls(hcenter, state.dir || "out", depth, !!state.ext);
    else if(view === "rings") built = layoutRings(hcenter);
    else if(view === "layers") built = layoutLayers();
    else if(view === "routes") built = layoutRoutes(hcenter);
    else if(hidingRoot) built = layoutModulesRooted(state.hideroot);
    else built = layoutModules(hcenter);

    // A graph view whose walk found boxes but not one edge between them is
    // empty too: the center alone (Deps, Module Calls) or its functions side
    // by side (Calls) answer nothing, and said nothing about why.
    if(built.count === 0 || (isGraphView(view) && built.edges && built.edges.length === 0)){
      clearGraph();
      hpathEl.textContent = hidingRoot
        ? (state.hideroot + " root level" + (state.hideroot === 1 ? "" : "s") + " hidden")
        : (center.module || center.path);
      hgraph.style.width = ""; hgraph.style.height = "";
      hstage.style.width = ""; hstage.style.height = "";
      // Cleared, not just left behind: applyZoom() multiplies this by the
      // scale, so a stale extent would give an empty message a scroll area
      // thousands of pixels wide the moment the wheel is touched.
      stageExtent = { w: 0, h: 0 };
      // Into #hgraph, not #hstage: the stage is position:absolute (it carries
      // the zoom transform), so it contributes no height to its parent, and
      // #hgraph's explicit height was just cleared above — a message parented
      // to the stage therefore renders into a 0px-tall box and is clipped away
      // by #hgraph-wrap's overflow. Every empty state in this tab was
      // invisible for that reason; a normal-flow child of the relative #hgraph
      // gives it height on its own, with nothing measured off the DOM (which
      // would read 0 anyway while the pane is display:none).
      hgraph.insertAdjacentHTML("beforeend", emptyMessage(view, center));
      return;
    }

    var suffix = { types: " · types", inheritance: " · inheritance",
                   deps: " · deps", calls: " · calls",
                   modulecalls: " · module calls", rings: " · rings" }[view] || "";
    // A view that names its own middle (the entry of the Rings) is about
    // that, not about the folder the Hierarchy happens to be centered on.
    if(isMapView(view) && built.centerKey && byId[built.centerKey]) center = byId[built.centerKey];
    var focusFn = view === "calls" && wantFn;
    if(hidingRoot){
      hpathEl.textContent = state.hideroot + " root level" + (state.hideroot === 1 ? "" : "s") +
        " hidden — " + (built.layers[0] ? built.layers[0].length : 0) + " subtree" +
        ((built.layers[0] && built.layers[0].length === 1) ? "" : "s") + " shown";
    } else {
      hpathEl.textContent = (focusFn ? wantFn.split("#")[1] + "  in  " : "") +
        (center.module || center.path) + suffix +
        (isGraphView(view) ? "  ·  " + (state.dir || "out") + ", depth " + (depth === 0 ? "∞" : depth) : "");
    }
    // A view of the whole tree has no center to name.
    if(built.path) hpathEl.textContent = built.path;

    // The empty branch above writes its explanation straight into #hgraph;
    // nothing else removes it, because reconcile() only ever adds and removes
    // boxes it knows about. Without this, going Calls-on-a-namespace (empty)
    // → Modules left "lib.nvim declares no functions." sitting above a
    // ninety-box diagram.
    var stale = hgraph.querySelector(".hmsg");
    if(stale) stale.remove();

    // A view may bring positions of its own (the Rings); every other one is
    // layers, and layers become positions here.
    var laid = built.positions ? { positions: built.positions, maxRowWidth: 0 } : layerPositions(built.layers);
    var positions = laid.positions;

    // The key the view considers "the middle": a node id in three views, a
    // function id in Calls. Used for the highlight ring and the scroll
    // target, so both follow whatever the view is actually about.
      renderCrumb();
    var lrBtn = document.getElementById("hlr");
    if(lrBtn) lrBtn.classList.toggle("active", isLR());
  var centerKey = hcenter;
    if(view === "types") centerKey = built.layers[0] && built.layers[0][0];
    else if(view === "inheritance" || view === "routes" || isMapView(view)) centerKey = built.centerKey;
    else if(view === "calls") centerKey = wantFn || (built.layers[0] && built.layers[0][0]);
    // A forest has no single "middle" — every layer-0 box is equally a
    // root, so none of them gets the highlight ring a real center would.
    else if(hidingRoot) centerKey = null;

    var moved = reconcile(positions, view, centerKey);
    applyTint();
    if(built.paint) built.paint();

    // The layer axis and the spread axis swap with the orientation; the
    // canvas has to swap with them or half the graph is outside it.
    var depth = built.layers.length;
    var alongLayers = PAD * 2 + depth * (isLR() ? BOX_W : BOX_H) +
      Math.max(0, depth - 1) * (isLR() ? GAP_X : GAP_Y);
    var totalW = isLR() ? alongLayers : laid.maxRowWidth + PAD * 2;
    var totalH = isLR() ? laid.maxRowWidth + PAD * 2 : alongLayers;
    if(built.extent){ totalW = built.extent.w; totalH = built.extent.h; }

    var svgNS = "http://www.w3.org/2000/svg";
    var old = document.getElementById("hsvg");
    if(old) old.remove();
    var oldTop = document.getElementById("hsvg2");
    if(oldTop) oldTop.remove();
    // A second layer over the boxes, for the edges a view must not let a box
    // hide (a require that breaks a layer rule). Made on demand.
    var svgTop = null;
    var svg = document.createElementNS(svgNS, "svg");
    svg.id = "hsvg";
    svg.setAttribute("width", totalW);
    svg.setAttribute("height", totalH);
    svg.appendChild(buildDefs(svgNS));
    if(built.decor) built.decor(svg, svgNS);

    // Edge geometry cannot be interpolated the way a box position can — `d`
    // is not an animatable CSS property, and a per-frame path interpolator
    // for up to 90 edges buys very little over simply not drawing lines that
    // would be pointing at boxes still in motion. So: hidden while the boxes
    // move, faded in once they have arrived.
    // Both directions of a pair are separate edge objects (`pairKey` is
    // `from + " " + to`), so the reverse call count is a lookup away rather
    // than something to recompute. Built once per draw, not per hover.
    var weightByPair = {};
    built.edges.forEach(function(e){
      if(e.weight) weightByPair[e.from + " " + e.to] = e.weight;
    });

    var neighbours = {};
    built.edges.forEach(function(e){
      var a = positions[e.from], b = positions[e.to];
      if(!a || !b || e.from === e.to) return;
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", built.edgePath ? built.edgePath(a, b) : edgePath(a, b));
      p.setAttribute("class", e.cls);
      p.setAttribute("marker-end", "url(#m-" + (e.marker || "tree") + ")");
      // Weighted edges (Module Calls) get a thicker stroke for more calls —
      // log-scaled so one outlier pair doesn't flatten every other edge to a
      // hairline. Set via inline style, not a `stroke-width` attribute: the
      // `.hedge{stroke-width:1.5}` CSS rule would win over a presentation
      // attribute but not over an inline style.
      if(e.weight){
        p.style.strokeWidth = String(Math.min(1.5 + Math.log2(e.weight) * 1.1, 7));
      }
      p.dataset.from = e.from;
      p.dataset.to = e.to;
      if(e.label){
        var title = document.createElementNS(svgNS, "title");
        title.textContent = e.label;
        p.appendChild(title);
      }
      if(e.top){
        if(!svgTop){
          svgTop = document.createElementNS(svgNS, "svg");
          svgTop.id = "hsvg2";
          svgTop.setAttribute("width", totalW);
          svgTop.setAttribute("height", totalH);
        }
        svgTop.appendChild(p);
      } else svg.appendChild(p);
      // The hover companion, added after its own edge so it sits on top and
      // wins the pointer. Only where there is something to read: an
      // unweighted tree edge has no count to show, and giving every edge a
      // 14px hit area would make the graph's own boxes harder to reach.
      if(e.weight){
        var hit = document.createElementNS(svgNS, "path");
        hit.setAttribute("d", edgePath(a, b));
        hit.setAttribute("class", "hedge-hit");
        edgeHover(hit, p, e, weightByPair);
        svg.appendChild(hit);
      }
      (neighbours[e.from] = neighbours[e.from] || {})[e.to] = true;
      (neighbours[e.to] = neighbours[e.to] || {})[e.from] = true;
    });

    // What a view writes over its edges (the names of the rings).
    if(built.overlay) built.overlay(svg, svgNS);

    hstage.style.width = totalW + "px";
    hstage.style.height = totalH + "px";
    hstage.insertBefore(svg, hstage.firstChild);
    if(svgTop) hstage.appendChild(svgTop);
    stageExtent = { w: totalW, h: totalH };
    applyZoom();

    if(moved){
      svg.classList.add("settling");
      if(svgTop) svgTop.classList.add("settling");
      setTimeout(function(){
        svg.classList.remove("settling");
        if(svgTop) svgTop.classList.remove("settling");
      }, ANIM_MS);
    }

    hgraphNeighbours = built.neighbours || neighbours;
    hgraphEdgeNear = built.edgeNear || null;

    // Rows are centered on the widest layer, so the centered box can sit
    // thousands of pixels from the left edge on a wide map — without this,
    // opening the tab scrolls to (0,0) and shows an arbitrary fragment of
    // whichever layer is widest, not the node the view is actually about.
    // After a zoom-driven jump the cursor is the anchor: re-centering the
    // view here would yank the diagram out from under the pointer the gesture
    // is still on. The flag is consumed once, so ordinary navigation keeps
    // its centering.
    var selfPos = (centerKey && !suppressAutoScroll) ? positions[centerKey] : null;
    if(suppressAutoScroll){ suppressAutoScroll = false; }
    if(selfPos){
      var targetLeft = Math.max(0, selfPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      var targetTop = Math.max(0, selfPos.y - hgraphWrap.clientHeight / 2 + BOX_H);
      if(moved && !reducedMotion()){
        hgraphWrap.scrollTo({ left: targetLeft, top: targetTop, behavior: "smooth" });
      } else {
        hgraphWrap.scrollLeft = targetLeft;
        hgraphWrap.scrollTop = targetTop;
      }
      var centerEl = hboxes[centerKey];
      if(centerEl && !reducedMotion()){
        centerEl.classList.remove("pulse");
        void centerEl.offsetWidth;
        centerEl.classList.add("pulse");
      }
    }

    if(autoCentered){
      var auto = document.createElement("div");
      auto.className = "htrunc hauto";
      auto.textContent = "Started on " + (center.module || center.name) + ", the node with the most " +
        { deps: "requires", calls: "calls", modulecalls: "module calls" }[view] +
        " — the root has none of its own. Click a box or search to re-center.";
      hgraphWrap.parentNode.insertBefore(auto, hgraphWrap.nextSibling);
    }

    var noteEl = isMapView(view) ? mapNote(view) : null;
    if(noteEl) hgraphWrap.parentNode.insertBefore(noteEl, hgraphWrap.nextSibling);

    if(built.truncated){
      var note = document.createElement("div");
      note.className = "htrunc";
      note.textContent = built.truncNote || "Showing the first " + MAX_HNODES + " boxes — narrow the depth, or double-click a box to re-center on a smaller neighbourhood.";
      hgraphWrap.parentNode.insertBefore(note, hgraphWrap.nextSibling);
    }
  }

  function reducedMotion(){
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

]]
