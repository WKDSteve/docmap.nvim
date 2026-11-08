---@module 'docmap.core.render.html'
-- handrolled-ok: JavaScript inside an HTML string (the wheel cooldown of the page), not Lua
--- Renders the docmap IR as a single self-contained HTML page.
---
--- Self-contained is a hard requirement, not a preference: the artifact has to
--- work from a `file://` URL and from a `gh-pages` branch with no build step,
--- and a documentation page that breaks without network access is a bad
--- documentation page. Everything — CSS, JS, the IR itself — is inlined.
---
--- The IR is embedded as JSON in a `<script type="application/json">` block
--- rather than being expanded into markup at generation time, so the same file
--- powers the tree, the filter and the detail pane without duplicating data.

local json = require("docmap.core.json")
-- One finding, one sentence. Rendered here rather than carried already
-- rendered — see `core/findings.lua` for why the check no longer builds
-- its own English.
local fmt_finding = require("docmap.core.findings").format

local M = {}

-- HTML-escape text destined for server-rendered markup. Not to be confused
-- with the client-side `esc()` defined further down inside the embedded `JS`
-- string (a JavaScript function, escaping in the browser) — that one is
-- data, not Lua, and is unrelated to this.
local esc = require("lib.lua.strings.encoding").html_escape

local CSS = require("docmap.core.render.html.css")

local JS = require("docmap.core.render.html.js")

---@param ir Docmap.IR
---@param findings Docmap.Finding[]
---@param opts Docmap.Opts
---@return string
function M.render(ir, findings, opts)
  -- How far the artifact sits below the repo root, so relative links back to
  -- README files resolve from wherever it was written.
  local out_dir = opts.out_dir or "docs/map"
  local depth = select(2, out_dir:gsub("[^/]+", "")) or 0

  local meta = vim.deepcopy(ir.meta)
  meta.out_depth = depth
  -- Render-time-only, same as `out_depth` above: `opts.godbolt` needs no new
  -- IR field and touches no scan step, only whether the client-side
  -- Compiler Explorer trigger renders anything at all — see that code's own
  -- header comment.
  meta.godbolt = not not opts.godbolt

  -- Validated here rather than trusted, because the value is interpolated
  -- into a `<script>` in the emitted document: a typo would be inert, but
  -- an arbitrary string would not be. Only the two literals that mean
  -- anything survive; "system", nil, and everything else become no default
  -- at all, which is what the page has always done.
  local baked_theme = (opts.theme == "light" or opts.theme == "dark") and opts.theme or nil

  -- The startup flamegraph, read from disk and checked before it is allowed
  -- into the document — see `core/startup_graph.lua` for why it is baked in
  -- rather than fetched like Telemetry and Loaded, and why "checked" here
  -- means refused rather than sanitised. Absent is the normal case (nobody
  -- has measured, or runtime-analysis.nvim is not installed), and absent
  -- means both the button and the template are simply not emitted.
  local startup_graph_button, startup_graph_html = "", ""
  local graph = require("docmap.core.startup_graph").load(opts)
  if graph then
    startup_graph_button = '<button class="anview-btn plugin-gated" data-atool="startup"'
      .. ' data-explain="atool.startup">Startup</button>'
    -- The measurement's own date, not the generation's: a reader looking at
    -- a slow-startup graph needs to know whether it predates the change they
    -- are here about.
    -- The cast is the format: `os.date` is typed `string|osdate`, and the
    -- table only ever comes back for a `*t` format, which this is not.
    local measured = graph.mtime and os.date("!%Y-%m-%d", graph.mtime) --[[@as string]] or nil
    startup_graph_html = ('<template id="startup-graph"%s>%s</template>'):format(
      measured and (' data-measured="' .. esc(measured) .. '"') or "",
      graph.svg
    )
  end

  local nodes = {}
  for _, id in ipairs(ir.order) do
    nodes[#nodes + 1] = ir.nodes[id]
  end

  local payload = json.encode({
    meta = meta,
    root = ir.root,
    nodes = nodes,
    edges = ir.edges or {},
    tag_links = ir.tag_links or {},
    -- Was missing, which made the Duplicates panel unreachable: it reads
    -- `IR.duplicates`, found nothing, and showed its "this map was generated
    -- before duplicate detection existed — regenerate it" message on *every*
    -- map including one generated a second earlier. The advice was impossible
    -- to follow, because regenerating produced the same payload again.
    --
    -- The empty shape rather than `nil` when absent, so the panel can tell
    -- "ran, found nothing" (its real no-duplicates message) apart from "this
    -- artifact predates the feature" (the message above, which is now only
    -- reachable by an artifact that genuinely predates it).
    duplicates = ir.duplicates or { groups = {}, functions = 0, considered = 0, min_size = 0 },
    -- The same omission as `duplicates` above, made a second time and caught
    -- the same way — by opening the generated page and finding the feature
    -- silently absent. This payload is built independently of
    -- `docmap.to_json`, so adding a field to `ir` and to the JSON
    -- artifact does *not* put it on the page; both sites need it. That is
    -- the trap, and it has now cost two features, so it is worth stating
    -- plainly rather than leaving for a third.
    docs = ir.docs or { files = {}, refs = {}, missing = {} },
    -- Third time this field list has had to be extended by hand, and the
    -- comment above is the reason it went right the first try here. Same empty
    -- shape rather than `nil`, so the tab can tell "computed, nothing crossed a
    -- threshold" (a real and quite good answer for a healthy tree) apart from
    -- "this artifact predates Quicks".
    quicks = ir.quicks or { good = {}, bad = {}, total_good = 0, total_bad = 0 },
    -- Caught here, before shipping, precisely *because* of the comment
    -- thread above — the fourth and fifth fields added to `ir` after
    -- `M.render`'s own field list existed, checked against this trap on
    -- purpose instead of by opening the page and finding them missing.
    -- No empty-shape fallback, unlike duplicates/docs/quicks: `nil` here is
    -- not "this artifact predates the feature", it is the real, common
    -- answer "this repo ships no lib.nvim.deps manifest" / "no
    -- docs/FEATURES/ folder" — `renderAnalysisTools`/`drawFeatures` already
    -- check for exactly that falsy value.
    tools = ir.tools,
    features = ir.features,
    -- Opt-in (`opts.spec_state`), absent otherwise: which modules have specs
    -- and how the last run ended. Nothing in the page changes without it.
    spec_state = ir.spec_state,
    -- The trap above claimed a third feature after all, and the comment
    -- thread did not prevent it: `ir.checklist` is set by `scan_full` and
    -- serialised by `docmap.to_json`, but never reached this list —
    -- so the Checklist panel rendered "This repository has no checklist" on
    -- every page, including one whose own `module_map.json` carried the
    -- ledger and whose `/api/checklist` answered `available: true`. Found by
    -- opening the served page and comparing the three against each other,
    -- which is the same way the first two were found.
    --
    -- No empty-shape fallback, for the same reason as `tools`/`features`:
    -- `nil` here is the real, common answer "this repo ships no
    -- docs/CHECKLIST/", which `drawAnalysisChecklist` already handles.
    checklist = ir.checklist,
    -- Keyword glossaries, keyed by file extension. Tool data rather than
    -- scanned data -- the same bytes in every checkout -- so it rides on
    -- the page and deliberately not in `module_map.json`, which is
    -- byte-deterministic and describes the repository rather than the
    -- renderer. Reached through the registry, never by requiring a backend:
    -- `docmap.core` must not name `docmap.core.lang.*`, and
    -- this module is under that prefix.
    glossaries = require("docmap.core.lang_registry").glossaries(),
    -- The annotation catalogue, for the same reason and on the same terms as
    -- `glossaries` above: tool data, identical in every checkout, so it rides
    -- on the page rather than inflating a byte-deterministic artifact that is
    -- supposed to describe the repository.
    --
    -- Carried before either consumer exists, deliberately and visibly: the
    -- lookup layer's third kind (`ReferenceTab.md`) and the annotation
    -- adoption panel (`IDEAS_IMPLEMENTATION_PLAN.md` §2.1) both need exactly
    -- this table, and shipping it once here is what makes each of them the
    -- quick win their own estimate claims. A payload key with no reader is a
    -- cost of a few hundred bytes; two panels each inlining their own copy is
    -- the duplication this repository argues against everywhere else.
    tags = require("docmap.core.tags").for_page(),
    -- The keyword table `core/markers.lua` matched with, so the Notes tab
    -- renders sections in the same order and with the same names the
    -- scanner used. Passed rather than repeated in JavaScript: a second
    -- copy of this list is a second thing to keep in step, and the page
    -- would show a `PERF` section that the scanner had stopped filling.
    -- Tool data, like `glossaries` above, so it rides on the page and not
    -- in the byte-deterministic artifact.
    marker_kinds = require("docmap.core.markers").KEYWORDS,
  })
  -- `</script>` inside JSON would terminate the block early.
  payload = payload:gsub("</", "<\\/")

  -- **This page is an edge, so this is where a finding becomes a
  -- sentence.** The embedded array carries `message` rather than the
  -- `params` the finding travels with, because the page's own JS reads
  -- `x.message` and a committed artifact has to be readable without a
  -- catalog beside it. Sending params and a catalog instead is I18N-3,
  -- deliberately not this task: it changes what the artifact *is*, and
  -- the point of I18N-0 is that it changes nothing anyone can see.
  local rendered = {}
  for i, f in ipairs(findings) do
    rendered[i] = {
      severity = f.severity,
      check = f.check,
      node = f.node,
      message = fmt_finding(f),
    }
  end
  local findings_json = json.encode(rendered):gsub("</", "<\\/")

  local c = ir.meta.counts
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end

  -- Checks that skipped part of the tree because the language has no such
  -- convention: shown beside the findings so a skip never reads as a pass.
  -- Nothing is emitted for a tree that skipped none (Lua), keeping its page
  -- byte-identical.
  local na_html = ""
  for _, na in ipairs(require("docmap.core.check").not_applicable(ir, opts)) do
    na_html = na_html
      .. ('<p class="na">%s</p>'):format(
        esc(require("docmap.core.findings").format_not_applicable(na))
      )
  end

  local rows = {}
  for _, f in ipairs(findings) do
    -- data-node drives the click-to-select wiring in JS. Left off entirely
    -- (rather than set to an empty string) when the finding has no node, or
    -- points at something that isn't a real IR node id (config.lua's
    -- aggregator check reports against a synthetic "lua/lib/@types" path
    -- that was never a scanned node) — the click handler only wires up rows
    -- that actually carry the attribute, so an unresolvable target silently
    -- stays inert instead of being a dead click.
    local node_attr = f.node and (' data-node="%s"'):format(esc(f.node)) or ""
    rows[#rows + 1] = ([[<tr%s><td><span class="sev %s">%s</span></td><td class="msg">%s</td><td class="msg">%s</td></tr>]]):format(
      node_attr,
      f.severity,
      f.severity,
      esc(f.check),
      esc(fmt_finding(f))
    )
  end

  return table.concat({
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>",
    esc(ir.meta.title),
    " — module map",
    -- Suppressed when the scanned project *is* docmap.nvim:
    -- "docmap.nvim — module map · docmap.nvim" repeats the
    -- name for no reason. Every other project gets the credit.
    (ir.meta.title ~= "docmap.nvim") and " · docmap.nvim" or "",
    "</title>",
    "<style>",
    CSS,
    "</style>",

    -- The theme, settable from outside the page.
    --
    -- `:root[data-theme]` has always been here; nothing could reach it.
    -- That is not academic: `docmap-desktop` embeds this page in an
    -- iframe served from `127.0.0.1` while its own shell is on `tauri://`,
    -- so the attribute it stamps on its own document never crosses, and a
    -- reader who chose dark on a light OS got a dark window with a white
    -- page in it.
    --
    -- In `<head>`, before any element exists, because a theme applied
    -- after first paint is a flash of the wrong one. `?theme=` is read
    -- rather than a `postMessage` handler added: a page that executes
    -- instructions from whatever embeds it is a different security
    -- posture than one that only reads its own URL, and a query parameter
    -- is also the thing a person can type into a browser.
    --
    -- Three states, like the app: `light` and `dark` decide, anything
    -- else -- including no parameter at all -- means follow the OS.
    --
    -- `opts.theme` is the same three states, baked in as the *fallback*
    -- rather than as the answer: a project that reads better dark can say
    -- so in its own artifact, and a reader who appends `?theme=light`
    -- still wins, because the person holding the window is a better judge
    -- of their own screen than the person who generated the file. Absent
    -- (or "system") emits no default at all, so every map generated before
    -- this option existed is byte-identical to one generated after it.
    [[<script>(function(){]],
    [[  try{]],
    [[    var t = new URLSearchParams(location.search).get("theme");]],
    -- `""` rather than `nil` when there is no baked theme: this is one
    -- `table.concat` over a list, and a `nil` in the middle of it puts a
    -- hole in the array part and truncates the document at that point.
    baked_theme and ('    if(t !== "light" && t !== "dark") t = "%s";'):format(baked_theme) or "",
    [[    if(t === "light" || t === "dark")]],
    [[      document.documentElement.setAttribute("data-theme", t);]],
    [[  }catch(e){}]],
    [[})();</script>]],

    "</head><body>",

    -- Above the project's own header, not inside it: the header names the
    -- repository being read, and putting the tool's name in there would
    -- make the two look like one thing.
    '<div class="topbar">'
      .. '<a class="brand" href="https://github.com/WKDSteve/docmap.nvim"'
      .. ' target="_blank" rel="noopener">docmap.nvim</a>'
      .. '<span class="tagline">know your project</span>'
      .. "</div>",

    "<header><h1>",
    esc(ir.meta.title),
    '<span class="sub">module map</span></h1>',
    -- Each count links to the view that shows that set. They were inert
    -- `<span>`s: five numbers naming sets the reader could see the size of and
    -- had no way to reach.
    --
    -- `<button>` rather than `<a href="#...">`, deliberately. An anchor would
    -- write the fragment itself and then `applyState` would write it again
    -- from the parsed state, producing two history entries per click — and the
    -- errors/warnings ones are not navigations at all, they open a disclosure
    -- further down the same page.
    --
    -- A count of zero is rendered disabled rather than as a live link, because
    -- "0 warnings" that navigates somewhere empty is worse than a number that
    -- never claimed to be clickable.
    '<div class="stats">',
    ('<button class="stat-link" data-goto="modules"%s><b>%d</b> modules</button>'):format(
      (c.module or 0) == 0 and " disabled" or "",
      c.module or 0
    ),
    ('<button class="stat-link" data-goto="namespaces"%s><b>%d</b> namespaces</button>'):format(
      (c.namespace or 0) == 0 and " disabled" or "",
      c.namespace or 0
    ),
    ('<button class="stat-link" data-goto="files"%s><b>%d</b> files</button>'):format(
      (c.file or 0) == 0 and " disabled" or "",
      c.file or 0
    ),
    ('<button class="stat-link" data-goto="errors"%s><b class="sev error">%d</b> errors</button>'):format(
      t.error == 0 and " disabled" or "",
      t.error
    ),
    ('<button class="stat-link" data-goto="warnings"%s><b class="sev warn">%d</b> warnings</button>'):format(
      t.warn == 0 and " disabled" or "",
      t.warn
    ),
    "</div></header>",

    -- Quicks leads the tab bar because it is the one tab that answers a
    -- question the reader has before they have a question. It is deliberately
    -- *not* the default tab: `state.tab` still starts on "tree", so every link
    -- ever shared and every habit ever formed lands where it always did.
    -- Eight tabs in reading order, and two of them own a second level.
    --
    -- **Tree is no longer one of them.** Tree, Functions and Modules are
    -- three ways of listing the same repository, so they are three modes of
    -- Index rather than one top-level tab and two buttons inside another.
    -- Promoted features moved the same way: a feature marked `Tab: true`
    -- used to append a button to *this* bar, so a repository documenting
    -- five features pushed the tabs onto a second row and buried the eight
    -- that are always there under five that are particular to it.
    --
    -- `#subtabs` below is the second level for both, rendered from whichever
    -- group is active. One strip, not one per owner: two strips in the same
    -- place that are never both visible are one strip with extra code.
    '<div class="tabs">',
    '<button class="tab-btn active" data-tab="hierarchy" data-explain="tab.hierarchy">Hierarchy</button>',
    '<button class="tab-btn" data-tab="index" data-explain="tab.index">Index</button>',
    '<button class="tab-btn" data-tab="analysis" data-explain="tab.analysis">Analysis</button>',
    '<button class="tab-btn" data-tab="compare" data-explain="tab.compare">Compare</button>',
    '<button class="tab-btn" data-tab="features" data-explain="tab.features">Features</button>',
    '<button class="tab-btn" data-tab="quicks" data-explain="tab.quicks">Quicks</button>',
    '<button class="tab-btn" data-tab="notes" data-explain="tab.notes">Notes</button>',
    '<button class="tab-btn" data-tab="history" data-explain="tab.history">History</button>',
    '<button class="tab-btn" data-tab="findings" data-explain="tab.findings">Findings</button>',
    "</div>",

    '<div class="subtabs" id="subtabs" hidden></div>',

    '<div class="toolbar">',
    '<input id="q" type="search" placeholder="Filter modules, paths, descriptions…" autocomplete="off">',
    '<button id="expand">Expand all</button><button id="collapse">Collapse</button>',
    -- Sits with the filter rather than inside any one tab: marks are collected
    -- while reading *any* list, so the control that says how many there are and
    -- opens them has to be visible from all of them.
    '<button id="markbar" class="markbar" hidden></button>',
    -- Beside the marks pill for the same reason it is: the state being
    -- copied is whatever tab, node, graph view and filter the reader is
    -- looking at right now, so the control belongs where it is reachable
    -- from all of them rather than inside one.
    '<button id="copylink" title="Copy a link to exactly this view">Copy link</button>',
    "</div>",

    '<main id="view-tree" class="view active"><div id="langbar" class="langbar" hidden></div>'
      .. '<div id="tree"></div><div id="detail"></div></main>',

    '<div id="view-hierarchy" class="view">',
    '<div class="hctl">',
    '<button id="hup">▲ Up</button><button id="hroot">⌂ Root</button>',
    -- Where the graph is rooted, and every level above it. `Up` and `Root`
    -- were the only way back and neither says where you are — after two
    -- recentres the reader knows they moved and not from where.
    '<nav id="hcrumb" class="hcrumb" aria-label="Graph root"></nav>',
    [[<button id="hlr" title="Lay the graph out left-to-right instead of top-down">&#8644; Sideways</button>]],
    '<div class="hview-toggle">',
    '<button class="hview-btn active" data-view="modules" data-explain="view.modules">Modules</button>',
    '<button class="hview-btn" data-view="deps" data-explain="view.deps">Deps</button>',
    '<button class="hview-btn" data-view="calls" data-explain="view.calls">Calls</button>',
    '<button class="hview-btn" data-view="modulecalls" data-explain="view.modulecalls">Module Calls</button>',
    '<button class="hview-btn" data-view="types" data-explain="view.types">Types</button>',
    '<button class="hview-btn" data-view="inheritance" data-explain="view.inheritance">Inheritance</button>',
    '<button class="hview-btn" data-view="tree" data-explain="view.tree">Tree</button>',
    '<button class="hview-btn" data-view="treemap" data-explain="view.treemap">Treemap</button>',
    "</div>",
    -- Direction and depth belong to the directed views only; `syncGraphControls`
    -- hides them in Modules/Types rather than leaving two control groups that
    -- do nothing.
    '<div class="hview-toggle" id="hdir">',
    '<button class="hdir-btn" data-dir="in" title="What depends on / calls this">← In</button>',
    '<button class="hdir-btn" data-dir="both" title="Both directions around the center">⇄ Both</button>',
    '<button class="hdir-btn active" data-dir="out" title="What this depends on / calls">Out →</button>',
    "</div>",
    -- Not a zoom control -- the label exists because it read like one
    -- without it (see .hctl-label's own comment).
    '<span class="hctl-label" title="How many hops from the centered node to draw">Depth</span>',
    '<div class="hview-toggle" id="hdepth">',
    '<button class="hdepth-btn" data-depth="1" title="Depth 1">1</button>',
    '<button class="hdepth-btn active" data-depth="2" title="Depth 2">2</button>',
    '<button class="hdepth-btn" data-depth="3" title="Depth 3">3</button>',
    '<button class="hdepth-btn" data-depth="0" title="Unbounded, still capped at 90 boxes">∞</button>',
    "</div>",
    '<div class="hview-toggle" id="hext">',
    '<button class="hext-btn" title="Also draw requires/calls that resolve outside this map">+ external</button>',
    "</div>",
    -- Which gesture recentres and which one leaves the view. A toggle rather
    -- than a fixed choice because the two answers have genuinely different
    -- costs: the default is the one that surprises a first-time reader least
    -- (a single click stays where you are), and the pill is for the reader
    -- who already has the opposite muscle memory from every earlier map.
    -- Styled as a pill like `#hext` rather than as a bare checkbox, because a
    -- lone checkbox among nine pills reads as a different kind of control.
    '<div class="hview-toggle" id="hgest">',
    '<button class="hgest-btn" title="Classic gestures: single click leaves for the Tree view, double click recentres. Off by default — a single click recentres and stays here.">⇵ Classic clicks</button>',
    "</div>",
    '<button id="hzoomreset" title="Reset zoom to 100% (or press 0)">⌕ 100%</button>',
    '<span class="hzoom" id="hzoomlabel">100%</span>',
    '<button id="hexport" title="Download the current diagram as a standalone SVG">↓ SVG</button>',
    -- Right-click a box to dim/show it — see the context menu. This pill
    -- only says how many are dimmed right now and clears all of them,
    -- mirroring #markbar's own role for Compare marks.
    -- The language legend again, same state as the Tree tab's. Inline in the
    -- control row rather than a band above the graph: the graph area is the
    -- scarce space here, and this is a control among controls.
    '<span id="langbar-h" class="langbar langbar-h" hidden></span>',
    '<button id="hiddenbar" class="markbar" hidden></button>',
    '<span class="hpath" id="hpath"></span>',
    "</div>",
    -- Outside #hgraph-wrap, not inside it: the wrap itself scrolls
    -- (overflow:auto, for a diagram bigger than the viewport), and an
    -- absolutely-positioned child of a scrolling element scrolls away with
    -- its content. This outer div exists only to give the slider a
    -- positioned ancestor that never moves.
    '<div id="hgraph-outer">',
    '<div class="hrootslider" id="hrootslider" title="Hide root levels — every node at that depth becomes its own root">',
    '<span class="hrootslider-label">Levels</span>',
    '<button class="hroot-btn" id="hrootplus" title="Hide one more root level">+</button>',
    '<input type="range" id="hrootrange" min="0" max="0" value="0" step="1">',
    '<button class="hroot-btn" id="hrootminus" title="Show one more root level">−</button>',
    "</div>",
    '<div id="hgraph-wrap"><div id="hgraph"><div id="hstage"></div></div></div>',
    -- Tree and Treemap (see isAltView): a list and an area, so they scroll
    -- and size like a page rather than zoom like the diagram above.
    '<div id="halt" hidden><div id="halt-bar" class="hctl"></div><div id="halt-body"></div></div>',
    "</div>",
    '<div class="hlegend" id="hlegend"></div>',
    "</div>",

    '<div id="view-quicks" class="view"></div>',

    '<div id="view-compare" class="view">',
    '<div class="hview-toggle" id="cmptoggle">',
    '<button class="cmpview-btn active" data-cview="matrix">Matrix</button>',
    '<button class="cmpview-btn" data-cview="columns">Columns</button>',
    '<button class="cmpview-btn" data-cview="stacked">Stacked</button>',
    '<button id="cmpclear" title="Drop every mark">Clear all</button>',
    "</div>",
    '<div id="cmpbody"></div>',
    "</div>",

    '<div id="view-notes" class="view"></div>',

    '<div id="view-features" class="view"></div>',

    '<div id="view-index" class="view">',
    '<div id="ixbody"></div>',
    "</div>",

    '<main id="view-history" class="view">',
    '<div id="hist-list"></div><div id="hist-detail"></div>',
    "</main>",

    '<div id="view-analysis" class="view">',
    '<div class="hview-toggle" id="antoggle">',
    '<button class="anview-btn active" data-atool="test" data-explain="atool.test">Test coverage</button>',
    '<button class="anview-btn" data-atool="doc" data-explain="atool.doc">Documentation</button>',
    '<button class="anview-btn" data-atool="annotations" data-explain="atool.annotations">Annotations</button>',
    '<button class="anview-btn" data-atool="api" data-explain="atool.api">API surface</button>',
    '<button class="anview-btn" data-atool="deps" data-explain="atool.deps">Dependencies</button>',
    '<button class="anview-btn" data-atool="complexity" data-explain="atool.complexity">Complexity</button>',
    '<button class="anview-btn" data-atool="duplicates" data-explain="atool.duplicates">Duplicates</button>',
    '<button class="anview-btn" data-atool="plugins" data-explain="atool.plugins">Plugins</button>',
    '<button class="anview-btn" data-atool="lazy" data-explain="atool.lazy">Lazy loading</button>',
    '<button class="anview-btn" data-atool="bindings" data-explain="atool.bindings">Bindings</button>',
    '<button class="anview-btn plugin-gated" data-atool="tools" data-explain="atool.tools">Tools</button>',
    '<button class="anview-btn" data-atool="checklist" data-explain="atool.checklist">Checklist</button>',
    '<button class="anview-btn" data-atool="hooks" data-explain="atool.hooks">Hooks</button>',
    '<button class="anview-btn" data-atool="decorators" data-explain="atool.decorators">Decorators</button>',
    '<button class="anview-btn" data-atool="rust" data-explain="atool.rust">Rust</button>',
    '<button class="anview-btn" data-atool="docs" data-explain="atool.docs">Docs</button>',
    '<button class="anview-btn" data-atool="endpoints" data-explain="atool.endpoints">Endpoints</button>',
    -- The runtime-fed tools as one group at the end of the toolbar: what ran, as opposed to what the
    -- source says. A group inside the same toolbar rather than a tab of its own, so `#tab=analysis&atool=…`
    -- links and the selection logic (`#antoggle .anview-btn`) keep working unchanged.
    '<span class="anview-group" role="group" aria-labelledby="anview-runtime-label">',
    '<span class="anview-group-label" id="anview-runtime-label">Runtime</span>',
    '<button class="anview-btn plugin-gated" data-atool="telemetry" data-explain="atool.telemetry">Telemetry</button>',
    '<button class="anview-btn plugin-gated" data-atool="loaded" data-explain="atool.loaded">Loaded</button>',
    -- `plugin-gated` like its two neighbours, and for the same reason — the
    -- data comes from runtime-analysis.nvim — but it is the one of the three
    -- that needs no server: see `core/startup_graph.lua` for why startup
    -- attribution is the one runtime measurement worth baking in. Rendered
    -- only when a graph was actually baked in: a toolbar entry that is
    -- always there and usually empty teaches the reader to skip it, which
    -- is the same reasoning `docTrigger` states for its own icon.
    startup_graph_button,
    "</span>",
    "</div>",
    '<div id="anbody"></div>',
    "</div>",

    '<div id="view-findings" class="view"><div id="findings"><details open><summary>Drift findings (',
    tostring(#findings),
    ')</summary><div class="wrap"><table>',
    "<thead><tr><th>Severity</th><th>Check</th><th>Message</th></tr></thead><tbody>",
    table.concat(rows),
    "</tbody></table>",
    na_html,
    "</div></details></div></div>",

    -- The startup flamegraph, in a `<template>` so the browser parses it
    -- once at load and the Startup panel can clone it without a second
    -- pass through `innerHTML`. Emitted only when there is one; the panel
    -- says what to run when there is not, and the button is hidden
    -- entirely so nobody clicks into an empty tool.
    startup_graph_html,

    '<div id="ctx" role="menu"></div>',
    '<div id="sigpop" class="sigpop" role="tooltip"></div>',
    '<div id="kwpop" class="kwpop" role="tooltip"></div>',

    '<script type="application/json" id="ir">',
    payload,
    "</script>",
    '<script type="application/json" id="findings-data">',
    findings_json,
    "</script>",
    "<script>",
    JS,
    "</script>",
    "</body></html>",
  })
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
