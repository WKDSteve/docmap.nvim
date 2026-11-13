-- TESTS/sheets/coupling-view.sheet.lua -- the Coupling view of the Hierarchy, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page: a small tree whose
-- modules require each other a little, so every dot is a leaf. The sheet checks what a spec cannot: that the
-- plot is drawn, that the keyboard walks it and that a dot leads to its module.
local DOTS = "[...document.querySelectorAll('#halt-body .cq-dot')]"
local READ = "document.getElementById('cq-read').textContent"

return {
  id = "coupling-view",
  title = "Hierarchy: the Coupling view (fan-in against fan-out)",
  task = "docmap.nvim/map-coupling-quadrant",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { click = 'button[data-tab="hierarchy"]', note = "the Hierarchy tab" },
    {
      focus = 'button.hview-btn[data-view="coupling"]',
      note = "the view is reached with the keyboard",
    },
    { press = "Enter" },
    { wait = DOTS .. ".length > 0", note = "the plot is drawn" },
    {
      expect = "/view=coupling/.test(location.hash) && !document.getElementById('halt').hidden"
        .. " && document.getElementById('hgraph-wrap').style.display === 'none'",
      note = "the link carries the view; the plot replaces the diagram",
    },
    {
      expect = "(t => /Hubs 0/.test(t) && /Tangles 0/.test(t) && /Pass-throughs 0/.test(t) && /Leaves \\d+/.test(t))"
        .. "(document.querySelector('#halt-body svg.cq').textContent)",
      note = "the four corners are named and counted",
    },
    {
      expect = "/the lines are at 5/.test(document.getElementById('halt-bar').textContent)"
        .. " && document.querySelectorAll('#halt-body .cq-split').length === 2",
      note = "the threshold is said in the bar and drawn as two lines",
    },
    {
      expect = DOTS .. ".filter(d => d.getAttribute('tabindex') === '0').length === 1",
      note = "the plot is one tab stop",
    },
    { focus = "#halt-body .cq-dot[tabindex='0']" },
    {
      wait = "/required by \\d+ · requires \\d+ · leaf$/.test(" .. READ .. ")",
      note = "the focused dot is read out: module, both numbers, corner",
    },
    { shot = "focus-light" },
    { press = "ArrowRight" },
    {
      expect = "document.activeElement === "
        .. DOTS
        .. "[1] && "
        .. READ
        .. " === document.activeElement.getAttribute('aria-label')",
      note = "the arrow moves to the next module and the readout follows",
    },
    { press = "Home" },
    { expect = "document.activeElement === " .. DOTS .. "[0]", note = "Home goes to the first" },
    { scheme = "dark" },
    { shot = "focus-dark" },
    { scheme = "light" },
    {
      expect = "(window.__cq = document.activeElement.dataset.id, !!window.__cq)",
      note = "remember which module has the focus",
    },
    { press = "Enter" },
    {
      wait = "document.getElementById('view-tree').classList.contains('active')"
        .. " && location.hash.indexOf('id=' + encodeURIComponent(window.__cq)) !== -1",
      note = "Enter opens that module in the Tree tab",
    },
    { expect = "(history.back(), true)", note = "Back" },
    {
      wait = DOTS .. ".length > 0 && /view=coupling/.test(location.hash)",
      note = "Back returns to the plot",
    },
    { click = "#halt-body .cq-dot[data-i='1']", note = "the pointer opens a module too" },
    { wait = "document.getElementById('view-tree').classList.contains('active')" },
  },
  judge = {
    "the plot reads as a chart: axes, ticks, the two dashed lines and the four corner names are legible (focus-light)",
    "the focused dot can be told from the others in the light and the dark theme (focus-light, focus-dark)",
  },
}
