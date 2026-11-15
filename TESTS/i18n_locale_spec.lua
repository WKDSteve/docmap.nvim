-- TESTS/i18n_locale_spec.lua — which surface speaks which language (docs/i18n.md, "Artifacts stay English").
--
--   * a finding is rendered in the active locale for an interactive surface, and in the locale a renderer
--     names: that is what keeps `overview.md` and SARIF the same bytes on a machine that speaks German;
--   * the renderers of committed files name the source locale, the interactive ones do not (pinned as text);
--   * the hosts resolve their locale in the documented order (pinned as text; the order itself is
--     `i18n.resolve`, which the golden cases cover);
--   * the suite itself is pinned to English.

return function(H)
  local ok, eq = H.ok, H.eq

  local i18n = require("docmap.core.i18n")
  local findings = require("docmap.core.findings")

  eq(vim.env.DOCMAP_LOCALE, "en", "locale: the suite is pinned to English (TESTS/minimal_init.lua)")

  -- ── One finding, two readers ─────────────────────────────────────────────
  local source = assert(i18n.catalog("en")).messages
  i18n._use({
    en = source,
    de = {
      ["finding.missing-readme"] = "{path} hat keine README.md",
      ["report.not-applicable"] = "Nicht anwendbar: {check} auf {count} Knoten; kein {needs} in {languages}",
    },
  })
  local finding =
    { severity = "info", check = "missing-readme", node = "lua/x", params = { path = "lua/x" } }
  local skipped =
    { check = "missing-summary", count = 2, needs = "doc comments", languages = { "c", "go" } }

  eq(
    findings.format(finding),
    "lua/x has no README.md",
    "locale: English until a host says otherwise"
  )
  i18n.configure({ locale = "de_DE.UTF-8" })
  eq(findings.format(finding), "lua/x hat keine README.md", "locale: the active locale speaks")
  eq(
    findings.format(finding, "en"),
    "lua/x has no README.md",
    "locale: a renderer that names English gets it"
  )
  eq(
    findings.format_not_applicable(skipped),
    "Nicht anwendbar: missing-summary auf 2 Knoten; kein doc comments in c, go",
    "locale: the not-applicable line follows the active locale"
  )
  eq(
    findings.format_not_applicable(skipped, "en"),
    "Not applicable: missing-summary on 2 node(s); no doc comments in c, go",
    "locale: and English when a renderer names it"
  )
  -- A check the German catalog has not translated yet reads English, never blank.
  local untranslated =
    { severity = "warn", check = "missing-summary", node = "a", params = { file = "a.lua" } }
  eq(
    findings.format(untranslated),
    "a.lua has no description line",
    "locale: an untranslated finding reads English"
  )
  -- Prose a foreign check brought along is nobody's to translate.
  eq(
    findings.format({ check = "x", message = "their own words" }),
    "their own words",
    "locale: `message` wins"
  )
  i18n._reset()

  -- ── Who names the source locale ──────────────────────────────────────────
  local function src(rel)
    return assert(H.slurp("lua/docmap/" .. rel), rel .. " is readable")
  end
  local function count(text, needle)
    local n, from = 0, 1
    while true do
      local at = text:find(needle, from, true)
      if not at then
        return n
      end
      n, from = n + 1, at + #needle
    end
  end
  local pinned = 'require("docmap.core.findings").format(f, "en")'
  local active = 'require("docmap.core.findings").format(f)'
  eq(count(src("core/render/markdown.lua"), pinned), 2, "overview.md is rendered in English")
  eq(
    count(src("core/render/markdown.lua"), active),
    0,
    "overview.md: no finding in the active locale"
  )
  eq(count(src("core/render/sarif.lua"), pinned), 1, "SARIF is rendered in English")
  eq(count(src("mcp/tools.lua"), pinned), 1, "the MCP answer is rendered in English")
  ok(count(src("core/cli.lua"), active) >= 1, "the report follows the active locale")
  ok(count(src("bindings/diagnostics.lua"), active) >= 1, "diagnostics follow the active locale")
  ok(
    count(src("bindings/usrcmds/generate.lua"), active) >= 1,
    "the quickfix list follows the active locale"
  )

  -- ── Where a host takes its locale from ───────────────────────────────────
  ok(
    src("init.lua"):find(
      "i18n.resolve(opts and opts.locale, vim.env.DOCMAP_LOCALE, vim.v.lang, vim.env.LANG)",
      1,
      true
    ),
    "the editor: opts.locale, $DOCMAP_LOCALE, v:lang, $LANG"
  )
  local cli = src("core/cli.lua")
  ok(cli:find('cli_locale = a:sub(#"--locale=" + 1)', 1, true), "the engine reads --locale=")
  ok(
    cli:find('os.getenv("DOCMAP_LOCALE"),', 1, true)
      and cli:find('os.getenv("LC_MESSAGES"),', 1, true),
    "the engine: then $DOCMAP_LOCALE and the POSIX variables"
  )
  ok(
    require("docmap.config").build ~= nil
      and src("config/init.lua"):find("\n  locale = true,\n", 1, true),
    "`locale` is a known option of setup()"
  )
  ok(
    not src("config/file.lua"):find("locale = true", 1, true),
    "`locale` is not read from .docmap.json: the language belongs to the reader"
  )
end
