-- Test code: when something here comes back nil, this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/lookup_layer_spec.lua — the lookup layer of the page: one registry, one card, and the kinds the IR
-- answers (a call that resolves in the tree, a function's own name, a type name, a `require` path, an external
-- module, a check id), next to the three that were there (keyword, stdlib name, tag).
--
-- Three halves:
--   * the catalogue of checks (`findings.CHECKS`) reaches the page as `IR.checks`, and the findings views
--     carry the triggers;
--   * the wiring of the page, pinned as text;
--   * the registry, the tokenizer and the card run in `node` against a hand-built IR (skipped without it).
-- That every check has an explanation is `findings_spec.lua`; the behaviour in a real window is
-- TESTS/sheets/lookup-hovers.sheet.lua.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("docmap")
  local findings = require("docmap.core.findings")

  -- ── The catalogue reaches the page ───────────────────────────────────────
  local page_checks = findings.for_page()
  local by_name = {}
  for i, c in ipairs(page_checks) do
    by_name[c.name] = c
    if i > 1 then
      ok(page_checks[i - 1].name < c.name, "for_page: sorted by name, so the page is deterministic")
    end
  end
  eq(
    #by_name["dead-function"].templates,
    3,
    "for_page: a check with variants carries each of its sentences"
  )
  eq(
    by_name["layer-violation"].templates[1],
    findings.CATALOG["layer-violation"],
    "for_page: the sentence is the catalog's own, not a copy"
  )
  eq(by_name["missing-module-tag"].severity, "error", "for_page: the default grade rides along")

  do
    local root = H.tmpfile("_lookup_layer")
    local function dwrite(rel, lines)
      local abs = root .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
      local fd = assert(io.open(abs, "w"), "lookup spec: fixture must be writable")
      fd:write(table.concat(lines, "\n"))
      fd:close()
    end
    -- No summary line: one `missing-summary` finding on a real node.
    dwrite("lua/t/init.lua", { "---@module 't'", "local M = {}", "return M" })
    local opts = { root = root, source = "lua/t", lua_root = "lua", extra_checks = {} }
    local ir, found = docmap.scan_full(opts)
    local html = docmap.render.html(ir, found, opts)
    ok(
      html:find('"checks":[{', 1, true) ~= nil,
      "page: the catalogue rides in the payload as IR.checks"
    )
    ok(
      html:find(
        '<td class="msg"><span class="kw" data-kw="missing-summary" data-kwkind="check" tabindex="0">missing-summary</span></td>',
        1,
        true
      ) ~= nil,
      "page: the check id in the Findings table is a focusable trigger of kind check"
    )
    ok(
      not docmap.to_json(ir):find('"checks"', 1, true),
      "artifact: the catalogue is tool data and stays out of module_map.json"
    )
  end

  -- ── The page: wiring ─────────────────────────────────────────────────────
  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "lookup page: " .. msg)
  end
  for _, kind in ipairs({ "kw", "std", "tag", "call", "fn", "type", "ext", "req", "check" }) do
    has('lookupRegister("' .. kind .. '", ', "the kind " .. kind .. " is registered")
  end
  has(
    'var card = lookup(el.dataset.kwkind || "kw", el.dataset.kw, kwContext(el));',
    "the card asks the registry and knows no kind itself"
  )
  has("kwpop.innerHTML = lookupCardHTML(card);", "one card component renders every kind")
  has(
    "snipBodyHTML(fn.snippet, path, node ? { fnKey: fnKey(node.id, fn.name) } : null)",
    "a snippet is tokenized with its function as context"
  )
  has(
    "(node ? ' data-fnkey=\"' + esc(fnKey(node.id, fn.name)) + '\"' : '')",
    "the function rides on the snippet container, once"
  )
  has("typeHTML(p.type)", "a parameter's type is a trigger surface")
  has("typeHTML(r.type)", "so is a return type")
  has(
    "html = fnAnnotationHTML(entry.fn, entry.key) + snippetHTML(entry.fn, entry.node)",
    "the popup hands the badges their function"
  )
  has(
    [[data-kw="'+esc(x.check)+]],
    "the severity badge of a node's drift list is the trigger of its check"
  )
  has(
    'if(ev.target.closest && ev.target.closest("[data-kw]")) return;',
    "a click on a check id asks, it does not follow the row"
  )
  has(
    'var way = kwpop.querySelector("a[data-kw-nav]") || kwpop.querySelector("a[href]");',
    "Enter on a focused trigger follows the card's way on"
  )
  has(
    "if(kwAnchor && Date.now() < kwFocusScrollUntil){ kwPlace(kwAnchor); return; }",
    "the scroll a focus causes does not close the card"
  )
  has(".kwpop{position:fixed;z-index:70;display:none;max-width:340px;", "the card is one box")
  has("max-height:50vh;overflow-y:auto}", "and it is bounded")

  -- ── The registry, the tokenizer and the card, in node ────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local s01 = require("docmap.core.render.html.js.01_marks_and_dimming")
  local s02 = require("docmap.core.render.html.js.02_explorer_and_state")
  ---The text of a slice from one marker up to (not including) another.
  local function cut(text, from, to)
    local a = assert(text:find(from, 1, true), "lookup spec: cannot find " .. from)
    local b = assert(text:find(to, a, true), "lookup spec: cannot find " .. to)
    return text:sub(a, b - 1)
  end
  local program = table.concat({
    "var FIELDS = []; for(var fi = 0; fi < 11; fi++) FIELDS.push({ name: 'f' + fi, view: 'string', desc: '' });",
    "var SNIP = ['function M.run(x)',",
    "  '  local v = helper.help(x) -- help(x) in a comment',",
    "  '  M2.quiet()',",
    "  '  local j = require(\"dkjson\")',",
    "  '  local b = require(\"b\")',",
    "  '  local g = require(\"gone.mod\")',",
    "  '  return dkjson.encode(v), table.concat(g)',",
    "  '  -- a method of the same name on a line no edge names',",
    "  '  local w = other:help(x) + old.legacy(x)',",
    "  'end'].join('\\n');",
    "var IR = { tags: [ { name: 'deprecated', summary: 'Marks it old.', origin: 'luals', url: 'https://x/#d' },",
    "                   { name: 'internal', summary: 'Not API.', origin: 'project' } ],",
    "  checks: [ { name: 'layer-violation', severity: 'warn', compares: 'Edges against `layers`.',",
    "              why: 'A decision.', templates: ['{from} requires {to}'] } ],",
    "  glossaries: { lua: { keywords: { 'function': { summary: 'a function' }, 'local': { summary: 'a local' },",
    "                                    'return': { summary: 'r' }, 'end': { summary: 'e' } },",
    "    stdlib: { 'table.concat': { summary: 'joins', anchor: '#tc' },",
    "              'vim.split': { summary: 'splits', origin: 'Neovim' } },",
    "    reference: { url: 'https://lua/manual', label: 'Lua 5.1 manual' },",
    "    syntax: { line_comment: '--', strings: [ ['\"', '\"'] ], escape: '\\\\' } } },",
    "  nodes: [",
    "   { id: 'lua/a.lua', path: 'lua/a.lua', source: 'lua/a.lua', module: 'a', language: 'lua', summary: 'Module A.',",
    "     requires_external: ['dkjson', 'plenary.path', 'a.missing'],",
    "     calls_external: [ { module: 'dkjson', member: 'decode', count: 1 },",
    "                       { module: 'dkjson', member: 'encode', count: 3 } ],",
    "     functions: [ { name: 'M.run', line: 10, signature: 'M.run(x)', summary: 'Runs it.', complexity: 4,",
    "                    tested: true, snippet: SNIP } ] },",
    "   { id: 'lua/b.lua', path: 'lua/b.lua', source: 'lua/b.lua', module: 'b', language: 'lua', summary: 'Module `B`.',",
    "     functions: [ { name: 'M.help', line: 3, signature: 'M.help(s)', summary: 'Helps `well`.',",
    "                    deprecated: 'use other', complexity: 1, tested: false },",
    "                  { name: 'M.quiet', line: 9, signature: 'M.quiet()', internal: true },",
    "                  { name: 'M.legacy', line: 12, signature: 'M.legacy(x)' } ],",
    "     types_detail: [ { name: 'B.Opts', kind: 'class', desc: 'What B takes.', file: 'lua/b.lua',",
    "                       extends: ['B.Base'], fields: FIELDS },",
    "                     { name: 'B.Empty', kind: 'class', desc: '', file: 'lua/b.lua', extends: [], fields: [] } ] },",
    "   { id: 'py/c.py', path: 'py/c.py', source: 'py/c.py', language: 'python',",
    "     functions: [ { name: 'go', line: 1, signature: 'go()', snippet: 'def go():\\n    return lib.run(1)' } ],",
    "     requires_external: ['lib'] } ],",
    "  edges: [ { kind: 'call', from: 'lua/a.lua', from_fn: 'M.run', to: 'lua/b.lua', to_fn: 'M.help', line: 11 },",
    "           { kind: 'call', from: 'lua/a.lua', from_fn: 'M.run', to: 'lua/b.lua', to_fn: 'M.help', line: 99 },",
    "           { kind: 'call', from: 'lua/a.lua', from_fn: 'M.run', to: 'lua/b.lua', to_fn: 'M.quiet', line: 12 },",
    "           { kind: 'call', from: 'lua/a.lua', from_fn: 'M.run', to: 'lua/b.lua', to_fn: 'M.legacy' },",
    "           { kind: 'require', from: 'lua/a.lua', to: 'lua/b.lua', to_module: 'b', line: 14 } ] };",
    "var FIND = [ { check: 'layer-violation', severity: 'warn', node: 'lua/a.lua', message: 'm' },",
    "             { check: 'repo-own', severity: 'info', message: 'x' } ];",
    "var byId = {}, fnByKey = {}, classByName = {}, callIn = {}, callOut = {}, depOut = {};",
    "function fnKey(id, name){ return id + '#' + name; }",
    "IR.nodes.forEach(function(n){ byId[n.id] = n;",
    "  (n.functions || []).forEach(function(f){ fnByKey[fnKey(n.id, f.name)] = { node: n, fn: f, key: fnKey(n.id, f.name) }; });",
    "  (n.types_detail || []).forEach(function(t){ classByName[t.name] = { info: t, nodeId: n.id }; }); });",
    "function push(m, k, v){ (m[k] = m[k] || []).push(v); }",
    "IR.edges.forEach(function(e){",
    "  if(e.kind === 'call'){ push(callOut, fnKey(e.from, e.from_fn), e); push(callIn, fnKey(e.to, e.to_fn), e); }",
    "  else push(depOut, e.from, e); });",
    "function getExternalCallTotals(){ return { dkjson: { encode: 3, decode: 1 } }; }",
    cut(s01, "  function esc(s){", "  // Markdown info strings that are not"),
    cut(s02, "  function typeHTML(text){", "  // `key` (the function's `fnKey`) is optional"),
    cut(s02, "  function glossaryForPath(path){", "  // Artifact lives in out_dir"),
    "var A = 'lua/a.lua#M.run', out = {};",
    "out.snip = snipBodyHTML(SNIP, 'lua/a.lua', { fnKey: A });",
    "out.plain = snipBodyHTML(SNIP, 'lua/a.lua');",
    "out.noGlossary = snipBodyHTML(SNIP, 'lua/a.zz', { fnKey: A });",
    "out.noGlossaryPlain = snipBodyHTML(SNIP, 'lua/a.zz');",
    "out.python = snippetHTML(IR.nodes[2].functions[0], IR.nodes[2]);",
    "out.call = lookup('call', 'lua/b.lua#M.help');",
    "out.callQuiet = lookup('call', 'lua/b.lua#M.quiet');",
    "out.callGone = lookup('call', 'lua/zz.lua#M.x');",
    "out.fn = lookup('fn', A);",
    "out.fnHelp = lookup('fn', 'lua/b.lua#M.help');",
    "out.fnPython = lookup('fn', 'py/c.py#go');",
    "out.type = lookup('type', 'B.Opts');",
    "out.typeEmpty = lookup('type', 'B.Empty');",
    "out.typeMissing = lookup('type', 'Other.Thing');",
    "out.typeHTML = typeHTML('table<string, B.Opts>|Other.Thing|constructor');",
    "out.reqTree = lookup('req', 'b', { fnKey: A });",
    "out.reqExt = lookup('req', 'dkjson', { fnKey: A });",
    "out.reqQuiet = lookup('req', 'plenary.path', { fnKey: A });",
    "out.reqGone = lookup('req', 'gone.mod', { fnKey: A });",
    "out.reqMissing = lookup('req', 'a.missing', { fnKey: A });",
    "out.ext = lookup('ext', 'dkjson', { fnKey: A });",
    "out.extTree = lookup('ext', 'dkjson', {});",
    "out.extNotHere = lookup('ext', 'dkjson', { fnKey: 'lua/b.lua#M.help' });",
    "out.check = lookup('check', 'layer-violation');",
    "out.checkOwn = lookup('check', 'repo-own');",
    "out.tagPlain = lookup('tag', 'deprecated', {});",
    "out.tagDeprecated = lookup('tag', 'deprecated', { fnKey: 'lua/b.lua#M.help' });",
    "out.tagInternal = lookup('tag', 'internal', { fnKey: 'lua/b.lua#M.quiet' });",
    "out.tagGone = lookup('tag', 'nosuch', {});",
    "out.kw = lookup('kw', 'local', { path: 'lua/a.lua' });",
    "out.kwProto = lookup('kw', 'constructor', { path: 'lua/a.lua' });",
    "out.std = lookup('std', 'table.concat', { path: 'lua/a.lua' });",
    "out.stdVim = lookup('std', 'vim.split', { path: 'lua/a.lua' });",
    "out.noKind = lookup('nosuchkind', 'x');",
    "out.cardType = lookupCardHTML(out.type);",
    "out.cardCall = lookupCardHTML(out.call);",
    "out.cardGone = lookupCardHTML(out.reqGone);",
    "out.cardStd = lookupCardHTML(out.std);",
    "out.cardLong = lookupCardHTML({ word: 'w', rows: { items: [ { text: new Array(400).join('x') } ] } });",
    -- A map without any class detail: the same type name is then a trigger that says so.
    "IR.nodes[1].types_detail = null; classByName = {}; mapHasTypes = null;",
    "out.typeNoDetail = lookup('type', 'B.Opts');",
    "out.typeHTMLNoDetail = typeHTML('table<string, B.Opts>|string|Opts|vim.api.x');",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "lookup page: the layer runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}", { luanil = { object = true } })

  local function count(text, needle)
    local n, from = 0, 1
    while true do
      local a, b = text:find(needle, from, true)
      if not a then
        return n
      end
      n, from = n + 1, b + 1
    end
  end
  local function span(key, kind, label)
    return ('<span class="kw" data-kw="%s" data-kwkind="%s" tabindex="0">%s</span>'):format(
      key,
      kind,
      label
    )
  end

  -- The tokenizer.
  ok(
    got.snip:find("function</span> " .. span("lua/a.lua#M.run", "fn", "M.run") .. "(x)", 1, true),
    "snippet: the function's own name is a trigger where it is declared — " .. got.snip
  )
  eq(
    count(got.snip, span("lua/b.lua#M.help", "call", "helper.help")),
    1,
    "snippet: a call that resolves in the tree is a trigger, on the line the edge names"
  )
  eq(
    count(got.snip, 'data-kwkind="call"'),
    3,
    "snippet: the same name in a comment is not a call, and neither is it on a line no edge names"
  )
  ok(
    got.snip:find(span("lua/b.lua#M.legacy", "call", "old.legacy") .. "(x)", 1, true),
    "snippet: an edge without a line (an older map) is matched by its name alone"
  )
  ok(
    got.snip:find(span("lua/b.lua#M.quiet", "call", "M2.quiet") .. "()", 1, true),
    "snippet: the key of a call is the callee, whatever the receiver is called"
  )
  for _, path in ipairs({ "dkjson", "b", "gone.mod" }) do
    ok(
      got.snip:find("require</span>(&quot;" .. span(path, "req", path) .. "&quot;)", 1, true)
        or got.snip:find("require(&quot;" .. span(path, "req", path) .. "&quot;)", 1, true),
      "snippet: the path of a require is a trigger, quotes left outside — " .. path
    )
  end
  ok(
    got.snip:find(span("dkjson", "ext", "dkjson") .. ".encode(v)", 1, true),
    "snippet: an external module is a trigger, the member stays plain"
  )
  ok(
    got.snip:find(span("table.concat", "std", "table.concat"), 1, true),
    "snippet: the language's own names keep their card (the glossary answers first)"
  )
  eq(
    count(got.plain, 'data-kwkind="call"')
      + count(got.plain, 'data-kwkind="fn"')
      + count(got.plain, 'data-kwkind="req"')
      + count(got.plain, 'data-kwkind="ext"'),
    0,
    "snippet: without a function nothing of the IR is marked (a fenced block stays as it was)"
  )
  ok(
    count(got.noGlossary, 'data-kwkind="call"') >= 2
      and not got.noGlossary:find('data-kwkind="kw"', 1, true),
    "snippet: a language without a glossary still gets what the IR knows"
  )
  ok(
    not got.noGlossaryPlain:find("<span", 1, true),
    "snippet: no glossary and no function is plain text"
  )
  ok(
    got.python:find('data-fnkey="py/c.py#go"', 1, true)
      and got.python:find(span("py/c.py#go", "fn", "go"), 1, true)
      and got.python:find(span("lib", "ext", "lib") .. ".run(1)", 1, true),
    "snippet: the container names its function; a module used under its own name is found — "
      .. got.python
  )

  -- call
  eq(got.call.summary, "Helps `well`.", "call: the callee's summary")
  eq(got.call.origin, "b", "call: its module")
  eq(got.call.nav.to.id, "lua/b.lua", "call: and the way there")
  ok(
    got.callQuiet.unknown and not got.callQuiet.summary,
    "call: a callee without a summary says so"
  )
  ok(got.callGone.unknown ~= nil, "call: an edge to a function the map does not hold says so")

  -- fn
  local function line(card, label)
    for _, l in ipairs(card.lines or {}) do
      if l.label == label then
        return l.text
      end
    end
  end
  eq(line(got.fn, "Complexity"), "4 (cyclomatic)", "fn: complexity")
  eq(
    line(got.fn, "Calls"),
    "3 functions of this tree",
    "fn: fan-out counts functions, not call sites"
  )
  eq(line(got.fn, "Called by"), "0 functions of this tree", "fn: fan-in")
  eq(line(got.fn, "Tests"), "a spec names it", "fn: tested")
  eq(line(got.fnHelp, "Called by"), "1 function of this tree", "fn: one caller, two sites")
  eq(line(got.fnHelp, "Tests"), "no spec names it", "fn: not tested is said, too")
  eq(got.fn.nav.to.view, "calls", "fn: the way on is the Calls view")
  ok(
    line(got.fnPython, "Called by"):find("not known", 1, true)
      and line(got.fnPython, "Complexity"):find("not known", 1, true)
      and line(got.fnPython, "Tests"):find("not known", 1, true)
      and got.fnPython.nav == nil,
    "fn: a language without call edges, and a map without the numbers, say not known instead of 0"
  )

  -- type
  eq(got.type.kind, "class : B.Base", "type: kind and parents")
  eq(got.type.origin, "lua/b.lua", "type: where it is declared")
  eq(#got.type.rows.items, 11, "type: every field is handed to the card")
  eq(got.typeEmpty.note, "No fields declared.", "type: a class without fields says so")
  ok(
    got.typeMissing.unknown:find("is declared in the tree", 1, true),
    "type: a name the tree does not declare is not known"
  )
  ok(
    got.typeNoDetail.unknown:find("--full", 1, true),
    "type: a map without class details says how to get them"
  )
  eq(
    got.typeHTML,
    "table&lt;string, " .. span("B.Opts", "type", "B.Opts") .. "&gt;|Other.Thing|constructor",
    "type: in a map with class details only declared names are triggers"
  )
  eq(
    got.typeHTMLNoDetail,
    "table&lt;string, " .. span("B.Opts", "type", "B.Opts") .. "&gt;|string|Opts|vim.api.x",
    "type: without them a name spelled like a class is one, and says not known"
  )

  -- req / ext
  eq(got.reqTree.origin, "in this tree: lua/b.lua", "req: resolved in the tree")
  eq(got.reqTree.nav.to.id, "lua/b.lua", "req: with the way there")
  eq(got.reqExt.origin, "external: outside this map", "req: external")
  eq(
    got.reqExt.rows.items[1].code .. " " .. got.reqExt.rows.items[1].count,
    "encode 3",
    "req: what this file calls on it, most called first"
  )
  ok(
    got.reqQuiet.note:find("no call into it", 1, true),
    "req: an external module nothing is called on says so"
  )
  ok(
    got.reqGone.unknown:find("unresolved", 1, true),
    "req: neither is the third answer, not an empty card"
  )
  ok(
    got.reqMissing.unknown:find("under this tree's own prefix", 1, true),
    "req: a name under the tree's own prefix that nothing declares is missing, not external"
  )
  eq(got.ext.rows.title, "This file calls", "ext: scoped to the file of the snippet")
  eq(got.extTree.rows.title, "This tree calls", "ext: without a file, the tree")
  ok(got.extNotHere.unknown ~= nil, "ext: a file that does not require it is told so")

  -- check
  eq(got.check.summary, "Edges against `layers`.", "check: what it compares")
  eq(got.check.lines[1].text, "A decision.", "check: why it exists")
  eq(got.check.rows.items[1].text, "{from} requires {to}", "check: what a finding reads like")
  eq(got.check.origin, "severity warn by default · 1 finding here", "check: grade and count")
  ok(
    got.checkOwn.unknown:find("extra_checks", 1, true),
    "check: a check of the project's own has no explanation here, and the card says so"
  )

  -- tag, kw, std: the three that were there answer through the registry.
  eq(got.tagPlain.word, "@deprecated", "tag: the word")
  eq(got.tagPlain.link.href, "https://x/#d", "tag: the resolved reference")
  ok(
    got.tagPlain.rows == nil and got.tagPlain.lines == nil,
    "tag: without a function, the meaning only"
  )
  eq(
    got.tagDeprecated.rows.title,
    "Still called by",
    "tag: a deprecated function names its callers"
  )
  eq(got.tagDeprecated.rows.items[1].code, "M.run", "tag: by name")
  eq(#got.tagDeprecated.rows.items, 1, "tag: each caller once")
  eq(
    got.tagInternal.rows.title,
    "Called from outside its module by",
    "tag: an internal function names the callers outside its module"
  )
  eq(got.tagGone, nil, "tag: a name the catalogue does not have has no card")
  eq(got.kw.summary, "a local", "kw: from the glossary of the snippet's language")
  eq(got.kwProto, nil, "kw: a word of Object.prototype is no entry")
  eq(
    got.std.link.href,
    "https://lua/manual#tc",
    "std: one base URL per language, the anchor derived"
  )
  ok(
    got.stdVim.origin == "Neovim" and got.stdVim.link == nil,
    "std: a name that is not the language gets its origin and no manual link"
  )
  eq(got.noKind, nil, "registry: an unregistered kind answers nothing")

  -- The card.
  eq(count(got.cardType, "<li>"), 8, "card: rows are cut")
  ok(
    got.cardType:find('<div class="kw-more">… and 3 more</div>', 1, true),
    "card: and the omitted amount is stated"
  )
  ok(
    got.cardType:find('<span class="kw-kind">class : B.Base</span>', 1, true),
    "card: the kind sits beside the word"
  )
  ok(
    got.cardCall:find("Helps <code>well</code>.", 1, true)
      and got.cardCall:find(
        'data-kw-nav="{&quot;tab&quot;:&quot;tree&quot;,&quot;id&quot;:&quot;lua/b.lua&quot;}">b:3</a>',
        1,
        true
      ),
    "card: prose is rendered, the jump is a state patch — " .. got.cardCall
  )
  ok(
    got.cardGone:find('<div class="kw-unknown">Not known: unresolved.', 1, true),
    "card: not known is shown in place"
  )
  ok(
    got.cardStd:find(
      '<a href="https://lua/manual#tc" target="_blank" rel="noreferrer noopener">Lua 5.1 manual &#8599;</a>',
      1,
      true
    ),
    "card: the reference link leaves the page in a new tab"
  )
  ok(#got.cardLong < 400, "card: one row cannot make the card arbitrarily long")
end
