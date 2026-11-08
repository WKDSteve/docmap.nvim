---@module 'docmap.core.render.html.js.07_analysis_panels'
--- A slice of the page's script: Analysis tab (second part).
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // ---------------------------------------------------------------------
  // Analysis -> Telemetry: the runtime-analysis.nvim join, on demand.
  //
  // Not computed from the embedded IR, and cannot be: call counts change
  // between runs, and baking them into `module_map.json` would make
  // `--check`'s byte-for-byte comparison depend on when it happened to run
  // relative to real usage — the same reason `core/tools.lua`'s own header
  // keeps host-presence checks out of the artifact, one step further
  // (there, the *shape* is deterministic and only presence is not; here,
  // the counts themselves are the volatile part). `/api/telemetry` reads
  // `runtime-analysis.telemetry` straight off disk on every request, so
  // this is always the latest aggregate, never a stale snapshot baked in
  // at generate() time — see `docmap.editor.serve`'s own header for
  // why that means a server, exactly the History tab's own reasoning.
  //
  // `state.tsnap` (which capture the single-view table reads) and
  // `state.tsnapb` (set only in compare mode — `null` means "not
  // comparing", the string `"latest"` means "compare against the live
  // aggregate explicitly", anything else is a snapshot name) both default
  // to `null`/`"latest"` meaning the live aggregate, matching what this
  // panel always showed before named snapshots existed. Threaded through
  // `navigate()`/the URL the same way `atool`/`asort` already are, so a
  // link to a specific comparison is shareable.
  // ---------------------------------------------------------------------
  var telSnapLoaded = false, telSnapList = null;
  var telCache = {}, telReqToken = 0;

  // Fetch (and cache) /api/telemetry's response for one capture. `name` is
  // null/"latest" for the live aggregate, otherwise a snapshot name — both
  // forms state.tsnap/state.tsnapb can hold.
  function telFetch(name){
    var key = (!name || name === "latest") ? "" : name;
    if(telCache[key]) return Promise.resolve(telCache[key]);
    var url = key ? ("/api/telemetry?snapshot=" + encodeURIComponent(key)) : "/api/telemetry";
    return fetch(url).then(function(r){ return r.json(); }).then(function(d){
      telCache[key] = d;
      return d;
    });
  }

  function drawAnalysisTelemetry(){
    var host = document.getElementById("anbody");
    if(!historyAvailable()){
      host.innerHTML = '<p class="hmsg">This page was opened from a file, so the Telemetry panel has ' +
        'nothing to ask.<br><br>Call counts live outside the committed map on purpose — they change between ' +
        'runs, which the committed artifact never does — so reading them needs a server. Run ' +
        '<code>:DocMap serve</code> and open the URL it prints (or <code>:DocMap open</code> while it runs).</p>';
      return;
    }

    var token = ++telReqToken;
    host.innerHTML = '<p class="hmsg">Loading telemetry…</p>';

    var snapListPromise = telSnapLoaded
      ? Promise.resolve(telSnapList)
      : fetch("/api/telemetry/snapshots").then(function(r){ return r.json(); }).then(function(d){
          telSnapLoaded = true;
          telSnapList = (d && d.snapshots) || [];
          return telSnapList;
        }).catch(function(){ telSnapLoaded = true; telSnapList = []; return telSnapList; });

    var fetches = [telFetch(state.tsnap)];
    if(state.tsnapb) fetches.push(telFetch(state.tsnapb));

    Promise.all([snapListPromise].concat(fetches))
      .then(function(results){
        if(token !== telReqToken) return; // a newer selection superseded this one
        renderAnalysisTelemetryBody(results[1], state.tsnapb ? results[2] : null);
      })
      .catch(function(e){
        if(token !== telReqToken) return;
        explainFetchFailure(e, "the Telemetry panel").then(function(msg){
          // The token is re-checked after the probe: a newer selection may
          // have superseded this one while it was in flight.
          if(token === telReqToken) host.innerHTML = msg;
        });
      });
  }

  // The picker row: "Snapshot:" (single view) plus, once at least one
  // snapshot exists, a "Compare vs:" second select that switches into the
  // diff render below. Rendered even with zero snapshots saved yet — the
  // "Snapshot:" select still lets a reader pick "Latest" explicitly, and
  // an empty picker row would read as a missing feature rather than "no
  // snapshots saved yet".
  // {v, l} (value, label) objects to <option> HTML, marking whichever
  // matches "selected" -- one small builder instead of the fragile "join
  // then string-replace the right value= in afterward" a first draft of
  // this used, which risked matching the wrong option whenever one value
  // was a substring of another. Objects rather than [value, label]
  // tuples for a second, entirely mechanical reason: this whole script is
  // one Lua long-bracket string, and two adjacent closing square brackets
  // anywhere inside it -- which a tuple array closing right after a
  // nested one produces -- close that Lua string early. Not a style
  // preference; the first draft of this function shipped with exactly
  // that bug.
  function telOptionsHTML(items, selected){
    return items.map(function(it){
      return '<option value="' + esc(it.v) + '"' + (it.v === selected ? " selected" : "") + '>' +
        esc(it.l) + "</option>";
    }).join("");
  }

  function telPickerHTML(){
    var aItems = [{ v: "", l: "Latest" }].concat((telSnapList || []).map(function(s){
      var d = new Date(s.saved_at * 1000);
      return { v: s.name, l: s.name + " (" + d.toLocaleString() + ")" };
    }));
    var h = ['<div class="telpicker">'];
    h.push('<label>Snapshot: <select id="telsnap">' +
      telOptionsHTML(aItems, state.tsnap || "") + '</select></label>');
    if((telSnapList || []).length > 0){
      var bItems = [{ v: "", l: "— not comparing —" }, { v: "latest", l: "Latest" }]
        .concat((telSnapList || []).map(function(s){ return { v: s.name, l: s.name }; }));
      h.push('<label>Compare vs: <select id="telsnapb">' +
        telOptionsHTML(bItems, state.tsnapb || "") + '</select></label>');
    }
    h.push("</div>");
    return h.join("");
  }

  function telWirePicker(){
    var snapSel = document.getElementById("telsnap");
    if(snapSel) snapSel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "telemetry", tsnap: snapSel.value || null });
    });
    var snapBSel = document.getElementById("telsnapb");
    if(snapBSel) snapBSel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "telemetry", tsnapb: snapBSel.value || null });
    });
  }

  function telUnavailableMessage(d){
    var reason = (d && d.reason) || "unknown";
    if(reason === "no namespace"){
      return "No telemetry namespace configured for this project — set " +
        "<code>opts.telemetry_namespace</code> or <code>opts.title</code>.";
    }
    if(reason === "no map generated yet"){
      return "No map has been generated yet on this machine — run <code>:DocMap</code> first.";
    }
    if(reason === "snapshot not found"){
      return "Snapshot <code>" + esc((d && d.snapshot) || "") + "</code> was not found — it may have " +
        "been evicted (only the most recent ones are kept).";
    }
    return "No telemetry data for namespace <code>" + esc((d && d.namespace) || "") + "</code> yet — " +
      "install/enable <code>runtime-analysis.nvim</code>, or <code>:RATelemetry start</code> there.";
  }

  function renderAnalysisTelemetryBody(dA, dB){
    var host = document.getElementById("anbody");

    if(!dA || !dA.available){
      host.innerHTML = telPickerHTML() + '<p class="ntext none">' + telUnavailableMessage(dA) + '</p>';
      telWirePicker();
      return;
    }
    if(dB !== null && (!dB || !dB.available)){
      host.innerHTML = telPickerHTML() + '<p class="ntext none">' + telUnavailableMessage(dB) + '</p>';
      telWirePicker();
      return;
    }

    var parts = [telPickerHTML()];

    if(dB === null){
      // Single-capture view — unchanged from before the picker existed,
      // just fed by whichever capture is currently selected instead of
      // always the live aggregate.
      var totalRows = (dA.rows || []).length;
      var rows = anFilter((dA.rows || []).map(function(r){
        return {
          id: r.id, fn: r.fn, ir_key: r.ir_key, calls: r.calls,
          has_static_caller: r.has_static_caller,
          haystack: r.ir_key, sortkey: r.ir_key
        };
      }));

      if(totalRows === 0){
        parts.push('<p class="ntext none">Telemetry namespace <code>' + esc(dA.namespace) +
          '</code> has data, but none of it resolved to a function still in this map.</p>');
        host.innerHTML = parts.join("");
        telWirePicker();
        return;
      }

      var cols = [
        { label: "Function", key: "ir_key", get: function(r){ return r.ir_key; }, initial: "asc" },
        { label: "Calls", key: "calls", get: function(r){ return r.calls; }, initial: "desc" },
        { label: "Static caller?", key: "has_static_caller",
          get: function(r){ return r.has_static_caller ? 1 : 0; }, initial: "desc" }
      ];
      anSort(rows, cols, function(a, b){ return b.calls - a.calls; });

      parts.push('<p class="nsub">' + rows.length + ' function' + (rows.length === 1 ? '' : 's') +
        ' with telemetry data in namespace <code>' + esc(dA.namespace) + '</code>' +
        (state.tsnap ? ' (snapshot ' + esc(state.tsnap) + ')' : ' (latest)') + '.' +
        anFilterNote(rows.length, totalRows) + '</p>');
      if(rows.length === 0){
        parts.push('<p class="ntext none">No function matches that filter.</p>');
        host.innerHTML = parts.join("");
        telWirePicker();
        return;
      }
      parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
      rows.forEach(function(r){
        parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
          '<td><code>' + esc(r.ir_key) + '</code></td>' +
          '<td>' + r.calls + '</td>' +
          '<td>' + (r.has_static_caller ? "yes" : "no static caller found") + '</td>' +
          '</tr>');
      });
      parts.push("</tbody></table>");
      host.innerHTML = parts.join("");
      host.querySelectorAll(".anrow").forEach(function(tr){
        tr.addEventListener("click", function(){
          navigate({ tab: "tree", id: tr.dataset.node });
        });
      });
      telWirePicker();
      return;
    }

    // A/B diff — the point of naming snapshots at all: "what changed
    // between these two captures", not just "what does one look like".
    // Union of both sides' functions, not an intersection: a function only
    // one side has data for is exactly as real a result as one both do —
    // it either did not exist yet, or was never called, at the other
    // point in time, which is itself the answer to "what changed".
    var byKeyA = {}, byKeyB = {};
    (dA.rows || []).forEach(function(r){ byKeyA[r.ir_key] = r; });
    (dB.rows || []).forEach(function(r){ byKeyB[r.ir_key] = r; });
    var allKeys = Object.keys(byKeyA);
    Object.keys(byKeyB).forEach(function(k){ if(!(k in byKeyA)) allKeys.push(k); });

    var diffRows = anFilter(allKeys.map(function(k){
      var ra = byKeyA[k], rb = byKeyB[k];
      var callsA = ra ? ra.calls : 0, callsB = rb ? rb.calls : 0;
      return {
        id: (ra || rb).id, ir_key: k, callsA: callsA, callsB: callsB,
        delta: callsB - callsA, haystack: k, sortkey: k
      };
    }));

    var cols = [
      { label: "Function", key: "ir_key", get: function(r){ return r.ir_key; }, initial: "asc" },
      { label: "A", key: "callsA", get: function(r){ return r.callsA; }, initial: "desc" },
      { label: "B", key: "callsB", get: function(r){ return r.callsB; }, initial: "desc" },
      { label: "Δ (B − A)", key: "delta", get: function(r){ return Math.abs(r.delta); }, initial: "desc" }
    ];
    anSort(diffRows, cols, function(a, b){ return Math.abs(b.delta) - Math.abs(a.delta); });

    var aLabel = state.tsnap ? esc(state.tsnap) : "latest";
    var bLabel = (state.tsnapb === "latest" || !state.tsnapb) ? "latest" : esc(state.tsnapb);
    parts.push('<p class="nsub">Comparing <code>' + aLabel + '</code> (A) against <code>' + bLabel +
      '</code> (B) — ' + diffRows.length + ' function' + (diffRows.length === 1 ? '' : 's') + '.' +
      anFilterNote(diffRows.length, allKeys.length) + '</p>');
    if(diffRows.length === 0){
      parts.push('<p class="ntext none">No function matches that filter.</p>');
      host.innerHTML = parts.join("");
      telWirePicker();
      return;
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    diffRows.forEach(function(r){
      var sign = r.delta > 0 ? "+" : "";
      parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
        '<td><code>' + esc(r.ir_key) + '</code></td>' +
        '<td>' + r.callsA + '</td>' +
        '<td>' + r.callsB + '</td>' +
        '<td class="' + (r.delta > 0 ? "telup" : r.delta < 0 ? "teldown" : "") + '">' +
          sign + r.delta + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    host.innerHTML = parts.join("");
    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });
    telWirePicker();
  }

  // ---------------------------------------------------------------------
  // Analysis -> Loaded: the runtime-analysis.loaded persisted-snapshot join,
  // "cold viewing" of a loaded-vs-declared diff taken
  // in a process that is not this one.
  //
  // Unlike Telemetry, there is no "live aggregate" fallback here: a loaded
  // diff is inherently a property of *some* live session's package.loaded,
  // and the only such session `:DocBrowse loaded` can read is the one the
  // browser was opened from — a browser tab, running in a different
  // process entirely, has no live package.loaded of its own to read. So
  // this panel only ever reads named snapshots (`:RA loaded snapshot
  // <prefix> [name]`, runtime-analysis.nvim's own §5.4 command) — never a
  // "Latest" option the way Telemetry's picker has one. `state.lsnap` is
  // `null` until a snapshot is actually chosen; the panel prompts for one
  // rather than guessing.
  // ---------------------------------------------------------------------
  var loadedSnapLoaded = false, loadedSnapList = null;
  var loadedCache = {};

  function loadedFetch(name){
    if(loadedCache[name]) return Promise.resolve(loadedCache[name]);
    return fetch("/api/loaded?snapshot=" + encodeURIComponent(name))
      .then(function(r){ return r.json(); })
      .then(function(d){ loadedCache[name] = d; return d; });
  }

  // ── Checklist ────────────────────────────────────────────────────────────
  //
  // The one Analysis panel whose data is baked but whose *verdict* is not.
  // `IR.checklist` carries the whole ledger, so every item, citation and
  // date renders from `file://` with no server. What cannot be baked is
  // whether the cited files have moved since verification: that comes from
  // `git log`, and core/churn.lua established that git data in a
  // byte-compared artifact leaves the map with no fixed point.
  //
  // So the panel renders twice — immediately from the IR, then again with
  // the verdict once `/api/checklist` answers. A reader on a static page
  // gets a complete ledger and a one-line note saying what is missing and
  // how to get it, rather than a blank panel.

  // Verdict by "<file>:<line>", or null before the fetch resolves / when
  // there is no server to ask.
  var checklistStatus = null, checklistFailed = false;
  var checklistTried = false;

  function checklistStateLabel(st){
    if(!st) return { cls: "cl-unknown", text: "—" };
    if(st.state === "stale"){
      return { cls: "cl-stale", text: st.commits + " commit" + (st.commits === 1 ? "" : "s") + " since" };
    }
    if(st.state === "unverified") return { cls: "cl-unverified", text: "never verified" };
    if(st.state === "uncited") return { cls: "cl-uncited", text: "no citation" };
    return { cls: "cl-current", text: "unchanged" };
  }

  function renderChecklistBody(){
    var led = IR.checklist;
    if(!led){
      return '<p class="ntext none">This repository has no checklist. Create ' +
        '<code>docs/CHECKLIST/*.md</code> (or <code>docs/CHECKLIST.md</code>) — ' +
        'see <code>docs/checklist_format.md</code>.</p>';
    }

    var out = [];
    var note;
    if(checklistStatus){
      var c = checklistStatus.counts || {};
      note = '<p class="ntext">' + (c.stale || 0) + ' stale, ' + (c.unverified || 0) +
        ' unverified, ' + (c.current || 0) + ' current, ' + (c.uncited || 0) +
        ' uncited — of ' + led.total + ' item' + (led.total === 1 ? "" : "s") + '.</p>';
    } else if(!historyAvailable() || checklistFailed){
      // `checklistFailed` covers the published copy: the protocol says
      // fetching is possible, the enrichment still cannot be answered, and
      // without this the note sat on "Reading history…" forever. The wording
      // below is already right for both — the verdict needs git *and* a local
      // server, neither of which a static host has.
      note = '<p class="ntext">' + led.done + ' of ' + led.total + ' done, ' + led.cited +
        ' cited. <em>Changed-since-verified needs git, so it is not in this file.</em> Run ' +
        '<code>:DocMap serve</code> and open the URL it prints to fill in the verdict — or ' +
        '<code>:DocMap checklist</code> for the same answer in the quickfix list.</p>';
    } else {
      note = '<p class="ntext">' + led.done + ' of ' + led.total + ' done, ' + led.cited +
        ' cited. Reading history…</p>';
    }
    out.push(note);

    (led.files || []).forEach(function(f){
      (f.sections || []).forEach(function(sec){
        if(!sec.items || sec.items.length === 0) return;
        var heading = sec.name || f.name;
        out.push('<h3 class="cl-h">' + esc(heading) +
          ' <span class="cl-src">' + esc(f.path) + '</span></h3>');
        out.push('<ul class="cl-list">');
        sec.items.forEach(function(it){
          var st = checklistStatus && checklistStatus.status
            ? checklistStatus.status[it.file + ":" + it.line] : null;
          var lab = checklistStateLabel(st);
          var bits = [];
          bits.push('<li class="cl-item ' + (it.done ? "cl-done" : "cl-open") + '">');
          bits.push('<span class="cl-box">' + (it.done ? "✓" : " ") + '</span>');
          bits.push('<span class="cl-text">' + esc(it.text) + '</span>');
          if(it.ref){
            bits.push('<span class="cl-ref">' + esc(it.ref) +
              (it.ref_line ? ":" + it.ref_line : "") + '</span>');
          }
          if(it.verified) bits.push('<span class="cl-date">verified ' + esc(it.verified) + '</span>');
          if(st) bits.push('<span class="cl-state ' + lab.cls + '">' + esc(lab.text) + '</span>');
          (it.meta || []).forEach(function(m){
            bits.push('<span class="cl-meta"><b>@' + esc(m.key) + '</b> ' + esc(m.value) + '</span>');
          });
          bits.push('</li>');
          out.push(bits.join(""));
        });
        out.push('</ul>');
      });
    });

    return out.join("");
  }

  // ---------------------------------------------------------------------
  // Analysis -> Startup: the flamegraph, already in this document.
  //
  // Nothing is built or fetched here. `core/startup_graph.lua` read the SVG
  // `:RATelemetry flamegraph` wrote, refused it unless it was the shape a
  // flamegraph has, and the document carries it inside
  // `<template id="startup-graph">`. This clones that node into the panel.
  //
  // **A node, not a string, and that is the reason this is not a case in
  // `renderAnalysis`.** Everything there returns HTML that reaches `#anbody`
  // through `innerHTML`, which would parse this content a second time —
  // once by the HTML parser at load, once by the assignment. Cloning a
  // `<template>`'s content parses it exactly once, at load, from bytes Lua
  // wrote after checking them. It also means a `<script>` could not run even
  // if one got this far, which is worth keeping as a second line behind
  // `startup_graph.is_safe` rather than instead of it.
  // ---------------------------------------------------------------------
  function drawAnalysisStartup(){
    var host = document.getElementById("anbody");
    var tpl = document.getElementById("startup-graph");

    if(!tpl){
      host.innerHTML = '<p class="ntext none">No startup flamegraph is baked ' +
        'into this page. It comes from <code>runtime-analysis.nvim</code>: ' +
        'measure a session (<code>telemetry.startup.autostart()</code> from ' +
        'that plugin\'s own lazy.nvim <code>init</code> hook), run ' +
        '<code>:RATelemetry flamegraph</code>, then regenerate the map.</p>';
      return;
    }

    var when = tpl.dataset.measured ? " Measured " + tpl.dataset.measured + "." : "";
    host.innerHTML = '<p class="nsub">Startup attribution from ' +
      '<code>runtime-analysis.nvim</code>: width is total time, depth is ' +
      'require nesting, one colour per module root.' + esc(when) +
      ' Baked in at generation time — unlike Telemetry and Loaded this needs ' +
      'no <code>:DocMap serve</code>.</p>';

    var frame = document.createElement("div");
    frame.className = "startup-graph";
    frame.appendChild(document.importNode(tpl.content, true));
    host.appendChild(frame);
  }

  function drawAnalysisChecklist(){
    var host = document.getElementById("anbody");
    host.innerHTML = renderChecklistBody();

    // One fetch per page load, not per panel open: the answer only changes
    // when someone commits, and re-asking on every tab switch would spawn a
    // whole-history `git log` each time.
    if(!IR.checklist || checklistTried || !historyAvailable()) return;
    checklistTried = true;

    fetch("/api/checklist").then(function(r){ return r.json(); }).then(function(d){
      if(d && d.available) checklistStatus = d;
      if(state.tab === "analysis" && state.atool === "checklist"){
        document.getElementById("anbody").innerHTML = renderChecklistBody();
      }
    }).catch(function(){
      // Still silent — the panel above is already complete and correct
      // without a verdict, and a scary error over a missing enrichment would
      // overstate what went wrong. But the note has to stop claiming it is
      // still reading, which is what this flag is for.
      checklistFailed = true;
      if(state.tab === "analysis" && state.atool === "checklist"){
        document.getElementById("anbody").innerHTML = renderChecklistBody();
      }
    });
  }

  function drawAnalysisLoaded(){
    var host = document.getElementById("anbody");
    if(!historyAvailable()){
      host.innerHTML = '<p class="hmsg">This page was opened from a file, so the Loaded panel has ' +
        'nothing to ask.<br><br>Snapshots live outside the committed map on purpose — the same reason ' +
        'Telemetry does — so reading them needs a server. Run <code>:DocMap serve</code> and open the ' +
        'URL it prints (or <code>:DocMap open</code> while it runs).</p>';
      return;
    }

    // Two separate fetches can run below — the snapshot list (once per page
    // load) and, once a snapshot is picked, that snapshot's own data (every
    // time the picker changes) — and either one left in flight with nothing
    // shown was the same bug from two different code paths. The list-fetch
    // case: switching tabs to Loaded left whatever panel was on screen
    // before sitting there unchanged, so the toolbar said "Loaded" while
    // the body still showed a different panel's table. The snapshot-fetch
    // case, found the same way right after: picking a snapshot from the
    // dropdown left the *previous* "choose a snapshot" message on screen
    // for the length of the request, which reads as "nothing happened" and
    // not as "loading". Telemetry never had either problem — it shows its
    // own loading message unconditionally because it re-fetches live data on
    // every draw; here the same message needs a wider gate than "not yet
    // fetched" because a *second*, later fetch is just as real as the first.
    // Left un-gated only for the true no-op case: an already-loaded list
    // with no snapshot picked resolves with nothing to wait for.
    if(!loadedSnapLoaded || state.lsnap) host.innerHTML = '<p class="hmsg">Loading…</p>';

    var snapListPromise = loadedSnapLoaded
      ? Promise.resolve(loadedSnapList)
      : fetch("/api/loaded/snapshots").then(function(r){ return r.json(); }).then(function(d){
          loadedSnapLoaded = true;
          loadedSnapList = (d && d.snapshots) || [];
          return loadedSnapList;
        });
    // No `.catch` swallowing the failure into an empty list, deliberately.
    // A server that simply has no snapshots answers `{"snapshots":[]}` with
    // a 200, so this promise only rejects when the request genuinely failed
    // — and turning that into "No snapshots saved yet" states something
    // about the *data* when the truth is about the *server*. On a published
    // copy of the map that reading is plainly wrong, which is how it was
    // found. Letting it reject hands it to the outer catch, which explains
    // the real situation; `loadedSnapLoaded` staying false also means the
    // next draw retries rather than caching a failure forever.

    snapListPromise.then(function(list){
      if(!state.lsnap){
        renderAnalysisLoadedBody(null, list);
        return;
      }
      return loadedFetch(state.lsnap).then(function(d){
        renderAnalysisLoadedBody(d, list);
      });
    }).catch(function(e){
      explainFetchFailure(e, "the Loaded panel").then(function(msg){ host.innerHTML = msg; });
    });
  }

  function loadedPickerHTML(list){
    var items = [{ v: "", l: (list.length === 0 ? "No snapshots saved yet" : "— choose a snapshot —") }]
      .concat(list.map(function(s){
        var d = new Date(s.saved_at * 1000);
        return { v: s.name, l: s.name + " (" + d.toLocaleString() + ")" };
      }));
    return '<div class="telpicker"><label>Snapshot: <select id="loadedsnap">' +
      telOptionsHTML(items, state.lsnap || "") + '</select></label></div>';
  }

  function loadedWirePicker(){
    var sel = document.getElementById("loadedsnap");
    if(sel) sel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "loaded", lsnap: sel.value || null });
    });
  }

  function loadedUnavailableMessage(d){
    var reason = (d && d.reason) || "unknown";
    if(reason === "no map generated yet"){
      return "No map has been generated yet on this machine — run <code>:DocMap</code> first.";
    }
    if(reason === "no single root module prefix for this tree"){
      return "This tree has no single root module (opts.source resolves to several top-level " +
        "modules, or equals opts.lua_root) — there is no one prefix to snapshot.";
    }
    if(reason === "snapshot not found"){
      return "Snapshot <code>" + esc((d && d.snapshot) || "") + "</code> was not found — it may have " +
        "been evicted (only the most recent ones are kept).";
    }
    return "No loaded-snapshot data for prefix <code>" + esc((d && d.prefix) || "") + "</code> yet — " +
      "install/enable <code>runtime-analysis.nvim</code>, then <code>:RA loaded snapshot " +
      esc((d && d.prefix) || "&lt;prefix&gt;") + "</code> there.";
  }

  function renderAnalysisLoadedBody(d, list){
    var host = document.getElementById("anbody");
    var parts = [loadedPickerHTML(list || [])];

    if(!state.lsnap){
      parts.push('<p class="ntext none">Choose a snapshot above — this panel has nothing live to ' +
        'fall back to (see the panel\'s own note: a browser tab has no package.loaded of its own).</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }
    if(!d || !d.available){
      parts.push('<p class="ntext none">' + loadedUnavailableMessage(d) + '</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }

    var totalRows = (d.rows || []).length;
    var rows = anFilter((d.rows || []).map(function(r){
      var key = r.id + "#" + r.name;
      return {
        id: r.id, kind: r.kind, name: r.name, declared_name: r.declared_name,
        line: r.line, haystack: key, sortkey: key
      };
    }));

    var capturedAt = d.captured_at ? new Date(d.captured_at * 1000).toLocaleString() : "unknown time";
    if(totalRows === 0){
      parts.push('<p class="ntext none">Snapshot <code>' + esc(d.snapshot) + '</code> (captured ' +
        esc(capturedAt) + ') has data for prefix <code>' + esc(d.prefix) +
        '</code>, but nothing disagreed with the source.</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }

    var cols = [
      { label: "Module", key: "id", get: function(r){ return r.id; }, initial: "asc" },
      { label: "Name", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Discrepancy", key: "kind", get: function(r){ return r.kind; }, initial: "asc" }
    ];
    anSort(rows, cols, function(a, b){
      if(a.id !== b.id) return a.id < b.id ? -1 : 1;
      return a.name < b.name ? -1 : 1;
    });

    parts.push('<p class="nsub">' + rows.length + ' discrepanc' + (rows.length === 1 ? 'y' : 'ies') +
      ' in snapshot <code>' + esc(d.snapshot) + '</code> (captured ' + esc(capturedAt) +
      ') for prefix <code>' + esc(d.prefix) + '</code>.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      parts.push('<p class="ntext none">No function matches that filter.</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var label = r.kind === "declared_only"
        ? "✕ declared, not loaded" : "! loaded, not declared";
      parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
        '<td><code>' + esc(r.id) + '</code></td>' +
        '<td><code>' + esc(r.name) + '</code></td>' +
        '<td class="' + (r.kind === "declared_only" ? "teldown" : "telup") + '">' + label + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    host.innerHTML = parts.join("");
    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });
    loadedWirePicker();
  }

]]
