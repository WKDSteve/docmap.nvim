# Hosting the map

Everything this project exposes to a program that *embeds* it rather than
reads it: the capability handshake, the API routes, the URL parameters the
page reads, and the two-way message channel between the page and whatever
frame it is in.

`docmap-desktop` is the host that exists today, and its own docs describe its
half. This file describes **this** half — the surfaces the engine and the
generated page publish, and the decisions behind them, because those are what
a second host would have to hold to.

## Table of content

- [Why there is a host surface at all](#why-there-is-a-host-surface-at-all)
- [`--capabilities`, the handshake](#--capabilities-the-handshake)
- [`--api=<route>`, one question at a time](#--apiroute-one-question-at-a-time)
- [`?theme=`, and the other URL parameters](#theme-and-the-other-url-parameters)
- [The page talks to its host](#the-page-talks-to-its-host)
- [The host asks the page](#the-host-asks-the-page)
- [The artifact is the extension point](#the-artifact-is-the-extension-point)
- [What a host must not assume](#what-a-host-must-not-assume)

---

## Why there is a host surface at all

The generated page is self-contained: no CDN, no build step, no server. Open
`docs/map/index.html` in any browser and everything structural works.

Three things do not, and each of them is why one of the surfaces below
exists.

- **Some panels need data the artifact does not carry** — the Telemetry
  join, the Loaded snapshots, the checklist, the commit list. Those come from
  `/api/*`, which needs something on the other end. Inside Neovim that is
  `:DocMap serve`; outside it, a host forwards to `--api=<route>`.
- **A host has a window, and the page is inside it.** It wants the header's
  counts for its own status bar, and the diagram for a Save dialog. Reading
  the DOM across a frame boundary is not available to it and would be the
  wrong contract anyway.
- **The theme has to be right before the first paint**, which rules out
  anything that arrives as a message.

**The rule all three follow: the page answers questions and takes no
instructions.** Nothing a host sends changes what the page does — only what
it reports back. That is what makes embedding it safe in both directions, and
it is a property to keep rather than a coincidence.

---

## `--capabilities`, the handshake

```bash
docmap --capabilities
```

Prints one JSON object and exits 0. It is what a host asks before trusting a
binary with anything.

| Field | What it says |
|---|---|
| `capabilities` | Coarse feature names this build has — `api`, `languages`, `schema`, `rules` when `rules.nvim`'s engine is part of it, `rules-agent` when its agent functions are too (`rules/plan`, `rules/validate`), `rules-attach` with them (`rules/attach`), and `rules-write` when its two writers are too (`rules/accept`, `rules/waive`). `telemetry` when `runtime-analysis.telemetry` actually loads in this engine (the route is listed either way; without the capability it answers with the reason below). The `rules/*` routes are listed in `routes` either way and answer with a reason without the engine; an older engine lacks the route names, so a missing route is read off this answer, never from an error. A host that wants one thing can test for it without parsing the rest. |
| `schema` | The artifact schema this build writes. The release is rolling (`standalone-latest`), so there is no version number to report that would not be fiction; the schema is what actually decides whether two artifacts are comparable, and it is bumped deliberately. |
| `build` | Commit, commit date, and whether the tree it was built from was clean. **Present only in a bundled binary** — `scripts/package.lua` writes it at bundle time and never into the source tree, so a run from a checkout answers `null` rather than claiming a provenance it does not have. |
| `routes` | Every `/api/*` route name this build answers, read from `core/api.routes`. A route added there is advertised here without this being told. |
| `languages` | One entry per backend: `name`, `grammar`, `grammar_loaded`, `calls`. See [`languages.md`](languages.md). |

**`languages` is what lets a host stop guessing why a map came back thin.**
Pointed at a mostly-Python repository, an engine without the Python grammar
produces a valid, nearly empty map. A host that reads this list can say so
*before* generating, rather than presenting the empty result as a success.

**`grammar_loaded` is three-valued and must stay that way**: `true`, `false`
(wants a grammar, has none — a complete module tree and no function-level
data) and `null` (needs no parser, which is full fidelity). A host that
flattens the last two reports a healthy backend as broken.

### Why the flag sits in root-argument position

`--capabilities` is the *first* argument, where a path would go, and that is
deliberate. An older binary that has never heard of it rejects a leading `-`
immediately, before doing any work. One that arrives as an ordinary flag
after a root would be ignored by an old build — which would then **generate a
map**, writing into the caller's repository and exiting 0 with output that is
not JSON.

That is measured rather than imagined: it is what the shipped binary did the
first time it was handed `--api=telemetry`, and a host polling a panel would
have rewritten a user's `docs/map` on every fetch.

So "this engine has no capabilities" and "this engine is too old" are a
single observation, which is what a host actually needs.

---

## `--api=<route>`, one question at a time

```bash
docmap /path/to/repo --api=telemetry
docmap /path/to/repo --api=commits --snapshot=50
```

Answers one of the generated page's own `/api/*` routes and prints its JSON,
instead of generating anything. Today's routes:

| Route | Answers |
|---|---|
| `telemetry` | The telemetry join for this repository. When it cannot answer, `available` is `false` and `reason` says why: `no data` (nothing stored, or the namespace is unknown to the store), `runtime-analysis.nvim was not found`, or `runtime-analysis.nvim is installed but does not load: <one line>` (no paths). The last two also carry `reason_code` (`runtime-analysis-not-found`, `runtime-analysis-load-failed`) for a host that must not parse text; the text follows `--locale`. |
| `telemetry/snapshots` | Which named telemetry snapshots exist. |
| `loaded` | The loaded-versus-declared comparison. |
| `loaded/snapshots` | Which named loaded snapshots exist. |
| `checklist` | The hand-verified ledger and what has drifted. |
| `traffic` | What `:RA send` recorded for the project, per endpoint: sends, status counts, median and maximum duration, size and shape of the last answer. Metadata only; read at request time, never in the committed map. |
| `commits` | Recent commits, for the History tab. |
| `commit/<sha>` | One commit's diff. Not in `routes` because its name carries the sha. |
| `shape/<sha>`, `shape/<older>/<newer>` | The shape change between the map committed at a revision and the one on disk, or between two committed maps: nodes added and removed, requires gained and lost, and the same change as text. For the Hierarchy tab's comparison. Not in `routes`, for the same reason. |
| `rules/catalog` | Every rule of the project's rulesets (`.rules.json`, else the vault): id, severity, family, title, section, text, source file and line, the check type if any, the agent hint. See below. |
| `rules/run` | The mechanical run of a selection: one result per rule, `pass`, `fail`, `error`, `manual` or `waived`, with findings. See below. |
| `rules/judged` | What a person decided: the verdicts of `.rules-verdicts.json` and the waivers of `.rules-waivers.json`, read by `rules.nvim`'s own readers, with expired waivers and stale verdicts marked. Reads only. See below. |
| `rules/plan` | What an agent run over a selection would send: the requests (`system`, `prompt`, files, rules), what is not sent and why, sizes and a token estimate. Sends nothing. See below. |
| `rules/validate` | One model answer about one rule, checked against the tree: a proposal with the findings whose quotes hold up. See below. |
| `rules/attach` | One file of the project as a request would carry it, or why the deny list, the size limit or the tree keeps it out. For a host's conversation about a rule. Sends nothing; not offered by `:DocMap serve`. See below. |
| `rules/accept` | **Writes.** One proposal of `rules/validate`, accepted by a person: the verdict goes into the project's `.rules-verdicts.json`. See below. |
| `rules/waive` | **Writes.** A waiver of one rule into the project's `.rules-waivers.json`. See below. |

**One route per invocation, deliberately.** A request is one question, and a
process that answered several would need a protocol to say which answer is
which. `stdout` carries exactly the JSON, so a caller does not have to find
where it starts.

`--snapshot=<value>` carries the single optional parameter, whatever the
chosen route makes of it — a snapshot name for `telemetry`/`loaded`, a commit
count for `commits`, unused otherwise. One flag rather than one per route,
because exactly one route reads it at a time.

### `rules/catalog` and `rules/run`

```bash
docmap /path/to/project --api=rules/catalog
docmap /path/to/project --api=rules/run --select=DEP,LUA-12,gate:release --trust=/path/to/ruleset
```

`rules.nvim`'s engine (`lua/docmap/core/rules_api.lua`), for the desktop app's Rules tab. The rulesets and gates
come from `rules.settings`, the same resolution `:Rules check` uses: the project's `.rules.json`, else the vault
(`$RULES_VAULT`); waivers from the project's `.rules-waivers.json`.

- `--select=` (the same single parameter as `--snapshot=`) is a comma-separated list of rule ids (`DEP-01`),
  families (`DEP`) and gates (`gate:release`). Nothing selected is an answer with a reason, never a sweep of the
  whole catalog; items that match no rule come back in `unknown`.
- `--trust=<folder>` (repeatable) is the host's decision, **per rule**: a `lua_predicate` runs only when its rule
  file lies (by real path) under one of these folders. Otherwise it reports `error` with the finding
  `predicate not trusted: ...`, visibly. No other source of trust counts here, not even a vault named by
  `$RULES_VAULT`: a child process inherits an environment nobody looked at for this run. Grep, file and JSON
  checks run regardless, they read files and execute nothing.
- Absence answers `{ "available": false, "reason": ... }`: `rules.nvim` not part of this build, a `.rules.json`
  that cannot be used, no ruleset configured, a ruleset that does not exist, a selection that matches nothing,
  and an error raised inside the engine (its message is the reason).
- `gates` in the catalog is a list sorted by name, `[{ "name": "release", "families": ["FIX", "PRD"] }]`, so a
  project without gates answers `[]` like any other list.
- From the editor (`:DocMap serve`) the same routes answer at `/api/rules/catalog` and
  `/api/rules/run?select=...` (`select=` as on the command line). That server passes **no trust**: there is no
  `--trust=` to name, and the trust of `rules.nvim`'s own settings (`setup({ trust })`, `$RULES_TRUST`) is not
  taken over, so every `lua_predicate` there reports `predicate not trusted`. Run predicates with `:Rules check`.
  **Decided 2026-11-12: it stays that way.** A predicate is Lua code, and this server is reachable by any page that
  can send a request to loopback, so handing it the editor's trust would let a page cause code to run. The decision
  is the editor's, taken in the editor (`:Rules check`); the desktop app has its own trust store for it.

### `rules/plan` and `rules/validate`

```bash
docmap /path/to/project --api=rules/plan --select=ARCH,DEP-07
docmap /path/to/project --api=rules/validate --select=DEP-07 --answer=/tmp/answer.json
```

The agent half of the Rules tab: `rules.nvim`'s own pure functions (`rules.engine.agent.plan`, `.request`,
`.validate`), the same ones `:Rules agent` runs in the editor, so the prompt, the deny list and the evidence check
exist once. Neither route sends anything or opens a connection; sending a request is the host's job.

- `rules/plan` plans the selected rules **without** a check (rules with one come back in `with_check`: `rules/run`
  answers them, and nothing of them runs here, so no predicate runs and no trust is asked for). Each entry of
  `batches` is one request: `system`, `prompt`, `files` (what the prompt carries), `unreadable`, `bytes`, `chars`,
  `tokens` (about 4 characters a token) and its `rules` (`source` says whether the scope is the rule's own or its
  family's, `truncated` what `max_files` cut). `skipped` lists every rule that is not sent, with `status` (`manual`:
  stays on the worklist; `unclear`: sending it would have been wrong) and the `reason` (`no scope to look in`,
  `scope matches no file that may be sent (n denied)`, `context exceeds limit (...)`, a batch none of whose files can
  be read). `denied` lists the files the deny list kept out (built in: `.env*`, keys, credential stores; plus
  `agent.deny`; links are never sent). `totals`, `limits` (`batch_size`, `max_context_bytes`) and `agent`
  (`backends`, `models`: the project's allow-list, which the host enforces) come from the project's `.rules.json`.
- `rules/validate` takes one rule id and the model's answer as a **file** (`--answer=<file>`; not stdin, so a host
  cannot leave the engine waiting on a pipe). The files the answer may claim to have read are planned again here,
  never taken from the caller. The `proposal` has `status` (`violation`, `compliant`, `unclear`), `findings` (only the
  ones whose quote occurs literally within 3 lines of the named line, in a file that was sent), `dropped` (the rest,
  with the reason), `checked`, `unchecked`, `reason`, and always `proposed: true`, `verified: false`. An answer that
  is not the schema is `unclear` with the text in `raw`; a rule that is not sent is `unclear` whatever the answer says.
- Bounds: a selection over 64 KiB or 4096 items, an answer over 1 MiB and a plan whose requests add up to more than
  16 MiB are refused with a reason (`available: false`), never read in full or printed.
- `:DocMap serve` answers `/api/rules/plan?select=...` by GET and `POST /api/rules/validate?select=<ID>` with the
  model's answer as the request body (required, at most 1 MiB; a GET there still says that a query is no place for an
  answer). Validating only compares the answer with the tree and returns a proposal: nothing is written or run.

### `rules/attach`

```bash
docmap /path/to/project --api=rules/attach --select=lua/mod/init.lua
```

A conversation about a rule (the desktop app's chat in the run view) cannot open files by itself: a person attaches
one. Whether that file may go into a request is the planner's question, so it is asked of the planner: the path is
planned as the only scope of a stand-in rule, and the deny list (built in plus `agent.deny`, case ignored), the links
that are never sent, the folders the walk never enters (`.git`, `.deps`, `.claude`), `agent.max_context_bytes` and
the reading of the file (binary, too large, unreadable) are exactly those of `rules/plan`.

- `--select=` is one path relative to the project (`\` is read as `/`, `.` segments are dropped). A path that is
  empty, absolute, leaves the project (`..`), has a control character or a `*` (a pattern) is refused with a reason
  (`available: false`).
- The answer is `{ "available": true, "file", "sent": true, "denied": false, "text", "bytes", "chars", "tokens" }`,
  `text` being the file the way a request carries it (`=== path ===` and numbered lines) and `tokens` the same rough
  estimate as `rules/plan`'s. A file that may not go is `{ "available": true, "file", "sent": false, "denied", "reason" }`
  with no text; `denied` is true when the deny list (or a link) is the reason.
- **`:DocMap serve` does not offer it** (404, like the writers): it hands out the text of any file a request may
  carry, not only the files a rule's scope names, and a page that can reach loopback must not be able to ask for
  that. `--capabilities` lists `rules-attach` when the agent functions are part of the build.

### `rules/judged`

```bash
docmap /path/to/project --api=rules/judged
```

What a person decided about the rules of the project, so a host can show it next to `rules/run` without reading
either file itself: `rules/run` reports a waived manual rule as `manual`, and the verdicts are no result of a run.

- The answer is `{ "available": true, "today", "verdicts", "waivers", "unreadable", "stale_checked" }`, every list
  sorted by `id`. A verdict is `{ "id", "verdict", "date", "by", "note"?, "commit"?, "evidence", "stale"?,
  "stale_reasons"? }` (`evidence` the number of findings it holds); a waiver is `{ "id", "reason", "expires"?,
  "paths"?, "expired", "partial" }` (`partial`: limited to some paths).
- Both files are read by `rules.nvim` (`rules.engine.verdicts.load`, `rules.engine.waivers.load_entries`). A file that
  is there and cannot be used is `{ "file", "reason" }` in `unreadable`, never an empty list.
- `expired` counts by the engine's local day (`today`), the day `rules/run` waives by, not UTC.
- `stale`: a file of the verdict's evidence changed in a commit after the day it was accepted
  (`rules.engine.verdicts.stale` over one `git log` of the project). Without git `stale_checked` is false and `stale`
  is left out. A change that is not committed yet is not seen.
- `:DocMap serve` offers it; it writes nothing.


```bash
docmap /path/to/project --api=rules/accept --select=DEP-07 --proposal=/tmp/proposal.json --by="A. Person" [--note=...]
docmap /path/to/project --api=rules/waive --select=DEP-07 --reason="..." [--expires=2027-01-31] [--paths=lua/a.lua,lua/b/*]
docmap /path/to/project --api=rules/waive --select=DEP-07 --input=/tmp/waive.json
```

**Decided 2026-11-15: the engine writes these two files, and only through `rules.nvim`'s own writers.** Every other
route reads. These two are the first that change the project, because the desktop app has no editor and the
alternative was worse: a second writer of `.rules-verdicts.json` and `.rules-waivers.json` in Rust would have had to
rebuild what `rules.nvim` guarantees, and would drift from it. So:

- `rules/accept` calls `rules.engine.verdicts.accept`, the only function that writes `.rules-verdicts.json`. Its
  guarantees are `rules.nvim`'s: one proposal at a time (there is no "accept all"), a proposal that says `verified` is
  refused (the one who proposes does not confirm), an `unclear` one is not a verdict, the person comes from the caller
  and never from the proposal, the verdict is what was proposed, a verdicts file that exists and cannot be used (or is
  a link) is never overwritten, and a file that changed between read and write stops the write. What the route adds
  is what a host must not decide: the rule must be the one `--select` names and one without a check, and the files
  the request carried (`sent`, against which the evidence is held) are **planned again here** and replace whatever the
  proposal says, as in `rules/validate`. The verdict is dated today.
- `rules/waive` runs the `waive` operation of `rules.nvim`'s write door (`rules.ops`, `rules-ops/1`), the code
  `:Rules waive` runs: a loaded rule, a one-line reason that says something, a calendar date, relative paths; a waiver
  that is there already is refused (renew or remove it with `:Rules`), the same one again is `unchanged`; the file is
  written canonically, under its lock, never through a link.
- `--proposal=<file>` is the `proposal` object of a `rules/validate` answer, as it came back (at most 1 MiB, a file
  and not stdin, as `--answer=`). `--by=` is required and is the person at the host, never anything from the
  proposal. `--paths=` is comma-separated.
- `--input=<file>` gives the texts instead as a UTF-8 JSON object `{ "by", "note", "reason", "expires", "paths" }`
  (each optional, `paths` a list or one comma-separated text, a byte order mark is allowed). On Windows the arguments
  of the standalone engine pass through the ANSI code page: a letter outside it arrives as `?` or as a control
  character, so a host passes any text a person typed this way (the file's own path should stay ASCII). A key given
  both by the file and by its flag is refused, as is a key the file does not know.
- The answer: `{ "available": true, "written": true, "file", "id", "verdict" }` (the entry as the file now holds it)
  for `rules/accept`; `{ "available": true, "written", "outcome", "file", "id", "waiver" }` for `rules/waive`
  (`outcome` is `waived` or `unchanged`). A refusal is `{ "available": false, "reason" }`, for `rules/waive` with the
  `code` of the door (`invalid_argument`, `forbidden`, ...); the file is then as it was.
- `--capabilities` lists `rules-write` when both writers are part of the build (after `rules` and `rules-agent`;
  `rules/accept` needs the agent functions to plan the request again).
- **`:DocMap serve` does not offer them**, by any method: it answers whatever can reach loopback, a page in a browser
  included, and a route that writes into the project is not something a page may ask for. Both answer 404 there, as a
  route that does not exist. In the editor, `:Rules` writes the same two files.
- **In the standalone build** the writers run under `standalone/vim_shim.lua`, which now has a write half. It is
  weaker than libuv in four places, each said where it is implemented: creating a file exclusively (`wx`, the lock
  file and the temp file) is a look-then-create, not `O_EXCL`; the flush before the rename does not reach the disk;
  replacing a file on Windows renames the old one aside first, so for a moment the name is missing; and off Linux the
  process number in a temp name is not the pid. The writers re-read the file before writing (`verdicts.accept`) or
  compare its etag (`rules.ops`), so a race between two writers can lose a write that was not yet checked, never
  overwrite one that was. The `standalone` gate of `scripts/ci.lua` runs both routes on both hosts and compares the
  answers and the written files byte for byte.

**The join logic stays in Lua.** `docmap-desktop` runs a small HTTP server
that forwards `/api/*` here; its Rust side is transport only. `core/api.lua`
owns the answers and shares them with `editor/serve.lua`'s in-editor server,
so the two hosts cannot disagree.

---

## `?theme=`, and the other URL parameters

```
index.html?theme=dark
index.html?theme=light
```

Three states: `light` and `dark` decide, and anything else — including no
parameter — follows the OS.

Applied in `<head>`, before any element exists, because a theme applied after
first paint is a flash of the wrong one.

**A query parameter rather than a message, for two reasons that both matter.**
A message cannot arrive early enough. And a page that executes instructions
from whatever embeds it is a different security posture from one that reads
its own URL — the same line the message channel below draws, drawn here as
well.

It is also a feature outside any host: it is a thing a person can type into a
browser.

The page reads two more keys, both about its interface language
([`i18n.md`](i18n.md#the-generated-page)):

```
index.html?lang=de
index.html?i18n=debug
```

`?lang=` is the language a host asks for: a tag such as `de` or `de-AT`. A
language the reader picks in the page wins over it, and a tag that names no
shipped locale reads English. `?i18n=debug` marks every text that fell back to
English.

`:DocMap serve` lets `?theme=light`, `?theme=dark` and `?theme=system`,
`?lang=<a language tag>` and `?i18n=debug` through to the page and refuses any
other value or key with a 400: its routes are whitelists, and these are the
keys the page itself reads.

---

## The page talks to its host

The page volunteers two messages, both `postMessage` to `window.parent`, both
tagged `source: "docmap"`. A page with no listening host is not an error and
not a special case — nothing happens.

**Where the reader is**, on every navigation:

```js
{ source: "docmap", tab: "hierarchy", atool: null, view: "calls", id: null, fn: null }
```

Coarse on purpose. `tab`, the Analysis sub-tool, the Hierarchy view, and on
the tree tab the chosen node `id` and function key `fn` (the same two fields
as the link fragment `#tab=tree&id=<node>&fn=<key>`; `null` elsewhere, and
`fn` `null` when no function is chosen) — not scroll position. It is sent
only when one of the five changes, so a host is not woken by every interaction. This is what lets a
host put a note over a panel it knows something about, and what lets it
return the reader to the same panel after a reload.

**A request to open a file**, from the map's own right-click menu:

```js
{ source: "docmap", kind: "open-file", path: "lua/x/init.lua", line: 42 }
```

The path is repository-relative, because that is what the artifact stores.
`line` is `null` for a node with no function behind the click. **The page
does not open anything** — it cannot, and should not be able to. It says what
was asked for; a host that has an editor decides what to do about it, and a
host that has none ignores it.

---

## The host asks the page

The one inbound direction, and the one with a security posture written into
it. A message is read only if it carries `source: "docmap-host"`, and only a
fixed vocabulary is understood:

| `ask` | Reply |
|---|---|
| `"export-svg"` | `{ok: true, kind: "svg", name, data}` — or `{ok: false, reason: "no-diagram"}` when nothing is drawn. |
| `"counts"` | `{ok: true, kind: "counts", modules, namespaces, files, errors, warnings}` — what the header shows. |

Every reply carries `source: "docmap"` and `replyTo: <the message's id>`.

Four consequences, stated so a later verb has to argue against them rather
than quietly break them:

- **A malicious embedder gains nothing it did not have.** Everything
  answerable here is already rendered on the page it embedded.
- **A fixed vocabulary, not a dispatch table keyed by whatever arrived.** An
  unknown verb is answered with silence, never with an error echoing the
  input back.
- **Replies go to the asker's own origin, never `"*"`.** An `opener` that is
  not the embedder learns nothing by listening. `ev.origin` is `"null"` for a
  sandboxed or `file:` embedder and `postMessage` rejects that as a target —
  those hosts get no answer, which is the correct outcome rather than a
  broadcast.
- **`counts` cannot drift from the header beside it.** The three structural
  counts come from the artifact and the two finding counts from the same
  array the header reads, so this needs no new payload.

**There was a third question, `state`, and it was removed rather than kept.**
It answered with the same coarse context the page already volunteers, on the
reasoning that asking is cheaper than waiting. A round later nothing had ever
asked it: the one host there is reads the volunteered message, because by the
time it has a reason to care the message has already arrived. A question
nobody asks is not free — it is a branch in a published channel that every
generated artifact carries, and that every future change has to keep
answering correctly.

---

## The artifact is the extension point

**There is no plugin API, and that is the answer rather than a gap.**
`module_map.json` is byte-deterministic, versioned and documented — anything
that reads a repository's map is already an extension, today, with no code in
this project and nothing to register. What was missing was saying so, and
saying what a schema bump is allowed to do to you. This section is both.

### What you can rely on

- **`meta.schema` is present and increases.** It has been in every artifact
  since schema 1. Compare it; never assume it.
- **A node's `id` is its repo-relative path**, forward-slashed, and it is the
  key everything else joins on — edges, findings, the page's own selection
  links. This is the one identifier worth building on.
- **Key order is fixed and output is deterministic** for unchanged input.
  There is no timestamp anywhere in the IR, deliberately, which is what makes
  `--check`'s byte comparison a usable staleness test — and what lets you
  diff two artifacts yourself.
- **An absent optional field means "this did not run", not "zero".**
  `types_detail` is the sharpest case: `nil` means LuaLS enrichment never
  ran, `{}` means it ran and found nothing. Collapsing those two produces a
  confidently wrong report.

### What a schema bump may do to you

**Add a field.** Always allowed, and the common case. A reader that ignores
unknown keys is unaffected — write one.

**Remove a field.** Allowed, and it has happened: schema 5 moved `quicks`'
`headline`, `basis` and `detail` onto the page, because they are the tool
describing a tree in English rather than facts about the tree. When a field
is removed for that reason, **the fact it carried stays** — the same bump
added `n` and `total` beside `value`, so "45 of 72" survives without the
English phrasing it used to arrive in. A removal that loses information is
not a bump this project intends to make.

**Change what a field means.** Rarest, and the only kind that can break a
reader silently. It is why the schema number exists at all.

### What it may not do

- **Reuse a number.** Schema 5 is schema 5 forever.
- **Change a field's meaning without a bump.** If the number is the same, the
  meaning is the same.
- **Remove `meta.schema`.**

### How to read it, in one line

Tolerate forward, refuse backward — the same rule this project's own code
follows. `core/diff.lua` compares `schema >= 2`, not `== 2`, and degrades
by *naming what it cannot say* ("the older map predates the dependency
graph") rather than by failing. That is the pattern to copy: a reader that
requires an exact number breaks on the next bump for no reason, and one that
ignores the number entirely reports nonsense about an older map.

Reading extensions that go further than the file — a panel computing
something from the artifact — are stage 2, and **the first one is built**:
`docmap-desktop`'s workspace view resolves `requires_external` across every
map it holds, which is the one question a single artifact cannot answer. It
records that a module outside the repository was required and can say nothing
about where that module lives, because it never saw it; several artifacts
can. That consumer runs entirely off the files, with no engine involved and
nothing registered here — which is the claim this section makes, now with
something standing on it.

Writing extensions are stage 3 and still open; both live in
[`docmap-desktop`'s plan](https://github.com/WKDSteve/docmap-desktop).

## What a host must not assume

- **That the map on disk was written by the engine now on `PATH`.** A
  generated map is a snapshot of the engine that wrote it; page-side features
  arrive by regenerating, not by updating whatever reads the map. This is the
  single fact that makes the app's behaviour predictable rather than
  mysterious — see [`USAGE.md`'s first section in
  `docmap-desktop`](https://github.com/WKDSteve/docmap-desktop/blob/main/docs/USAGE.md).
- **That an empty panel means an empty project.** Several panels are empty
  for reasons that belong to the build, not the repository — no grammar, no
  call extraction for this language, no telemetry collected. The handshake is
  what lets a host tell those apart, and a host that can tell them apart
  should say which.
- **That `build` is present.** It is absent for an engine run from a source
  checkout, and absent is a real answer.
- **That the schema will not change.** Compare `schema` rather than assuming.
  And do not read "bump" as "gains a field": **schema 5 removed three**
  (`quicks.headline`/`basis`/`detail`, which moved onto the page). The full
  compatibility statement is the next section.
