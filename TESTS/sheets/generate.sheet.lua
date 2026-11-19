-- TESTS/sheets/generate.sheet.lua -- `:DocMap` writes the map of the project the user is in.
-- The scan asks git for the remote and the branch (the "view on GitHub" links of the page); the sheet checks that
-- the artifacts land in docs/map and that the page links to the remote of the repository.
return {
  id = "docmap.generate",
  title = ":DocMap writes the module map of the project",
  feature = "docmap.generate",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
      note = "the artifact is written",
    },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/index.html') == 1",
      timeout = 30000,
      note = "and the page",
    },
    {
      expect = "io.open(_G.root .. '/docs/map/index.html'):read('*a'):find('github.com/example/app', 1, true) ~= nil",
      note = "the page links to the remote git named",
    },
  },
}
