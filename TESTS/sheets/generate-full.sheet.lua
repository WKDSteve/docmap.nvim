-- TESTS/sheets/generate-full.sheet.lua -- `:DocMap full`: the map with the lua-language-server pass
-- (`lua-language-server --doc`), which adds the @class/@alias detail.
-- No `feature`: the language server is not installed on the CI runners, and a feature sheet that skips is red there.
-- Without it the sheet skips everywhere; where it is installed (`testing perf` on a workstation) it measures the
-- pass. The catalog marks `docmap.generate-full` with `perf = "skip:..."` for that reason.
return {
  id = "docmap.generate-full",
  title = ":DocMap full adds the lua-language-server pass to the map",
  requires = {
    {
      lua = "vim.fn.executable('lua-language-server') == 1",
      reason = "lua-language-server is not on PATH",
    },
  },
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap full<CR>", note = "the map is generated with the language server" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 120000,
      note = "the artifact is written",
    },
    {
      expect = "not P.said('lua-language-server not found')",
      note = "the language server ran",
    },
  },
}
