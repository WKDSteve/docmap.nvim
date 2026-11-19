-- TESTS/sheets/checklist.sheet.lua -- `:DocMap checklist`: hand-verified facts whose cited file changed since.
-- The project's ledger has one item verified in 2020 on a file committed since (stale) and one never verified; the
-- history is one `git log` in the background, the answer a quickfix list of both.
return {
  id = "docmap.checklist",
  title = ":DocMap checklist lists the stale and the unverified items",
  feature = "docmap.checklist",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { keys = ":DocMap checklist<CR>", note = "the ledger is checked against the history" },
    {
      wait = "P.said('1 stale, 1 unverified')",
      timeout = 15000,
      note = "the summary counts both",
    },
    {
      expect = "#vim.fn.getqflist() == 2",
      note = "both items are in the quickfix list",
    },
  },
}
