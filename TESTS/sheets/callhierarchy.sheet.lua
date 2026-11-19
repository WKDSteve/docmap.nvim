-- TESTS/sheets/callhierarchy.sheet.lua -- the call hierarchy of a mapped Lua file, answered from the map.
-- With `callhierarchy = true` and once the map exists, a Lua file of the tree that is opened gets docmap's language
-- client (an in-process server: `vim.lsp.start` with a function as `cmd`, no process). Incoming calls of `trim` name
-- its caller in the store.
return {
  id = "docmap.callhierarchy",
  title = "Incoming calls of a function in a mapped Lua file come from the map",
  feature = "docmap.callhierarchy",
  steps = {
    {
      lua = 'dofile("TESTS/sheets/support/project.lua").make({ callhierarchy = true })',
      timeout = 30000,
      note = "the user's spec turns the call hierarchy on",
    },
    { keys = ":edit lua/app/init.lua<CR>", note = "a file of the project is open" },
    { input = ":DocMap<CR>", note = "the map is generated" },
    {
      wait = "vim.fn.filereadable(_G.root .. '/docs/map/module_map.json') == 1",
      timeout = 30000,
    },
    { keys = ":edit lua/app/util/text.lua<CR>", note = "a file of the tree is opened" },
    {
      wait = "#vim.lsp.get_clients({ bufnr = 0, name = 'docmap-callhierarchy' }) == 1",
      timeout = 10000,
      note = "docmap's client is attached",
    },
    { keys = "/function M.trim<CR>w", note = "the cursor is on trim" },
    { keys = ":lua vim.lsp.buf.incoming_calls()<CR>", note = "the incoming calls are asked for" },
    {
      wait = "vim.iter(vim.fn.getqflist()):any(function(i)"
        .. " return vim.fs.normalize(vim.fn.bufname(i.bufnr)):find('core/store.lua', 1, true) ~= nil end)",
      timeout = 10000,
      note = "the store, which calls it, is listed",
    },
  },
}
