-- TESTS/sheets/hierarchy-tint.sheet.lua -- the tint of the Modules view, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page (12 functions, 7 of
-- them documented; two FIX markers and one TODO in core/store.lua, one PERF in util/text.lua). The numbers below
-- are that fixture's: lua/app/core holds 5 functions with 1 documented (20%), lua/app/ui 3 of 3.
local function box(id)
  return ("document.querySelector('#hstage .hnode[data-key=\"%s\"]')"):format(id)
end

return {
  id = "hierarchy-tint",
  title = "Hierarchy: the tint switch of the Modules view",
  task = "docmap.nvim/map-health-tint",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { click = 'button[data-tab="hierarchy"]', note = "the Hierarchy tab" },
    { wait = box("lua/app/core") .. " !== null", note = "the Modules view is drawn" },
    {
      expect = "document.getElementById('htint').value === '' && !document.querySelector('.htv')"
        .. " && !document.querySelector('.lg-tint') && !/tint=/.test(location.hash)",
      note = "off by default: no value on a box, no tint legend, nothing in the link",
    },
    { focus = "#htint", note = "the switch is reached with the keyboard" },
    { press = "ArrowDown", note = "the next choice: documented" },
    {
      wait = "document.getElementById('htint').value === 'doc' && !!document.querySelector('.htv')",
    },
    {
      expect = box("lua/app/core")
        .. ".classList.contains('tint-3') && "
        .. box("lua/app/core")
        .. ".querySelector('.htv').textContent === '20%'",
      note = "1 of 5 documented is 20%: step 3, and the value is printed on the box",
    },
    {
      expect = "(b => !/tint-\\d/.test(b.className) && b.querySelector('.htv').textContent === '100%')("
        .. box("lua/app/ui")
        .. ")",
      note = "a fully documented subtree keeps the plain box and says 100%",
    },
    {
      expect = box("lua/app/core") .. ".title.indexOf('1 of 5 functions documented (20%)') !== -1",
      note = "the counts are in the tooltip",
    },
    {
      expect = "document.querySelectorAll('#hlegend .lg-tint .bx').length === 6"
        .. " && /under 20%/.test(document.getElementById('hlegend').textContent)"
        .. " && /nothing to measure/.test(document.getElementById('hlegend').textContent)",
      note = "the legend names the five steps and the box without a value",
    },
    { expect = "/tint=doc/.test(location.hash)", note = "the link carries the tint" },
    { blur = true, note = "the explanation card of the switch goes with its focus" },
    { shot = "doc-light" },
    { scheme = "dark" },
    {
      expect = "getComputedStyle("
        .. box("lua/app/core")
        .. ").backgroundImage.indexOf('240, 150, 40') !== -1",
      note = "the dark theme has its own tint colour",
    },
    { shot = "doc-dark" },
    { scheme = "light" },
    {
      expect = "(location.hash = '#tab=hierarchy&view=modules&tint=doc&hidden=' + encodeURIComponent('lua/app/core'), true)",
      note = "a link that also hides a box",
    },
    {
      wait = "(b => b && b.classList.contains('hidden') && b.classList.contains('tint-3'))("
        .. box("lua/app/core")
        .. ")",
      note = "hidden and tinted at once: neither takes the other's class",
    },
    {
      expect = "(window.__svg = null, URL.createObjectURL = function(b){ window.__svg = b; return 'blob:none'; }, true)",
      note = "catch the file the export button makes",
    },
    { click = "#hexport" },
    {
      wait = "window.__svg && window.__svg.text().then(t => t.indexOf('fill-opacity') !== -1"
        .. " && t.indexOf('>20%<') !== -1 && t.indexOf('Tint: documented') !== -1)",
      note = "the SVG keeps the tint, the values and the legend line",
    },
    {
      expect = "(location.hash = '#tab=hierarchy&view=modules&tint=fix', true)",
      note = "marker density: the FIX family",
    },
    {
      wait = "(b => b && b.classList.contains('tint-4') && b.querySelector('.htv').textContent === '2')("
        .. box("lua/app/core/store.lua")
        .. ")",
      note = "two FIX markers in 18 lines: the darkest step, the count on the box",
    },
    {
      expect = "(b => !/tint-\\d/.test(b.className) && b.querySelector('.htv').textContent === '0')("
        .. box("lua/app/util")
        .. ")",
      note = "the PERF marker in util is not a FIX marker",
    },
    {
      expect = "/FIX markers per 1,000 lines/.test(document.getElementById('hlegend').textContent)",
      note = "the legend says what is counted",
    },
    {
      expect = "(location.hash = '#tab=hierarchy&view=modules&tint=debt', true)",
      note = "TODO, HACK and PERF",
    },
    {
      wait = "(b => b && b.querySelector('.htv') && b.querySelector('.htv').textContent === '1' && /tint-\\d/.test(b.className))("
        .. box("lua/app/util")
        .. ")",
      note = "now util counts its PERF marker",
    },
    { shot = "debt-light" },
    { click = 'button[data-view="deps"]', note = "another view" },
    {
      wait = "document.getElementById('htintwrap').style.display === 'none' && !document.querySelector('.htv')",
      note = "the tint is the Modules view's: the switch and the values are gone",
    },
  },
  judge = {
    "the tinted boxes are readable in the light and the dark theme, and the value sits on each box (doc-light, doc-dark)",
    "the steps of the legend can be told apart without relying on the hue (doc-light)",
  },
}
