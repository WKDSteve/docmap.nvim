-- TESTS/sheets/impact.sheet.lua -- `:DocMap impact`: which functions a change touches and who calls them.
-- `git diff --unified=0 HEAD` gives the changed lines, `git show HEAD:docs/map/module_map.json` the committed map; the
-- touched functions and their callers land in the quickfix list.
return {
  id = "docmap.impact",
  title = ":DocMap impact lists the touched functions and their callers",
  feature = "docmap.impact",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
    },
    {
      lua = "P.commit_map()",
      timeout = 30000,
      note = "the project keeps its map in git",
    },
    {
      lua = [[P.edit(_G.root .. "/lua/app/util/text.lua",
        'return vim.split(s, " ")', 'return vim.split(s, " ", { trimempty = true })')]],
      note = "a function body is changed, not committed",
    },
    { keys = ":DocMap impact<CR>", note = "the change is weighed" },
    {
      wait = "P.said('function(s) touched')",
      timeout = 15000,
      note = "the summary counts the touched function",
    },
    {
      expect = "vim.iter(vim.fn.getqflist()):any(function(i) return (i.text or ''):find('words', 1, true) ~= nil end)",
      note = "the touched function is in the quickfix list",
    },
  },
}
