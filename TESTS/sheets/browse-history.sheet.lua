-- TESTS/sheets/browse-history.sheet.lua -- `:DocBrowse history`: the commits of the repository in the map browser.
-- The list comes from `git log` in the background and is drawn when it lands.
return {
  id = "docmap.browse-history",
  title = ":DocBrowse history lists the commits of the repository",
  feature = "docmap.browse-history",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
    },
    { keys = ":DocBrowse history<CR>", note = "the browser opens on the History list" },
    { wait = "P.shows('second')", timeout = 15000, note = "the newest commit is listed" },
    { expect = "P.shows('first')", note = "and the one before" },
    { keys = "q", note = "the browser closes" },
  },
}
