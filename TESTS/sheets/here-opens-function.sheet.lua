-- TESTS/sheets/here-opens-function.sheet.lua -- the link `:DocMap here` builds opens the tree at one function.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/lookup_page: its module
-- `lua/look` holds `M.start`. The fragment is `find.fragment` of a function hit: the node in `id`, the function
-- key (`<node>#<name>`) in `fn`.
local KEY = "lua/look#M.start"

return {
  id = "here-opens-function",
  title = ":DocMap here: the tree opens at the function, not only at its module",
  task = "docmap.nvim/docmap-zu-cursor-oder-markierung-datei-und-zeile-zum-funktion",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/lookup-page.html" },
    { wait = "document.querySelector('#tree .row') !== null", note = "the page is up" },
    {
      expect = "(location.hash = '#tab=tree&id=lua%2Flook&fn=lua%2Flook%23M.start', true)",
      note = "the link a function hit builds",
    },
    {
      wait = "document.querySelector('#detail .fn.focus[data-fn=\"" .. KEY .. "\"]') !== null",
      note = "the detail pane marks that function's block",
    },
    {
      expect = "document.querySelector('#tree .row.k-fn.sel[data-fn=\""
        .. KEY
        .. "\"]') !== null && !document.querySelector('#tree .row.k-fn.sel[data-fn=\""
        .. KEY
        .. "\"]').parentNode.classList.contains('hide')",
      note = "the tree row of the function is selected and its group is open",
    },
    {
      expect = "(location.hash = '#tab=tree&id=lua%2Flook', true)",
      note = "the same module without a function",
    },
    {
      wait = "document.querySelector('#detail .fn.focus') === null && document.querySelector('#detail h2') !== null",
      note = "no function is marked: the module is shown as before",
    },
    { shot = "function-focused" },
  },
}
