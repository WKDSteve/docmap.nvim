-- TESTS/page_history_spec.lua — the generated page and the browser's history.
--
-- `applyState` skips a push whose link equals the last pushed one (a second click on the same tab must not add
-- a Back-stack entry). After Back or Forward that memory is stale: the entry on top is another one. Going
-- A -> B, Back, and to B again then drew B, pushed nothing, and left the address bar on A.
--
-- The guard and its reset run here for real: the two pieces of the state slice are cut out and evaluated in
-- `node` against a recording `history` (skipped without `node`). The same walk in a real window is part of
-- TESTS/sheets/features-way-back.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq
  local slice = require("docmap.core.render.html.js.02_explorer_and_state")

  local push = slice:match("\n    var hash = serializeState%(s%);\n.-\n    }\n")
  local pop = slice:match('\n  window%.addEventListener%("popstate", function%(ev%){\n.-\n  }%);\n')
  ok(push ~= nil, "history: the push guard of applyState is where this spec cuts it out")
  ok(pop ~= nil, "history: the popstate listener is where this spec cuts it out")
  if not (push and pop) or vim.fn.executable("node") == 0 then
    return
  end
  ok(
    pop:find("lastPushedHash = serializeState(state);", 1, true) ~= nil,
    "history: Back and Forward reset what the last push was"
  )

  local program = table.concat({
    "var log = [], state = null, lastPushedHash = null, onpop = null;",
    "var location = { hash: '' };",
    "var history = { pushState: function(s, t, h){ log.push('push ' + h); location.hash = h; },",
    "                replaceState: function(s, t, h){ log.push('replace ' + h); location.hash = h; } };",
    "var window = { addEventListener: function(name, fn){ onpop = fn; } };",
    "function serializeState(s){ return '#tab=' + s.tab; }",
    "function parseState(hash){ return { tab: hash.replace('#tab=', '') }; }",
    "function applyState(s, push){",
    "  state = s;",
    push,
    "}",
    pop,
    "applyState({ tab: 'a' }, true);",
    "applyState({ tab: 'b' }, true);",
    "applyState({ tab: 'b' }, true);", -- the same tab again: no second entry
    "location.hash = '#tab=a'; onpop({ state: { tab: 'a' } });", -- Back
    "applyState({ tab: 'b' }, true);", -- and to b again
    "applyState({ tab: 'b' }, true);",
    "location.hash = '#tab=a'; onpop({ state: null });", -- Back, an entry without a state object
    "applyState({ tab: 'a' }, true);", -- the entry we are on: nothing to push
    "console.log(JSON.stringify(log));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(
    result.code,
    0,
    "history: the two pieces run on their own — " .. vim.trim(result.stderr or "")
  )
  eq(
    table.concat(vim.json.decode(result.stdout or "[]"), ", "),
    "push #tab=a, push #tab=b, replace #tab=a, push #tab=b, replace #tab=a",
    "history: after Back the same target is pushed again, and the entry landed on is not pushed twice"
  )
end
