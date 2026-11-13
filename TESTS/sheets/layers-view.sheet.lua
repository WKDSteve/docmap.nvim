-- TESTS/sheets/layers-view.sheet.lua -- the Layers view of the Hierarchy, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/maps_page, whose .docmap.json
-- declares two rules (`app.core` may not reach `app.ui`, `app.util` may not reach `app.core`) and whose
-- `app.core.store` breaks the first. The sheet checks what a spec cannot: that the bands are drawn in the zooming
-- diagram in the right order, that the broken require is a visible arrow over the boxes, that pointing at a box
-- shows its other requires, and what a page without rules says.
local BOX = "document.querySelector('#hstage .hnode[data-key=\"%s\"]')"
local function box(id)
  return BOX:format(id)
end
local function top(id)
  return "parseFloat(" .. box(id) .. ".style.top)"
end
local QUIET = "[...document.querySelectorAll('#hsvg .hedge-quiet')]"
  .. ".filter(p => p.classList.contains('near') && document.getElementById('hgraph').classList.contains('focusing'))"
  .. ".map(p => p.dataset.from + '>' + p.dataset.to).sort().join(' ')"

return {
  id = "layers-view",
  title = "Hierarchy: the Layers view (the bands of the layering rules)",
  task = "docmap.nvim/map-layer-view",
  engine = "browser",
  sizes = { { cols = 1300, rows = 900 } },
  steps = {
    { open = "TESTS/sheets/out/maps-page.html" },
    { click = 'button[data-tab="hierarchy"]', note = "the Hierarchy tab" },
    {
      focus = 'button.hview-btn[data-view="layers"]',
      note = "the view is reached with the keyboard",
    },
    { press = "Enter" },
    {
      wait = "document.querySelectorAll('#hsvg .hunit').length === 3",
      note = "a frame per layer is drawn",
    },
    {
      expect = "(w => w.scrollLeft === 0 && w.scrollTop === 0)(document.getElementById('hgraph-wrap'))",
      note = "the view opens at its top left corner",
    },
    {
      expect = "/view=layers/.test(location.hash) && document.getElementById('halt').hidden"
        .. " && document.getElementById('hexport').style.display !== 'none'"
        .. " && document.getElementById('hlr').style.display === 'none'"
        .. " && document.getElementById('hentrywrap').style.display === 'none'"
        .. " && document.getElementById('hpath').textContent === '2 rules · layers'",
      note = "the link carries the view; it is the zooming diagram, without the controls of other views",
    },
    {
      expect = "(t => /band 3 of 3/.test(t) && /band 1 of 3 · the base/.test(t) && /named by no rule · 1 module/.test(t)"
        .. " && /app\\.ui · 2 modules/.test(t) && /app\\.core · 2 modules/.test(t) && /app\\.util · 2 modules/.test(t))"
        .. "([...document.querySelectorAll('#hsvg .hmap-label')].map(e => e.textContent).join(' | '))",
      note = "three bands and what no rule names, every layer with its name",
    },
    {
      expect = top("lua/app/ui/window.lua")
        .. " < "
        .. top("lua/app/core/store.lua")
        .. " && "
        .. top("lua/app/core/store.lua")
        .. " < "
        .. top("lua/app/util/text.lua")
        .. " && "
        .. top("lua/app/util/text.lua")
        .. " < "
        .. top("lua/app"),
      note = "what may not be reached is above: ui over core over util, the unnamed root at the bottom",
    },
    {
      expect = "(e => e.length === 1 && e[0].dataset.from === 'lua/app/core/store.lua'"
        .. " && e[0].dataset.to === 'lua/app/ui/window.lua' && getComputedStyle(e[0]).opacity > 0.9"
        .. " && /must not reach into app\\.ui \\(the core knows no window\\)/.test(e[0].textContent))"
        .. "([...document.querySelectorAll('#hsvg2 .hedge-viol')])",
      note = "the one require that breaks a rule is an arrow over the boxes, and says which rule",
    },
    {
      expect = "(b => b.classList.contains('lv-from') && /breaks a rule · 1 require/.test(b.textContent)"
        .. " && b.querySelector('.hnm').textContent === 'store' && /app\\.core\\.store requires app\\.ui\\.window/.test(b.title))("
        .. box("lua/app/core/store.lua")
        .. ")",
      note = "the requiring module says so in words; its name drops the prefix its frame states",
    },
    {
      expect = "/2 rules put 6 modules into 3 layers on 3 bands\\. 1 module is named by no rule\\. 1 require breaks a rule/"
        .. ".test(document.querySelector('.hmap-note').textContent)",
      note = "the note counts rules, layers, bands and broken requires",
    },
    { expect = QUIET .. " === ''", note = "no other require is drawn until a box is pointed at" },
    { press = "Escape", note = "close the explanation the keyboard focus opened" },
    {
      wait = "!document.getElementById('hsvg').classList.contains('settling')"
        .. " && !document.getElementById('hsvg2').classList.contains('settling')"
        .. " && [...document.querySelectorAll('#hstage .hnode')].every(b => getComputedStyle(b).left === b.style.left"
        .. " && getComputedStyle(b).opacity === '1')",
      note = "the boxes have arrived and the edges are shown, the arrow over the boxes with the others",
    },
    { shot = "layers-light" },
    { hover = '#hstage .hnode[data-key="lua/app/core/store.lua"]' },
    {
      wait = QUIET
        .. " === 'lua/app/core/store.lua>lua/app/util/text.lua lua/app/core>lua/app/core/store.lua"
        .. " lua/app/ui/window.lua>lua/app/core/store.lua'",
      note = "pointing at a box shows its other requires, both ways",
    },
    {
      wait = "[...document.querySelectorAll('#hsvg .hedge-quiet.near')].every(p => getComputedStyle(p).opacity === '1')",
      note = "they have faded in",
    },
    { shot = "focus-light" },
    { scheme = "dark" },
    {
      wait = "new Promise(done => setTimeout(() => done(true), 450))",
      note = "the colours of the other theme have faded in",
    },
    { shot = "focus-dark" },
    { scheme = "light" },
    {
      expect = "(window.__svg = null, URL.createObjectURL = function(b){ window.__svg = b; return 'blob:none'; }, true)",
      note = "catch the file the export button makes",
    },
    { click = "#hexport" },
    {
      wait = "window.__svg && window.__svg.text().then(t => (t.match(/<rect x=/g) || []).length === 14"
        .. " && (t.match(/<path /g) || []).length === 7 && t.indexOf('app.core · 2 modules') !== -1"
        .. " && t.indexOf('band 1 of 3') !== -1 && t.lastIndexOf('<path ') > t.lastIndexOf('<rect x=')"
        .. " && t.indexOf('color(') === -1 && t.indexOf('fill-opacity=\"0.05\"') !== -1)",
      note = "the SVG file carries bands, frames, names, the seven boxes and the broken require, drawn last; its"
        .. " colours are plain ones every SVG reader knows",
    },
    { click = '#hstage .hnode[data-key="lua/app/ui/window.lua"]', note = "a click pins a box" },
    {
      expect = box("lua/app/ui/window.lua")
        .. ".classList.contains('pinned') && /view=layers/.test(location.hash)",
    },
    {
      click = '#hstage .hnode[data-key="lua/app/ui/window.lua"]',
      note = "a second click opens it",
    },
    {
      wait = "document.getElementById('view-tree').classList.contains('active')"
        .. " && location.hash.indexOf('id=' + encodeURIComponent('lua/app/ui/window.lua')) !== -1",
      note = "in the Tree tab: the view has no center to move",
    },
    { expect = "(history.back(), true)", note = "Back" },
    {
      wait = "document.querySelectorAll('#hsvg .hunit').length === 3 && /view=layers/.test(location.hash)",
      note = "Back returns to the layers",
    },
    { click = "#hmap-findings", note = "the note leads to the findings" },
    { wait = "document.getElementById('view-findings').classList.contains('active')" },
    { open = "TESTS/sheets/out/keyword-page.html", note = "a page of a tree without rules" },
    { expect = "(location.hash = '#tab=hierarchy&view=layers', true)" },
    {
      wait = "/No layers are declared for this map\\./.test((document.querySelector('#hgraph .hmsg') || {}).textContent || '')"
        .. " && document.querySelectorAll('#hstage .hnode').length === 0",
      note = "it says that no layers are declared, and how to declare one",
    },
    { shot = "no-rules" },
  },
  judge = {
    "the bands read as bands: three stripes above each other, a frame per layer, the dashed stripe below (layers-light)",
    "the broken require is the one arrow on the plain view and cannot be missed; it does not hide a module name (layers-light)",
    "the other requires of the pointed-at box are visible in the light and the dark theme (focus-light, focus-dark)",
    "the message of a page without rules is readable and names the setting (no-rules)",
  },
}
