-- TESTS/sheets/serve.sheet.lua -- `:DocMap serve`: the page over a local server, whose API answers from git.
-- The History tab asks `/api/commits`; the server runs `git log` for it. `:DocMap open` then opens the server's URL
-- (the opener is a stand-in, as in open.sheet.lua), and `:DocMap serve stop` closes it.
return {
  id = "docmap.serve",
  title = ":DocMap serve answers the page's history from git and opens through the server",
  feature = "docmap.serve",
  fakes = { "xdg-open" },
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/index.html') == 1",
      timeout = 30000,
    },
    { keys = ":DocMap serve<CR>", note = "the server starts" },
    { wait = "P.said('Map server listening at')", timeout = 10000 },
    { lua = "P.get('/api/commits?n=5')", note = "the page asks for the history" },
    { wait = "_G.answer ~= nil", timeout = 15000, note = "the server answers" },
    {
      expect = "(_G.answer:match('^HTTP/1%.%d 200') ~= nil and _G.answer:find('second', 1, true) ~= nil) or error(_G.answer:sub(1, 600))",
      note = "with the commits of the repository",
    },
    {
      lua = "P.get('/api/traffic')",
      note = "the Endpoints panel asks for the recorded request traffic",
    },
    { wait = "_G.answer ~= nil", timeout = 15000, note = "the server answers" },
    {
      expect = "(_G.answer:match('^HTTP/1%.%d 200') ~= nil and _G.answer:find('\"available\"', 1, true) ~= nil) or error(_G.answer:sub(1, 600))",
      note = "with a verdict, also when nothing was recorded for the project",
    },
    { lua = "P.pretend_linux()" },
    { keys = ":DocMap open<CR>", note = "the page is opened while the server runs" },
    { wait = "#P.opened() == 1", timeout = 10000 },
    { lua = "P.real_platform()" },
    { expect = "P.opened()[1]:match('^http://') ~= nil", note = "the server's URL, not the file" },
    { keys = ":DocMap serve stop<CR>" },
    { wait = "P.said('Map server stopped')", note = "the server is closed" },
  },
  manual = { "once in a real browser: the History tab lists the commits" },
}
