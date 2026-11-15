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

---One entry per check: how severe a hit is by default. What the check compares and why it exists are
---sentences, so they live in the interface catalog as `check.<name>.compares` and `check.<name>.why`
---(`core/i18n/en.json`, translated beside it) and are read with `M.explain`.
---
---**Next to the templates on purpose.** `M.CATALOG` says what a finding reads like; this says which checks
---exist and how they grade. `findings_spec.lua` ties the two together in both directions (a template without
---an entry fails, and so does an entry without a template, or without its two sentences in the catalog), so
---there is no second list of checks somewhere else that can drift from the first.
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
---@field severity Docmap.Severity The default grade.

---@type table<string, Docmap.CheckInfo>
M.CHECKS = {
  ["missing-module-tag"] = { severity = "error" },
  ["missing-summary"] = { severity = "warn" },
  ["module-path-mismatch"] = { severity = "error" },
  ["file-holds-many-modules"] = { severity = "info" },
  ["missing-readme"] = { severity = "info" },
  ["dead-readme-link"] = { severity = "warn" },
  ["placeholder-readme-link"] = { severity = "warn" },
  ["doc-references-missing"] = { severity = "warn" },
  ["sibling-reference-missing"] = { severity = "warn" },
  ["tools-spec-invalid"] = { severity = "warn" },
  ["feature-module-missing"] = { severity = "warn" },
  ["tag-require-missing"] = { severity = "warn" },
  ["tag-file-unavailable"] = { severity = "info" },
  ["unreferenced-module"] = { severity = "info" },
  ["orphaned-class-alias"] = { severity = "info" },
  ["test-references-missing"] = { severity = "warn" },
  ["binding-conflict"] = { severity = "warn" },
  ["unused-require"] = { severity = "info" },
  ["example-does-not-parse"] = { severity = "warn" },
  ["consumer-require-missing"] = { severity = "warn" },
  ["require-cycle"] = { severity = "warn" },
  ["require-not-declared"] = { severity = "warn" },
  ["layer-violation"] = { severity = "warn" },
  ["dead-see-target"] = { severity = "warn" },
  ["type-vs-class"] = { severity = "warn" },
  ["undocumented-param"] = { severity = "info" },
  ["param-name-mismatch"] = { severity = "info" },
  ["dead-function"] = { severity = "info" },
}

---What a check compares and why it exists, in a locale.
---@param name string A key of `M.CHECKS`.
---@param locale string? Defaults to the active locale; a renderer of a committed file passes `i18n.SOURCE`.
---@return string compares What the check holds against what.
---@return string why Why a mismatch is worth a finding.
function M.explain(name, locale)
  return i18n.t("check." .. name .. ".compares", nil, locale),
    i18n.t("check." .. name .. ".why", nil, locale)
end

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
---of `module_map.json`. The sentences are English (`i18n.SOURCE`), the page being one artifact for every
---language; `keys` names the catalog key of each template (`finding.<key>`), and the page says the card in the
---reader's language from `check.<name>.*` and those keys.
---@return { name: string, severity: Docmap.Severity, compares: string, why: string, templates: string[], keys: string[] }[]
function M.for_page()
  local by_check, keys_of = {}, {}
  -- A plain loop, not `vim.tbl_keys`: this runs in the standalone build too, whose shim has no such function.
  local keys = {}
  for key in pairs(M.CATALOG) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local name = M.check_of(key)
    by_check[name] = by_check[name] or {}
    keys_of[name] = keys_of[name] or {}
    table.insert(by_check[name], M.CATALOG[key])
    table.insert(keys_of[name], key)
  end
  local out = {}
  for name, info in pairs(M.CHECKS) do
    local compares, why = M.explain(name, i18n.SOURCE)
    out[#out + 1] = {
      name = name,
      severity = info.severity,
      compares = compares,
      why = why,
      templates = by_check[name] or {},
      keys = keys_of[name] or {},
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
