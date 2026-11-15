-- TESTS/i18n_runtime_spec.lua — the two runtimes of the interface catalog answer the golden cases alike.
--
-- `TESTS/fixtures/i18n/cases.json` is the contract in executable form (docs/i18n.md): which shipped locale a
-- tag means, which plural form a count selects, what a missing key or a missing parameter renders as. Each case
-- is run through
--   * the Lua runtime (`docmap.core.i18n`), here in this editor, and
--   * the JavaScript runtime of the page (`docmap.core.render.html.i18n_js`), in `node` (skipped without `node`,
--     and said so),
-- and both have to give the answer the file states. A change of semantics is a change of that file first.

return function(H)
  local ok, eq = H.ok, H.eq

  local path = "TESTS/fixtures/i18n/cases.json"
  local doc = vim.json.decode(H.slurp(path))
  ok(#doc.t >= 30 and #doc.normalize >= 20, "i18n runtime: the golden file holds its cases")

  ---`null` in the file is `vim.NIL` here; the runtimes are handed nil.
  local function denil(v)
    if v == vim.NIL then
      return nil
    end
    return v
  end

  -- ── Lua ──────────────────────────────────────────────────────────────────
  local i18n = require("docmap.core.i18n")
  i18n._use(doc.catalogs)

  for i, case in ipairs(doc.normalize) do
    eq(
      i18n.normalize(denil(case.tag)),
      denil(case.want),
      ("lua normalize #%d (%s)"):format(i, tostring(case.tag))
    )
  end
  for i, case in ipairs(doc.resolve) do
    local list = case.candidates
    local got
    -- Up to four candidates in the file; handed over as arguments, nils included.
    got = i18n.resolve(denil(list[1]), denil(list[2]), denil(list[3]), denil(list[4]))
    eq(got, case.want, ("lua resolve #%d"):format(i))
  end
  for i, case in ipairs(doc.plural) do
    eq(i18n.plural_category(case.locale, denil(case.n)), case.want, ("lua plural #%d"):format(i))
  end
  for i, case in ipairs(doc.t) do
    i18n.configure({ locale = case.active or "en", debug = case.debug == true })
    local got = i18n.t(case.key, case.params, case.locale)
    eq(
      got,
      case.want,
      ("lua t #%d (%s in %s)"):format(i, case.key, tostring(case.locale or case.active))
    )
  end

  -- What the cases cannot say in JSON.
  i18n.configure({ locale = "en", debug = false })
  eq(i18n.has("plain"), true, "lua has: a key of the source catalog")
  eq(i18n.has("no.such.key"), false, "lua has: an unknown key")
  eq(i18n.configure({ locale = "de-AT" }), "de", "lua configure: returns the locale now active")
  eq(i18n.configure({ locale = "zz" }), "en", "lua configure: an unknown tag leaves English active")
  eq(i18n.configure({}), "en", "lua configure: nothing given changes nothing")
  eq(#i18n.keys("count."), 3, "lua keys: a prefix narrows the list")
  eq(i18n.keys()[1], "braces", "lua keys: sorted")
  local page = i18n.for_page({ "count." })
  eq(page.source, "en", "lua for_page: names the source locale")
  eq(#page.locales, 3, "lua for_page: every shipped locale")
  ok(
    page.catalogs.en["count.files"] ~= nil and page.catalogs.en.plain == nil,
    "lua for_page: only the prefixes asked for"
  )

  -- Back to the shipped catalogs: this editor runs the other specs after this one.
  i18n._reset()
  eq(i18n.locale(), "en", "lua: reset returns to English")
  ok(i18n.has("finding.missing-readme"), "lua: the shipped source catalog is read from its file")
  eq(next(i18n.problems()), nil, "lua: every shipped catalog loads")

  -- ── JavaScript, in node ──────────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    print("  i18n runtime: node not found, the JavaScript half was NOT run")
    return
  end
  local js = require("docmap.core.render.html.i18n_js")
  -- Line by line: `H.write` hands the list to `writefile`, which writes a line break inside an item as NUL.
  local driver = vim.split(js, "\n", { plain = true })
  vim.list_extend(driver, {
    "var fs = require('fs');",
    "var doc = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));",
    "var rt = docmapI18n({ source: 'en', catalogs: doc.catalogs, locales: [] });",
    "var out = { normalize: [], resolve: [], plural: [], t: [] };",
    "doc.normalize.forEach(function(c){ out.normalize.push(rt.normalize(c.tag)); });",
    "doc.resolve.forEach(function(c){ out.resolve.push(rt.resolve(c.candidates)); });",
    "doc.plural.forEach(function(c){ out.plural.push(rt.pluralCategory(c.locale, c.n)); });",
    "doc.t.forEach(function(c){",
    "  rt.configure({ locale: c.active || 'en', debug: c.debug === true });",
    "  out.t.push(rt.t(c.key, c.params, c.locale));",
    "});",
    "rt.configure({ locale: 'en', debug: false });",
    "out.has = [rt.has('plain'), rt.has('no.such.key'), rt.configure({ locale: 'de-AT' }), rt.configure({ locale: 'zz' })];",
    -- The formatters of the page, in each locale: they follow the active locale, not the machine's.
    "out.format = {};",
    "['en', 'de'].forEach(function(code){",
    "  rt.configure({ locale: code });",
    "  out.format[code] = {",
    "    number: rt.number(1234567.5), small: rt.number(7), notnum: rt.number('n/a'),",
    "    date: rt.date('2026-03-01'), notdate: rt.date('yesterday'), nodate: rt.date(undefined),",
    "    moment: rt.dateTime(Date.UTC(2026, 2, 1, 12, 0) / 1000),",
    "    sorted: ['zebra', 'Äpfel', 'banana', 'apfel', 'Zoo'].sort(rt.compare)",
    "  };",
    "});",
    "rt.configure({ locale: 'en' });",
    "process.stdout.write(JSON.stringify(out));",
  })
  local tmp = H.tmpfile(".js")
  H.write(tmp, driver)
  -- A fixed zone, so the moment reads the same on every machine.
  local result = vim.system({ "node", tmp, path }, { text = true, env = { TZ = "UTC" } }):wait()
  vim.fn.delete(tmp)
  eq(result.code, 0, "js: the runtime evaluates in node: " .. tostring(result.stderr))
  local got = vim.json.decode(result.stdout)
  for _, kind in ipairs({ "normalize", "resolve", "plural", "t" }) do
    for i, case in ipairs(doc[kind]) do
      eq(
        denil(got[kind][i]),
        denil(case.want),
        ("js %s #%d (%s)"):format(kind, i, tostring(case.key or case.tag or ""))
      )
    end
  end
  eq(got.has[1], true, "js has: a key of the source catalog")
  eq(got.has[2], false, "js has: an unknown key")
  eq(got.has[3], "de", "js configure: returns the locale now active")
  eq(got.has[4], "en", "js configure: an unknown tag leaves English active")

  -- ── The formatters of the page (no Lua twin: Lua writes ungrouped ASCII digits) ──
  local en_f, de_f = got.format.en, got.format.de
  eq(en_f.number, "1,234,567.5", "js number: grouped the English way")
  eq(de_f.number, "1.234.567,5", "js number: and the German way")
  eq(de_f.small, "7", "js number: a small count stays as it is")
  eq(de_f.notnum, "n/a", "js number: what is no number is shown as given")
  eq(en_f.date, "Mar 1, 2026", "js date: a git day in English")
  ok(de_f.date:match("^1%. M.+ 2026$") ~= nil, "js date: and in German, day first: " .. de_f.date)
  eq(de_f.notdate, "yesterday", "js date: what is no git day is shown as given")
  eq(de_f.nodate, "", "js date: no day, no text")
  ok(
    en_f.moment:find("Mar 1, 2026", 1, true) and en_f.moment:find("12:00", 1, true),
    "js dateTime: day and time in English: " .. en_f.moment
  )
  ok(
    de_f.moment:match("^1%. M.+ 2026") and de_f.moment:find("12:00", 1, true),
    "js dateTime: and in German: " .. de_f.moment
  )
  eq(
    table.concat(de_f.sorted, " "),
    "apfel Äpfel banana zebra Zoo",
    "js compare: the order of the locale, case and accents second"
  )
end
