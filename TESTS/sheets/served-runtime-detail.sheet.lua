-- TESTS/sheets/served-runtime-detail.sheet.lua -- the function detail of a served page shows what runtime-analysis
-- measured, and tells "not measured" from "measured, never called".
-- A browser sheet. Its app `telemetry-host` (.testing.lua, TESTS/telemetry_host.lua) runs `:DocMap serve` on a free
-- port over the lookup-page fixture, with a telemetry store of known content that lives in the run's folder only:
--   lua/look#M.start               13 calls, 3 of them in the last week, timed, 1 error, callers, argument fingerprints
--   lua/look/store.lua#M.load      wrapped, never called
--   lua/look/store.lua#M.old_load  not wrapped: no row at all
-- The first steps open the same page as a file, where `/api/telemetry` cannot be asked.
-- the URL of the host this sheet's app started; it ends in "/"
local HOST = "${host}"

---The block of a function in the detail pane, as an expression.
---@param key string
---@return string
local function block(key)
  return "document.querySelector('#detail .fn[data-fn=\"" .. key .. "\"]')"
end

---The runtime part of a function's block, as an expression for its text.
---@param key string
---@return string
local function rt(key)
  return "("
    .. block(key)
    .. " && "
    .. block(key)
    .. ".querySelector('.fn-rt') ? "
    .. block(key)
    .. ".querySelector('.fn-rt').textContent : '')"
end

local START = "lua/look#M.start"
local LOAD = "lua/look/store.lua#M.load"
local OLD = "lua/look/store.lua#M.old_load"

return {
  id = "served-runtime-detail",
  title = "A served page shows runtime data in the function detail",
  task = "docmap.nvim/sheet-gediente-karte-laufzeitdetail-aus-api-telemetry-fixture",
  engine = "browser",
  app = "telemetry-host",
  steps = {
    -- A page from a file cannot ask for the data: nothing is added to the detail.
    { open = "TESTS/sheets/out/lookup-page.html" },
    { wait = "document.querySelector('#tree .row') !== null", note = "the page is up" },
    {
      expect = "(location.hash = '#tab=tree&id=lua%2Flook&fn=lua%2Flook%23M.start', true)",
      note = "the function is opened",
    },
    { wait = block(START) .. " !== null", note = "the detail shows the function" },
    {
      expect = "document.querySelector('#detail .fn-rt') === null",
      note = "opened from a file there is no runtime block (no host to ask)",
    },

    -- The same page from the host.
    {
      open = HOST .. "#tab=tree&id=lua%2Flook&fn=lua%2Flook%23M.start",
      note = "the served page",
    },
    {
      wait = rt(START) .. ".length > 0",
      timeout = 15000,
      note = "the runtime block of the function arrives",
    },
    {
      expect = rt(START) .. ".includes('13 calls, 3 in the last week')",
      note = "calls in total and in the last week are two numbers",
    },
    {
      expect = "/duration: mean [0-9.]+ ms, slowest [0-9.]+ ms \\(3 timed\\)/.test("
        .. rt(START)
        .. ")",
      note = "the duration of the timed calls",
    },
    { expect = rt(START) .. ".includes('errors: 1')", note = "the one error" },
    {
      expect = "/top callers: .*telemetry_host\\.lua:[0-9]+.* ×3/.test(" .. rt(START) .. ")",
      note = "the callers, with their count",
    },
    {
      expect = "/top arguments: .*<string:5:[0-9a-f]+>.* ×2/.test(" .. rt(START) .. ")",
      note = "the arguments as fingerprints (length and digest), with their count",
    },
    {
      expect = "!" .. rt(START) .. ".includes('alpha') && !" .. rt(START) .. ".includes('boom')",
      note = "never the argument text itself",
    },
    { shot = "measured" },

    -- A function wrapped but never called, and one that was never measured.
    {
      open = HOST .. "#tab=tree&id=lua%2Flook%2Fstore.lua&fn=lua%2Flook%2Fstore.lua%23M.load",
      note = "the module with the two other functions",
    },
    {
      wait = rt(LOAD) .. ".length > 0 && " .. rt(OLD) .. ".length > 0",
      timeout = 15000,
      note = "both blocks got their runtime part",
    },
    {
      expect = rt(LOAD) .. ".includes('wrapped, never called')",
      note = "measured and never called",
    },
    {
      expect = "!"
        .. rt(LOAD)
        .. ".includes('Not measured') && !"
        .. rt(LOAD)
        .. ".includes(' 0 calls')",
      note = "which is not the 'not measured' answer, and not a zero count",
    },
    {
      expect = rt(OLD) .. ".includes('Not measured')",
      note = "a function the store has no row for is 'not measured'",
    },
    { shot = "unmeasured" },
  },
}
