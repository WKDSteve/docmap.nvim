---@module 'docmap.core.render.html.css'
--- The stylesheet of the generated page, inlined into `<style>` by `docmap.core.render.html`.
---
--- One long string, unchanged since it was moved out of html.lua (the spec of the page pins a hash of it).

return [[
:root{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
  --tint:200,100,0; --ta1:.14; --ta2:.3; --ta3:.48; --ta4:.68;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
    --accent:#7aa9dd; --accent-soft:#22303f;
    --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
    --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
    --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
    --tint:240,150,40; --ta1:.14; --ta2:.26; --ta3:.38; --ta4:.5;
  }
}
:root[data-theme="light"]{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
  --tint:200,100,0; --ta1:.14; --ta2:.3; --ta3:.48; --ta4:.68;
}
:root[data-theme="dark"]{
  --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
  --accent:#7aa9dd; --accent-soft:#22303f;
  --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
  --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
  --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
  --tint:240,150,40; --ta1:.14; --ta2:.26; --ta3:.38; --ta4:.5;
}
*{box-sizing:border-box}
/* Type scale: 9.5 / 10.5 / 11.5 / 12.5 / 13 / 14 / 15 / 17 / 19 / 20px.
   Ten steps, not the fifteen this file used to declare — measured, not
   eyeballed: `grep -oE "font-size:[0-9.]+px"` found half-integer pairs
   less than a pixel apart (`11px`/`11.5px`, `12px`/`12.5px`…) with no
   distinguishing use — real signal the scale accreted through ordinary
   editing rather than being designed, exactly as Phase 4 named and
   deliberately deferred pending visual verification. Verified this time
   by counting which of each pair was already used more: every merge
   moved the *less*-used value onto the *more*-used one, so the majority
   of rules — the ones most likely to anchor a reader's sense of the
   page's rhythm — render pixel-identical to before, and only the
   minority actually shifted. No rule's *relative* ordering changed. */
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
/* Who made the thing you are reading. Muted and one line: this page is
   someone else's project, and a tool that shouts inside its own output is
   a tool people strip out. */
.topbar{padding:6px 24px;font-size:11.5px;color:var(--muted);
  display:flex;gap:8px;align-items:baseline;border-bottom:1px solid var(--line)}
.topbar .brand{color:var(--muted);text-decoration:none;font-weight:600;letter-spacing:.02em}
.topbar .brand:hover{color:var(--ink);text-decoration:underline}
.topbar .tagline{opacity:.75}
header{padding:20px 24px 14px;border-bottom:1px solid var(--line);
  display:flex;flex-wrap:wrap;gap:14px;align-items:baseline}
h1{margin:0;font-size:20px;font-weight:650;letter-spacing:-.01em}
h1 .sub{color:var(--muted);font-weight:400;font-size:14px;margin-left:8px}
.stats{margin-left:auto;display:flex;gap:14px;font-size:12.5px;color:var(--muted);flex-wrap:wrap}
.stats b{color:var(--ink);font-weight:600}
/* The counts are buttons, but they must not look like the toolbar's. Stripped
   back to text, gaining an underline only on hover — the affordance appears
   where the pointer already is, without five chrome buttons in the header. */
.stat-link{padding:0;border:0;background:none;color:inherit;font:inherit;cursor:pointer;
  border-radius:4px}
.stat-link:hover:not(:disabled){text-decoration:underline;text-underline-offset:3px}
.stat-link:focus-visible{outline:2px solid var(--accent-soft);outline-offset:2px}
/* A zero count is not a link. Same opacity as the surrounding muted text, so
   it reads as a number rather than as something broken. */
.stat-link:disabled{cursor:default}
/* Where an errors/warnings click lands. Fades, so the eye is drawn to the row
   without leaving a permanent highlight the reader then has to dismiss. */
@keyframes findflash{from{background:var(--accent-soft)}to{background:transparent}}
#findings tbody tr.flash td{animation:findflash 1.6s ease-out}
.toolbar{padding:12px 24px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;
  border-bottom:1px solid var(--line)}
#q{flex:1;min-width:200px;max-width:440px;padding:7px 11px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);color:var(--ink);font-size:14px}
#q:focus{outline:2px solid var(--accent-soft);border-color:var(--accent)}
button{padding:6px 11px;border:1px solid var(--line);border-radius:7px;background:var(--panel);
  color:var(--ink);font-size:13px;cursor:pointer}
button:hover{border-color:var(--accent);color:var(--accent)}
.tabs{display:flex;flex-wrap:wrap;gap:2px;padding:0 24px;border-bottom:1px solid var(--line)}
.tab-btn{padding:9px 13px;border:none;background:none;color:var(--muted);font-size:13px;
  cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px}
.tab-btn:hover{color:var(--ink)}
.tab-btn.active{color:var(--accent);border-bottom-color:var(--accent);font-weight:600}
.view{display:none}
.view.active{display:block}
main.view.active{display:grid}
main{grid-template-columns:minmax(300px,1.1fr) minmax(0,1.4fr);gap:0;align-items:start}
@media (max-width:860px){main{grid-template-columns:1fr}}
/* =====================================================================
   Print.

   The page is one artifact and printing it is a media query, not a
   feature — but only if the query actually says something, and four
   things here would otherwise print badly rather than merely plainly.

   1. **The panes are clipped, not long.** `#tree`, `#detail` and the two
      history panes carry `max-height:calc(100vh - Npx)` with
      `overflow:auto`, which on paper means the first screenful prints and
      the rest silently does not exist. Unclipping them is the single
      change that makes this work at all.
   2. **Dark mode follows you to the printer.** `prefers-color-scheme` is
      a property of the reader, not of the sheet, and browsers do not
      override it — so a reader in dark mode gets a black page. The tokens
      are forced back to the light set here rather than fought
      per-element.
   3. **Chrome that cannot be used on paper.** Tabs, the search box, the
      graph's control row and every button are affordances; on a sheet they
      are ink. The tab *bar* goes, the current view stays — `.view` already
      hides the others, so a printout is whatever tab you were on, which is
      also the least surprising thing it could be.
   4. **Rows split across the fold.** A tree row or a finding cut in half
      by a page break is unreadable in exactly the way a table is not.

   Deliberately not done: expanding collapsed tree branches. What prints is
   what is on screen — a printout that silently contains more than the page
   did is a different document, not a better one.
   ===================================================================== */
@media print{
  /* Light tokens, unconditionally: see note 2 above. */
  :root{
    --bg:#fff; --panel:#fff; --ink:#111; --muted:#555; --line:#bbb;
    --accent:#245; --accent-soft:#f0f0f0;
    --error:#900; --warn:#750; --info:#444;
    --mod:#245; --ns:#666; --file:#363; --dep:#743; --call:#534;
    --fn:#750; --ext:#255;
    --tint:200,100,0; --ta1:.14; --ta2:.3; --ta3:.48; --ta4:.68;
  }
  @page{margin:14mm}
  body{background:#fff;color:#111;font-size:10.5pt}

  /* Chrome. `.topbar` and `header` stay: they carry the project name and
     the counts, which is what tells a reader a week later what this sheet
     even is. */
  .tabs, .toolbar, .subtabs, .hctl, #markbar, #hiddenbar,
  #ctx, .sigpop, .explainpop, #hzoomlabel{display:none !important}
  button, input, select{display:none !important}

  /* Note 1: unclip every scrolling pane. */
  #tree, #detail, #hist-list, #hist-detail, #hgraph-wrap{
    max-height:none !important; overflow:visible !important;
    border-right:0 !important;
  }

  /* One column. Two panes side by side fit a screen, not a sheet — the
     tree ends up a narrow gutter and the detail wraps to nothing. */
  main.view.active{display:block !important}

  /* Note 4. */
  .row, .card, .qk, tr, .hnode, li{break-inside:avoid; page-break-inside:avoid}
  h1, h2, h3{break-after:avoid; page-break-after:avoid}

  /* A link's colour means nothing on paper and its target is not worth a
     parenthesis after every one — this page's links are internal
     navigation, so the URL would be noise rather than information. */
  a{color:inherit; text-decoration:none}

  /* Hover-only dimming must not survive into a static sheet. */
  #hgraph.focusing .hnode{opacity:1 !important}
}

#tree{padding:12px 8px 60px 16px;border-right:1px solid var(--line);
  max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#tree{max-height:none;border-right:0;border-bottom:1px solid var(--line)}}
.row{display:flex;align-items:baseline;gap:7px;padding:3px 8px;border-radius:6px;cursor:pointer;
  white-space:nowrap}
.row:hover{background:var(--accent-soft)}
.row.sel{background:var(--accent-soft);box-shadow:inset 2px 0 0 var(--accent)}
.tw{width:14px;flex:none;color:var(--muted);font-size:11.5px;user-select:none}
.nm{font-family:var(--mono);font-size:13px}
.k-module .nm{color:var(--mod)} .k-namespace .nm{color:var(--ns)} .k-file .nm{color:var(--file)}
.sm{color:var(--muted);font-size:12.5px;overflow:hidden;text-overflow:ellipsis;flex:1;min-width:0}
.badges{display:flex;gap:4px;flex:none}
.bd{font-size:9.5px;letter-spacing:.04em;text-transform:uppercase;padding:1px 5px;
  border-radius:4px;border:1px solid var(--line);color:var(--muted)}
.bd.rd{color:var(--accent);border-color:var(--accent)}
.bd.dep{color:var(--error);border-color:var(--error)}
.bd.tested{color:var(--accent);border-color:var(--accent)}
.kids{margin-left:15px;border-left:1px solid var(--line);padding-left:3px}
.kids.hide{display:none}
#detail{padding:22px 26px 60px;max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#detail{max-height:none}}
#detail h2{margin:0 0 3px;font-size:17px;font-family:var(--mono);font-weight:600}
.mp{font-family:var(--mono);font-size:12.5px;color:var(--muted);margin-bottom:16px;
  word-break:break-all}
.links{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 18px}
.links a{font-size:12.5px;padding:4px 10px;border:1px solid var(--line);border-radius:6px;
  text-decoration:none;color:var(--accent);background:var(--panel)}
.links a:hover{border-color:var(--accent)}
.prose{white-space:pre-wrap;font-size:13px;color:var(--ink);
  background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:13px 15px;
  margin-bottom:18px;overflow-x:auto}
.sec{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin:18px 0 7px;font-weight:600}
.lst{list-style:none;margin:0;padding:0}
.lst li{font-family:var(--mono);font-size:12.5px;padding:2px 0;color:var(--muted)}
.empty{color:var(--muted);font-size:13px;font-style:italic}
.fn{margin-bottom:14px;padding-bottom:12px;border-bottom:1px dashed var(--line)}
.fn:last-child{border-bottom:0;padding-bottom:0;margin-bottom:0}
.scope{margin:14px 0 0;padding-left:11px;border-left:2px solid var(--line)}
.scope-head{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600;
  margin:0 0 8px;margin-left:-11px}
.scope-head .bd{margin-right:6px}
.scope-head .sdet{font-size:11.5px;color:var(--muted);font-weight:400}
.fn-sig{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600}
.fn-badges{display:inline-flex;gap:4px;margin-left:8px;vertical-align:middle}
.fn-desc{font-size:12.5px;color:var(--muted);margin:4px 0}
.fn-dep{color:var(--error);font-size:11.5px;font-weight:600;margin:4px 0}
.fn-plist{list-style:none;margin:4px 0;padding:0;font-size:11.5px}
.fn-plist li{padding:1px 0}
.fn-plist code{background:none;padding:0;color:var(--accent)}
.fn-ex{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin-top:6px;overflow-x:auto}
.fn-see a{color:var(--accent);text-decoration:none}
.fn-see a:hover{text-decoration:underline}
/* The bounded source snippet — popup-only, see snippetHTML()'s own comment
   for why this never touches the Tree tab's detail pane. Same shape as
   `.fn-ex`'s code block, a distinct class since the content is source, not
   an authored `@example`. */
.fn-snip-label{font-size:11.5px;text-transform:uppercase;letter-spacing:.05em;
  color:var(--muted);margin-top:10px}
.fn-snip-label .bd{text-transform:none;letter-spacing:0;margin-left:6px}
.fn-snip{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin-top:4px;overflow-x:auto}
/* An authored fenced block. Same shape again as `.fn-ex`/`.fn-snip` — a
   reader should not have to learn three looks for "this is code" on one
   page — and a distinct class only because the margins differ: this one
   sits inside flowing prose with text above and below it, the other two
   are the last thing in their card.
   `pre` rather than `div`, so the block still reads as preformatted text
   with JavaScript off and in whatever strips the page down (a reader mode,
   a print stylesheet). The language rides on `data-lang` purely so it is
   inspectable; nothing styles it. */
.fence{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin:8px 0;overflow-x:auto}
/* The baked-in startup flamegraph. It scrolls horizontally rather than
   scaling to fit: the graph is 1200px of deliberate arithmetic (width IS
   time), and squeezing it into a narrower panel would make two frames of
   different cost look the same width. The SVG carries its own light
   background, so it stays legible in the dark theme as the card it is —
   see core/startup_graph.lua for why it is embedded rather than fetched. */
.startup-graph{margin-top:8px;overflow-x:auto;border:1px solid var(--line);border-radius:6px}
.startup-graph svg{display:block}
/* Annotation popup — the same fn-* markup the detail pane renders, floated
   over whichever list the reader is scanning. Every list in this map shows a
   signature and nothing else; the params, returns and prose that were
   already parsed sat one navigation away, which is what this closes.
   `position:fixed` because the trigger can live inside a scrolling panel and
   an absolutely-positioned card would scroll away from its own anchor. */
.sigpop{position:fixed;z-index:60;display:none;max-width:520px;min-width:260px;
  max-height:60vh;overflow-y:auto;background:var(--bg);border:1px solid var(--line);
  border-radius:8px;box-shadow:0 8px 28px rgba(0,0,0,.18);padding:12px 14px}
.sigpop.on{display:block}
/* The language legend. Drawn only for a polyglot map -- see renderLangBar --
   so a single-language tree pays nothing for it. Quiet by default: a row of
   coloured chips over every map would be exactly the permanent chrome the
   rest of this page avoids. */
.langbar{display:flex;align-items:center;gap:6px;flex-wrap:wrap;
  padding:6px 10px;border-bottom:1px solid var(--line)}
.lb-label{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
.lb-chip{font-family:var(--mono);font-size:11px;padding:2px 7px;border-radius:11px;
  border:1px solid var(--line);background:transparent;color:var(--muted);cursor:pointer}
.lb-chip.on{color:var(--accent);border-color:var(--accent);background:var(--accent-soft)}
.lb-n{margin-left:5px;opacity:.65}
.lb-clear{font-size:11px;padding:2px 7px;border-radius:11px;border:1px dashed var(--line);
  background:transparent;color:var(--muted);cursor:pointer}
/* Sized off the toolbar's own buttons rather than styled separately: it is
   one more control in that row, not a feature announcing itself. The fixed
   width keeps "Copied" from resizing the toolbar under the pointer. */
#copylink{min-width:82px}
/* In the Hierarchy control row the bar is one control among several, not a
   band across the top: no border, no padding of its own. */
.langbar-h{border-bottom:none;padding:0}
/* Filtered out by language. Same opacity as the right-click dim above and a
   separate class on purpose -- a box the reader dimmed by hand must stay
   dimmed when the language filter clears, and the reverse. The
   `#hgraph.focusing` overrides repeat for the same reason they do there:
   equal specificity, decided by source order. */
.hnode.langoff{opacity:.08;pointer-events:none}
#hgraph.focusing .hnode.langoff{opacity:.08}
#hgraph.focusing .hnode.langoff.near{opacity:.08}
/* The keyword card: the same component as .sigpop, one layer above it,
   because a snippet is rendered *inside* .sigpop and its triggers therefore
   cannot borrow it. Narrower, because the content is two sentences. */
.kwpop{position:fixed;z-index:70;display:none;max-width:340px;
  background:var(--bg);border:1px solid var(--line);border-radius:8px;
  box-shadow:0 8px 28px rgba(0,0,0,.18);padding:10px 12px}
.kwpop.on{display:block}
.kw-word{font-family:var(--mono);font-size:12px;color:var(--accent);margin-bottom:4px}
.kw-sum{font-size:12px;line-height:1.45}
/* The surprising-fact line, set apart because it is the exception rather
   than a second half of the definition. */
.kw-note{font-size:11.5px;line-height:1.4;color:var(--muted);margin-top:6px}
.kw-ref{font-size:11px;margin-top:8px}
.kw-origin{font-size:10.5px;margin-top:6px;color:var(--muted);
  text-transform:uppercase;letter-spacing:.04em}
/* Decorated keywords stay unobtrusive until pointed at: a snippet where
   every keyword is coloured is syntax highlighting, which this page turned
   down on purpose. A dotted underline says "there is an answer here" and
   nothing more. */
.kw{border-bottom:1px dotted var(--muted);cursor:help}
.kw:hover,.kw:focus{border-bottom-color:var(--accent);color:var(--accent);outline:none}
.sigpop .fn-sig{font-size:12.5px}
/* The trigger. Kept at full opacity for keyboard focus and while its popup
   is open, so tabbing through a list does not chase an invisible control. */
.sigi{display:inline-block;margin-left:6px;padding:0 4px;border-radius:4px;cursor:help;
  font-size:10.5px;line-height:15px;color:var(--muted);border:1px solid var(--line);
  opacity:.45;transition:opacity .12s,color .12s;user-select:none}
.sigi:hover,.sigi:focus,.sigi.on{opacity:1;color:var(--accent);border-color:var(--accent);
  outline:none}
li:hover>.sigi,tr:hover .sigi{opacity:.8}
/* The prose-reference affordance. Rendered only where references exist, so
   unlike `.sigi` it carries information by being present at all — hence a
   accent-tinted resting state rather than `.sigi`'s near-invisible one. */
.doci,.feati{display:inline-block;margin-left:6px;padding:0 5px;border-radius:4px;cursor:help;
  font-size:10.5px;line-height:15px;color:var(--accent);border:1px solid var(--line);
  background:var(--accent-soft);opacity:.75;transition:opacity .12s;user-select:none}
.doci:hover,.doci:focus,.doci.on,.feati:hover,.feati:focus,.feati.on{opacity:1;
  border-color:var(--accent);outline:none}
/* The feature card in the popup: the name is the link, the theme a badge. */
.featref .docref-where{font-family:inherit;font-size:12.5px;font-weight:600}
.featref .docref-where a{color:var(--accent);text-decoration:none}
.featref .docref-where a:hover,.featref .docref-where a:focus{text-decoration:underline}
.docn{margin-left:4px;font-weight:600}
.docref{margin:7px 0;padding-left:9px;border-left:2px solid var(--line)}
.docref-where{font-family:var(--mono);font-size:11.5px;color:var(--accent)}
.docref-where .bd{margin-left:6px}
.docref-ctx{font-size:11.5px;color:var(--muted);margin-top:2px}
/* @overload — one block per alternative call shape, indented under the
   primary signature so it reads as "also, this" rather than a second
   function. Left border rather than a background: a filled block here would
   compete with the deprecation banner for the reader's eye, and this is a
   much quieter fact. */
.fn-overloads{margin:6px 0 0 0;padding-left:10px;border-left:2px solid var(--line)}
.fn-ov-label{font-size:10.5px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.04em;margin-bottom:2px}
.fn-ov-sig{font-family:var(--mono);font-size:12.5px;color:var(--ink)}
.fn-ov-raw{font-family:var(--mono);font-size:11.5px;color:var(--muted);font-style:italic}
code{font-family:var(--mono);font-size:.92em;background:var(--accent-soft);
  padding:1px 4px;border-radius:4px}
/* Inside its own view now, so it gets the same padding every other view has
   rather than the trailing gap it needed when it sat at the foot of the
   page under everything else. */
#view-findings{padding:22px 26px 60px}
#findings{padding:0}
#findings table{border-collapse:collapse;width:100%;font-size:12.5px}
#findings th{text-align:left;padding:6px 9px;border-bottom:1px solid var(--line);
  color:var(--muted);font-weight:600;font-size:11.5px;text-transform:uppercase;letter-spacing:.05em}
#findings td{padding:5px 9px;border-bottom:1px solid var(--line);vertical-align:top}
#findings td.msg{font-family:var(--mono);font-size:11.5px;word-break:break-word}
.sev{font-weight:650;text-transform:uppercase;font-size:10.5px;letter-spacing:.05em}
.sev.error{color:var(--error)} .sev.warn{color:var(--warn)} .sev.info{color:var(--info)}
details>summary{cursor:pointer;font-size:13px;color:var(--muted);padding:8px 0}
.wrap{overflow-x:auto}
#view-notes{padding:22px 26px 60px}
#view-notes h3{margin:26px 0 4px;font-size:13px;font-weight:600;color:var(--ink)}
#view-notes h3:first-child{margin-top:0}
#view-notes .nsub,#view-index .nsub,#view-analysis .nsub,#view-features .nsub{
  font-size:12.5px;color:var(--muted);margin:0 0 10px}
/* `#view-features` was missing here while the Features panel emitted the
   same span, so its counter had no rule at all and rendered glued to the
   heading: `FAVORITES6`. Three panels use this badge; three selectors. */
#view-notes .ncount,#view-index .ncount,#view-features .ncount{color:var(--muted);font-weight:400;font-size:11.5px;
  margin-left:6px}
/* A group heading, one level above the per-keyword headings under it.
   The Notes tab now has two halves that answer different questions --
   annotations on functions, markers on lines -- and a reader who cannot
   see the seam reads the second half as more of the first. */
#view-notes h3.ngroup{margin-top:34px;font-size:11px;letter-spacing:.08em;
  text-transform:uppercase;color:var(--muted);border-bottom:1px solid var(--line);
  padding-bottom:6px}
#view-notes h3.ngroup:first-child{margin-top:0}
/* The spelling the author actually typed, when it differs from the
   section it landed in -- `BUG` under FIX. A tag, not prose. */
.nlist .nauthor{font-size:11.5px;color:var(--muted);margin-left:8px}
.nlist .nword{font-family:var(--mono);font-size:11px;color:var(--muted);
  border:1px solid var(--line);border-radius:3px;padding:1px 5px;margin-left:8px}
.nlist{list-style:none;margin:0;padding:0}
.nlist li{padding:7px 0;border-bottom:1px dashed var(--line)}
.nlist li:last-child{border-bottom:0}
.nlist .nfn{font-family:var(--mono);font-size:12.5px;color:var(--accent);
  text-decoration:none;font-weight:600;cursor:pointer}
.nlist .nfn:hover{text-decoration:underline}
.nlist .nfn:focus-visible{outline:2px solid var(--accent-soft);outline-offset:2px}
.godi-wrap{position:relative;display:inline-block}
.godi-tip{display:none;position:absolute;z-index:40;left:0;top:calc(100% + 6px);
  width:min(46ch,80vw);padding:9px 11px;border:1px solid var(--line);border-radius:8px;
  background:var(--panel);color:var(--ink);font-size:12.5px;line-height:1.45;
  box-shadow:0 6px 20px rgba(0,0,0,.18)}
.godi-tip b{color:var(--accent)}
/* Hover *and* focus: a warning only a mouse can see is not a warning. */
.godi-wrap:hover .godi-tip,.godi-wrap:focus-within .godi-tip{display:block}
.godi-off{opacity:.55;text-decoration:line-through}
.godi-note{margin-top:4px;font-size:11.5px;color:var(--muted);max-width:62ch}
/* The Compare tab's Compiler Explorer bar. Above the comparison rather than
   under it: it acts on what is marked, and a control below a matrix of ten
   rows is a control nobody finds. */
.cebar{display:flex;flex-wrap:wrap;align-items:baseline;gap:8px 12px;
  margin:0 0 14px;padding-bottom:12px;border-bottom:1px solid var(--line)}
.cebtn{font:inherit;font-size:12.5px;padding:5px 10px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);color:var(--ink);cursor:pointer}
.cebtn:hover{border-color:var(--accent);color:var(--accent)}
.cebtn:focus-visible{outline:2px solid var(--accent-soft);outline-offset:2px}
.cenote{font-size:12px;color:var(--muted);max-width:64ch}
.cehost{flex-basis:100%}
.cehost>summary{cursor:pointer;font-size:12px;color:var(--muted)}
.cehost .cenote{margin:8px 0}
.cehostin{font:inherit;font-family:var(--mono);font-size:12px;padding:5px 8px;
  border:1px solid var(--line);border-radius:7px;background:var(--bg);
  color:var(--ink);width:min(34ch,100%);margin-right:8px}
.feat-name[data-node]:focus-visible,.feat-tab-name[data-node]:focus-visible{
  outline:2px solid var(--accent-soft);outline-offset:2px}
/* Roving-tabindex lists: the container is the tab stop, the item is what the
   arrows move. Both need to say where focus is. `outline-offset:-2px` on the
   row keeps the ring inside the row box, which a table row would otherwise
   clip against its neighbours. */
#tree:focus-visible,#hist-list:focus-visible,#anbody:focus-visible{
  outline:2px solid var(--accent-soft);outline-offset:-2px}
.row:focus-visible,.crow:focus-visible,tr.anrow:focus-visible{
  outline:2px solid var(--accent);outline-offset:-2px}
.antable th.ansort:focus-visible{outline:2px solid var(--accent-soft);outline-offset:-2px}
.nlist .nwhere{font-family:var(--mono);font-size:11.5px;color:var(--muted);margin-left:8px}
.nlist .ntext{font-size:12.5px;color:var(--ink);margin-top:2px}
/* Unscoped variant: the Analysis panels' empty-state paragraphs
   (`<p class="ntext none">`) and the Features tab both use this outside any
   `.nlist`, and it was previously only ever styled inside one. */
.ntext.none{color:var(--muted);font-style:italic}
/* --- Features tab -------------------------------------------------------- */
#view-features{padding:22px 26px 60px}
.feat-wrap{max-width:820px}
.feat-intro{font-size:13px;color:var(--ink);line-height:1.5;margin-bottom:16px}
/* The intros are rendered Markdown now, so they arrive as real block
   elements. Without these the first paragraph's own top margin pushes the
   block away from its heading and the last one's pushes the next section
   down twice. */
.feat-intro>:first-child,.feat-fileintro>:first-child{margin-top:0}
.feat-intro>:last-child,.feat-fileintro>:last-child{margin-bottom:0}
.feat-intro h1,.feat-intro h2,.feat-intro h3{font-size:13.5px;margin:14px 0 6px}
.feat-intro ul,.feat-fileintro ul{margin:6px 0;padding-left:18px}
.feat-intro code,.feat-fileintro code{font-family:var(--mono);font-size:12px}
.feat-card{border:1px solid var(--line);border-radius:8px;background:var(--panel);
  padding:11px 14px;margin-bottom:8px}
.feat-name{font-size:13px;font-weight:600;color:var(--ink)}
.feat-name[data-node]{cursor:pointer;color:var(--accent)}
.feat-name[data-node]:hover{text-decoration:underline}
.feat-summary{font-size:12.5px;color:var(--ink);margin-top:4px;line-height:1.45}
.feat-meta{margin-top:7px;display:flex;flex-direction:column;gap:2px}
.feat-meta-row{font-size:11.5px;color:var(--muted);font-family:var(--mono)}
.feat-meta-row b{color:var(--ink);font-weight:600;margin-right:4px}
.feat-src{margin-top:6px}
.feat-src a{font-size:10.5px;color:var(--muted);font-family:var(--mono);text-decoration:none;
  cursor:pointer}
.feat-src a:hover{color:var(--accent);text-decoration:underline}
/* A promoted feature's own tab (`Tab: true` — see docs/features_format.md).
   Dynamically created, one `[id^="view-feature-"]` panel per promoted
   feature — `.view`/`.view.active` above already govern its visibility,
   nothing feature-tab-specific needed there. */
[id^="view-feature-"]{padding:22px 26px 60px}
.feat-tab-wrap{max-width:760px}
.feat-tab-theme{font-size:11.5px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.05em}
.feat-tab-name{margin:2px 0 0;font-size:19px;font-weight:600;color:var(--ink)}
.feat-tab-name[data-node]{cursor:pointer;color:var(--accent)}
.feat-tab-name[data-node]:hover{text-decoration:underline}
.feat-tab-summary{font-size:13px;color:var(--ink);margin-top:6px;line-height:1.5}
.feat-tab-body{margin-top:16px;font-size:13px;color:var(--ink);line-height:1.55}
.feat-tab-body h4,.feat-tab-body h5,.feat-tab-body h6{margin:18px 0 4px;font-weight:600;
  color:var(--ink)}
.feat-tab-body h4:first-child,.feat-tab-body h5:first-child,
.feat-tab-body h6:first-child{margin-top:0}
.feat-tab-body p{margin:8px 0}
.feat-tab-body ul{margin:8px 0;padding-left:22px}
.feat-tab-body li{margin:2px 0}
.feat-tab-body pre{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;
  background:var(--accent-soft);border-radius:6px;padding:8px 10px;margin:10px 0;
  overflow-x:auto}
.feat-tab-body pre code{background:none;padding:0}
.feat-tab-body a{color:var(--accent)}
/* One sub-tab per theme file: the Analysis toolbar, allowed to wrap because
   the number of buttons is the repository's, not this page's. */
.feat-themes{flex-wrap:wrap;width:fit-content;max-width:100%;margin-bottom:12px}
.feat-themes .ncount{margin-left:6px}
.feat-group[hidden]{display:none}
.feat-card.feat-flash{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft)}
#hist-list{padding:12px 8px 60px 16px;border-right:1px solid var(--line);
  max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#hist-list{max-height:none;border-right:0;
  border-bottom:1px solid var(--line)}}
#hist-detail{padding:22px 26px 60px;max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#hist-detail{max-height:none}}
.crow{padding:5px 8px;border-radius:6px;cursor:pointer}
.crow:hover{background:var(--accent-soft)}
.crow.sel{background:var(--accent-soft);box-shadow:inset 2px 0 0 var(--accent)}
.crow .csub{font-size:12.5px;color:var(--ink);overflow:hidden;text-overflow:ellipsis;
  white-space:nowrap}
.crow .cmeta{font-family:var(--mono);font-size:10.5px;color:var(--muted);margin-top:1px}
.hist-approx{color:var(--warn);font-size:11.5px;border:1px solid var(--warn);
  border-radius:5px;padding:5px 8px;margin:0 0 12px}
.hist-sec{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin:18px 0 7px;font-weight:600}
.hist-fn{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600}
.hist-callers{list-style:none;margin:2px 0 8px;padding:0 0 0 14px}
.hist-callers li{font-family:var(--mono);font-size:11.5px;color:var(--muted);padding:1px 0}
.hist-mods{display:flex;flex-wrap:wrap;gap:5px;margin:0 0 4px}
.hist-mods a{font-family:var(--mono);font-size:11.5px;padding:2px 7px;border-radius:5px;
  border:1px solid var(--line);color:var(--accent);cursor:pointer;text-decoration:none}
.hist-mods a:hover{border-color:var(--accent);background:var(--accent-soft)}
.hist-mods span.gone{font-family:var(--mono);font-size:11.5px;padding:2px 7px;
  border-radius:5px;border:1px dashed var(--line);color:var(--muted)}
.hist-diff{font-family:var(--mono);font-size:11.5px;white-space:pre;overflow-x:auto;
  background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 12px;
  max-height:460px;overflow-y:auto}
.hist-diff .da{color:var(--file)} .hist-diff .dd{color:var(--error)}
.hist-diff .dh{color:var(--accent);font-weight:600} .hist-diff .dm{color:var(--muted)}
#view-index{padding:22px 26px 60px}
/* The second level, under the tab bar and above the view.

   Visually subordinate on purpose: smaller, no bottom border of its own,
   and the active mark is a filled pill rather than the underline the top
   bar uses. Two rows of identical-looking tabs would read as sixteen tabs
   rather than as eight with a choice inside two of them. */
.subtabs{display:flex;gap:4px;flex-wrap:wrap;padding:7px 20px;
  border-bottom:1px solid var(--line);background:var(--panel)}
.subtabs[hidden]{display:none}
.subtab-btn{border:1px solid transparent;border-radius:999px;background:none;
  color:var(--muted);font-size:12px;padding:3px 11px;cursor:pointer}
.subtab-btn:hover{color:var(--ink)}
.subtab-btn.active{background:var(--accent-soft);color:var(--accent);
  border-color:var(--line);font-weight:600}
.subtab-btn:focus-visible{outline:2px solid var(--accent-soft);outline-offset:1px}
/* The explanation card. Narrower than the annotation card it borrows from:
   these are two sentences about a control, not a function signature with a
   snippet under it, and a wide card over a tab strip covers the tabs. */
/* The graph's own breadcrumb. Quiet: it is orientation, not a control
   group, and it sits beside two buttons that are. */
.hcrumb{display:flex;align-items:center;gap:4px;flex-wrap:wrap;
  font-size:12px;color:var(--muted);margin-left:4px}
.hcrumb[hidden]{display:none}
.hcrumb button{border:none;background:none;padding:1px 4px;border-radius:4px;
  color:var(--accent);font:inherit;cursor:pointer}
.hcrumb button:hover{background:var(--accent-soft)}
.hcrumb .here{color:var(--ink);font-weight:600;padding:1px 4px}
.explainpop{max-width:340px}
.explainpop .fn-desc{white-space:normal;line-height:1.5}
#view-analysis{padding:22px 26px 60px}
#antoggle{margin-bottom:14px;flex-wrap:wrap}
.cl-h{margin:18px 0 6px;font-size:14px}
.cl-h .cl-src{font-weight:400;font-size:11.5px;color:var(--muted);margin-left:8px}
.cl-list{list-style:none;margin:0;padding:0}
.cl-item{display:flex;flex-wrap:wrap;align-items:baseline;gap:8px;padding:7px 10px;
  border:1px solid var(--line);border-radius:7px;background:var(--panel);margin-bottom:6px}
.cl-box{font-family:ui-monospace,monospace;color:var(--muted)}
.cl-item.cl-done .cl-box{color:var(--accent)}
.cl-text{flex:1 1 320px}
.cl-ref,.cl-date,.cl-meta{font-size:11.5px;color:var(--muted)}
.cl-ref{font-family:ui-monospace,monospace}
.cl-state{font-size:11.5px;padding:1px 7px;border-radius:999px;border:1px solid var(--line)}
.cl-stale{color:#b3261e;border-color:#b3261e}
.cl-unverified{color:#8a6d00;border-color:#8a6d00}
.cl-uncited,.cl-unknown{color:var(--muted)}
.cl-current{color:var(--muted)}

.antable{width:100%;border-collapse:collapse;font-size:12.5px}
.antable th.ansort{cursor:pointer;user-select:none;white-space:nowrap}
.antable th.ansort:hover{color:var(--ink)}
.antable th.ansort.active{color:var(--accent)}
.antable th{text-align:left;font-weight:600;color:var(--muted);font-size:11.5px;
  text-transform:uppercase;letter-spacing:.03em;padding:4px 8px;border-bottom:1px solid var(--line);
  background:var(--panel);position:sticky;top:0}
.antable td{padding:5px 8px;border-bottom:1px dashed var(--line);font-family:var(--mono)}
.dupview{display:flex;gap:4px;margin:8px 0}
.dupview-btn{font:inherit;font-size:12.5px;padding:2px 10px;border:1px solid var(--line);border-radius:4px;background:var(--panel);color:var(--ink);cursor:pointer}
.dupview-btn.active{background:var(--accent-soft);border-color:var(--accent)}
.dupcl-mods{display:flex;flex-wrap:wrap;gap:8px}
.dupcl-mod{flex-basis:220px;min-width:0;border:1px solid var(--line);border-radius:4px;padding:6px 8px;background:var(--panel)}
.dupcl-name{font-weight:600;font-size:12.5px;margin-bottom:4px;overflow-wrap:anywhere}
.dupcl-fn{font-size:12.5px;padding:2px 4px;overflow-wrap:anywhere}
.dupcl-fn:hover{background:var(--accent-soft)}
.dupcl-line{color:var(--muted)}
.anrow{cursor:pointer}
.anrow:hover td{background:var(--accent-soft)}
.anflag{color:var(--warn);font-size:11.5px;border:1px solid var(--warn);
  border-radius:4px;padding:1px 5px;margin-left:6px}
.anbar{width:120px;height:8px;background:var(--line);border-radius:4px;overflow:hidden}
.anfill{height:100%;background:var(--accent)}
.telpicker{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:10px;font-size:12.5px}
.telpicker label{display:flex;align-items:center;gap:6px;color:var(--muted)}
.telpicker select{font:inherit;color:var(--ink);background:var(--panel);
  border:1px solid var(--line);border-radius:5px;padding:2px 6px}
.telup{color:var(--file);font-weight:600}
.teldown{color:var(--warn);font-weight:600}
#view-index h3{margin:22px 0 6px;font-size:15px;font-weight:700;color:var(--accent);
  font-family:var(--mono);border-bottom:1px solid var(--line);padding-bottom:3px}
.ixjump{display:flex;flex-wrap:wrap;gap:3px;margin:0 0 6px;position:sticky;top:0;
  background:var(--bg);padding:6px 0;z-index:2}
.ixjump a{font-family:var(--mono);font-size:12.5px;padding:2px 7px;border-radius:5px;
  border:1px solid var(--line);color:var(--accent);cursor:pointer;text-decoration:none}
.ixjump a:hover{border-color:var(--accent);background:var(--accent-soft)}
.ixlist li{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap;padding:3px 0}
.ixtag{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);
  border:1px solid var(--line);border-radius:4px;padding:0 4px}
.ixtag.dep{color:var(--error);border-color:var(--error)}
.ixtag.tested{color:var(--accent);border-color:var(--accent)}
#view-hierarchy{padding:16px 24px 60px}
.hctl{display:flex;gap:8px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.hctl .hpath{font-family:var(--mono);font-size:12.5px;color:var(--muted);word-break:break-all}
.hctl button{padding:4px 9px;font-size:12.5px}
#hgraph-outer{position:relative}
/* `max-height` is not optional here — same `calc(100vh - 132px)` #detail
   and #hist-detail already cap themselves at, reused rather than
   invented. Without it `overflow:auto` has nothing to overflow *against*:
   a block with no height constraint sizes to its content, so as
   `applyZoom()` grows #hgraph's own width/height to match the scaled
   diagram, #hgraph-wrap (and everything containing it, up to the page
   itself) grew right along with it instead of clipping the content
   behind scrollbars. Reported exactly that way, watching someone zoom in
   and the whole page grow under them rather than the diagram zooming
   within a fixed frame — the zoom math itself (cursor-anchored, see
   zoomAt()) was already correct; this was the one property missing that
   let it actually behave like a viewport. */
#hgraph-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;
  background:var(--panel);max-height:calc(100vh - 132px)}
/* Root-level hide/show slider (Modules view only) — a vertical Google
   Maps-style control: "+" hides one more layer (zooming into a narrower
   slice of the tree), "-" shows one more (zooming back out). Positioned
   against #hgraph-outer, not #hgraph-wrap, so it stays put while the
   diagram underneath scrolls.

   Reported, watching someone use the page for the first time: this reads
   as an actual zoom control, not a tree-depth one — the vertical
   range-input shape and the "+"/"-" pair are exactly what a real zoom
   widget would look like, and this comment's own "zooming into a
   narrower slice" phrasing shows why: the word applies here only as a
   metaphor. `.hrootslider-label` exists because the tooltip
   (`title="Hide root levels…"`) was the only place that said so, and
   nobody hovers a control to find out what it does before deciding
   whether to use it. */
.hrootslider{position:absolute;left:10px;top:14px;z-index:20;display:none;
  flex-direction:column;align-items:center;gap:4px;background:var(--panel);
  border:1px solid var(--line);border-radius:8px;padding:8px 6px;
  box-shadow:0 2px 8px rgba(0,0,0,.14)}
.hrootslider.on{display:flex}
.hrootslider-label{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;
  color:var(--muted);white-space:nowrap;margin-bottom:1px}
.hroot-btn{width:22px;height:22px;padding:0;border:1px solid var(--line);
  border-radius:5px;background:var(--bg);color:var(--ink);font-size:14px;
  line-height:1;cursor:pointer;display:flex;align-items:center;justify-content:center}
.hroot-btn:hover:not(:disabled){border-color:var(--accent);color:var(--accent)}
.hroot-btn:disabled{opacity:.35;cursor:default}
/* `writing-mode:vertical-lr` turns a plain range input vertical with no JS
   transform hack — min renders at the bottom, max at the top, which is
   exactly "+" (more hidden, higher value) above "-" (less hidden, lower
   value) without any extra flipping. */
#hrootrange{writing-mode:vertical-lr;width:20px;height:84px;margin:2px 0;
  cursor:pointer;accent-color:var(--accent)}
/* Middle-drag panning. `grabbing` only while a drag is live — a permanent
   grab cursor would advertise left-drag panning, which is deliberately not
   what this does. `user-select:none` is on the dragging state only, so text
   in the boxes stays selectable the rest of the time. */
#hgraph-wrap.panning{cursor:grabbing;user-select:none}
#hgraph{position:relative}
/* The zoom lives on its own layer. #hstage carries the transform and keeps the
   analytic pixel layout; #hgraph is sized to the *scaled* extent, because a
   transform does not change layout size and the scroll area would otherwise
   not grow when zooming in. */
#hstage{position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform}
#hstage.zooming{transition:none}
#hstage.jumping{transition:transform .34s cubic-bezier(.2,.7,.2,1)}
/* Level of detail: below ~0.65 the secondary line is unreadable grey noise,
   so it goes away rather than being rendered illegibly. Pure CSS — no redraw. */
#hstage.lod-min .hsm,#hstage.lod-min .hline,#hstage.lod-min .hkind{display:none}
#hstage.lod-min .hnode{padding:4px 8px}
.hzoom{font-family:var(--mono);font-size:11.5px;color:var(--muted);min-width:44px;
  text-align:right}
@media (prefers-reduced-motion:reduce){#hstage.jumping{transition:none}}
.hnode{position:absolute;box-sizing:border-box;padding:7px 10px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);cursor:pointer;overflow:hidden}
.hnode:hover{border-color:var(--accent);z-index:1}
/* Pinned: the focus is being held rather than followed. A ring rather than
   a different colour, because the box keeps whatever its language and kind
   already say about it — this adds a state, it does not replace one. Without
   it, a held focus and a hovered one look identical and the reader cannot
   tell whether moving the mouse will cost them the view. */
.hnode.pinned{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft);z-index:2}
.hnode .hnm{font-family:var(--mono);font-size:12.5px;font-weight:600;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.hnode .hsm{font-size:10.5px;color:var(--muted);margin-top:2px;max-height:2.6em;overflow:hidden}
.hnode.k-module .hnm{color:var(--mod)} .hnode.k-namespace .hnm{color:var(--ns)} .hnode.k-file .hnm{color:var(--file)}
#hsvg{position:absolute;top:0;left:0;pointer-events:none}
.hedge{fill:none;stroke:var(--muted);stroke-width:1.5;opacity:.6}
.hedge-type{stroke:var(--accent);stroke-dasharray:4 3;opacity:.75}
.hedge-ext{stroke:var(--ext);stroke-width:2;opacity:.9}
.hmsg{color:var(--muted);font-size:13px;padding:20px;text-align:center}
.htrunc{color:var(--warn);font-size:12.5px;margin-top:8px}
#halt{border:1px solid var(--line);border-radius:8px;background:var(--panel)}
#halt-bar{padding:8px;border-bottom:1px solid var(--line);margin:0}
#halt-bar .hmuted{color:var(--muted);font-size:12.5px}
#htq{min-width:260px}
#halt-body{max-height:calc(100vh - 190px);overflow:auto;padding:4px 0}
.ht-row{display:flex;gap:10px;align-items:baseline;padding:3px 8px;cursor:pointer;white-space:nowrap}
.ht-row:hover,.ht-row:focus{background:var(--line);outline:none}
.ht-row.dim{opacity:.45}
.ht-row.hit .ht-name{text-decoration:underline}
.ht-tw{width:12px;flex:none;color:var(--muted)}
.ht-name{font-family:ui-monospace,monospace;font-weight:600}
.ht-kind,.ht-num{color:var(--muted);font-size:12px}
.ht-sum{color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis}
.tm{position:relative;margin:4px}
.tm-group,.tm-tile{position:absolute;box-sizing:border-box;overflow:hidden;border:1px solid var(--panel)}
.tm-group{background:color-mix(in srgb,var(--accent) 12%,var(--panel))}
.tm-head{font-size:11.5px;font-weight:600;padding:1px 4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;cursor:pointer}
.tm-tile{background:color-mix(in srgb,var(--accent) 30%,var(--panel));font-size:11px;padding:1px 3px;cursor:pointer;white-space:nowrap;text-overflow:ellipsis}
.tm-tile.tm-solo{background:color-mix(in srgb,var(--accent) 22%,var(--panel))}
.tm-tile:hover,.tm-head:hover{outline:2px solid var(--accent);outline-offset:-2px}
.tm-group.dim,.tm-tile.dim{opacity:.4}
/* The Coupling plot. The corner a dot is in is said by its place, its
   tooltip and the readout; the fill only tells the expensive corners from
   the leaves, in lightness as well as hue. */
.cq{display:block;margin:4px 5px}
.cq-axis{fill:none;stroke:var(--line);stroke-width:1}
.cq-split{stroke:var(--line);stroke-width:1;stroke-dasharray:4 4}
.cq-tick,.cq-label{fill:var(--muted);font-size:11px}
.cq-corner{fill:var(--muted);font-size:12px;font-weight:600}
.cq-corner .cq-n{font-weight:400}
.cq-dot{fill:color-mix(in srgb,var(--accent) 45%,var(--panel));stroke:var(--accent);stroke-width:1;cursor:pointer}
.cq-dot.cq-hub,.cq-dot.cq-tangle{fill:var(--accent)}
.cq-dot.cq-leaf{fill:var(--panel)}
.cq-dot.dim{opacity:.35}
.cq-dot:hover,.cq-dot:focus{stroke:var(--ink);stroke-width:2;outline:none}
.cq-read{margin-left:auto;font-family:var(--mono);font-size:11.5px;color:var(--ink)}
.htrunc.hauto{color:var(--muted)}
/* The Rings view. A ring is a line and a name; the last one, for what the
   entry does not reach, is dashed. A box out there is dashed as well and says
   so in its second line; one that carries the unreferenced-module finding
   names the finding there and has a heavier border. The colour of a warning
   comes on top of that, it is never the only sign. */
.hring{fill:none;stroke:var(--line);stroke-width:1.5}
.hring.hring-out{stroke:var(--warn);stroke-dasharray:6 5}
.hring-label{fill:var(--muted);font-size:11.5px;font-family:var(--mono);paint-order:stroke;stroke:var(--panel);stroke-width:5px;stroke-linejoin:round}
.hring-label.hring-out{fill:var(--warn)}
#hsvg .hedge.hedge-quiet{opacity:0}
#hgraph.focusing .hedge.hedge-quiet{opacity:0}
#hgraph.focusing .hedge.hedge-quiet.near{opacity:1}
/* The Layers view. A band is a stripe, a layer a frame in it; what no rule
   names sits in a dashed stripe below. A require that breaks a rule is the
   one arrow always drawn, over the boxes (#hsvg2), heavier than any other
   edge, and the module it leaves says so in words and has a heavier border:
   the red comes on top of that. */
#hsvg2{position:absolute;top:0;left:0;pointer-events:none;z-index:3}
.hband{fill:color-mix(in srgb,var(--accent) 5%,transparent);stroke:var(--line);stroke-width:1}
.hband.hband-loose{fill:none;stroke-dasharray:6 5}
.hunit{fill:var(--panel);stroke:var(--line);stroke-width:1.5}
.hmap-label{fill:var(--muted);font-size:11.5px;font-family:var(--mono);paint-order:stroke;stroke:var(--panel);
  stroke-width:4px;stroke-linejoin:round}
.hmap-label.hunit-name{fill:var(--ink);font-weight:600}
.hedge-viol{stroke:var(--error);stroke-width:2.5;opacity:.95}
#hgraph.focusing .hedge.hedge-viol.near{stroke-width:3.5}
#m-viol path{fill:var(--error)}
.hlegend .sw.viol{border-top-color:var(--error);border-top-width:3px}
.hnode.lv-from,.hlegend .bx.lv-from{border-color:var(--error);border-width:2px}
.hnode.lv-from .hkind{color:var(--error)}
.hmap-note button{padding:2px 8px;font-size:12px;margin-left:4px}
/* The Routes view. The kind of a segment is in its name as written on disk
   (brackets, parentheses, @); a box that is a route has a heavier left edge
   and its URL below the name, one that only groups is dashed. */
.hnode.rt-route,.hlegend .bx.rt-route{border-left:4px solid var(--accent)}
.hnode.rt-handler{border-left-style:double}
.hnode.rt-group,.hnode.rt-slot,.hnode.rt-intercept{border-style:dashed}
.hnode.rt-group .hnm,.hnode.rt-slot .hnm{color:var(--muted)}
.hnode.rt-dynamic .hnm,.hnode.rt-catchall .hnm,.hnode.rt-optional .hnm{color:var(--fn)}
.hnode.rt-root .hnm{color:var(--mod)}
.hnode.ring-out,.hlegend .bx.ring-out{border-style:dashed}
.hnode.ring-out .hnm{color:var(--muted)}
.hnode.ring-unref,.hlegend .bx.ring-unref{border-color:var(--warn);border-width:2px}
.hnode.ring-unref .hkind{color:var(--warn)}
.hlegend .bx.ring-entry{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft)}
.hring-note button{padding:2px 8px;font-size:12px;margin-left:4px}
#hentry{max-width:260px}
/* Sits directly before `#hdepth`'s button group. "1"/"2"/"3"/"∞" alone
   read as a slider or a zoom control — reported exactly that way after
   watching someone use the page for the first time — because every other
   number on this toolbar (`#hzoomlabel`) *is* a percentage. Direction and
   view-switcher groups need no such label; their own button text
   ("← In", "Out →", "Modules") already says what they do. */
.hctl-label{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;
  color:var(--muted);align-self:center}
.hview-toggle{display:flex;gap:0;border:1px solid var(--line);border-radius:7px;overflow:hidden}
.hview-toggle button{border:none;border-radius:0;padding:4px 10px;font-size:12.5px}
.hview-toggle button+button{border-left:1px solid var(--line)}
.hview-toggle button.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
/* Marks a panel/mode that only does anything when a soft-dependency plugin
   (or, for Tools, a project-level manifest file) is present -- same signal
   `--ext` already carries for "connects outside this map" in the Hierarchy
   graphs, reused here for "depends on something outside this plugin". The
   badge is the primary cue (readable even without color); the tint is a
   second one for a quick scan of the tab bar. */
.hview-toggle button.plugin-gated{color:var(--ext)}
.hview-toggle button.plugin-gated::after{content:"\1F50C";font-size:9.5px;margin-left:3px;opacity:.85}
.hview-toggle button.plugin-gated.active{background:var(--ext);color:var(--bg);font-weight:600}
.anview-group{display:flex;align-items:stretch;border-left:1px solid var(--line)}
.anview-group-label{align-self:center;padding:0 8px;font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted)}
.anview-group-label+button{border-left:1px solid var(--line)}
.hnode.t-class .hnm{color:var(--mod)}
.hnode.t-alias .hnm{color:var(--ns)}
.hnode .hkind{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-top:1px}
/* --- Stats grid + module-scope symbols in the detail pane --------------- */
.stat-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:7px;
  margin-bottom:6px}
.stat{border:1px solid var(--line);border-radius:7px;padding:6px 9px;background:var(--panel)}
.stat b{display:block;font-size:15px;font-weight:650;font-family:var(--mono)}
.stat span{font-size:10.5px;color:var(--muted)}
.sec .sub{text-transform:none;letter-spacing:0;font-weight:400;font-size:10.5px}
.lst.syms li{padding:4px 0;color:var(--ink)}
.sdet{color:var(--muted);font-size:11.5px;font-family:var(--mono)}
.bd.sk-table{color:var(--mod);border-color:var(--mod)}
.bd.sk-constant{color:var(--file);border-color:var(--file)}
.bd.sk-binding{color:var(--ns)}
#findings tbody tr[data-node]{cursor:pointer}
#findings tbody tr[data-node]:hover{background:var(--accent-soft)}
/* --- Quicks ------------------------------------------------------------- */
.qk-wrap{padding:18px 24px;max-width:1100px}
.qk-col{margin-bottom:22px}
.qk-h{font-size:12.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin-bottom:9px}
.qk{border:1px solid var(--line);border-left-width:3px;border-radius:8px;background:var(--panel);
  padding:11px 14px;margin-bottom:8px}
.qk.good{border-left-color:var(--ok,#3f9142)}
.qk.bad{border-left-color:var(--error)}
.qk-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.qk-line{font-size:14px;font-weight:600;color:var(--ink)}
.qk-val{font-family:var(--mono);font-size:12.5px;color:var(--muted);white-space:nowrap}
/* The reason a verdict is allowed to be a sentence at all — see quicks.lua's
   header. Quieter than the sentence, never hidden behind a disclosure. */
.qk-basis{font-size:11.5px;color:var(--muted);margin-top:5px;line-height:1.45}
.qk-acts{margin-top:8px;display:flex;gap:7px;flex-wrap:wrap}
.qk-acts button{font-size:11.5px;padding:3px 9px}
.qk-none{color:var(--muted);font-size:13px;padding:6px 0}
/* --- Compare marks ------------------------------------------------------ */
/* Sits beside `.sigi` rather than replacing its click: that click already
   pins the annotation popup open, which is what makes a long `@example`
   readable, and taking it over would trade one affordance for another. */
.marki{display:inline-block;margin-left:3px;padding:0 4px;border-radius:4px;cursor:pointer;
  font-size:10.5px;line-height:15px;color:var(--muted);border:1px solid var(--line);
  opacity:.45;transition:opacity .12s,color .12s,background .12s;user-select:none}
.marki:hover,.marki:focus{opacity:1;color:var(--accent);border-color:var(--accent);outline:none}
li:hover>.marki,tr:hover .marki{opacity:.8}
.marki.on{opacity:1;color:var(--bg);background:var(--accent);border-color:var(--accent)}
.markbar{white-space:nowrap}
.markbar.has{color:var(--accent);border-color:var(--accent);font-weight:600}
/* --- Compare tab -------------------------------------------------------- */
#cmpbody{padding:14px 24px}
.cmp-cols{display:flex;gap:12px;overflow-x:auto;padding-bottom:8px;align-items:flex-start}
.cmp-cols .cmp-card{flex:0 0 340px}
.cmp-stack .cmp-card{margin-bottom:12px}
.cmp-card{border:1px solid var(--line);border-radius:8px;background:var(--panel);padding:12px 14px}
.cmp-card-h{display:flex;justify-content:space-between;align-items:baseline;gap:8px;
  margin-bottom:6px}
.cmp-where{font-family:var(--mono);font-size:11.5px;color:var(--accent)}
.cmp-drop{border:none;background:none;color:var(--muted);cursor:pointer;font-size:14px;padding:0 3px}
.cmp-drop:hover{color:var(--error)}
.cmptable{width:100%;border-collapse:collapse;font-size:12.5px}
.cmptable th,.cmptable td{border:1px solid var(--line);padding:6px 9px;text-align:left;
  vertical-align:top}
.cmptable thead th{background:var(--panel);position:sticky;top:0;font-size:11.5px}
.cmptable tbody th{background:var(--panel);font-weight:600;color:var(--muted);
  font-size:11.5px;white-space:nowrap}
/* The point of the matrix: a row where every marked object agrees is not what
   the reader came for, so the ones that differ are the ones that are lit. */
.cmptable tr.differs td{background:var(--accent-soft)}
.cmptable tr.differs th{color:var(--ink)}
.cmp-scroll{overflow-x:auto}

/* --- Function rows in the tree ------------------------------------------ */
.row.k-fn .nm{color:var(--fn)}
.row.fnhead .nm{color:var(--muted);font-style:italic}
.fnkids.hide{display:none}

/* --- Graph: edge kinds, arrowheads, legend ------------------------------ */
.hedge-dep{stroke:var(--dep);opacity:.8}
.hedge-dep.deferred{stroke-dasharray:2 4;opacity:.55}
.hedge-dep.external{stroke-dasharray:6 3;opacity:.5}
.hnode.k-external{border-style:dashed;background:none}
.hnode.k-external .hnm{color:var(--muted)}
.hnode.k-external.linked{border-style:solid;border-color:var(--accent)}
.hnode.k-external.linked .hnm{color:var(--accent)}
.hlegend .sw.dep.external{border-top-style:dashed}
#hext.active button{background:var(--accent-soft);color:var(--accent);font-weight:600}
#hgest.active button{background:var(--accent-soft);color:var(--accent);font-weight:600}
.hedge-call{stroke:var(--call);opacity:.8}
.hedge-call.weak{stroke-dasharray:3 4;opacity:.5}
/* An invisible, much wider companion path per edge. A 1.5px line is a 1.5px
   hover target, which is not a target — the weighted Module Calls edges made
   that obvious, since the thing worth reading (how many calls, which way) was
   hardest to point at on the thinnest edges. `stroke:transparent` rather than
   `opacity:0`: an `opacity:0` element still paints nothing *and* still takes
   pointer events, but reads to a future editor as "hidden, delete me".
   `pointer-events:stroke` is not optional here — #hsvg itself is
   `pointer-events:none` (so the HTML boxes stacked on top of the SVG stay
   clickable through it), and every path inside inherits that unless it
   opts back in. Missed the first time, and invisible to any test that
   fires the handler directly instead of a real hit-tested mouse event:
   `element.dispatchEvent(new MouseEvent(...))` runs the listener
   regardless of `pointer-events`, since that property only gates the
   browser's own hit-testing for real input, not a manually dispatched
   event. `document.elementFromPoint` at a hedge-hit's own screen
   coordinates returned the background `<div>` underneath, never the SVG
   at all, until this line existed. `stroke` rather than `auto`: this
   shape is `fill:none`, so only the stroked band should ever be
   clickable — `auto` happens to behave the same way here, `stroke` says
   so without depending on that being true. */
.hedge-hit{fill:none;stroke:transparent;stroke-width:14;cursor:default;pointer-events:stroke}
/* Edge readout. `position:fixed` for exactly the reason `.sigpop` is: the
   graph lives in a pannable, zoomable stage, and an absolutely-positioned
   card would ride along with that transform instead of staying by the
   cursor. `pointer-events:none` so it can never sit between the cursor and
   the edge it describes and flicker the hover off. */
.hedge-tip{position:fixed;z-index:60;display:none;pointer-events:none;
  background:var(--bg);border:1px solid var(--line);border-radius:6px;
  box-shadow:0 6px 20px rgba(0,0,0,.18);padding:6px 9px;font-size:11.5px;
  max-width:300px;line-height:1.5}
.hedge-tip.on{display:block}
.hedge-tip .et-row{white-space:nowrap;font-family:var(--mono);color:var(--ink)}
.hedge-tip .et-n{font-weight:650;color:var(--call)}
/* The reverse direction, when the pair calls both ways. Muted because it is
   context for the edge under the cursor, not the edge itself. */
.hedge-tip .et-back{color:var(--muted)}
.hedge-tip .et-back .et-n{color:var(--muted)}
#hsvg marker path{stroke:none}
#m-tree path{fill:var(--muted)}
#m-type path{fill:var(--accent)}
#m-ext path{fill:var(--ext)}
#m-dep path{fill:var(--dep)}
#m-call path{fill:var(--call)}
.hlegend{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:10px 0 0;
  font-size:11.5px;color:var(--muted)}
.hlegend .lg{display:inline-flex;align-items:center;gap:5px}
.hlegend .sw{width:20px;height:0;border-top:2px solid var(--muted)}
.hlegend .sw.type{border-top-style:dashed;border-top-color:var(--accent)}
.hlegend .sw.ext{border-top-color:var(--ext);border-top-width:3px}
.hlegend .sw.dep{border-top-color:var(--dep)}
.hlegend .sw.dep.deferred{border-top-style:dotted}
.hlegend .sw.call{border-top-color:var(--call)}
.hlegend .sw.call.weak{border-top-style:dashed}
.hlegend .bx{width:11px;height:11px;border-radius:3px;border:1px solid currentColor}
.hnode.k-fn .hnm{color:var(--fn)}
/* Tint of the Modules view (see the maps slice). One hue in four steps of opacity over the box's own
   background, so the steps differ in lightness in both themes; the value is printed on the box, so the colour
   is never the only carrier. From step 3 on the name is drawn in the ink colour: the kind colours do not
   hold their contrast on the darker steps. */
.tint-1{background-image:linear-gradient(rgba(var(--tint),var(--ta1)),rgba(var(--tint),var(--ta1)))}
.tint-2{background-image:linear-gradient(rgba(var(--tint),var(--ta2)),rgba(var(--tint),var(--ta2)))}
.tint-3{background-image:linear-gradient(rgba(var(--tint),var(--ta3)),rgba(var(--tint),var(--ta3)))}
.tint-4{background-image:linear-gradient(rgba(var(--tint),var(--ta4)),rgba(var(--tint),var(--ta4)))}
.hnode.tint-3 .hnm,.hnode.tint-4 .hnm,.hnode.tint-3 .hsm,.hnode.tint-4 .hsm{color:var(--ink)}
.hnode.tint-na,.hlegend .bx.tint-na{border-style:dashed}
#hstage.tinted .hnode .hnm{padding-right:38px}
.hnode .htv{position:absolute;top:6px;right:8px;font-family:var(--mono);font-size:10.5px;font-weight:600;
  color:var(--ink)}
.htint{display:inline-flex;align-items:center;gap:6px}
.htint select{font:inherit;font-size:12.5px;padding:3px 6px;border:1px solid var(--line);border-radius:7px;
  background:var(--panel);color:var(--ink)}
.hlegend .lg-tint b{color:var(--ink);font-weight:600}
.hnode.center{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft)}
.hnode .hline{font-size:9.5px;color:var(--muted);margin-top:1px;font-family:var(--mono)}

/* --- Graph: movement ---------------------------------------------------
   Boxes keep their identity across redraws (see reconcile() in the JS), so a
   re-center animates the boxes that survive from their old position to their
   new one instead of the whole diagram cutting. left/top are transitioned
   rather than transform, because positions are already absolute pixels
   computed from the IR — a transform would need a second coordinate system
   for no gain. */
.hnode{transition:left .34s cubic-bezier(.2,.7,.2,1),top .34s cubic-bezier(.2,.7,.2,1),
  opacity .22s ease,border-color .15s ease}
.hnode.entering{opacity:0;transform:scale(.94)}
.hnode.leaving{opacity:0;pointer-events:none}
#hsvg,#hsvg2{transition:opacity .18s ease}
#hsvg.settling,#hsvg2.settling{opacity:0}
.hnode.pulse{animation:hpulse .7s ease-out}
@keyframes hpulse{
  0%{box-shadow:0 0 0 0 var(--accent)}
  100%{box-shadow:0 0 0 12px transparent}
}
/* Hover focus: dim everything that is not a direct neighbour. Class-driven so
   it costs no layout recomputation on a graph that can hold 90 boxes. */
#hgraph.focusing .hnode{opacity:.22}
#hgraph.focusing .hnode.near{opacity:1}
#hgraph.focusing .hedge{opacity:.08}
#hgraph.focusing .hedge.near{opacity:1;stroke-width:2}
/* Persistent per-box dim (":DocMap"'s "hide/dim a module" — see the JS
   section above this one for the state it reads). Same opacity mechanism as
   hover-focus, deliberately independent of it: a dimmed box has to stay
   dimmed even when hover-focus would otherwise light it up as a ".near"
   neighbour, which is why both overrides below repeat the "#hgraph.focusing"
   prefix — equal specificity to the rules above, decided by source order. */
.hnode.hidden{opacity:.08;pointer-events:none}
#hgraph.focusing .hnode.hidden{opacity:.08}
#hgraph.focusing .hnode.hidden.near{opacity:.08}
.hedge{transition:opacity .15s ease}
@media (prefers-reduced-motion:reduce){
  .hnode,#hsvg,#hsvg2,.hedge{transition:none}
  .hnode.pulse{animation:none}
}

/* --- Context menu ------------------------------------------------------- */
#ctx{position:fixed;z-index:50;min-width:210px;padding:5px;border:1px solid var(--line);
  border-radius:9px;background:var(--panel);box-shadow:0 8px 28px rgba(0,0,0,.18);display:none}
#ctx.open{display:block}
#ctx .ci{display:flex;align-items:center;gap:8px;padding:6px 10px;border-radius:6px;
  font-size:12.5px;cursor:pointer;white-space:nowrap;color:var(--ink)}
#ctx .ci:hover,#ctx .ci.hi{background:var(--accent-soft);color:var(--accent)}
#ctx .ci.disabled{color:var(--muted);cursor:default;opacity:.6}
#ctx .ci.disabled:hover{background:none;color:var(--muted)}
#ctx .ci .hint{margin-left:auto;font-size:10.5px;color:var(--muted)}
#ctx .sep{height:1px;background:var(--line);margin:4px 6px}
#ctx .hdr{padding:5px 10px 6px;font-family:var(--mono);font-size:11.5px;color:var(--muted);
  max-width:280px;overflow:hidden;text-overflow:ellipsis}
]]
