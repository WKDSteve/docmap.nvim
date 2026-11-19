-- TESTS/sheets/diff.sheet.lua -- `:DocMap diff <ref>`: what changed about the shape of the tree since a revision.
-- The revision is completed from the branches of the repository (`git for-each-ref`, cached a few seconds), and the
-- old map is read with `git show <ref>:docs/map/module_map.json`.
return {
  id = "docmap.diff",
  title = ":DocMap diff compares the tree with the map committed at a revision",
  feature = "docmap.diff",
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
    { input = ":DocMap diff m<Tab>", note = "the revision is completed" },
    {
      wait = "vim.fn.getcmdline() == 'DocMap diff main'",
      timeout = 10000,
      note = "the branch is offered",
    },
    { input = "<C-u><Esc>" },
    { wait = "vim.fn.mode() == 'n'" },
    { keys = ":DocMap diff HEAD<CR>", note = "the tree is compared with HEAD" },
    {
      wait = "P.said('Nothing structural changed since HEAD')",
      timeout = 15000,
      note = "nothing changed since the commit",
    },
  },
}
