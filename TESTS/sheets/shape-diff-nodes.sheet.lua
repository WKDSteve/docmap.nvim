-- TESTS/sheets/shape-diff-nodes.sheet.lua -- the shape diff on the Modules view: nodes added and removed, two
-- commits against each other, the way out and back, and a commit without a map.
-- The second half of TESTS/sheets/shape-diff.sheet.lua, against the same host (TESTS/shape_host.lua, started by
-- TESTS/sheets_spec.lua on port 38417; see that file for the two commits). It starts from a link that carries
-- the comparison, the way a shared one arrives.
local HOST = "http://127.0.0.1:38417/"
local BAR = "document.getElementById('hshape')"
local OLDER = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
local NEWER = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

---The box of a node, as an expression.
---@param id string
---@return string
local function box(id)
  return "document.querySelector('.hnode[data-key=\"" .. id .. "\"]')"
end

---The four counts of the bar, joined: "+1 node|−1 node|+1 require|−2 requires".
local COUNTS =
  "[...document.querySelectorAll('#hshape .sd-count')].map(e => e.textContent).join('|')"

return {
  id = "shape-diff-nodes",
  title = "Shape diff: nodes on the Modules view, two commits, and the way out",
  task = "docmap.nvim/page-compare-two-artifacts",
  engine = "browser",
  steps = {
    { open = HOST .. "#tab=hierarchy&view=modules&cmp=" .. OLDER },
    {
      wait = COUNTS .. " === '+1 node|−1 node|+1 require|−2 requires'",
      note = "a link that carries a comparison opens with it: the bar is there and the host has answered",
    },
    {
      expect = "document.getElementById('hshape-a').value === '" .. OLDER .. "'",
      note = "and the choice shows which commit it is",
    },
    {
      wait = box("lua/app/util/orphan.lua")
        .. " !== null && "
        .. box("lua/app/util/orphan.lua")
        .. ".classList.contains('sd-added')",
      note = "the added node is framed",
    },
    {
      expect = "document.querySelectorAll('.hnode.sd-added').length === 1",
      note = "and it is the only one",
    },
    {
      expect = "(b => b.classList.contains('sd-lost') && b.querySelector('.sd-badge').textContent === '−1'"
        .. " && /app\\.core\\.cache/.test(b.querySelector('.sd-badge').title))("
        .. box("lua/app/core")
        .. ")",
      note = "the place a node was removed from carries the count and the name",
    },
    {
      expect = "document.querySelectorAll('#hsvg .sd-del, #hsvg .sd-add').length === 0",
      note = "the Modules view draws no requires, so none is marked or drawn in",
    },
    { shot = "modules-light" },

    -- Two commits.
    {
      expect = "(s => (s.value = '"
        .. NEWER
        .. "', s.dispatchEvent(new Event('change', { bubbles: true })), true))"
        .. "(document.getElementById('hshape-b'))",
      note = "the newer side: a second commit",
    },
    {
      wait = "/cmp="
        .. OLDER
        .. "\\.\\."
        .. NEWER
        .. "/.test(location.hash) && "
        .. COUNTS
        .. " === '+0 nodes|−1 node|+1 require|−2 requires'",
      note = "between the two commits the orphan was not added yet",
    },
    {
      expect = "/Marked on the map this page shows/.test("
        .. BAR
        .. ".textContent) && document.querySelectorAll('.hnode.sd-added').length === 0",
      note = "the bar says which map the marks are on",
    },

    -- Out, and back.
    { focus = "#hshape-end" },
    { press = "Enter", note = "End comparison, from the keyboard" },
    {
      wait = "!/cmp=/.test(location.hash) && " .. BAR .. ".hidden",
      note = "the link and the bar are as before",
    },
    {
      expect = "document.querySelectorAll('.sd-added, .sd-lost, .sd-same, .sd-badge, .sd-del').length === 0"
        .. " && document.activeElement === document.getElementById('hshapebtn')",
      note = "every mark is gone, and the focus is back on the button that started it",
    },
    { expect = "(history.back(), true)", note = "Back" },
    {
      wait = "/cmp="
        .. OLDER
        .. "\\.\\."
        .. NEWER
        .. "/.test(location.hash) && !"
        .. BAR
        .. ".hidden && "
        .. box("lua/app/core")
        .. ".classList.contains('sd-lost')",
      note = "a comparison is a navigation: Back returns to it, marks included",
    },

    -- A commit that has no map.
    {
      expect = "(location.hash = '#tab=hierarchy&view=modules&cmp=ccccccc', true)",
      note = "a link to a commit without a map",
    },
    {
      wait = "/no map is committed at ccccccc/.test(" .. BAR .. ".textContent)",
      note = "says so in the bar",
    },
    {
      expect = "document.querySelectorAll('.sd-added, .sd-lost, .sd-same').length === 0",
      note = "and marks nothing",
    },
  },
  judge = {
    "the added node and the place a node was removed from are easy to find (modules-light)",
  },
}
