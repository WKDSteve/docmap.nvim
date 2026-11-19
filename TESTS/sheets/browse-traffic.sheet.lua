-- TESTS/sheets/browse-traffic.sheet.lua -- `:DocBrowse traffic`: github_stats.nvim's traffic digest of the repository.
-- The repository ("owner/repo") is derived from the git remote. Without github_stats.nvim (as here) the list says
-- that there is no data for it (the name itself is cut at 80 columns); without a remote it would say that no
-- repository was resolved.
return {
  id = "docmap.browse-traffic",
  title = ":DocBrowse traffic names the repository of the remote and its traffic",
  feature = "docmap.browse-traffic",
  steps = {
    { lua = 'dofile("TESTS/sheets/support/project.lua").make()', timeout = 30000 },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
    },
    { keys = ":DocBrowse traffic<CR>", note = "the browser opens on the Traffic list" },
    {
      wait = "P.shows('(no traffic data for')",
      timeout = 10000,
      note = "a repository was derived from the remote (else: no repository resolved)",
    },
    { keys = "q", note = "the browser closes" },
  },
}
