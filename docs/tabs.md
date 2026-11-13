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
