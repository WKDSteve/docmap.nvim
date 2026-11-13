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

local M = {}

---Message templates, keyed by finding id.
---
---The id is the finding's `check` name, except where one check has to say
---materially different things: `dead-function` reports three genuinely
---different facts and `param-name-mismatch` one, so those carry a
---`params.variant` and the key becomes `<check>.<variant>`. A variant is
---not a formatting detail — it is a different sentence, which is precisely
---what a translator needs to see as a separate entry.
---
---Every template is byte-identical to the sentence the check produced
---before this table existed. That is the acceptance criterion `I18N.md`
---sets for this task, and it is checked two ways: `findings_spec.lua`
---renders one finding per key, and the whole existing suite asserts on
---these strings in twenty-one places.
---@type table<string, string>
M.CATALOG = {
  ["missing-module-tag"] = "{file} has no ---@module annotation",
  ["missing-summary"] = "{file} has no description line",
  ["module-path-mismatch"] = "{file} declares @module '{declared}' but lives at '{expected}'",
  ["file-holds-many-modules"] = "{file} holds {count} module identities the map cannot separate: {modules}",
  ["missing-readme"] = "{path} has no README.md",
  ["dead-readme-link"] = "{file} links to '{target}' which does not exist",
  ["placeholder-readme-link"] = "{file} links to '{target}', which starts with the placeholder ${var}: no Markdown viewer expands it",
  ["doc-references-missing"] = "{doc}:{line} references '{text}', but {module} has no '{missing}'",
  ["sibling-reference-missing"] = "{file} references '{target}', which does not exist in the {repo} checkout",
  ["tools-spec-invalid"] = "{source}: entry #{index} is invalid — {reason}",
  ["feature-module-missing"] = "{file}:{line} names '{text}' as the module of '{feature}', but this tree has no such file or module",
  ["tag-require-missing"] = "{module} is required by {who} but {prefix}'s own map does not declare it — either that require is broken, or that map predates a rename",
  ["tag-file-unavailable"] = "tag_files['{prefix}'] points at {dir}, which has no readable module_map.json — requires under '{prefix}' were not checked",
  ["unreferenced-module"] = "{module} is required by no other file in the tree",
  ["orphaned-class-alias"] = "{kind} {name} is declared in {file} and referenced by nothing in the tree",
  ["test-references-missing"] = "{file}:{line} references '{alias}.{field}', but {module} has no '{field}'",
  ["binding-conflict"] = "{what} is registered {count} times; the last one wins: {where}",
  ["unused-require"] = "{file}:{line} binds require('{module}') to '{alias}' and never uses it",
  ["example-does-not-parse"] = "{fn}'s @example is not valid Lua: {error}",
  ["consumer-require-missing"] = "{module} is required by {who} but no module here declares it — either they are broken, or their map predates a rename",
  ["require-cycle"] = "require cycle across {count} modules: {members}",
  -- The quotes are the template's, not a value's: the check used `%q` here
  -- and the acceptance criterion is byte-identity. A module name has
  -- nothing `%q` would escape beyond wrapping it.
  ["require-not-declared"] = 'requires "{module}" (line {line}), which no file in this tree declares',
  ["layer-violation"] = "{from} requires {to}, but {from_layer} must not reach into {to_layer}{why}",
  ["dead-see-target"] = "{fn}: @see target '{target}' does not resolve to a known module or function",
  ["type-vs-class"] = '{module}: local "{name}" annotated ---@type {type}, but {count} field(s) are assigned to it after its literal — LuaLS reports missing-fields/"fields cannot be injected" for this shape; use ---@class instead (---@class {module} : {type}, plus @see the type definition, if {type} should still be checked against it)',
  ["undocumented-param"] = "{fn} has {declared} parameter(s) but only {documented} @param line(s)",
  ["param-name-mismatch"] = "{fn}: @param #{index} is documented as '{documented}' but the signature declares '{actual}' at that position",
  ["dead-function.file-local"] = "{fn} is file-local and nothing in its own file mentions it",
  ["dead-function.internal"] = "{fn} is marked @internal and nothing in the tree calls it",
  ["dead-function.no-caller"] = "{fn} has no caller anywhere in the tree",
}

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

---Substitute `{name}` placeholders from `params`.
---
---A placeholder with no matching parameter is left standing rather than
---replaced with the empty string: a template and its call site drifting
---apart is a defect, and `{who}` sitting visibly in the output says so
---where a silent gap would not. Same reasoning as rule 2.3 one level down.
---
---Values are substituted literally, and a **function** replacement is what
---makes that true: `gsub` interprets `%1`/`%%` only in a replacement
---*string*, never in what a replacement function returns. An earlier
---version escaped the value defensively and so turned a `%s` inside an
---`@example` parse error into `%%s`. Found by this module's own spec, not
---by the three-repository byte comparison — no real finding happened to
---carry a percent sign.
---@param template string
---@param params table<string, any>?
---@return string
local function interpolate(template, params)
  if not params then
    return template
  end
  return (
    template:gsub("{([%w_]+)}", function(name)
      local value = params[name]
      if value == nil then
        return "{" .. name .. "}"
      end
      return tostring(value)
    end)
  )
end

---Render one finding as a sentence.
---
---The single entry point every surface calls. Three cases, in order:
---a finding that already carries prose (an `opts.extra_checks` finding)
---keeps it; a known key is interpolated; an unknown key renders visibly
---rather than blank.
---@param finding Docmap.Finding
---@return string
function M.format(finding)
  if finding.message then
    return finding.message
  end
  local key = M.key(finding)
  local template = M.CATALOG[key]
  if not template then
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
  return interpolate(template, finding.params)
end

---Catalog entry for a check that skipped nodes because their language lacks
---the convention it needs (`check.not_applicable`). Plural-neutral on purpose:
---`{languages}` is a list.
M.NOT_APPLICABLE = "Not applicable: {check} on {count} node(s); no {needs} in {languages}"

---Render one `Docmap.NotApplicable` as a sentence, for the CLI report and the
---page alike.
---@param na Docmap.NotApplicable
---@return string
function M.format_not_applicable(na)
  return interpolate(M.NOT_APPLICABLE, {
    check = na.check,
    count = na.count,
    needs = na.needs,
    languages = table.concat(na.languages, ", "),
  })
end

return M
