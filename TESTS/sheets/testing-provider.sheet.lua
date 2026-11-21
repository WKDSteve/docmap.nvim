-- TESTS/sheets/testing-provider.sheet.lua -- the affected-spec provider a test runner asks (testing.nvim's
-- affected selection): which specs does a change since a revision touch? The changed files come from git
-- (`docmap.testing.git`: `git diff --name-only <rev>` and one `git status --porcelain=v2`).
return {
  id = "docmap.testing-provider",
  title = "The affected-spec provider names the specs a change since a revision touches",
  feature = "docmap.testing-provider",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
    },
    { lua = "P.commit_map()", timeout = 30000, note = "the project keeps its map in git" },
    {
      lua = [[_G.affected, _G.err = require("docmap").testing.affected_specs({
        root = _G.root,
        since = "HEAD~2",
        tests_dir = "checks",
      })]],
      timeout = 30000,
      note = "the runner asks what changed since two commits ago",
    },
    {
      expect = "_G.affected ~= nil or error(tostring(_G.err))",
      note = "the provider answers",
    },
    {
      expect = "vim.iter(_G.affected.modules):any(function(m)"
        .. " return m.module == 'app.core.store' and m.role == 'changed' end)",
      note = "the changed store is named, and the modules that load it",
    },
    {
      expect = "vim.iter(_G.affected.graph.gaps):any(function(g) return g.module == 'app.core.store' end)",
      note = "no spec covers it: said as a gap, never as unaffected",
    },
  },
}
