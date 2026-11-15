---@module 'docmap.core.findings'
--- The English message catalog, and the one place a finding becomes a
--- sentence.
---
--- **Why this exists.** Until now every check in `core/check.lua` built its
--- own English sentence with `string.format` and handed it out already
--- rendered. That is fine for exactly one locale and impossible for a
--- second: the sentence is produced deep inside the check, five layers
--- before anything knows who is reading it. `I18N.md`'s task 0 — the one it
--- calls "blocks everything, useful alone" — is to move the rendering to the
--- *edge*, so a finding travels as data and becomes text once, at the
--- quickfix list, the page, the CLI report, the markdown, the SARIF file or
--- the MCP response.
---
--- **Named placeholders, not positional ones**, and this is the whole point
--- rather than a style preference. `%s requires %s, but %s must not reach
--- into %s` cannot be translated: German, Japanese and Arabic each put those
--- four pieces in a different order, and a translator handed four anonymous
--- slots has no way to reorder them. `{from} requires {to}` can be written
--- `{to} wird von {from} …` without touching a line of Lua.
---
--- **Untranslated is visible, never invisible** (`I18N.md` rule 2.3). A key
--- with no template renders as `<check-name>` plus its parameters rather
--- than an empty string, so a check added without a catalog entry looks
--- obviously unfinished instead of silently producing a blank row. The spec
--- fails on it too — that is the gate — but the runtime behaviour still has
--- to be honest, because a catalog is exactly the kind of table that gains
--- an entry later than the code it describes.
---
--- **`message` still wins when present**, and that is not a transition
--- shim. `opts.extra_checks` is a documented extension point: another
--- repository plugs in its own checks and returns findings with prose it
--- wrote itself, and nothing here has a catalog entry for those. Such a
--- finding passes through untouched.
---
--- Findings are **not** part of `module_map.json` — `init.lua` serialises an
--- explicit whitelist and has never included them — so this change needs no
--- schema bump. The English sentences that *are* in the artifact live in
--- `quicks`, which is its own task.

local i18n = require("docmap.core.i18n")

local M = {}

---The namespace of the findings in the interface catalog (`core/i18n/en.json`): the template of the check
---`missing-readme` is the message `finding.missing-readme`.
local PREFIX = "finding."

---Message templates of the source locale, keyed by finding id: the `finding.*` messages of the interface
---catalog, read once. The sentences live in `core/i18n/en.json` since the general catalog exists; this table
---is the view of them the specs, the check card of the page and `M.format` go by.
---
---The id is the finding's `check` name, except where one check has to say
---materially different things: `dead-function` reports three genuinely
---different facts and `param-name-mismatch` one, so those carry a
---`params.variant` and the key becomes `<check>.<variant>`. A variant is
---not a formatting detail — it is a different sentence, which is precisely
---what a translator needs to see as a separate entry.
---
---Every template is byte-identical to the sentence the check produced
---before a catalog existed. That is the acceptance criterion `I18N.md`
---sets, and it is checked two ways: `findings_spec.lua`
---renders one finding per key, and the whole existing suite asserts on
---these strings in twenty-one places.
---
---The quotes in `require-not-declared` are the template's, not a value's: the check used `%q` there and the
---criterion is byte-identity. A module name has nothing `%q` would escape beyond wrapping it.
---@type table<string, string>
M.CATALOG = {}
do
  local source = i18n.catalog(i18n.SOURCE)
  for _, key in ipairs(i18n.keys(PREFIX)) do
    -- A finding says one sentence per key; a plural table here would be a catalog defect the spec reports.
    local template = source and source.messages[key]
    if type(template) == "string" then
      M.CATALOG[key:sub(#PREFIX + 1)] = template
    end
  end
end

---One explanation per check: what it compares, how severe a hit is by default, and why the check exists.
---
---**Next to the templates on purpose.** `M.CATALOG` says what a finding reads like; this says what the
---check behind it is for. Two tables in one file, tied together by `findings_spec.lua` in both directions
---(a template without an explanation fails, and so does an explanation without a template), so there is no
---second list of checks somewhere else that can drift from the first.
---
---Keyed by the **check** name, never by a variant: `dead-function` says three different sentences and is one
---check with one reason to exist.
---
---`severity` is the grade the check raises a finding with before any `checks` policy re-grades it
---(`core/check_policy.lua`). The spec reads it back out of `core/check.lua`, so it cannot be wrong for long.
---
---This is the fourth kind of the page's lookup layer (`M.for_page`): a check id in a findings view is
---the trigger, and the card shows these three facts.
---@class Docmap.CheckInfo
---@field compares string What the check holds against what.
---@field why string Why a mismatch is worth a finding.
---@field severity Docmap.Severity The default grade.

---@type table<string, Docmap.CheckInfo>
M.CHECKS = {
  ["missing-module-tag"] = {
    severity = "error",
    compares = "Every source file against the `---@module` line it should open with.",
    why = "The module name is what every other check and every link resolves against; a file without one is in the map only as a path.",
  },
  ["missing-summary"] = {
    severity = "warn",
    compares = "Every module against the one description line under its `@module` tag.",
    why = "The summary is the text every list, box and search result shows for the module; without it the map names the file and says nothing about it.",
  },
  ["module-path-mismatch"] = {
    severity = "error",
    compares = "The name a file declares in `@module` against the name its path gives it.",
    why = "A declared name that no `require` can reach is documentation of a module that does not exist; it is usually what a move or a rename left behind.",
  },
  ["file-holds-many-modules"] = {
    severity = "info",
    compares = "The module identities one file declares against the one identity the map can give a file.",
    why = "The map attaches functions, requires and findings to a file; with several modules in one file it cannot say which of them they belong to.",
  },
  ["missing-readme"] = {
    severity = "info",
    compares = "The directories of the tree that should have one against a `README.md` in each.",
    why = "The README is the front door of a directory, and the map links to it from the node; a missing one is a dead end for the reader who starts there.",
  },
  ["dead-readme-link"] = {
    severity = "warn",
    compares = "Every relative link in a README against the files that exist.",
    why = "A link that leads nowhere is the first thing a reader of the documentation hits after a file was moved or deleted.",
  },
  ["placeholder-readme-link"] = {
    severity = "warn",
    compares = "Every link target in a README against the `${VAR}` placeholder form.",
    why = "No Markdown viewer expands a placeholder, so such a link works in nobody's browser, whatever the variable is set to.",
  },
  ["doc-references-missing"] = {
    severity = "warn",
    compares = "The functions and fields the prose under `docs/` names against what the named module really has.",
    why = "Prose that names a function which is gone describes an API that no longer exists; this is the drift between documentation and code the tool is for.",
  },
  ["sibling-reference-missing"] = {
    severity = "warn",
    compares = "References into a sibling repository against that repository's checkout.",
    why = "A path into another repository breaks without a trace when that repository moves the file; nothing in this tree changes when it happens.",
  },
  ["tools-spec-invalid"] = {
    severity = "warn",
    compares = "Each entry of the tools manifest against the shape the manifest must have.",
    why = "An entry that does not parse is left out of the Tools panel and of every installer that reads the manifest, without anyone being told.",
  },
  ["feature-module-missing"] = {
    severity = "warn",
    compares = "The `Module:` bullet of every feature description against the files and modules of the tree.",
    why = "The bullet is the way from a feature to its code and back; a stale one points a reader at a file that is gone.",
  },
  ["tag-require-missing"] = {
    severity = "warn",
    compares = "The requires into another mapped project (`tag_files`) against the modules that project's own map declares.",
    why = "A require of a module the other project no longer has fails at run time, in a file this tree's own checks would call clean.",
  },
  ["tag-file-unavailable"] = {
    severity = "info",
    compares = "Every configured `tag_files` entry against a readable `module_map.json` at that place.",
    why = "Without the other project's map the requires into it were not checked at all, and a check that did not run must not read as one that passed.",
  },
  ["unreferenced-module"] = {
    severity = "info",
    compares = "Every module against the requires of all other files in the tree.",
    why = "A module nothing requires is either an entry point or dead; the map cannot tell which, so it says that the question is open.",
  },
  ["orphaned-class-alias"] = {
    severity = "info",
    compares = "Every declared `@class` and `@alias` against the type references in the tree.",
    why = "A type nothing refers to is usually what a refactoring left behind, and it keeps describing a shape no value has any more.",
  },
  ["test-references-missing"] = {
    severity = "warn",
    compares = "The module members a spec file reaches for against what the module really has.",
    why = "A spec that calls a function which is gone fails late, or never runs that part at all; either way it no longer tests what its name says.",
  },
  ["binding-conflict"] = {
    severity = "warn",
    compares = "Every keymap, user command and autocmd registration against all other registrations of the same thing.",
    why = "Of two registrations of one key or command the last one wins without a message, and which one that is depends on load order.",
  },
  ["unused-require"] = {
    severity = "info",
    compares = "Every `local x = require(...)` against the uses of `x` in the same file.",
    why = "A require nobody uses still loads the module, costs startup time and draws a dependency edge in the map that is not real.",
  },
  ["example-does-not-parse"] = {
    severity = "warn",
    compares = "The code of every `@example` against the Lua parser.",
    why = "An example is the part of the documentation people copy; one that is not valid Lua fails in the reader's hands.",
  },
  ["consumer-require-missing"] = {
    severity = "warn",
    compares = "What the configured consumer projects require from this tree against the modules this tree declares.",
    why = "A module renamed here breaks a consumer over there, and nothing in this tree's own requires shows it.",
  },
  ["require-cycle"] = {
    severity = "warn",
    compares = "The require edges of the tree against a loop among them.",
    why = "Modules that require each other load in an order nobody chose, and one of them sees the other half-built.",
  },
  ["require-not-declared"] = {
    severity = "warn",
    compares = "Every require of a name under this project's own prefix against the modules the tree declares.",
    why = "Such a require can only fail at run time: the name belongs to this tree and no file answers to it.",
  },
  ["layer-violation"] = {
    severity = "warn",
    compares = "Every require edge against the configured layer rules (which layer may reach into which).",
    why = "The layering is a decision about the architecture; a single require across it undoes the decision without anyone having made a new one.",
  },
  ["dead-see-target"] = {
    severity = "warn",
    compares = "Every `@see` target against the modules and functions of the tree.",
    why = "A `@see` is a promise that there is more to read; one that resolves to nothing sends the reader looking for it.",
  },
  ["type-vs-class"] = {
    severity = "warn",
    compares = "A local annotated with `---@type` against the fields assigned to it after its literal.",
    why = "LuaLS reports exactly this shape as injected or missing fields; `---@class` is the annotation that says what the code does.",
  },
  ["undocumented-param"] = {
    severity = "info",
    compares = "The number of parameters in a signature against the number of `@param` lines above it.",
    why = "A documented function with fewer `@param` lines than parameters documents only part of its own call.",
  },
  ["param-name-mismatch"] = {
    severity = "info",
    compares = "The name of each `@param` line against the parameter at the same position of the signature.",
    why = "The usual cause is a parameter renamed in the code and not in the comment; the documentation then describes an argument that is not there.",
  },
  ["dead-function"] = {
    severity = "info",
    compares = "Every function against the calls and mentions the tree holds of it.",
    why = "A function nothing calls is either public API or dead code; the three variants say how sure the map can be about which.",
  },
}

---The check a catalog key belongs to: the key itself, or its part before `.<variant>`.
---@param key string A key of `M.CATALOG`.
---@return string
function M.check_of(key)
  return (key:gsub("%..*$", ""))
end

---The explanations as the page needs them: a list sorted by name, each entry with its templates, so the
---card can show what a finding of that check reads like.
---
---Tool data like `tags.for_page()`: the same bytes in every checkout, so it rides on the page and stays out
---of `module_map.json`.
---@return { name: string, severity: Docmap.Severity, compares: string, why: string, templates: string[] }[]
function M.for_page()
  local by_check = {}
  -- A plain loop, not `vim.tbl_keys`: this runs in the standalone build too, whose shim has no such function.
  local keys = {}
  for key in pairs(M.CATALOG) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local name = M.check_of(key)
    by_check[name] = by_check[name] or {}
    table.insert(by_check[name], M.CATALOG[key])
  end
  local out = {}
  for name, info in pairs(M.CHECKS) do
    out[#out + 1] = {
      name = name,
      severity = info.severity,
      compares = info.compares,
      why = info.why,
      templates = by_check[name] or {},
    }
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

---Catalog key for a finding: its check name, or `<check>.<variant>` when it
---carries one.
---@param finding Docmap.Finding
---@return string
function M.key(finding)
  local variant = finding.params and finding.params.variant
  if variant then
    return finding.check .. "." .. tostring(variant)
  end
  return finding.check
end

---Render one finding as a sentence.
---
---The single entry point every surface calls. Three cases, in order:
---a finding that already carries prose (an `opts.extra_checks` finding)
---keeps it; a known key is rendered from the interface catalog; an unknown
---key renders visibly rather than blank.
---
---`locale` decides the language. An interactive surface (quickfix, diagnostics, the report on a terminal) leaves
---it out and gets the active locale; a renderer of a committed artifact (`overview.md`, SARIF, the static rows of
---the page) passes `i18n.SOURCE`, because a file that `--check` compares must not depend on the `LANG` of the
---machine that wrote it (`docs/i18n.md`, "The artifact never contains translated text").
---@param finding Docmap.Finding
---@param locale string? A shipped locale code; the active locale when omitted.
---@return string
function M.format(finding, locale)
  if finding.message then
    return finding.message
  end
  local key = M.key(finding)
  if not M.CATALOG[key] then
    -- Deliberately not an error: a missing catalog entry must not take down
    -- a scan, and it must not be invisible either. `findings_spec.lua` is
    -- what makes it fail loudly at development time.
    local parts = {}
    for name, value in pairs(finding.params or {}) do
      if name ~= "variant" then
        parts[#parts + 1] = ("%s=%s"):format(name, tostring(value))
      end
    end
    table.sort(parts)
    return ("<%s>%s"):format(key, #parts > 0 and (" " .. table.concat(parts, " ")) or "")
  end
  return i18n.t(PREFIX .. key, finding.params, locale)
end

---Catalog entry for a check that skipped nodes because their language lacks
---the convention it needs (`check.not_applicable`), in the source locale. Plural-neutral on purpose:
---`{languages}` is a list.
---@type string
M.NOT_APPLICABLE = i18n.t("report.not-applicable", nil, i18n.SOURCE)

---Render one `Docmap.NotApplicable` as a sentence, for the CLI report and the
---page alike.
---@param na Docmap.NotApplicable
---@param locale string? As in `M.format`.
---@return string
function M.format_not_applicable(na, locale)
  return i18n.t("report.not-applicable", {
    check = na.check,
    count = na.count,
    needs = na.needs,
    languages = table.concat(na.languages, ", "),
  }, locale)
end

return M
