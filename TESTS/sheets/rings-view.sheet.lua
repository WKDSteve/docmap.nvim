-- TESTS/sheets/rings-view.sheet.lua -- the Rings view of the Hierarchy, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page: `app` requires
-- `app.core` and `app.ui`, those reach three more modules, and `app.util.orphan` is required by nothing. The sheet
-- checks what a spec cannot: that the rings are drawn in the zooming diagram, that pointing at a box shows its
-- chain, that the entry can be chosen and that the unreachable ring leads to the finding.
local BOX = "document.querySelector('#hstage .hnode[data-key=\"%s\"]')"
local function box(id)
  return BOX:format(id)
end
local LABELS = "[...document.querySelectorAll('#hsvg .hring-label')].map(e => e.textContent)"
local SHOWN_EDGES = "[...document.querySelectorAll('#hsvg .hedge-quiet')]"
  .. ".filter(p => getComputedStyle(p).opacity !== '0').map(p => p.dataset.from + '>' + p.dataset.to).sort().join(' ')"

return {
  id = "rings-view",
  title = "Hierarchy: the Rings view (distance from the entry module)",
  task = "docmap.nvim/map-entry-distance-rings",
  engine = "browser",
  sizes = { { cols = 1500, rows = 900 } },
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { click = 'button[data-tab="hierarchy"]', note = "the Hierarchy tab" },
    {
      focus = 'button.hview-btn[data-view="rings"]',
      note = "the view is reached with the keyboard",
    },
    { press = "Enter" },
    {
      wait = "document.querySelectorAll('#hsvg .hring').length === 3",
      note = "the rings are drawn",
    },
    {
      expect = "/view=rings/.test(location.hash) && document.getElementById('halt').hidden"
        .. " && document.getElementById('hgraph-wrap').style.display !== 'none'"
        .. " && document.getElementById('hexport').style.display !== 'none'"
        .. " && document.getElementById('hzoomreset').style.display !== 'none'",
      note = "the link carries the view; it is the zooming diagram, with zoom and export",
    },
    {
      expect = "JSON.stringify("
        .. LABELS
        .. ") === JSON.stringify(['1 require away · 2 modules', '2 requires away · 3 modules',"
        .. " 'not reachable from app · 1 module · 1 unreferenced-module'])",
      note = "a ring per distance, and one for what the entry does not reach",
    },
    {
      expect = box("lua/app")
        .. ".classList.contains('center') && /entry/.test("
        .. box("lua/app")
        .. ".textContent) && "
        .. box("lua/app/core/store.lua")
        .. ".dataset.ring === '2'",
      note = "the entry is the middle; a box knows its ring",
    },
    {
      expect = "(b => b.classList.contains('ring-out') && b.classList.contains('ring-unref')"
        .. " && /unreferenced-module/.test(b.textContent) && /nothing in this map requires it/.test(b.title))("
        .. box("lua/app/util/orphan.lua")
        .. ")",
      note = "the unreachable module carries the finding, in words on the box and in its tooltip",
    },
    {
      expect = "/app reaches 6 of 7 modules, the farthest 2 requires away\\. 1 module is not reachable from it and"
        .. " carries the unreferenced-module finding: nothing requires it\\./.test(document.querySelector('.hring-note').textContent)",
      note = "the note says how deep and how much is reachable",
    },
    { expect = SHOWN_EDGES .. " === ''", note = "no arrow is drawn until a box is pointed at" },
    { shot = "rings-light" },
    { hover = '#hstage .hnode[data-key="lua/app/core/store.lua"]' },
    {
      wait = SHOWN_EDGES .. " === 'lua/app/core>lua/app/core/store.lua lua/app>lua/app/core'",
      note = "pointing at a box shows its chain back to the entry",
    },
    {
      expect = "[...document.querySelectorAll('#hstage .hnode.near')].map(b => b.dataset.key).sort().join(' ')"
        .. " === 'lua/app lua/app/core lua/app/core/store.lua'"
        .. " && getComputedStyle(document.querySelector('#hstage .hnode[data-key=\"lua/app/ui\"]')).opacity < 1",
      note = "the boxes of the chain stay lit, every other one is dimmed",
    },
    { shot = "chain-light" },
    { scheme = "dark" },
    {
      wait = "new Promise(done => setTimeout(() => done(true), 450))",
      note = "the colours of the other theme have faded in",
    },
    { shot = "chain-dark" },
    { scheme = "light" },
    { press = "=", note = "the zoom keys work as in the other diagram views" },
    { wait = "document.getElementById('hzoomlabel').textContent === '120%'" },
    { press = "0" },
    { wait = "document.getElementById('hzoomlabel').textContent === '100%'" },
    {
      focus = "#hentry",
      note = "the entry select is a control of its own, reachable with the keyboard",
    },
    {
      expect = "(s => s === document.activeElement && s.value === 'lua/app' && /reaches 6 of 7/.test(s.options[0].text)"
        .. " && getComputedStyle(document.getElementById('hentrywrap')).display !== 'none')"
        .. "(document.getElementById('hentry'))",
      note = "it names the entry and how much it reaches",
    },
    { shot = "entry-focus" },
    {
      expect = "(location.hash = '#tab=hierarchy&view=rings&center=' + encodeURIComponent('lua/app/ui'), true)",
      note = "a link with another center: that module is the entry",
    },
    {
      wait = "/^app\\.ui · rings$/.test(document.getElementById('hpath').textContent) && "
        .. box("lua/app/ui")
        .. ".classList.contains('center') && "
        .. LABELS
        .. ".slice(-1)[0] === 'not reachable from app.ui · 3 modules · 1 unreferenced-module'",
      note = "the rings are counted from it, and what it does not reach moves to the last ring",
    },
    {
      expect = "(s => s.value === 'lua/app/ui' && s.options.length === 2 && (s.value = 'lua/app',"
        .. " s.dispatchEvent(new Event('change')), true))(document.getElementById('hentry'))",
      note = "the select offers the way back to the root of the require graph",
    },
    {
      wait = "/^app · rings$/.test(document.getElementById('hpath').textContent)"
        .. " && /center=lua%2Fapp(&|$)/.test(location.hash)",
      note = "choosing an entry is a navigation",
    },
    {
      expect = "(window.__svg = null, URL.createObjectURL = function(b){ window.__svg = b; return 'blob:none'; }, true)",
      note = "catch the file the export button makes",
    },
    { click = "#hexport" },
    {
      wait = "window.__svg && window.__svg.text().then(t => (t.match(/<ellipse /g) || []).length === 3"
        .. " && t.indexOf('not reachable from app · 1 module · 1 unreferenced-module') !== -1"
        .. " && t.indexOf('stroke-dasharray=\"3 3\"') !== -1 && (t.match(/<path /g) || []).length === 6"
        .. " && (t.match(/<rect x=/g) || []).length === 7)",
      note = "the SVG file carries the rings, their names and the seven boxes, the unreachable one dashed, and no"
        .. " arrow the screen does not show",
    },
    { click = "#hring-findings", note = "the note leads to the findings" },
    { wait = "document.getElementById('view-findings').classList.contains('active')" },
    { expect = "(history.back(), true)", note = "Back" },
    {
      wait = "document.querySelectorAll('#hsvg .hring').length === 3 && /view=rings/.test(location.hash)",
      note = "Back returns to the rings",
    },
  },
  judge = {
    "the rings read as rings: three ellipses with their names, the entry in the middle, no box over another (rings-light)",
    "the unreachable module can be told from the others without colour: dashed ring, its own line of text (rings-light)",
    "the chain of the pointed-at box is visible in the light and the dark theme (chain-light, chain-dark)",
    "the focused entry select has a visible focus ring (entry-focus)",
  },
}
