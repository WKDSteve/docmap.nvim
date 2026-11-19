-- TESTS/sheets/open.sheet.lua -- `:DocMap open`: the generated page opens in the system's browser.
-- The opener is a stand-in (`fakes`), reached on every system through lib.nvim's Linux way (support/project.lua,
-- `pretend_linux`); the sheet checks what would be opened. Opening through a running server: serve.sheet.lua.
return {
  id = "docmap.open",
  title = ":DocMap open hands the generated page to the system's opener",
  feature = "docmap.open",
  fakes = { "xdg-open" },
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/index.html') == 1",
      timeout = 30000,
    },
    { lua = "P.pretend_linux()" },
    { keys = ":DocMap open<CR>", note = "the page is opened" },
    { wait = "#P.opened() == 1", timeout = 10000, note = "the opener was called once" },
    { lua = "P.real_platform()" },
    {
      expect = "vim.fs.normalize(P.opened()[1]):find('docs/map/index.html', 1, true) ~= nil",
      note = "with the page of the project",
    },
  },
  manual = { "once with the real opener: the page opens in the browser" },
}
