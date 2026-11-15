-- TESTS/sheets/interface-language.sheet.lua -- the interface language of the page, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page. That tree has 6
-- findings, among them a `missing-readme` for lua/app/util, and the page embeds every shipped catalog; German is
-- embedded and not offered yet (core/render/html.lua, PAGE_OFFERED), so it is reached by `lang=` only.
local function text(sel)
  return ("document.querySelector('%s').textContent"):format(sel)
end

-- No horizontal overflow in a row of controls: the German labels are longer than the English ones the row was
-- sized against.
local function fits(sel)
  return ("(e => e.scrollWidth <= e.clientWidth + 1)(document.querySelector('%s'))"):format(sel)
end

return {
  id = "interface-language",
  title = "The page in English and in German: chrome, findings, link, picker",
  task = "docmap.nvim/i18n-generated-page",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { wait = "document.querySelector('#hstage .hnode') !== null", note = "the page is up" },
    {
      expect = "document.documentElement.lang === 'en'",
      note = "English by default: the browser of the sheet asks for no offered locale but English",
    },
    {
      expect = text('.tab-btn[data-tab="hierarchy"]') .. " === 'Hierarchy'",
      note = "the tab bar reads English",
    },
    {
      expect = "document.getElementById('q').placeholder === 'Jump to a module — Enter commits'",
      note = "and so does the filter",
    },
    {
      expect = "document.getElementById('langselwrap').hidden && !/lang=/.test(location.hash)",
      note = "one offered language: no picker, and the link carries no language",
    },
    {
      expect = "/ modules$/.test(" .. text('.stat-link[data-goto="modules"]') .. ")",
      note = "the count in the header keeps its English label",
    },
    { shot = "en-light" },

    -- German, by the link.
    {
      expect = "(location.hash = '#tab=hierarchy&lang=de', true)",
      note = "a link that names German",
    },
    {
      wait = "document.documentElement.lang === 'de'",
      note = "the page switches without a reload",
    },
    {
      expect = text('.tab-btn[data-tab="hierarchy"]') .. " === 'Hierarchie' && " .. text(
        '.tab-btn[data-tab="findings"]'
      ) .. " === 'Befunde' && " .. text('.hview-btn[data-view="deps"]') .. " === 'Abhängigkeiten'",
      note = "tab bar and view buttons are German",
    },
    {
      expect = "document.getElementById('q').placeholder === 'Zu einem Modul springen — Enter bestätigt'"
        .. " && document.getElementById('copylink').title === 'Einen Link auf genau diese Ansicht kopieren'"
        .. " && document.getElementById('hcrumb').getAttribute('aria-label') === 'Wurzel des Graphen'"
        .. " && document.querySelector('.hdepth-btn[data-depth=\"2\"]').title === 'Tiefe 2'",
      note = "placeholder, tooltip, aria-label and a tooltip with a parameter",
    },
    {
      expect = "/ Module$/.test("
        .. text('.stat-link[data-goto="modules"]')
        .. ") && /^\\d+ /.test("
        .. text('.stat-link[data-goto="modules"]')
        .. ")",
      note = "the header count: the number stays, the label is German",
    },
    {
      expect = "/Modulkarte/.test(document.title) && " .. text("h1 .sub") .. " === 'Modulkarte'",
      note = "the title of the document and of the page",
    },
    {
      expect = "(w => !w.hidden && document.getElementById('langsel').value === 'de'"
        .. " && [...document.getElementById('langsel').options].map(o => o.textContent).join('|')"
        .. " === 'Sprache des Browsers|English|Deutsch')(document.getElementById('langselwrap'))",
      note = "the picker appears with the active language in it, each language under its own name",
    },
    {
      expect = fits(".tabs") .. " && " .. fits(".toolbar"),
      note = "tab bar and toolbar do not overflow",
    },
    {
      expect = "/^enthält/.test(document.querySelector('#hlegend .lg').textContent)"
        .. " && /Rechtsklick für mehr/.test(document.getElementById('hlegend').textContent)",
      note = "the legend under the diagram is German",
    },
    { shot = "de-light-hierarchy" },

    -- The Coupling plot: its corners, axes and bar, drawn by the script.
    {
      expect = "(location.hash = '#tab=hierarchy&view=coupling&lang=de', true)",
      note = "the Coupling view",
    },
    {
      wait = "document.querySelector('#halt .cq, #halt .hmsg') !== null",
      note = "the plot (or its message) is drawn",
    },
    {
      expect = "/^Fan-out nach rechts/.test(document.querySelector('#halt .hmuted').textContent)"
        .. " && !/required by|fan-out across|No module/.test(document.getElementById('halt').textContent)",
      note = "bar, corners and axes are German",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-light-coupling" },
    {
      expect = "(location.hash = '#tab=hierarchy&lang=de', true)",
      note = "back to the Modules view",
    },
    { wait = "document.querySelector('#hstage .hnode') !== null" },

    -- The explanation card of a tab, from the catalog.
    { hover = '.tab-btn[data-tab="hierarchy"]', note = "a dwell on the Hierarchy tab" },
    {
      wait = "(p => !!p && p.classList.contains('on'))(document.querySelector('.explainpop'))",
      note = "its explanation card opens",
    },
    {
      expect = "/^Der Abhängigkeitsgraph, von einem Modul aus/.test(document.querySelector('.explainpop').textContent)",
      note = "and explains the tab in German",
    },
    { shot = "de-light-explain" },
    { press = "Escape", note = "the card is put away" },

    -- The findings, said from their parameters.
    { click = '.tab-btn[data-tab="findings"]', note = "the Findings tab" },
    {
      wait = "document.getElementById('view-findings').classList.contains('active')",
    },
    {
      expect = "/^Drift-Befunde \\(\\d+\\)$/.test("
        .. text("#findings summary")
        .. ") && "
        .. text("#findings th")
        .. " === 'Schwere'",
      note = "the disclosure and the table head",
    },
    {
      expect = "[...document.querySelectorAll('#findings td[data-finding]')].some(td =>"
        .. " / hat keine README\\.md$/.test(td.textContent))"
        .. " && ![...document.querySelectorAll('#findings td[data-finding]')].some(td =>"
        .. " / has no README\\.md$/.test(td.textContent))",
      note = "a finding reads German, with its path unchanged; no English sentence is left",
    },
    {
      expect = "/lang=de/.test(location.hash)",
      note = "the language stays in the link across tabs",
    },
    {
      -- The fixture has no history and no count above a thousand, so the formatters of the page are asked
      -- directly: the runtime the page embeds, with the catalogs it embeds, in this browser's Intl.
      expect = "(rt => (rt.configure({ locale: 'de' }), rt.number(1234567.5) === '1.234.567,5'"
        .. " && /^1\\. M.+ 2026$/.test(rt.date('2026-03-01'))"
        .. " && ['zebra', 'Äpfel', 'apfel'].sort(rt.compare).join(' ') === 'apfel Äpfel zebra'))"
        .. "(docmapI18n(JSON.parse(document.getElementById('i18n').textContent)))",
      note = "a German number, a German day and the German name order, in the browser's Intl",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-light-findings" },

    -- The card of a check id: chrome and sentences from the catalog.
    { click = '#findings .kw[data-kwkind="check"]', note = "a check id in the table" },
    { wait = "document.getElementById('kwpop').classList.contains('on')", note = "its card opens" },
    {
      expect = "(p => p.querySelector('.kw-kind').textContent === 'Prüfung'"
        .. " && p.querySelector('.kw-label').textContent === 'Warum'"
        .. " && /Befunde? hier$/.test(p.querySelector('.kw-origin').textContent))"
        .. "(document.getElementById('kwpop'))",
      note = "kind, label and the count line are German",
    },
    { shot = "de-light-check-card" },
    { press = "Escape", note = "the card is put away" },
    { scheme = "dark" },
    { shot = "de-dark-findings" },
    { click = '.tab-btn[data-tab="hierarchy"]' },
    { wait = "document.querySelector('#hstage .hnode') !== null" },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-dark-hierarchy" },

    -- Analysis: the longest row of buttons the page has.
    { click = '.tab-btn[data-tab="analysis"]' },
    { wait = "document.getElementById('view-analysis').classList.contains('active')" },
    {
      expect = text('.anview-btn[data-atool="test"]') .. " === 'Testabdeckung' && " .. text(
        "#anview-runtime-label"
      ) .. " === 'Laufzeit'",
      note = "the tools of the Analysis tab",
    },
    {
      wait = "document.querySelector('#anbody .nsub, #anbody .none') !== null",
      note = "a tool is drawn",
    },
    {
      expect = "[...document.querySelectorAll('#anbody th')].every(th => !/^(Module|Function|Functions|Tested|Documented)\\b/.test(th.textContent))"
        .. " && !/ functions \\(| documented functions| modules with at least/.test(document.getElementById('anbody').textContent)",
      note = "its column heads and its line are German",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-dark-analysis" },

    -- Quicks: the verdicts are said from their keys and parameters.
    { click = '.tab-btn[data-tab="quicks"]' },
    {
      wait = "document.querySelector('#view-quicks .qk') !== null",
      note = "the verdicts are drawn",
    },
    {
      expect = "[...document.querySelectorAll('#view-quicks .qk-h')].every(h =>"
        .. " /^(Lohnt eine Korrektur|Läuft gut)/.test(h.textContent))"
        .. " && [...document.querySelectorAll('#view-quicks .qk-acts button')].every(b =>"
        .. " /^(Die Zeilen zeigen|Alle \\d+ markieren)$/.test(b.textContent))",
      note = "column heads and buttons are German",
    },
    {
      expect = "[...document.querySelectorAll('#view-quicks .qk-line')].every(l =>"
        .. " !/^(Your|Most|The|Nothing|No |A |Many|Several|There|Almost|Deprecated|Nearly)/.test(l.textContent))",
      note = "and no verdict reads as one of the English sentences the page carries",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-dark-quicks" },
    { scheme = "light" },

    -- Compare with nothing marked, and History opened from a file: both say why they are empty, in German.
    { click = '.tab-btn[data-tab="compare"]' },
    {
      wait = "/^Noch nichts markiert/.test(document.getElementById('cmpbody').textContent)",
      note = "the empty Compare tab explains marks in German",
    },
    { click = '.tab-btn[data-tab="history"]' },
    {
      wait = "/^Diese Seite wurde aus einer Datei geöffnet/.test(document.getElementById('hist-detail').textContent)",
      note = "History says in German why a file page has nothing to ask",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-light-history" },

    -- The Tree detail pane of a module with a finding: section titles, the Stats labels, Meta.
    {
      expect = "(r => (location.hash = '#tab=tree&id=' + encodeURIComponent(r.dataset.id) + '&lang=de', true))"
        .. "([...document.querySelectorAll('#tree .row[data-id]')].find(r => /util/.test(r.textContent)))",
      note = "the module util in the Tree",
    },
    {
      wait = "[...document.querySelectorAll('#detail .sec')].some(s => /^Zahlen/.test(s.textContent))",
      note = "its detail pane is drawn, in German",
    },
    {
      expect = "(secs => secs.includes('Meta')"
        .. " && !secs.some(s => /^(Stats|Requires|Required by|Functions|Contains)\\b/.test(s)))"
        .. "([...document.querySelectorAll('#detail .sec')].map(s => s.textContent))"
        .. " && /^Art: /.test([...document.querySelectorAll('#detail .lst li')].pop().textContent)",
      note = "no section title is left in English, and the Meta line is German",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    {
      expect = "(document.getElementById('detail').scrollIntoView(), true)",
      note = "the pane in view",
    },
    { shot = "de-light-detail" },

    -- Notes and Index: drawn once per language.
    { click = '.tab-btn[data-tab="notes"]' },
    { wait = "document.querySelector('#view-notes .ngroup') !== null" },
    {
      expect = "[...document.querySelectorAll('#view-notes .ngroup')].map(h => h.firstChild.textContent).join('|')"
        .. " === 'Annotationen|Kommentar-Marker'",
      note = "the two groups of the Notes tab are German",
    },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-light-notes" },
    { click = '.tab-btn[data-tab="index"]' },
    { wait = "document.querySelector('#ixbody .nsub, #ixbody .none') !== null" },
    {
      expect = "/(dokumentierte Funktion|keine dokumentierten Funktionen)/.test(document.getElementById('ixbody').textContent)",
      note = "the Index says its line in German",
    },

    -- Back to English through the picker, the way a reader would.
    {
      expect = "(s => (s.value = 'en', s.dispatchEvent(new Event('change')), true))(document.getElementById('langsel'))",
      note = "English chosen in the picker",
    },
    {
      wait = "document.documentElement.lang === 'en' && "
        .. text('.tab-btn[data-tab="hierarchy"]')
        .. " === 'Hierarchy'",
    },
    {
      expect = "/lang=en/.test(location.hash) && localStorage.getItem('docmap.lang') === 'en'",
      note = "a choice is kept in the link and in this browser",
    },
    {
      expect = "(s => (s.value = '', s.dispatchEvent(new Event('change')), true))(document.getElementById('langsel'))",
      note = "and handed back: Browser language",
    },
    {
      wait = "!/lang=/.test(location.hash) && localStorage.getItem('docmap.lang') === null",
      note = "no language in the link, none stored",
    },
    { click = '.tab-btn[data-tab="hierarchy"]' },
    { wait = "document.querySelector('#hstage .hnode') !== null" },
    { scheme = "dark" },
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "en-dark" },
    { scheme = "light" },

    -- The picker says what is chosen, not what was: from a link that names English to one that names nothing
    -- the page stays English (the browser's own), and the choice is no longer made.
    {
      expect = "(location.hash = '#tab=hierarchy&lang=en', true)",
      note = "a link that names English",
    },
    { wait = "document.getElementById('langsel').value === 'en'" },
    {
      expect = "(location.hash = '#tab=hierarchy', true)",
      note = "and one that names no language",
    },
    {
      wait = "document.getElementById('langsel').value === '' && document.documentElement.lang === 'en'",
      note = "the picker is back on Browser language while the page stays English",
    },
  },
  judge = {
    "German: tab bar, toolbar and the row of Hierarchy controls do not wrap badly or overflow",
    "German: the Analysis tool row reads well at the width of the window",
    "German: the wording of tabs, views and findings is the wording wanted",
    "Both themes: the picker in the top bar is legible and sits where a reader looks for it",
  },
}
