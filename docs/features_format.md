# The `docs/FEATURES/` format: what the Features tab reads, and why

A field guide for **documenting your own plugin's features** so
`docmap.nvim` has something to build its Features tab from. Written
the same way [`annotation_tags.md`](annotation_tags.md) documents `@module`/
`@param`/etc.: what the parser reads, what you get in return, and what
happens if you leave a piece out.

Everything below is verified against the source at the time of writing —
[`core/features.lua`](../lua/docmap/core/features.lua)'s `M.resolve`
is the one function that decides what is understood.

---

## Why this exists, and why it looks like this

Before writing this, three of the user's own plugins already had a
`docs/FEATURES/`-shaped folder — `lib.nvim`, `markdown.nvim`,
`color_my_ascii.nvim` — and all three had independently invented a
**different** shape: essay-style problem/solution write-ups, compact
per-sub-feature metadata blocks, and full per-feature user manuals,
respectively. None of the three matches what a machine can reliably parse
line-by-line without a real Markdown/CommonMark parser, and none of the
three needed one — a human reads all three fine.

This format is deliberately closest to the **middle** one
(`markdown.nvim`'s), because it is the one shape that is both human-writable
prose *and* mechanically recognizable with the same "a cheap reliable
reading beats a general one" discipline `core/deps.lua`'s require-extraction
and `lib.nvim.deps.spec`'s fenced-block parsing already use elsewhere in
this codebase. Nothing here requires YAML, JSON, or a schema — a
`docs/FEATURES/` folder that predates this document and merely happens to
use `##` headings and `- **Key:** value` bullets already qualifies.

---

## The shape

```
docs/FEATURES/
  README.md          -- optional: the folder's own intro, shown once at
                         the top of the Features tab. Never itself a theme.
  UI.md               -- one file per theme, name is your own choice
  PERFORMANCE.md
  SECURITY.md
```

`docs/features/` (lowercase) is also recognized, `docs/FEATURES/` (matching
`docs/BINDINGS.md`'s own uppercase convention) is preferred when a repo
somehow ships both — same JSON-preferred-over-Markdown precedent
`lib.nvim.deps.spec`'s `SPEC_FILES` order sets. Neither existing is not an
error: `ir.features` is simply `nil`, and the tab says so — the same
"a missing thing is a real answer, not a broken one" posture `ir.tools`
already takes toward a repo with no `lib.nvim.deps` manifest.

### One file instead of a folder

A small plugin does not need a folder. **`docs/FEATURES.md` on its own is
read exactly like a folder holding one theme file**, with the same parse —
the file's `# Title` + prose is its intro, each `##` is a feature, the
bullets are metadata:

```
docs/FEATURES.md    -- the whole catalogue, one file
```

`docs/features.md` (lowercase) is recognized too, and **a folder wins over a
file** when a repo has both — so a plugin that has outgrown one file can
build `docs/FEATURES/` beside the old `docs/FEATURES.md` and delete it when
the split is finished, without the two fighting over which one the tab shows.

This was ambiguous until 2026-08-26 and read as folder-only, which left nine
sibling repos with a well-formed single-file catalogue reported as "no
features". Spelled out here because the sentence below is what they were
going by.

### Naming and order

A repo picks its own theme names and its own number of files — one
`FEATURES.md` for a small plugin, a dozen theme files for a large one.
Nothing here prescribes a taxonomy; `docs/FEATURES/README.md` is where a
repo states its own.

Two names do get a fixed position when present, because a reader's order is
not alphabetical order:

| File | Position |
|---|---|
| `core.md` (any case) | first — the handful of features the plugin exists for, ahead of the ones it grew |
| `FEATURES.md` (any case) | second — inside a folder, the overview of everything not singled out into its own theme |
| everything else | after those, by name |

Alphabetical order alone put `ARCHITECTURE.md` above `CORE.md`, which is the
reverse of how anybody reads them.

### One sub-tab per theme file

With more than one theme file, the Features tab shows one file at a time and
a strip of sub-tabs above it, one per file, in the order above. So the three
positions mean something: `core.md` is what a reader sees first, `FEATURES.md`
the overview next to it, and every other theme is opened when it is wanted.
The line under the strip says what is on screen (`UI: 4 of 31 features across
6 files`), and the link carries the theme (`#tab=features&ftheme=UI`) unless
it is the first. A repository with a single feature file gets no strip.

There is nothing to configure and nothing to write: the strip is how the
catalogue is navigated. It is not a second way to highlight a feature. That
stays `- **Tab:** true` (below), which answers a different question: "this one
feature needs a page of its own", where a theme file says "these features
belong together". A promoted feature is listed in the second-level strip of
the tab, not in a theme, and is counted in none.

---

## Inside a theme file

```markdown
# UI

Everything that draws something on screen.

## Status line marker

Shows the current mode in the status line, updated on every mode change.

- **Module:** `ui/statusline.lua` (`render`, `on_mode_changed`)
- **Config:** `opts.statusline.enabled` (default `true`)

## Cache eviction indicator

A feature does not have to be a visible action — a background cache that
evicts entries on a TTL counts too, and this one has nothing to bind a key
to.
```

- **A leading `# Title` plus prose before the first `##`** becomes the
  file's own intro, shown once above its features in the tab. Optional —
  a file that opens directly on a `##` has no intro, which is a real state,
  not a parse failure.
- **Each `## <name>`** is one feature. `name` is free text — it is what
  the tab's index shows, so write it the way a reader would look for it,
  not as a code identifier.
- **The first run of prose lines after the heading** is the feature's
  summary — one or a few sentences, no format requirement. A feature can be
  *only* this: the "cache eviction indicator" example above has no metadata
  bullets at all, and is still a complete, valid entry.
- **A contiguous run of `- **Key:** value` bullets**, immediately following
  the summary, is parsed into ordered key/value metadata. "Contiguous"
  matters: a blank line ends the run, so prose written *after* a metadata
  block (an example, a caveat) is never mistaken for more metadata.

### The metadata bullets

**There is no fixed vocabulary, and validating one was deliberately not
built.** `lib.nvim.deps.spec` enforces `bin`/`why`/`pkg` because that format
feeds an installer — a missing field there is a real defect. A feature
write-up feeds a reader, and `markdown.nvim`'s own real
`docs/FEATURES/headings.md` already uses `Module`, `Keymaps`, `Config`, *and*
one-off keys like `Scope-aware` in the same file — a whitelist would have
rejected working documentation that predates this parser. Any
`- **Label:** text` line is captured as `{key = "Label", value = "text"}`,
in the order written, duplicates and all.

That said, three keys are worth using consistently, because the Features
tab treats them specially when present:

| Key | What the tab does with it |
|---|---|
| `Module` | Read in both directions. **Forwards:** the card's name links to the first file or module the value names. **Backwards:** every file, module and function it names lists this feature (the &#9670; trigger in the Tree tab's detail pane, see "The way back" below). A value that names something this tree does not have is reported (`feature-module-missing`). |
| `Keymaps` / `Usercmds` / `Autocmds` | Rendered as-is; not cross-resolved against `docs/BINDINGS.md`'s own rows (which have no per-row anchors to resolve *to* — see "What this deliberately does not do" below). Write these as a normal Markdown link to `../BINDINGS.md#keymaps`/`#user-commands`/`#autocommands` yourself if you want a click-through; the tab only renders the link, it does not invent one. |
| `Config` | Rendered as-is. No cross-check against `config/DEFAULTS.lua` — that would mean parsing Lua defaults generically across every consuming plugin's own shape, a real feature and not this one. |
| `Tab` | `- **Tab:** true` promotes the feature to its own top-level tab instead of a card in the Features catalog — see "Promoting a feature to its own tab" below. Any other value is ignored (the feature stays an ordinary card); this is the one key consumed rather than displayed, so it never shows up as a "Tab: true" row either way. |

---

## The way back: from a module or a function to its features

A `Module:` bullet is written once and read twice. In the Tree tab, the detail
of a module shows a &#9670; trigger beside its path when a feature names it,
and each function a feature names shows one beside its prose references. The
trigger opens a card listing those features by name, with theme and summary;
a name leads to the feature itself (its card in the right theme, or its own
tab when it is promoted), the last line to the Features tab. The trigger is
rendered only where a feature names the thing, so seeing it is already the
answer to "is this described anywhere".

How a value is read:

```markdown
- **Module:** `core/annotate.lua` (`M.candidates`, `M.plan`), `bindings/usrcmds/annotate.lua`
- **Module:** `lib.nvim.bindings.usercmd` (`create`)
- **Module:** [`adapter/oil.lua`](../../lua/filetree/adapter/oil.lua) — `filetypes = {"oil"}`
```

- A backticked token **outside parentheses** names a file or a module: a
  path, matched from the end at a `/` (`core/check.lua` is
  `lua/docmap/core/check.lua`, and is not `precheck.lua`), or a module name,
  declared (`@module`) or simply its path with dots. A value may name several.
- The backticked tokens **in the parentheses after it** name members of that
  file: `M.plan`, `plan` and `plan()` all mean the function `plan`. For a
  directory module the files below it are searched too.
- `module.member` written as one dotted name (`sandbox.resolve_engine_name`)
  names both.
- Everything else is passed over: prose, a link target, a token that is not a
  path or a module name.

**What is reported, and what is not.** Only a file or module token, and only
when it claims a place in this tree: a path of a language the map holds
(`core/gone.lua`; not `relay/nav.go` in a map of Lua files, and not a real
file that is no module such as `docs/install.json`), or a dotted name under
one of the map's modules. A member that is not found is never reported, it is
just not indexed: measured over fourteen repositories, the parentheses hold
options, constants, literals and methods of instances about as often as
functions, and a check that cried at each of them would be switched off.

No new key was added. `Commit:` and `Keywords:` were considered as further
sources for the match and are not read: the existing `Module:` bullets already
reach the files of every repository they were measured on.

---

## Promoting a feature to its own tab

Session 2026-08-10. For the very few features important enough to deserve
more than a card — `- **Tab:** true` on its own line, anywhere in the
metadata block, gets a feature a dedicated tab in the generated page instead
of an entry in the Features catalog:

```markdown
## Undo-safe bulk rename

Renames a module and every `require` that points at it in one atomic
operation, with a single `u` undoing the whole thing.

- **Tab:** true
- **Module:** `core/rename.lua` (`M.run`)

### Why atomic matters

A rename that touched files one at a time left a tree that would not load
if interrupted halfway — a `require` pointing at a path that had already
moved. ...
```

**Everything after the metadata block is the tab's own content**, rendered
with a small Markdown subset — `#`.."######" headings, fenced ` ``` ` code
blocks, `-`/`*` bullet lists, paragraphs, and inline `` `code` ``/
**bold**/*italic*/`[text](url)`. Not understood: tables, blockquotes,
images, nested or ordered lists, raw HTML. This is still the same "cheap
reliable reading beats a general one" discipline the rest of this format
follows (see the intro above) — not a CommonMark implementation, and not
meant to become one. A feature whose write-up genuinely needs a table or an
image is better served by a real doc page this tab's body links out to (a
normal Markdown link in the body text) than by growing the renderer to
match one write-up's needs.

**No body is a real state, not a parse failure.** A promoted feature with
nothing after its metadata block — `- **Tab:** true` and maybe a `Module`
line, then straight into the next `## `  — gets a tab with just its title,
summary and metadata, no rendered body section. `- **Tab:** true` is itself
a bullet, so this never runs into the "no bullets at all" case the ordinary
summary/metadata split (see "The shape" above) has to worry about: a
promoted feature always has at least the one bullet that promoted it.

**Dropped from the Features catalog entirely**, not shown as both a card
and a tab — the whole point of promoting one is that it no longer needs
the card. If every feature in a theme file is promoted, that file's own
section of the catalog says so rather than rendering empty.

**No cap on how many can be promoted.** The roadmap item this format ships
for is explicit that this is "for very few, especially important features"
— a convention to follow, not a limit the parser enforces. A repo that
promotes a dozen features gets a dozen extra tabs and a wide tab bar; that
is a documentation-discipline problem for the repo, not a parser error.

---

## What this deliberately does not do

- **No full Markdown rendering — in the catalog.** The Features tab is an
  index — theme, feature name, summary, metadata — the same shape the
  Plugins and Tools Analysis panels already are, not a prose viewer.
  Anything written in a theme file *after* the metadata bullets (a longer
  example, a troubleshooting section) stays in the file; the tab links out
  to it (`srcUrl`-resolved the same way every other source link on the page
  is) rather than re-rendering it. A plugin that already writes full
  `color_my_ascii.nvim`-style manual pages loses nothing — the tab still
  extracts name/summary/metadata from the top of each `##` section and
  links to the rest. A **promoted** feature (`- **Tab:** true`) is the one
  exception — see "Promoting a feature to its own tab" above — and even
  there it is a small, deliberately bounded Markdown *subset*, not the real
  thing.
- **No per-row anchors into `docs/BINDINGS.md`.** GitHub-flavored Markdown
  does not anchor individual table rows, only headings — `docs/BINDINGS.md`
  as generated by `bindings/docs.lua` has exactly three anchors
  (`#user-commands`, `#keymaps`, `#autocommands`), not one per command. A
  `Keymaps:` bullet can link to the whole section; resolving to one row
  would need `docs/BINDINGS.md` to grow per-row ids, a change to a
  different, already-stable generator this feature does not touch.
- **No match by commit or by keyword.** The way back from code to features
  (above) is built from the `Module:` bullets alone. A feature that names no
  module is found from no module: there is no `Commit:` or `Keywords:` key
  that would reach it, and no check that every feature names one.
