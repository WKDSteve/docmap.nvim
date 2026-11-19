-- TESTS/sheets/cli-breaking.sheet.lua -- the CI gate `--breaking=<ref>` of the command line: does the tree break a
-- caller of the map committed at <ref>? The old side is `git show <ref>:docs/map/module_map.json`.
-- The CLI (`nvim -l scripts/gen_map.lua --breaking=<ref>`) is the `run` of core/cli.lua; the sheet calls that in
-- this editor (support/project.lua, `cli`), so its starts are traced.
return {
  id = "docmap.cli-breaking",
  title = "The CLI gate --breaking=<ref> compares the tree with the map at a revision",
  feature = "docmap.cli-breaking",
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
      lua = "_G.code = P.cli({ '--breaking=HEAD' })",
      timeout = 30000,
      note = "the gate runs against HEAD",
    },
    {
      expect = "_G.code == 0 or error(table.concat(_G.cli_out))",
      note = "nothing breaks: exit 0",
    },
    {
      lua = [[P.edit(_G.root .. "/lua/app/util/text.lua", "function M.words(s)", "function M.split_words(s)")]],
      note = "a published function is renamed",
    },
    { lua = "_G.code = P.cli({ '--breaking=HEAD' })", timeout = 30000 },
    {
      expect = "_G.code == 1 or error(_G.code .. ': ' .. table.concat(_G.cli_out))",
      note = "the rename breaks a caller: exit 1",
    },
  },
}
