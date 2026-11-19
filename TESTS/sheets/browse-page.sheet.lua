-- TESTS/sheets/browse-page.sheet.lua -- `gO` in the map browser: the same place on the generated page, in the browser.
-- The link carries the module and the view in its fragment; the opener is a stand-in (see open.sheet.lua).
return {
  id = "docmap.browse-page",
  title = "gO in :DocBrowse opens the generated page at the module under the cursor",
  feature = "docmap.browse-page",
  fakes = { "xdg-open" },
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/index.html') == 1",
      timeout = 30000,
    },
    { keys = ":DocBrowse<CR>", note = "the browser opens" },
    { wait = "P.shows('app')", timeout = 10000 },
    { lua = "P.pretend_linux()" },
    { keys = "gO", note = "the page is asked for" },
    { wait = "#P.opened() == 1", timeout = 10000, note = "the opener was called once" },
    { lua = "P.real_platform()" },
    {
      expect = "P.opened()[1]:find('index.html', 1, true) ~= nil and P.opened()[1]:find('hierarchy', 1, true) ~= nil",
      note = "with the page and the place in its fragment",
    },
    { keys = "q" },
  },
  manual = { "once with the real opener: the page opens at the module" },
}
