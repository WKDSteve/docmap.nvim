# The generated page, tab by tab

What each tab of `docs/map/index.html` shows, and why it shows it that way.
[The README](../README.md) says what the page *is*; [`pipeline.md`](pipeline.md)
says how each of these is computed. This page is the tour in between.

The Analysis tab ranks the tree eight ways, seven of them over the same IR —
test coverage, documentation coverage, fan-in/fan-out, cyclomatic complexity,
structural **duplicates** (functions whose parse-tree shape is identical,
which is the one kind of drift the require graph is blind to by construction
— two modules that each grew their own `read(path)` do not require each
other), **plugins**: every lazy.nvim spec in the tree, which matters when
`docmap.nvim` is pointed at a Neovim *config* rather than a plugin —
`lua/plugins/*.lua` is mostly `return { { "author/repo", event = "…" } }`
with no function in sight, invisible to every other panel — and **tools**:
this repo's own [`lib.nvim.deps`](https://github.com/WKDSteve/lib.nvim)
manifest (`docs/install.json`/`docs/INSTALL.md`), declared only — never a
live "is this installed here" probe, since a static page has no host to
ask. The eighth, **telemetry**, is the odd one out on purpose: call counts
change between runs, so unlike the other seven it is never baked into the
page — `:DocMap serve` reads [`runtime-analysis.nvim`](https://github.com/WKDSteve/runtime-analysis.nvim)'s
own counts fresh on every open instead, the same on-demand shape the
History tab already uses for the one other thing that cannot live in a
static artifact.

The Hierarchy tab draws six graphs and two layer-free views over the same IR — **Modules** (directory
hierarchy), **Types** (`@class`/`@alias` collaboration), **Inheritance**,
**Deps** (the require graph), **Calls** (function-level caller/callee) and
**Module Calls** (the same call graph collapsed module-to-module, edges
weighted by call count) — with direction and depth controls, semantic zoom,
right-click navigation and real browser Back/Forward. Right-click any box to
dim it (a "Hidden (N) — show all" pill clears them), shareable via the URL
the same way marks are — noise-reduction for a large tree, not a structural
re-layout. The Modules view also has a vertical zoom-style slider that hides
the top N levels of a deep tree, turning every node that used to sit at that
depth into its own parallel root — useful the moment a tree is several
directories deep before anything interesting starts.

Opened without a center in the URL, Deps, Calls and Module Calls do not start
on the root — a folder that requires nothing and declares no functions — but
on the node with the most edges of their kind, and say so under the graph; a
click or the search box re-centers as usual. A center somebody chose is kept,
and when it has no edge of the view's kind the view explains that instead of
drawing boxes with nothing between them.

Two more views read the same directory tree without laying a level out as one
row, for projects whose levels are too wide for boxes (an nvim config has 310
namespaces; the Modules view stops at 90 boxes). **Tree** is a folding list
from the center: a filter keeps every match and the path to it (`tq=` in the
link), the arrows walk and fold, Enter or a click on a name roots the tree
there. **Treemap** draws everything under the center as nested areas sized by
lines of code, or by functions (`tm=functions`): a click zooms into a group, a
leaf opens in the Tree tab, and ▲ Up and the path above go back. Rows and tiles
take the same right-click menu as boxes, and dimmed nodes stay dimmed.

**Rings** lays the require graph out by distance from an entry module and
answers "how deep is this, and what is reachable at all?". The entry sits in
the middle; ring 1 holds what it requires itself, ring 2 what those require,
and so on, each module once, on the ring of its shortest require chain (a lazy
require counts like any other). Whatever no chain reaches sits in a last,
dashed ring. That ring is the `unreferenced-module` finding as a picture: the
modules that carry the finding are marked and named as such, the others out
there are required only by unreachable modules or are exempt from the check,
and the line under the diagram gives the counts and leads to the Findings tab.
The entry is the center of the Hierarchy when that is a module, so a link
(`center=`), the search box and a second click on a box all choose it. When
the center is a folder, the rings start at the root of the map if that is a
module (a plugin's `init.lua`), else at the module that reaches the most; the
**Entry** select in the toolbar lists the roots of the require graph (modules
that require something and that nothing requires) with how many modules each
reaches, for a tree with several entries or without an `init.lua`. Arrows are
shown for the box under the pointer or the pin only: its chain back to the
entry and what is first reached through it. The view draws in the same zooming
diagram as the box views, so zoom, pan, dimming, the right-click menu and the
SVG export (rings, their names, and the chain when a box is pinned) work as
they do there. A ring too long for one row takes several; past 400 modules the
unreachable ring and the deepest rings are cut first, and the page says so.

**Layers** draws the tree in the bands its layering rules imply and answers
"does this tree have the shape I claim it has?". It needs `layers` in
`.docmap.json` (or `opts.layers`); without them the view says so and shows how
a rule looks. A rule is one forbidden direction ("modules under `from` may not
require modules under `to`"), not an ordered list, so the bands are derived:
every prefix a rule names is a layer, a module belongs to the layer with the
longest prefix it sits under, and a layer that may not reach another sits
*below* it, because the forbidden direction is up. The band of a layer is the
longest chain of such steps below it; the base is at the bottom. Rules need
not form an order: layers that forbid each other in a circle (two halves that
must not know each other) share one band, side by side, and the line under the
diagram names them. The prefix of a sibling rule is one layer, marked
*siblings*; modules of an `allow` list are tagged as shared targets, and the
modules no rule names sit in a dashed stripe below the bands. A require that
breaks a rule is a red arrow drawn over the boxes, always visible, heavier
than any other edge; the module it leaves says "breaks a rule" in words and
its tooltip gives the rule and its reason. That arrow is the `layer-violation`
finding as a line (the view and the check ask the same function), and the note
under the diagram counts them and leads to the Findings tab. Every other
require is shown for the box under the pointer or the pin only. A second click
on a box opens it in the Tree tab: the view shows the whole tree and has no
center to move. Zoom, pan, dimming, the right-click menu and the SVG export
work as in the box views. Past 600 modules a layer shows its first ones, those
in a broken rule first, and the page says so.

**Coupling** is the one view that is not a tree or a graph but a scatter plot:
every module at or below the center that has a require edge is a dot, placed
by how many modules it requires (fan-out, across) and how many require it
(fan-in, up). It answers "what would be expensive to change?". Two dashed
lines at 5 cut the plot into four corners with names: **hubs** (many require
it, it requires few), **tangles** (many both ways), **pass-throughs** (few
require it, it requires many) and **leaves**. The 5 is fixed and printed in
the bar; a line that followed the median would call the busiest module of a
three-file tree a hub. Both axes are square-root scales, because most modules
have one or two edges, and modules with the same two numbers are laid around
their point so each keeps a dot. The numbers count the whole tree, whatever
the center. The plot is one tab stop: the arrows walk the modules, the
expensive corners first, a readout names the module under the pointer or the
focus, and a click or Enter opens it in the Tree tab.

The Modules view has one more encoding, off by default: the **Tint** switch in its toolbar colours each
box by a measure of everything below it. *documented* and *tested* are the share of functions that
are (`@internal` functions are left out of the documented share, as in the Documentation panel);
*FIX markers* and *TODO / HACK / PERF* are comment markers per 1,000 lines, kept apart because a
`FIX` marker says a line is wrong and the other three are scheduled work. A stronger tint means
"look here first", so one glance says whether the weak spot is one corner or the whole tree. The
steps are fixed and named in the legend (80%, 60%, 40%, 20% for a share; 1, 3 and 6 markers per
1,000 lines), every box prints its value, the tooltip has the counts, and a box with nothing to
measure is dashed instead of being drawn as 0%. The tint rides in the link (`tint=doc`, `test`, `fix`
or `debt`), works together with dimmed boxes and the language legend, and the SVG export keeps it,
with the legend as a line below the diagram. Nothing new is in the artifact for it: the page
computes it from the functions, markers and line counts it already carries.

The Deps and Module Calls views' `+ external` toggle answers *why* a
dependency is there, not just that it is: each external box's tooltip
breaks down exactly which functions were actually called and how often
(`plenary.async.run (2×)`), counted from the same call-resolution pass as
the internal call graph — no
second traversal. `opts.external_repos` turns the box into a working GitHub
link too, verified against a local checkout when you name one (`opts.tag_files`
does the same for another `docmap`-shaped project's own committed map).

The **Quicks** tab states the same tree in sentences instead of tables — *"Most
of your published API is never named in a spec — 12% — 9 of 72"* — negatives
first, five of each polarity. Every verdict carries a line saying what was
actually measured, including its blind spot, and links to the panel holding the
rows it came from; a number that sounds this confident has to be checkable, or
it breaks the same rule `calls_heuristic` and `dead_code` are off by default to
keep. A verdict appears only when it passes one of two cut points, so an empty
Quicks tab means every measure landed in the unremarkable band — a good
reading, not a broken one. Purity is deliberately *not* among them: nothing in
the IR records side effects, and the cheap approximations would be exactly the
confident guess this plugin refuses elsewhere.

The **Compare** tab holds whatever you marked with the `+` beside any function
or module. Its Matrix layout puts attributes down the side and marked objects
across, highlighting every row where they disagree — *"where do these four
differ"* has no other answer on the page. Marks travel in the URL and survive a
reload; a negative Quicks verdict offers **Mark all N** straight into it.

The **Features** tab reads a repo's own `docs/FEATURES/` folder, when it has
one — one card per `## Feature` section, its summary and whatever
`- **Key:** value` metadata the author wrote (`Module`, `Keymaps`, `Config`,
or anything else; there is no fixed vocabulary). An index over hand-written
prose, not a Markdown viewer — a `Module:` bullet that resolves to a real
node links straight into the Tree tab, the rest of the file stays exactly
where the author put it. With several theme files the tab shows one at a
time, behind a strip of sub-tabs (`core.md` first). The same `Module:`
bullets lead back: in the Tree tab, a module or function a feature names
carries a &#9670; trigger that lists those features and opens them. A
`- **Tab:** true` bullet promotes the rare,
especially-important feature out of the card list entirely and into its own
top-level tab, with everything after its metadata rendered through a small
Markdown subset instead of just linked out to. See
[`docs/features_format.md`](features_format.md) for the format this
tab reads, and this repository's own [`docs/FEATURES/`](FEATURES) for
a real (if deliberately small) example — including one promoted feature.
