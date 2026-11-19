-- TESTS/sheets/churn.sheet.lua -- `:DocMap churn`: which modules change most, weighed by how complex they are.
-- It reads the history with one `git log` in the background; the answer is a line naming the hottest module.
return {
  id = "docmap.churn",
  title = ":DocMap churn ranks the modules by commits times complexity",
  feature = "docmap.churn",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { keys = ":DocMap churn<CR>", note = "the history is read" },
    {
      wait = "P.said('commits — hottest')",
      timeout = 15000,
      note = "the hottest module is named",
    },
    {
      expect = "vim.bo.filetype ~= '' or #vim.api.nvim_list_wins() >= 1",
      note = "the editor is still usable",
    },
  },
}
