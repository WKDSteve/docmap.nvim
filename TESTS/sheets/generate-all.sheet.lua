-- TESTS/sheets/generate-all.sheet.lua -- `:DocMap all`: the maps of every configured project, each in its own
-- headless editor (`nvim --headless -l scripts/generate_one_headless.lua`) in the background.
return {
  id = "docmap.generate-all",
  title = ":DocMap all generates the map of every configured project in the background",
  feature = "docmap.generate-all",
  steps = {
    {
      lua = [[dofile("TESTS/sheets/support/project.lua").make(function(root)
        return { generate_all = { projects = { { root = root, title = "app" } } } }
      end)]],
      timeout = 30000,
    },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { keys = ":DocMap all<CR>", note = "the maps are generated" },
    {
      expect = "P.said('Generating 1 project map(s) asynchronously')",
      note = "it says it started",
    },
    {
      wait = "P.said('All 1 project map(s) generated')",
      timeout = 60000,
      note = "and that it is done",
    },
    {
      expect = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      note = "the project's map is written",
    },
  },
}
