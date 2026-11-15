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
    { shot = "de-light-hierarchy" },

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
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-light-findings" },
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
    { hover = "h1" },
    { press = "Escape", note = "the explanation of the tab is put away" },
    { shot = "de-dark-analysis" },
    { scheme = "light" },

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
  },
  judge = {
    "German: tab bar, toolbar and the row of Hierarchy controls do not wrap badly or overflow",
    "German: the Analysis tool row reads well at the width of the window",
    "German: the wording of tabs, views and findings is the wording wanted",
    "Both themes: the picker in the top bar is legible and sits where a reader looks for it",
  },
}
