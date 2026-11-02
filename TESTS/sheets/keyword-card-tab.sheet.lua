-- TESTS/sheets/keyword-card-tab.sheet.lua -- the keyword card of the generated page, reached with the keyboard.
-- The card is HTML/JS of the page (`#kwpop`, `[data-kw]` spans with tabindex=0, focusin/Escape handlers), so this
-- is a browser sheet: a real chromium opens the page that TESTS/sheets_spec.lua renders from the fixture module
-- TESTS/fixtures/keyword_page (a `@nodiscard` function: its badge is a keyword span), opens a function and
-- works the card with Tab / Escape.
return {
  id = "keyword-card-tab",
  title = "Keyword card: Tab navigation in a real window",
  task = "docmap.nvim/keyword-card-tab-navigation-live-check",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/keyword-page.html" },
    { click = 'text="Index"', note = "the Index tab" },
    { click = 'a.nfn:has-text("M.count()")', note = "open the function" },
    {
      wait = "[...document.querySelectorAll('.bd[data-kw]')].some(e => e.offsetParent !== null)",
      timeout = 5000,
      note = "its detail has keyword badges",
    },
    {
      expect = "([...document.querySelectorAll('.bd[data-kw]')].find(e => e.offsetParent !== null).scrollIntoView({ block: 'center' }), true)",
      note = "bring the badge into view (a scroll closes the card, so this comes first)",
    },
    {
      expect = "new Promise(resolve => setTimeout(() => resolve(true), 400))",
      note = "let the scroll events pass",
    },
    {
      expect = "([...document.querySelectorAll('.bd[data-kw]')].find(e => e.offsetParent !== null).focus({ preventScroll: true }), document.activeElement.hasAttribute('data-kw'))",
      note = "a keyword badge takes the focus",
    },
    {
      expect = "document.getElementById('kwpop').classList.contains('on')",
      note = "focusing it opens the card",
    },
    { shot = "card-open" },
    { press = "Escape" },
    {
      expect = "!document.getElementById('kwpop').classList.contains('on')",
      note = "Escape closes the card",
    },
    { press = "Tab" },
    {
      expect = "document.activeElement !== document.body && document.activeElement.hasAttribute('tabindex')",
      note = "Tab moves the focus on to the next focusable thing",
    },
    {
      expect = "([...document.querySelectorAll('.bd[data-kw]')].find(e => e.offsetParent !== null).focus({ preventScroll: true }), document.getElementById('kwpop').classList.contains('on'))",
      note = "back on a badge the card is there again",
    },
  },
  judge = { "the keyword card is readable and sits next to its keyword (screenshot card-open)" },
}
