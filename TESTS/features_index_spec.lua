-- Test code: when something here comes back nil, this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/features_index_spec.lua — the way back from a module or a function to its feature descriptions, and the
-- theme sub-tabs of the Features tab.
--
-- Three halves:
--   * `features.index` (the `Module:` bullets read backwards) against a hand-built tree: what resolves, what is
--     reported, and what is passed over on purpose;
--   * `scan_full` on a real tmp tree: the index reaches `ir.features` and the stale bullet becomes the
--     `feature-module-missing` finding;
--   * the page: the wiring pinned as text, and the arithmetic of the slice run in `node` (skipped without it).
-- The behaviour in a real window is TESTS/sheets/features-way-back.sheet.lua.

return function(H)
  local eq, ok = H.eq, H.ok
  local features = require("docmap.core.features")
  local docmap = require("docmap")

  local function dwrite(root, rel, text)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "features index spec: fixture must be writable")
    fd:write(text)
    fd:close()
  end

  -- ── A hand-built tree ────────────────────────────────────────────────────
  local function tree()
    local nodes = {
      ["lua/app"] = {
        path = "lua/app",
        source = "lua/app/init.lua",
        module = "app",
        functions = { { name = "M.setup" } },
        children = { "lua/app/core", "lua/app/win" },
      },
      ["lua/app/core"] = {
        path = "lua/app/core",
        children = { "lua/app/core/check.lua", "lua/app/core/precheck.lua" },
      },
      ["lua/app/core/check.lua"] = {
        path = "lua/app/core/check.lua",
        source = "lua/app/core/check.lua",
        module = "app.core.check",
        functions = { { name = "M.run" }, { name = "helper" }, { name = "M.helper" } },
        symbols = { { name = "M.LIMIT" } },
      },
      ["lua/app/core/precheck.lua"] = {
        path = "lua/app/core/precheck.lua",
        source = "lua/app/core/precheck.lua",
        functions = {},
      },
      -- A directory module whose functions live one file down.
      ["lua/app/win"] = {
        path = "lua/app/win",
        source = "lua/app/win/init.lua",
        functions = {},
        children = { "lua/app/win/scratch.lua", "lua/app/win/deep" },
      },
      ["lua/app/win/scratch.lua"] = {
        path = "lua/app/win/scratch.lua",
        source = "lua/app/win/scratch.lua",
        functions = { { name = "M.make_scratch" } },
      },
      -- ... and a function of the same name two levels down, which is not the one meant.
      ["lua/app/win/deep"] = {
        path = "lua/app/win/deep",
        children = { "lua/app/win/deep/far.lua" },
      },
      ["lua/app/win/deep/far.lua"] = {
        path = "lua/app/win/deep/far.lua",
        source = "lua/app/win/deep/far.lua",
        functions = { { name = "M.make_scratch" }, { name = "M.only_here" } },
      },
    }
    return {
      nodes = nodes,
      order = {
        "lua/app",
        "lua/app/core",
        "lua/app/core/check.lua",
        "lua/app/core/precheck.lua",
        "lua/app/win",
        "lua/app/win/scratch.lua",
        "lua/app/win/deep",
        "lua/app/win/deep/far.lua",
      },
    }
  end

  ---One theme file whose entries carry one `Module:` bullet each, at lines 10, 20, 30, …
  local function result_of(values)
    local entries = {}
    for i, value in ipairs(values) do
      entries[i] = {
        name = "Feature " .. i,
        line = i * 10,
        meta = { { key = "Module", value = value } },
        tab = false,
      }
    end
    return {
      folder = "docs/FEATURES",
      files = { { path = "docs/FEATURES/CORE.md", theme = "CORE", entries = entries } },
    }
  end

  local function lines_of(refs, key)
    local out = {}
    for _, r in ipairs((refs or {})[key] or {}) do
      out[#out + 1] = r.line
    end
    return table.concat(out, ",")
  end

  eq(features.index(nil, tree()), nil, "index: no features folder stays nil")

  do
    local r = features.index(
      result_of({
        "`core/check.lua` (`M.run`, `helper`, `M.LIMIT`, `opts.env`, `false`), `core/precheck.lua`", -- 10
        "`check.lua`", -- 20: the boundary — not precheck.lua
        "`app.core.check` (`run()`)", -- 30: the declared module name
        "`app.win` (`make_scratch`, `only_here`)", -- 40: a module name that is only a path; members below it
        '[`core/check.lua`](../../lua/app/core/check.lua) — `filetypes = {"x"}`', -- 50: a link, then prose
        "`app.setup`", -- 60: module.member as one dotted name
        "`lua\\app\\core\\check.lua`", -- 70: backslashes
      }),
      tree()
    )
    local refs = r.refs
    eq(
      lines_of(refs, "lua/app/core/check.lua"),
      "10,20,30,50,70",
      "index: a path suffix, the bare file name, the module name, a link and backslashes all reach the file"
    )
    eq(
      lines_of(refs, "lua/app/core/precheck.lua"),
      "10",
      "index: the suffix stops at a path boundary (check.lua is not precheck.lua), and a second file token is its own"
    )
    eq(
      lines_of(refs, "lua/app/core/check.lua#M.run"),
      "10,30",
      "index: a member, with or without M. and ()"
    )
    eq(
      lines_of(refs, "lua/app/core/check.lua#helper")
        .. "|"
        .. lines_of(refs, "lua/app/core/check.lua#M.helper"),
      "10|10",
      "index: a local and an exported function of one name are both filed"
    )
    eq(
      lines_of(refs, "lua/app/win"),
      "40",
      "index: a dotted name that is only a directory resolves as a path"
    )
    eq(
      lines_of(refs, "lua/app/win/scratch.lua#M.make_scratch"),
      "40",
      "index: a member the named module does not have is looked up in the files below it"
    )
    eq(
      lines_of(refs, "lua/app/win/deep/far.lua#M.make_scratch")
        .. "|"
        .. lines_of(refs, "lua/app/win/deep/far.lua#M.only_here"),
      "|40",
      "index: the nearest level with that name ends the search; a name found only further down is still found"
    )
    eq(lines_of(refs, "lua/app"), "60", "index: module.member files the module …")
    eq(lines_of(refs, "lua/app#M.setup"), "60", "index: … and the member")
    eq(
      r.unresolved,
      nil,
      "index: a constant, an option, a literal and prose after a link are passed over, never reported"
    )
  end

  -- What is reported, and what is deliberately not.
  do
    local root = H.tmpfile("_features_index_root")
    dwrite(root, "docs/install.json", "{}\n")
    local r = features.index(
      result_of({
        "`core/gone.lua` (`M.run`)", -- 10: a path of a language the map holds
        "`app.core.gone`", -- 20: a dotted name under a module of the map
        "`docs/install.json`", -- 30: a real file that is no module
        "`relay/nav.go`", -- 40: a language the map does not hold
        "`vim.fn.expand`, `other.nvim.thing`", -- 50: not this tree's
        "`:Cmd sub`, `<leader>x`", -- 60: not a path at all
      }),
      tree(),
      root
    )
    eq(r.refs, nil, "index: nothing resolved leaves refs off")
    local got = {}
    for _, u in ipairs(r.unresolved or {}) do
      got[#got + 1] = ("%s:%d %s (%s)"):format(u.file, u.line, u.text, u.feature)
    end
    eq(
      table.concat(got, " | "),
      "docs/FEATURES/CORE.md:10 core/gone.lua (Feature 1) | docs/FEATURES/CORE.md:20 app.core.gone (Feature 2)",
      "index: only a token that claims a place in this tree is reported, once, without its member list"
    )
  end

  -- The same bullet twice, and a key that is not `Module`.
  do
    local r = result_of({ "`core/check.lua`, `app.core.check`" })
    r.files[1].entries[1].meta[2] = { key = "Config", value = "`core/gone.lua`" }
    r.files[1].entries[1].meta[3] = { key = "module", value = "`core/precheck.lua`" }
    features.index(r, tree())
    eq(
      lines_of(r.refs, "lua/app/core/check.lua"),
      "10",
      "index: one feature is listed once per node"
    )
    eq(
      lines_of(r.refs, "lua/app/core/precheck.lua"),
      "10",
      "index: the key is matched without case"
    )
    eq(r.unresolved, nil, "index: only `Module` bullets are read")
    eq(
      r.files[1].entries[1].node,
      "lua/app/core/check.lua",
      "index: the entry keeps the first node it names, which is where its card links to"
    )
  end

  -- ── scan_full and the finding ────────────────────────────────────────────
  do
    local dr = H.tmpfile("_features_index_scan")
    dwrite(
      dr,
      "lua/t/init.lua",
      table.concat({
        "---@module 't'",
        "--- A trivial module.",
        "local M = {}",
        "--- Does the thing.",
        "function M.go() end",
        "return M",
      }, "\n")
    )
    dwrite(
      dr,
      "docs/FEATURES/CORE.md",
      table.concat({
        "## Going",
        "",
        "It goes.",
        "",
        "- **Module:** `t/init.lua` (`M.go`)",
        "",
        "## Gone",
        "",
        "- **Module:** `t/renamed.lua`",
        "",
      }, "\n")
    )
    local ir, findings =
      docmap.scan_full({ root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} })
    eq(lines_of(ir.features.refs, "lua/t"), "1", "scan_full: the module names its feature")
    eq(lines_of(ir.features.refs, "lua/t#M.go"), "1", "scan_full: so does the function")
    local hits = {}
    for _, f in ipairs(findings) do
      if f.check == "feature-module-missing" then
        hits[#hits + 1] = f.severity .. ": " .. require("docmap.core.findings").format(f)
      end
    end
    eq(
      table.concat(hits, " | "),
      "warn: docs/FEATURES/CORE.md:7 names 't/renamed.lua' as the module of 'Gone', "
        .. "but this tree has no such file or module",
      "check: a stale Module bullet is one warning that says where and what"
    )
    ok(
      docmap.to_json(ir):find('"refs":', 1, true) ~= nil,
      "to_json: the index rides in the artifact (the page has no file system to rebuild it from)"
    )
  end

  -- ── The page: wiring ─────────────────────────────────────────────────────
  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "features page: " .. msg)
  end
  has("if(feats.files.length > 1){", "one feature file gets no strip")
  has(
    '<div class="hview-toggle feat-themes" id="feattoggle" role="tablist" ',
    "the strip is the Analysis toolbar"
  )
  has(
    'navigate({ tab: "features", ftheme: b.dataset.ftheme });',
    "a sub-tab is a navigation (Back works)"
  )
  has(
    "if(s.ftheme && s.ftheme === featureTheme(s) && s.ftheme !== featureTheme(null)){",
    "the link carries the theme only when it exists and is not the first"
  )
  has('else if(k === "ftheme") s.ftheme = v;', "a link restores the theme")
  has(
    "esc(n.module || n.path)+docTrigger(n.id)+featTrigger(n.id)+markTrigger(n.id)",
    "the module trigger sits beside the path in the Tree tab's detail"
  )
  has(
    "var dref = docTrigger(key) + featTrigger(key);",
    "the function trigger sits with its prose references"
  )
  has("html = featRefsHTML(el.dataset.feat);", "the card is the annotation popup")
  has(
    "var nodeId = e.node || resolveModuleNode(e.meta);",
    "a feature card links where the index resolved it (module names included)"
  )
  has(
    'ev.target.closest("[data-sig],[data-doc],[data-feat]")',
    "the trigger opens on hover and on click like the other two"
  )
  has(
    "!(el.dataset.sig || el.dataset.doc || el.dataset.feat)",
    "Enter and Space open it from the keyboard"
  )
  has(".feat-group[hidden]{display:none}", "a hidden theme is not laid out")

  -- ── The page: arithmetic, in node ────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.05_features_help_index")
  local program = table.concat({
    "var listeners = {};",
    "var stub = new Proxy(function(){}, { get: function(t, k){",
    "  if(k === Symbol.toPrimitive) return function(){ return ''; };",
    "  return stub; }, apply: function(){ return stub; } });",
    "var document = { addEventListener: function(n, f){ listeners[n] = f; },",
    "  getElementById: function(){ return stub; }, querySelectorAll: function(){ return []; },",
    "  querySelector: function(){ return null; }, createElement: function(){ return stub; },",
    "  body: stub, documentElement: stub };",
    "var window = { addEventListener: function(){} };",
    "var navigated = [];",
    "function navigate(p){ navigated.push(JSON.stringify(p)); }",
    "function esc(s){ return String(s == null ? '' : s); } function prose(s){ return s; }",
    "function sigClose(){} function srcUrl(){ return null; } function rel(p){ return p; }",
    "function fenceHTML(c){ return c; }",
    "var state = { tab: 'features' };",
    "var IR = { nodes: [], features: { folder: 'docs/FEATURES', files: [",
    "  { path: 'docs/FEATURES/core.md', theme: 'core', entries: [",
    "    { name: 'Store', line: 3, summary: 'Keeps things.', meta: [], tab: false },",
    "    { name: 'Big', line: 9, meta: [], tab: true } ] },",
    "  { path: 'docs/FEATURES/UI.md', theme: 'UI', entries: [",
    "    { name: 'Title', line: 5, meta: [], tab: false },",
    "    { name: 'Border', line: 12, meta: [], tab: false } ] } ],",
    "  refs: { 'a.lua': [ { file: 'docs/FEATURES/core.md', line: 3 }, { file: 'docs/FEATURES/UI.md', line: 5 },",
    "                     { file: 'docs/FEATURES/UI.md', line: 99 } ],",
    "          'a.lua#M.f': [ { file: 'docs/FEATURES/core.md', line: 9 } ] } } };",
    slice,
    "var out = {};",
    "out.themeDefault = featureTheme(null);",
    "out.themeNamed = featureTheme({ ftheme: 'UI' });",
    "out.themeGone = featureTheme({ ftheme: 'renamed' });",
    "out.lineCore = featureCountLine(IR.features, 'core');",
    "out.lineUi = featureCountLine(IR.features, 'UI');",
    "out.lineOne = featureCountLine({ folder: 'docs/FEATURES.md', files: [ IR.features.files[1] ] }, 'UI');",
    "out.none = featTrigger('b.lua');",
    "out.two = featTrigger('a.lua');",
    "out.one = featTrigger('a.lua#M.f');",
    "out.card = featRefsHTML('a.lua');",
    "gotoFeature('docs/FEATURES/UI.md:5'); gotoFeature('docs/FEATURES/core.md:9'); gotoFeature('');",
    "gotoFeature('docs/FEATURES/UI.md:99');",
    "out.navigated = navigated;",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(
    result.code,
    0,
    "features page: the slice runs on its own — " .. vim.trim(result.stderr or "")
  )
  local got = vim.json.decode(result.stdout or "{}")

  eq(got.themeDefault, "core", "sub-tabs: the first file is the default")
  eq(got.themeNamed, "UI", "sub-tabs: a state names its theme")
  eq(got.themeGone, "core", "sub-tabs: a theme that no longer exists opens the first")
  eq(
    got.lineCore,
    "Core: 1 of 3 features across 2 files in <code>docs/FEATURES</code>.",
    "sub-tabs: the line says what is on screen; a promoted feature is counted nowhere"
  )
  eq(
    got.lineUi,
    "UI: 2 of 3 features across 2 files in <code>docs/FEATURES</code>.",
    "sub-tabs: per theme"
  )
  eq(
    got.lineOne,
    "2 features across 1 file in <code>docs/FEATURES.md</code>.",
    "sub-tabs: one file keeps the plain line"
  )
  eq(got.none, "", "trigger: nothing names it, nothing is rendered")
  ok(
    got.two:find('data-feat="a.lua"', 1, true)
      and got.two:find('aria-label="Described by 2 features"', 1, true)
      and got.two:find('<span class="docn">2</span>', 1, true),
    "trigger: a reference to a feature that is gone is not counted — " .. got.two
  )
  ok(
    got.one:find('aria-label="Described by 1 feature"', 1, true)
      and not got.one:find("docn", 1, true),
    "trigger: one feature shows no count"
  )
  ok(
    got.card:find('data-feat-goto="docs/FEATURES/core.md:3">Store</a>', 1, true)
      and got.card:find("Keeps things.", 1, true)
      and got.card:find(
        'data-feat-goto="docs/FEATURES/UI.md:5">Title</a><span class="bd">UI</span>',
        1,
        true
      )
      and got.card:find('data-feat-goto="">All features', 1, true),
    "card: each feature by name with its theme and summary, and the way to the tab — " .. got.card
  )
  eq(
    table.concat(got.navigated, " "),
    '{"tab":"features","ftheme":"UI"} {"tab":"feature-big"} {"tab":"features"}',
    "card: a feature opens its theme, a promoted one its own tab, the foot the tab; a dead key does nothing"
  )
end
