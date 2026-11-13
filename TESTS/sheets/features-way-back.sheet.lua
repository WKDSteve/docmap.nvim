-- TESTS/sheets/features-way-back.sheet.lua -- the theme sub-tabs of the Features tab and the way back from a
-- module or a function to its feature descriptions, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page, whose docs/FEATURES
-- holds two theme files: CORE.md ("The store" naming core/store.lua with M.load and M.save, "Words" naming
-- app.util.text) and UI.md ("The window title" naming ui/window.lua and core/store.lua with M.load). So
-- core/store.lua is described by two features, M.load by two, M.save by one.
local STORE = "lua/app/core/store.lua"
local function trigger(key)
  return ("document.querySelector('#detail .feati[data-feat=\"%s\"]')"):format(key)
end
local POP = "document.getElementById('sigpop')"

return {
  id = "features-way-back",
  title = "Features: theme sub-tabs and the popup from a module back to its features",
  task = "docmap.nvim/features-reverse-index-popup",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { click = 'button[data-tab="features"]', note = "the Features tab" },
    {
      wait = "document.querySelectorAll('#feattoggle .anview-btn').length === 2",
      note = "two theme files, two sub-tabs",
    },
    {
      expect = "(g => g.length === 2 && !g[0].hidden && g[1].hidden && g[0].dataset.ftheme === 'CORE')"
        .. "([...document.querySelectorAll('.feat-group')])",
      note = "the first file shows, the other is hidden",
    },
    {
      expect = "document.querySelector('.feat-count').textContent"
        .. " === 'CORE: 2 of 3 features across 2 files in docs/FEATURES.'",
      note = "the line says what is on screen",
    },
    { expect = "!/ftheme=/.test(location.hash)", note = "the default theme is not in the link" },
    { shot = "core-light" },
    { focus = '#feattoggle .anview-btn[data-ftheme="UI"]', note = "reached with the keyboard" },
    { press = "Enter" },
    {
      wait = "(g => g[0].hidden && !g[1].hidden)([...document.querySelectorAll('.feat-group')])",
      note = "Enter switches the theme",
    },
    {
      expect = "/ftheme=UI/.test(location.hash) && document.querySelector('.feat-count').textContent"
        .. " === 'UI: 1 of 3 features across 2 files in docs/FEATURES.'",
      note = "the link carries the theme, the line follows",
    },
    { expect = "(history.back(), true)", note = "Back" },
    {
      wait = "(g => !g[0].hidden && g[1].hidden)([...document.querySelectorAll('.feat-group')])",
      note = "a sub-tab is a navigation: Back returns to the first theme",
    },
    {
      expect = "(location.hash = '#tab=tree&id=' + encodeURIComponent('" .. STORE .. "'), true)",
      note = "the store module in the Tree tab",
    },
    { wait = trigger(STORE) .. " !== null", note = "its detail carries the feature trigger" },
    {
      expect = trigger(STORE) .. ".getAttribute('aria-label') === 'Described by 2 features'",
      note = "two features name this file",
    },
    {
      expect = "!document.querySelector('#detail .feati[data-feat=\""
        .. STORE
        .. "#M.drop\"]') && "
        .. trigger(STORE .. "#M.save")
        .. ".getAttribute('aria-label') === 'Described by 1 feature'",
      note = "a function no feature names has no trigger; M.save has one",
    },
    { focus = '#detail .feati[data-feat="' .. STORE .. '"]' },
    {
      expect = "new Promise(resolve => setTimeout(() => resolve(true), 400))",
      note = "let the scroll the focus caused pass: a scroll of the page closes the card",
    },
    { press = "Enter", note = "the keyboard opens the card" },
    {
      wait = POP
        .. ".classList.contains('on') && "
        .. POP
        .. ".querySelectorAll('.featref').length === 2",
      note = "the card lists both features",
    },
    {
      expect = "/The store/.test("
        .. POP
        .. ".textContent) && /The window title/.test("
        .. POP
        .. ".textContent) && /Loads and saves what the app remembers/.test("
        .. POP
        .. ".textContent)",
      note = "by name, with the summary",
    },
    { shot = "card-light" },
    { scheme = "dark" },
    { shot = "card-dark" },
    { scheme = "light" },
    { press = "Escape" },
    { expect = "!" .. POP .. ".classList.contains('on')", note = "Escape closes it" },
    { click = '#detail .feati[data-feat="' .. STORE .. '"]', note = "the pointer opens it too" },
    { wait = POP .. ".classList.contains('on')" },
    { click = '#sigpop a[data-feat-goto="docs/FEATURES/UI.md:5"]', note = "to the feature itself" },
    {
      wait = "document.getElementById('view-features').classList.contains('active')"
        .. " && (g => g[0].hidden && !g[1].hidden)([...document.querySelectorAll('.feat-group')])",
      note = "the Features tab opens on the theme of that feature",
    },
    {
      expect = "!"
        .. POP
        .. ".classList.contains('on') && /tab=features&ftheme=UI/.test(location.hash)"
        .. " && document.querySelector('.feat-card.feat-flash .feat-name').textContent === 'The window title'",
      note = "the card is closed, the link says where we are, and the feature is pointed out",
    },
    { shot = "arrived-light" },
  },
  judge = {
    "the sub-tab strip reads as part of the Features tab and the active theme is clear (core-light)",
    "the feature card is readable in the light and the dark theme and the feature names read as links (card-light, card-dark)",
    "after following a feature from the card, the highlighted feature is easy to find (arrived-light)",
  },
}
