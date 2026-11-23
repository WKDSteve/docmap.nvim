-- TESTS/sheets/host-context.sheet.lua -- the page tells an embedding host which node and function the reader chose.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/lookup_page (module `lua/look`,
-- function `M.start`). The page is top level here, so `window.parent` is replaced by a collector, which makes
-- `postContext` believe it is embedded.
local GET = "window.__ctx"

return {
  id = "host-context",
  title = "Host contract: the context message carries the chosen node and function",
  task = "docmap.nvim/seite-meldet-den-gewaehlten-knoten-und-die-funktion-an-den",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/lookup-page.html" },
    { wait = "document.querySelector('#tree .row') !== null", note = "the page is up" },
    {
      expect = "(window.__ctx = [], Object.defineProperty(window, 'parent', { configurable: true,"
        .. " value: { postMessage: m => window.__ctx.push(m) } }), true)",
      note = "a collector stands in for the embedding host",
    },
    {
      expect = "(location.hash = '#tab=tree&id=lua%2Flook&fn=lua%2Flook%23M.start', true)",
      note = "the reader picks a function",
    },
    {
      wait = GET
        .. ".length > 0 && "
        .. GET
        .. "["
        .. GET
        .. ".length - 1].fn === 'lua/look#M.start'",
      note = "the host hears the function",
    },
    {
      expect = "(m => m.source === 'docmap' && m.tab === 'tree' && m.id === 'lua/look')("
        .. GET
        .. "["
        .. GET
        .. ".length - 1])",
      note = "and its node",
    },
    {
      expect = "(location.hash = '#tab=tree&id=lua%2Flook', true)",
      note = "the reader picks the module alone",
    },
    {
      wait = "(m => m.id === 'lua/look' && m.fn === null)(" .. GET .. "[" .. GET .. ".length - 1])",
      note = "a change of the function alone is a new message, with fn null",
    },
    {
      expect = "(location.hash = '#tab=notes', true)",
      note = "the reader leaves the tree",
    },
    {
      wait = "(m => m.tab === 'notes' && m.id === null && m.fn === null)("
        .. GET
        .. "["
        .. GET
        .. ".length - 1])",
      note = "off the tree both fields are null",
    },
  },
}
