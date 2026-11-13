-- TESTS/sheets/shape-diff.sheet.lua -- two maps compared on the Hierarchy tab, in a real window against a real
-- host.
-- A browser sheet. TESTS/sheets_spec.lua starts `:DocMap serve` on port 38417 over the maps-page artifacts while
-- this sheet runs; only git is stood in for, with two commits:
--   aaaaaaa (older): no app.util.orphan yet; an app.core.cache that app.core.store required; app.util.text
--                    required app.core.store; app.ui.window did not require app.core.store yet.
--   bbbbbbb (newer): this map without app.util.orphan.
-- So against the older commit this map has one node more and one less, one require gained and two lost.
-- The first steps open the same page as a file, where there is no host to ask.
-- Nodes on the Modules view, two commits and the way out are TESTS/sheets/shape-diff-nodes.sheet.lua.
local HOST = "http://127.0.0.1:38417/"
local BAR = "document.getElementById('hshape')"
local OLDER = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
local STORE = "lua/app/core/store.lua"

---The box of a node, as an expression.
---@param id string
---@return string
local function box(id)
  return "document.querySelector('.hnode[data-key=\"" .. id .. "\"]')"
end

---Choose `value` in a select of the bar, the way a reader's choice arrives: a `change` on the control.
---@param id string
---@param value string
---@return string
local function choose(id, value)
  return "(s => (s.value = '"
    .. value
    .. "', s.dispatchEvent(new Event('change', { bubbles: true })), s.value === '"
    .. value
    .. "'))(document.getElementById('"
    .. id
    .. "'))"
end

---The four counts of the bar, joined: "+1 node|−1 node|+1 require|−2 requires".
local COUNTS =
  "[...document.querySelectorAll('#hshape .sd-count')].map(e => e.textContent).join('|')"

return {
  id = "shape-diff",
  title = "Shape diff: two maps compared on the Hierarchy tab",
  task = "docmap.nvim/page-compare-two-artifacts",
  engine = "browser",
  steps = {
    -- A page that cannot fetch says so in place.
    { open = "TESTS/sheets/out/maps-page.html" },
    { expect = BAR .. ".hidden", note = "no bar until it is asked for" },
    { focus = "#hshapebtn" },
    { press = "Enter", note = "the keyboard opens it" },
    {
      wait = "!"
        .. BAR
        .. ".hidden && /This page was opened from a file/.test("
        .. BAR
        .. ".textContent)",
      note = "opened from a file, the bar says why there is nothing to compare with",
    },
    {
      expect = BAR .. ".querySelector('select') === null",
      note = "and offers no choice it could not honour",
    },
    { shot = "file-light" },

    -- The same page from a host.
    {
      open = HOST
        .. "#tab=hierarchy&view=deps&center="
        .. "lua%2Fapp%2Fcore%2Fstore.lua&dir=both&depth=2",
    },
    { wait = box(STORE) .. " !== null", note = "the Deps view around the store" },
    {
      expect = "(window.__pos = [...document.querySelectorAll('.hnode')].map(e => e.dataset.key + '@'"
        .. " + e.style.left + ',' + e.style.top).sort().join(' '), window.__pos.length > 0)",
      note = "where every box is, before anything is compared",
    },
    { click = "#hshapebtn", note = "the pointer opens the bar too" },
    {
      wait = "document.getElementById('hshape-a') !== null"
        .. " && document.getElementById('hshape-a').options.length === 3",
      note = "the older side is chosen from the commits the History tab lists",
    },
    {
      expect = "document.getElementById('hshape-b').options[0].textContent === 'this map'"
        .. " && document.getElementById('hshapebtn').getAttribute('aria-pressed') === 'false'",
      note = "the newer side is this map unless said otherwise; nothing is compared yet",
    },
    { focus = "#hshape-a", note = "the choice is reachable from the keyboard" },
    { expect = choose("hshape-a", OLDER), note = "the older commit" },
    {
      wait = COUNTS .. " === '+1 node|−1 node|+1 require|−2 requires'",
      note = "the host compared the two maps: one node more, one less, one require gained, two lost",
    },
    {
      expect = "/&cmp="
        .. OLDER
        .. "$/.test(location.hash)"
        .. " && document.getElementById('hshapebtn').getAttribute('aria-pressed') === 'true'",
      note = "the comparison is in the link and the button says it is on",
    },
    {
      expect = "[...document.querySelectorAll('.hnode')].map(e => e.dataset.key + '@'"
        .. " + e.style.left + ',' + e.style.top).sort().join(' ') === window.__pos",
      note = "no box moved and none was added or removed: the diagram is the one the reader was looking at",
    },
    {
      expect = "(e => e.length === 1 && e[0].dataset.from === 'lua/app/ui/window.lua' && e[0].dataset.to === '"
        .. STORE
        .. "')([...document.querySelectorAll('#hsvg .hedge.sd-add')])",
      note = "the gained require is marked on its own edge",
    },
    {
      expect = "(e => e.length === 1 && e[0].dataset.from === 'lua/app/util/text.lua' && e[0].dataset.to === '"
        .. STORE
        .. "' && getComputedStyle(e[0]).strokeDasharray !== 'none')"
        .. "([...document.querySelectorAll('#hsvg .hedge.sd-del')])",
      note = "the lost require between two boxes on screen is drawn dashed; the one to a removed node is not",
    },
    {
      expect = "document.querySelectorAll('.hnode.sd-same').length > 0 && !"
        .. box(STORE)
        .. ".classList.contains('sd-same') && parseFloat(getComputedStyle(document.querySelector('.hnode.sd-same')).opacity) < 1",
      note = "what did not change is dimmed, the ends of a changed require are not",
    },
    { shot = "deps-light" },
    { scheme = "dark" },
    { shot = "deps-dark" },
    { scheme = "light" },

    -- The list.
    { focus = "#hshape-list" },
    { press = "Enter", note = "the list of changes, from the keyboard" },
    {
      wait = "!document.getElementById('hshape-body').hidden"
        .. " && /Nodes removed/.test(document.getElementById('hshape-body').textContent)",
    },
    {
      expect = "(t => /app\\.core\\.cache/.test(t) && /app\\.util\\.orphan/.test(t) && /Requires lost\\s*2/.test(t)"
        .. " && /Structural diff against aaaaaaaa/.test(t))(document.getElementById('hshape-body').textContent)",
      note = "every change by name, and the same change as :DocMap diff prints it",
    },
    { shot = "list-light" },
  },
  judge = {
    "the file page explains in one sentence why nothing can be compared (file-light)",
    "gained and lost requires are told apart at a glance, and the unchanged boxes stay readable (deps-light, deps-dark)",
    "the list of changes reads as a list, with added and removed in the colours of the marks (list-light)",
  },
}
