-- TESTS/sheets/lookup-hovers.sheet.lua -- the cards of the lookup layer the IR answers, in a real window and
-- from the keyboard.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/lookup_page: `M.start` of
-- lua/look/init.lua calls `store.load` and the deprecated `store.old_load`, requires `look.store` (in the tree)
-- and `look.gone` (declared by no file), and calls `dkjson.encode` (outside the map); its parameter is a
-- `Look.Opts`, and the map carries no class details. The tree has one warning, `require-not-declared`.
local POP = "document.getElementById('kwpop')"
local SIG = "document.getElementById('sigpop')"
local START = "lua/look#M.start"

---The card is open and says `text` (no quote in it: a sheet is data and has nothing to escape with).
---@param text string
---@return string
local function shown(text)
  return POP
    .. ".classList.contains('on') && "
    .. POP
    .. ".textContent.indexOf('"
    .. text
    .. "') !== -1"
end

return {
  id = "lookup-hovers",
  title = "Lookup layer: the cards the IR answers, from the keyboard",
  task = "docmap.nvim/lookup-in-tree-hovers",
  engine = "browser",
  steps = {
    { open = "TESTS/sheets/out/lookup-page.html" },
    { click = 'button[data-tab="index"]', note = "the Index tab lists the functions" },
    { wait = "document.querySelector('[data-sig=\"" .. START .. "\"]') !== null" },
    {
      click = '[data-sig="' .. START .. '"]',
      note = "pin the card of M.start: annotations and snippet",
    },
    {
      wait = SIG
        .. ".classList.contains('on') && "
        .. SIG
        .. ".querySelector('.fn-snip[data-fnkey=\""
        .. START
        .. "\"]') !== null",
      note = "the snippet names its function",
    },
    {
      expect = "['fn','call','req','ext','type','kw','std'].every(k => "
        .. SIG
        .. ".querySelector('[data-kwkind=\"' + k + '\"][tabindex=\"0\"]'))",
      note = "every kind has a trigger in it, and each is focusable",
    },

    { focus = '#sigpop [data-kwkind="type"]' },
    {
      wait = shown("Not known: this map carries no class details"),
      note = "a type name: the map has no class details, and the card says so in place",
    },
    { shot = "type-not-known-light" },

    { focus = '#sigpop [data-kwkind="fn"]' },
    {
      wait = shown("Called by"),
      note = "the function's own name: complexity, callers, callees, tests",
    },
    {
      expect = "/Complexity\\s*1 \\(cyclomatic\\)/.test("
        .. POP
        .. ".textContent) && /Calls\\s*2 functions of this tree/.test("
        .. POP
        .. ".textContent) && /no spec names it/.test("
        .. POP
        .. ".textContent)",
      note = "the numbers of the Analysis tab, where the function is read",
    },
    { shot = "fn-light" },

    { focus = '#sigpop [data-kwkind="req"][data-kw="look.store"]' },
    {
      wait = shown("in this tree: lua/look/store.lua"),
      note = "a require path that resolves in the tree",
    },
    { focus = '#sigpop [data-kwkind="req"][data-kw="look.gone"]' },
    {
      wait = shown("Not known: unresolved"),
      note = "a require path nothing declares: the third answer",
    },
    { focus = '#sigpop [data-kwkind="ext"]' },
    {
      wait = shown("This file calls"),
      note = "an external module: what this file calls on it",
    },
    { expect = "/encode\\s*1×/.test(" .. POP .. ".textContent)", note = "and how often" },

    { focus = '#sigpop [data-kwkind="call"]' },
    {
      wait = shown("Loads a key."),
      note = "a call that resolves in the tree: the callee's summary and module",
    },
    { shot = "call-light" },
    { scheme = "dark" },
    { shot = "call-dark" },
    { scheme = "light" },
    { press = "Enter", note = "Enter on the focused call follows the card" },
    {
      wait = "/tab=tree&id=lua%2Flook%2Fstore\\.lua/.test(location.hash)",
      note = "to the callee's module in the Tree tab",
    },
    {
      expect = "!" .. POP .. ".classList.contains('on') && !" .. SIG .. ".classList.contains('on')",
      note = "both floating layers are gone",
    },

    {
      wait = "document.querySelector('#detail .bd[data-kw=\"deprecated\"][data-kwctx]') !== null",
      note = "the detail of the store lists the deprecated function with its badge",
    },
    { focus = '#detail .bd[data-kw="deprecated"]' },
    {
      wait = shown("Still called by"),
      note = "the deprecated badge: what the tag means, and who still calls the function",
    },
    { expect = "/M\\.start/.test(" .. POP .. ".textContent)", note = "by name" },
    { shot = "deprecated-light" },
    { press = "Escape" },

    { click = 'button[data-tab="findings"]', note = "the Findings tab" },
    { wait = "document.querySelector('#findings [data-kwkind=\"check\"]') !== null" },
    { focus = '#findings [data-kwkind="check"]' },
    { wait = shown("Why"), note = "a check id: what the check compares and why it exists" },
    {
      expect = "/require-not-declared/.test("
        .. POP
        .. ".textContent) && /severity warn by default/i.test("
        .. POP
        .. ".textContent) && /1 finding here/i.test("
        .. POP
        .. ".textContent)",
      note = "with its default grade and how many findings it has here",
    },
    { shot = "check-light" },
    { scheme = "dark" },
    { shot = "check-dark" },
    { scheme = "light" },
    { click = '#findings [data-kwkind="check"]', note = "a click on the id asks" },
    {
      expect = "/tab=findings/.test(location.hash) && " .. POP .. ".classList.contains('on')",
      note = "and does not follow the row to its module",
    },
    { press = "Escape" },
    { expect = "!" .. POP .. ".classList.contains('on')", note = "Escape closes it" },
  },
  judge = {
    "the not-known card reads as an answer, not as an error or an empty box (type-not-known-light)",
    "the function card is a compact list of labelled facts (fn-light)",
    "the call card is readable in the light and the dark theme and its link reads as a link (call-light, call-dark)",
    "the callers of the deprecated function are easy to find in the card (deprecated-light)",
    "the check card is readable in both themes and stays within the window (check-light, check-dark)",
  },
}
