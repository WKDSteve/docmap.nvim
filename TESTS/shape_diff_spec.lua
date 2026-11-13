-- Test code: when something here comes back nil, this file must crash and name it.
---@diagnostic disable: need-check-nil, missing-fields
-- TESTS/shape_diff_spec.lua — two maps compared on the Hierarchy tab.
--
-- Four halves:
--   * `diff.shape` against hand-built maps: what is added, removed and moved, where a removed node is
--     anchored, and what is said when a map is too old to compare;
--   * the route `shape/<a>[/<b>]` of `core/api.lua`: what reaches git, and every way there is nothing to show;
--   * the page: the wiring pinned as text;
--   * the bar and the indexes of the page's own script, run in `node` (skipped without it).
-- The behaviour in a real window, against a real server, is TESTS/sheets/shape-diff.sheet.lua.

return function(H)
  local eq, ok = H.eq, H.ok
  local diff = require("docmap.core.diff")
  local api = require("docmap.core.api")

  ---A map of `ids` (a parent is the id up to its last `/`) with `requires` as `{ from, to, deferred? }`.
  local function map(schema, ids, requires)
    local nodes, order = {}, {}
    for _, id in ipairs(ids) do
      local parent = id:match("^(.*)/[^/]+$")
      nodes[id] = {
        id = id,
        path = id,
        module = id:gsub("%.lua$", ""):gsub("/", "."),
        parent = parent,
      }
      order[#order + 1] = id
    end
    local edges = {}
    for _, r in ipairs(requires or {}) do
      edges[#edges + 1] = { kind = "require", from = r[1], to = r[2], deferred = r[3] or false }
    end
    return { meta = { schema = schema }, nodes = nodes, order = order, edges = edges }
  end

  local function edge_list(list)
    local out = {}
    for _, e in ipairs(list) do
      out[#out + 1] = ("%s>%s%s%s"):format(
        e.from,
        e.to,
        e.deferred and " lazy" or "",
        e.changed and " changed" or ""
      )
    end
    return table.concat(out, " | ")
  end

  -- ── diff.shape ───────────────────────────────────────────────────────────
  local before = map(
    6,
    { "a", "a/x.lua", "a/old", "a/old/gone.lua", "a/old/deep.lua", "a/y.lua" },
    {
      { "a/x.lua", "a/y.lua" },
      { "a/x.lua", "a/old/gone.lua" },
      { "a/y.lua", "a/x.lua", true },
    }
  )
  local after = map(
    6,
    { "a", "a/x.lua", "a/y.lua", "a/new.lua" },
    { { "a/x.lua", "a/y.lua", true }, { "a/x.lua", "a/new.lua" }, { "a/y.lua", "a/x.lua", true } }
  )
  do
    local s = diff.shape(before, after)
    eq(table.concat(s.nodes_added, ","), "a/new.lua", "shape: a node only the newer map has")
    local removed = {}
    for _, n in ipairs(s.nodes_removed) do
      removed[#removed + 1] = ("%s (%s) from %s"):format(n.id, n.name, tostring(n.anchor))
    end
    eq(
      table.concat(removed, " | "),
      "a/old (a.old) from a | a/old/deep.lua (a.old.deep) from a | a/old/gone.lua (a.old.gone) from a",
      "shape: a removed node carries its name and the nearest ancestor the newer map still has"
    )
    eq(
      edge_list(s.deps_added),
      "a/x.lua>a/new.lua | a/x.lua>a/y.lua lazy changed",
      "shape: a new require, and one that only changed when it loads"
    )
    eq(
      edge_list(s.deps_removed),
      "a/x.lua>a/old/gone.lua",
      "shape: a require the newer map no longer has"
    )
    eq(s.deps_comparable, true, "shape: two current maps are comparable")
    eq(#s.reasons, 0, "shape: and there is nothing to explain")
    eq(s.schema.before .. "/" .. s.schema.after, "6/6", "shape: both schemas are reported")
    -- `compare` is the text side of the same answer: the two must count alike.
    local c = diff.compare(before, after)
    eq(#s.nodes_added, #c.nodes_added, "shape: counts nodes like compare (added)")
    eq(#s.nodes_removed, #c.nodes_removed, "shape: counts nodes like compare (removed)")
    eq(#s.deps_added, #c.deps_added, "shape: counts requires like compare (added)")
    eq(#s.deps_removed, #c.deps_removed, "shape: counts requires like compare (removed)")
  end

  do
    local s = diff.shape(after, after)
    eq(
      #s.nodes_added + #s.nodes_removed + #s.deps_added + #s.deps_removed,
      0,
      "shape: a map against itself changes nothing"
    )
  end

  -- A cycle that the change introduced.
  do
    local s = diff.shape(
      map(6, { "a", "a/x.lua", "a/y.lua" }, { { "a/x.lua", "a/y.lua" } }),
      map(6, { "a", "a/x.lua", "a/y.lua" }, { { "a/x.lua", "a/y.lua" }, { "a/y.lua", "a/x.lua" } })
    )
    eq(#s.cycles_added, 1, "shape: a load-time cycle the newer map introduced")
    ok(s.cycles_added[1]:find("a/x.lua", 1, true) ~= nil, "shape: named by its members")
  end

  -- Schema 1 has no require graph: on either side, the edges are not compared and the answer says so.
  do
    local old = map(1, { "a", "a/x.lua" }, {})
    local s = diff.shape(old, after)
    eq(
      s.deps_comparable,
      false,
      "shape: an older map of schema 1 is not comparable in its requires"
    )
    eq(#s.deps_added + #s.deps_removed, 0, "shape: so no require is reported, in either direction")
    ok(
      s.reasons[1]:find("the older map predates the dependency graph (schema 1)", 1, true) ~= nil,
      "shape: and the reason names the side and the schema — " .. tostring(s.reasons[1])
    )
    eq(
      table.concat(s.nodes_added, ","),
      "a/new.lua,a/y.lua",
      "shape: nodes are still compared: ids are in every schema"
    )
    local r = diff.shape(after, old)
    eq(r.deps_comparable, false, "shape: the same holds when the too-old map is the newer side")
    ok(r.reasons[1]:find("the newer map", 1, true) ~= nil, "shape: and the reason says which side")
    -- A schema-1 map that does carry requires is one whose number is merely unset: compared.
    local unset = map(nil, { "a", "a/x.lua", "a/y.lua" }, { { "a/x.lua", "a/y.lua" } })
    eq(
      diff.shape(unset, after).deps_comparable,
      true,
      "shape: the rule is compare's own (no schema and no requires), not the number alone"
    )
  end

  -- ── The route ────────────────────────────────────────────────────────────
  ---A map as a committed artifact holds it: the nodes as a list, in order.
  local function artifact(ir)
    local nodes = {}
    for i, id in ipairs(ir.order) do
      nodes[i] = ir.nodes[id]
    end
    return vim.json.encode({ meta = ir.meta, root = ir.order[1], nodes = nodes, edges = ir.edges })
  end
  local asked = {}
  local function fake_git(maps)
    return function(_, args)
      asked[#asked + 1] = table.concat(args, " ")
      if args[1] ~= "show" then
        return nil, "unexpected"
      end
      local sha = args[2]:match("^(%x+):docs/map/module_map%.json$")
      local ir = sha and maps[sha]
      if not ir then
        return nil, "no such object"
      end
      return artifact(ir)
    end
  end
  local OLD, NEW = ("a"):rep(40), ("b"):rep(7)
  local opts = {
    root = H.tmpfile("_shape_root"),
    out_dir = "docs/map",
    git = fake_git({ [OLD] = before, [NEW] = after }),
  }

  do
    local res, err = api.answer(("shape/%s/%s"):format(OLD, NEW), opts, nil)
    eq(err, nil, "route: two commits are a route")
    eq(res.available, true, "route: and answer")
    eq(
      res.before.sha .. " " .. res.after.sha .. " " .. tostring(res.after.current),
      OLD .. " " .. NEW .. " false",
      "route: the answer says which two maps it compared"
    )
    eq(table.concat(res.nodes_added, ","), "a/new.lua", "route: the shape is diff.shape's")
    eq(#res.nodes_removed, 3, "route: removed nodes ride along with their names")
    ok(
      type(res.text) == "table"
        and res.text[1]:find("Structural diff against aaaaaaaa..bbbbbbb", 1, true) ~= nil,
      "route: the same change as `:DocMap diff` prints it — "
        .. tostring(res.text and res.text[1])
    )
    eq(
      table.concat(asked, " | "),
      ("show %s:docs/map/module_map.json | show %s:docs/map/module_map.json"):format(OLD, NEW),
      "route: git is asked for exactly the two committed maps"
    )
    -- `compare` walks the blast radius of every node of both maps; one answer needs it once.
    local real_compare, calls = diff.compare, 0
    diff.compare = function(...)
      calls = calls + 1
      return real_compare(...)
    end
    local again = api.answer(("shape/%s/%s"):format(OLD, NEW), opts, nil)
    diff.compare = real_compare
    eq(calls, 1, "route: the two maps are compared once for the graph and the text together")
    eq(#again.cycles_added, 0, "route: and the cycles of that one comparison are the answer's")
  end

  -- One commit: the newer side is the map on disk, which is the one the page shows.
  do
    local without = api.answer("shape/" .. OLD, opts, nil)
    eq(without.available, false, "route: no map on disk is nothing to compare with")
    ok(type(without.reason) == "string" and without.reason ~= "", "route: and says so")
    vim.fn.mkdir(opts.root .. "/docs/map", "p")
    H.write(opts.root .. "/docs/map/module_map.json", { artifact(after) })
    local res = api.answer("shape/" .. OLD, opts, nil)
    eq(res.available, true, "route: one commit compares against the map on disk")
    eq(res.after.current, true, "route: and the answer says that the newer side is this map")
    eq(res.after.sha, nil, "route: which has no sha")
    eq(#res.deps_removed, 1, "route: with the same shape")
  end

  -- Nothing but hex reaches git.
  asked = {}
  for _, name in ipairs({
    "shape/not-a-sha",
    "shape/" .. OLD .. "/HEAD",
    "shape/HEAD/" .. OLD,
    "shape/" .. OLD .. "/",
    "shape/" .. OLD .. "//" .. NEW,
    "shape/" .. OLD .. "/" .. NEW .. "/" .. NEW,
    "shape/" .. OLD .. ".." .. NEW,
    "shape/--upload-pack=x",
    "shape/abc",
    "shape/",
  }) do
    local res, err = api.answer(name, opts, nil)
    eq(res, nil, "route: " .. name .. " is no comparison")
    ok(type(err) == "string" and err ~= "", "route: " .. name .. " is refused with a reason")
  end
  eq(#asked, 0, "route: none of them reached git")

  do
    local res = api.answer("shape/" .. ("c"):rep(8), opts, nil)
    eq(res.available, false, "route: a commit without a map is nothing to show, not an error")
    ok(
      res.reason:find("no map is committed at cccccccc", 1, true) ~= nil,
      "route: and names the commit — " .. res.reason
    )
    local other = api.answer(("shape/%s/%s"):format(OLD, ("c"):rep(8)), opts, nil)
    ok(
      other.available == false and other.reason:find("cccccccc", 1, true) ~= nil,
      "route: the newer side can be the one without a map"
    )
    local no_git = api.answer("shape/" .. OLD, { root = opts.root, out_dir = "docs/map" }, nil)
    ok(
      no_git.available == false and no_git.reason == "no git access configured",
      "route: a host without git says so"
    )
    local _, unknown = api.answer("no-such-route", opts, nil)
    ok(unknown:find("shape/<sha>", 1, true) ~= nil, "route: the list of routes names it")
  end

  -- Real git, real history: this repository's own map at HEAD against the one on disk.
  do
    local real_root = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]TESTS[/\\]")) or "."
    local real = { root = real_root, out_dir = "docs/map" }
    real.git = function(o, args)
      local cmd = { "git" }
      vim.list_extend(cmd, args)
      local proc = vim.system(cmd, { cwd = o.root, text = true }):wait()
      if proc.code ~= 0 then
        return nil, vim.trim(proc.stderr or "git failed")
      end
      return proc.stdout or ""
    end
    local head = vim.trim(real.git(real, { "rev-parse", "HEAD" }) or "")
    if api.safe_sha(head) then
      local res = api.answer("shape/" .. head, real, nil)
      ok(type(res) == "table", "route: a real commit answers with a table")
      if res.available then
        ok(
          type(res.nodes_added) == "table" and type(res.deps_removed) == "table",
          "route: a real comparison carries its lists"
        )
        eq(res.deps_comparable, true, "route: this repository's own maps are comparable")
      end
    end
  end

  -- ── The page: wiring ─────────────────────────────────────────────────────
  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "shape page: " .. msg)
  end
  has(
    '<button id="hshapebtn" aria-pressed="false" aria-controls="hshape" data-explain="hier.shape">',
    "one button in the Hierarchy controls, explained like the others"
  )
  has(
    '<div id="hshape" class="hshape" role="group" aria-labelledby="hshape-label" hidden></div>',
    "its bar exists only while it is on"
  )
  has("cmp: null,", "the comparison is one axis of the state, off by default")
  has('if(s.cmp) parts.push("cmp=" + encodeURIComponent(s.cmp));', "the link carries it")
  has('else if(k === "cmp") s.cmp = shapeSpec(v);', "a link restores it, and only as commit hashes")
  has("syncShape(s);", "it is painted after every draw")
  has(
    "shapeForget(spec);\n    navigate({ cmp: spec });",
    "choosing a comparison that failed before asks the host again"
  )
  has(
    "if(list) list.scrollTop = scrolled;",
    "rebuilding the bar leaves the list scrolled where it was"
  )
  has(
    "paintShape(state.cmp ? shapeOf(state.cmp) : null);",
    "also after the draw the search preview does on its own"
  )
  has(
    'fetch("/api/shape/" + spec.replace("..", "/"))',
    "the comparison is the host's, not the page's; the route has no `..` in it"
  )
  has(
    "if(histCommits && histCommits.length){ shapeCommits = histCommits; return; }",
    "the commits are the History tab's list"
  )
  has('fetch("/api/commits?n=100")', "asked the way History asks")
  has(
    "if(!historyAvailable()){ shapeCache[spec] = { error: shapeFileMessage() }; return; }",
    "a page that cannot fetch says so in place"
  )
  has(
    'explainFetchFailure(e, "the comparison")',
    "a host that does not answer is explained like History's"
  )
  has(
    'p.setAttribute("class", "hedge hedge-dep sd-del");',
    "a lost require is drawn, not listed only"
  )
  has(
    'p.setAttribute("d", edgePath(shapeBoxPos(a), shapeBoxPos(b)));',
    "between the boxes where they already are"
  )
  has("#hstage.sd-on .hnode.sd-same{opacity:.5}", "what did not change is dimmed, not removed")
  has(".hnode.sd-added{border-color:var(--file);", "an added node is framed")
  has(".hedge.sd-del{stroke:var(--error);", "a lost require has the colour of removal")
  ok(
    not src:find("function layoutShape", 1, true) and not src:find("reconcile(shape", 1, true),
    "shape page: the comparison lays nothing out"
  )

  -- ── The page: the bar and the indexes, in node ───────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.11_quicks_compare_init")
  local a = assert(slice:find("  var shapeBar = document.getElementById", 1, true))
  local b = assert(
    slice:find(
      "  // =====================================================================\n  // Initial load",
      a,
      true
    )
  )
  local program = table.concat({
    "var stub = new Proxy(function(){}, { get: function(t, k){",
    "  if(k === Symbol.toPrimitive) return function(){ return ''; };",
    "  return stub; }, apply: function(){ return stub; } });",
    "var document = { getElementById: function(){ return stub; }, activeElement: null,",
    "  createElement: function(){ return stub; }, createElementNS: function(){ return stub; } };",
    "var location = { protocol: 'http:' };",
    "var navigated = [];",
    "function navigate(p){ navigated.push(JSON.stringify(p)); }",
    "function esc(s){ return String(s == null ? '' : s).replace(/[&<>\"]/g, function(c){",
    "  return {'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c]; }); }",
    "function own(o, k){ return !!o && Object.prototype.hasOwnProperty.call(o, k); }",
    "function historyAvailable(){ return location.protocol === 'http:'; }",
    "function explainFetchFailure(){ return { then: function(){} }; }",
    "function edgePath(){ return ''; }",
    "var histCommits = null, hstage = stub, hboxes = {}, fnByKey = {};",
    "var state = { tab: 'hierarchy', view: 'deps', cmp: null };",
    "var byId = { 'a': { id: 'a', path: 'a' }, 'a/x.lua': { id: 'a/x.lua', module: 'a.x', path: 'a/x.lua' },",
    "             'a/new.lua': { id: 'a/new.lua', module: 'a.new', path: 'a/new.lua' } };",
    slice:sub(a, b - 1),
    "var out = {};",
    "out.specs = ['abcdef0', 'ABCDEF0123', 'abcdef0..1234567', 'abcdef', 'abcdef0..', 'abcdef0...1234567',",
    "  'HEAD', 'abcdef0..HEAD', 'abcdef0;x', '', null].map(shapeSpec);",
    "out.sides = shapeSides('abcdef0..1234567');",
    "out.side = shapeSides('abcdef0');",
    "var d = shapeIndex({ available: true, deps_comparable: true, after: { current: false },",
    "  nodes_added: ['a/new.lua', 'gone/now.lua'],",
    "  nodes_removed: [ { id: 'a/old.lua', name: 'a.old', anchor: 'a' }, { id: 'a/old2.lua', name: 'a.old2', anchor: 'a' },",
    "                   { id: 'z.lua', name: 'z' } ],",
    "  deps_added: [ { from: 'a/x.lua', to: 'a/new.lua', deferred: false },",
    "                { from: 'a/x.lua', to: 'a', deferred: false, changed: true } ],",
    "  deps_removed: [ { from: 'a/x.lua', to: 'a/old.lua', deferred: true } ],",
    "  cycles_added: {}, cycles_removed: {}, reasons: {}, text: ['Structural diff against abcdef0', '<b>'] });",
    "out.added = Object.keys(d._added);",
    "out.lostAt = d._lostAt;",
    "out.edge = Object.keys(d._edge);",
    "out.touched = Object.keys(d._touched).sort();",
    "out.cycles = d.cycles_added;",
    "shapeCommits = [ { sha: 'abcdef0123456789abcdef0123456789abcdef01', short: 'abcdef0', date: '2026-01-02',",
    "                   subject: 'one <b> ' + new Array(80).join('x') },",
    "                 { sha: '1234567123456712345671234567123456712345', short: '1234567', date: '2026-01-01', subject: 'two' } ];",
    "shapeCache['abcdef0'] = d;",
    "out.bar = shapeBarHTML({ cmp: 'abcdef0', tab: 'hierarchy' });",
    "shapeListOpen = true;",
    "out.barOpen = shapeBarHTML({ cmp: 'abcdef0', tab: 'hierarchy' });",
    "shapeListOpen = false; shapeOpen = true;",
    "out.barIdle = shapeBarHTML({ cmp: null, tab: 'hierarchy' });",
    "shapeCache['fffffff'] = { loading: true };",
    "out.barLoading = shapeBarHTML({ cmp: 'fffffff', tab: 'hierarchy' });",
    "shapeCache['eeeeeee'] = shapeIndex({ available: true, deps_comparable: false, after: { current: true },",
    "  reasons: ['Requires and cycles are not compared: the older map predates the dependency graph (schema 1).'] });",
    "out.barOld = shapeBarHTML({ cmp: 'eeeeeee', tab: 'hierarchy' });",
    "shapeCache['ddddddd'] = shapeIndex({ available: true, deps_comparable: true, after: { current: true } });",
    "out.barNone = shapeBarHTML({ cmp: 'ddddddd', tab: 'hierarchy' });",
    "var many = []; for(var i = 0; i < 45; i++) many.push('n' + i);",
    "out.long = shapeListHTML(shapeIndex({ available: true, nodes_added: many }));",
    "location.protocol = 'file:'; shapeCommits = null; shapeLoadCommits();",
    "out.barFile = shapeBarHTML({ cmp: null, tab: 'hierarchy' });",
    "shapeFetch('ccccccc'); out.fileFetch = shapeCache['ccccccc'].error;",
    "shapeForget('ccccccc'); shapeForget('abcdef0'); shapeForget('never'); shapeForget(null);",
    "out.forgot = [own(shapeCache, 'ccccccc'), own(shapeCache, 'abcdef0')];",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(
    result.code,
    0,
    "shape page: the section runs on its own — " .. vim.trim(result.stderr or "")
  )
  local got = vim.json.decode(result.stdout or "{}", { luanil = { object = true, array = true } })

  local function count(text, needle)
    local n, from = 0, 1
    while true do
      local s, e = text:find(needle, from, true)
      if not s then
        return n
      end
      n, from = n + 1, e + 1
    end
  end

  eq(
    vim.inspect(got.specs),
    vim.inspect({ "abcdef0", "abcdef0123", "abcdef0..1234567" }),
    "spec: one or two commit hashes of at least seven digits, lower-cased; everything else is no comparison"
  )
  eq(got.sides.a .. " " .. got.sides.b, "abcdef0 1234567", "spec: the older side comes first")
  eq(got.side.a .. "|" .. got.side.b, "abcdef0|", "spec: one hash is against this map")
  eq(table.concat(got.added, ","), "a/new.lua,gone/now.lua", "index: added nodes by id")
  eq(
    table.concat(got.lostAt.a, ","),
    "a.old,a.old2",
    "index: removed nodes by the place they were removed from; one without a place is in the list only"
  )
  eq(
    table.concat(got.edge, ","),
    "a/x.lua a/new.lua,a/x.lua a",
    "index: gained requires by the pair an edge of the diagram carries"
  )
  eq(
    table.concat(got.touched, ","),
    "a,a/new.lua,a/old.lua,a/x.lua",
    "index: both ends of every changed require stay undimmed"
  )
  eq(#got.cycles, 0, "index: an empty object from the host is an empty list")

  ok(
    got.bar:find('<option value="abcdef0123456789abcdef0123456789abcdef01" selected>', 1, true)
      and got.bar:find("abcdef0 · 2026-01-02 · one &lt;b&gt; ", 1, true)
      and got.bar:find("…</option>", 1, true),
    "bar: the older side is chosen from the commits, subject escaped and cut"
  )
  ok(
    got.bar:find('<select id="hshape-b" aria-label="The newer map">', 1, true)
      and got.bar:find('<option value="">this map</option>', 1, true),
    "bar: the newer side defaults to this map"
  )
  ok(
    got.bar:find('<span class="sd-count sd-plus">+2 nodes</span>', 1, true)
      and got.bar:find('<span class="sd-count sd-minus">−3 nodes</span>', 1, true)
      and got.bar:find('<span class="sd-count sd-plus">+2 requires</span>', 1, true)
      and got.bar:find('<span class="sd-count sd-minus">−1 require</span>', 1, true),
    "bar: four counts, each in the colour of its marks — " .. got.bar
  )
  ok(
    got.bar:find('<button type="button" id="hshape-list" aria-expanded="false"', 1, true)
      and got.bar:find('<div id="hshape-body" class="sd-body" hidden></div>', 1, true),
    "bar: the list is folded until asked for, and costs nothing while it is"
  )
  ok(
    got.bar:find("Marked on the map this page shows.", 1, true),
    "bar: comparing two commits says which map the marks are on"
  )
  ok(got.bar:find(">End comparison</button>", 1, true), "bar: the way out is in the bar")
  ok(
    got.barOpen:find('aria-expanded="true"', 1, true)
      and got.barOpen:find(
        '<button type="button" class="sd-chip" data-sd-center="a/new.lua">a.new</button>',
        1,
        true
      )
      and got.barOpen:find('<span class="sd-gone">gone/now.lua</span>', 1, true),
    "list: a node of this map is a way to it, one this map does not have is only named"
  )
  ok(
    got.barOpen:find(
      '<span class="sd-gone">a.old</span> <span class="sd-under">from <button type="button" class="sd-chip" data-sd-center="a">a</button></span>',
      1,
      true
    ),
    "list: a removed node says where it was removed from"
  )
  ok(
    got.barOpen:find("was lazy, now at load time", 1, true)
      and got.barOpen:find('<span class="sd-under">lazy</span>', 1, true),
    "list: a require says when it loads, and when that is what changed"
  )
  ok(
    got.barOpen:find("Structural diff against abcdef0\n&lt;b&gt;</pre>", 1, true),
    "list: the text of `:DocMap diff` rides along, escaped"
  )
  ok(
    got.barIdle:find("choose a commit…", 1, true)
      and got.barIdle:find(">Close</button>", 1, true)
      and not got.barIdle:find("sd-count", 1, true),
    "bar: open without a comparison it offers the choice and nothing else"
  )
  ok(
    got.barLoading:find("Comparing…", 1, true)
      and got.barLoading:find('<option value="fffffff" selected>fffffff</option>', 1, true),
    "bar: a commit the list does not reach is still the selected one, and waiting is said"
  )
  ok(
    got.barOld:find(
      '<div class="sd-note">Requires and cycles are not compared: the older map predates the dependency graph (schema 1).</div>',
      1,
      true
    ) and count(got.barOld, "sd-count") == 2,
    "bar: what cannot be compared is said, and its counts are not shown as zero — " .. got.barOld
  )
  ok(
    got.barNone:find("No node and no require differs between the two maps.", 1, true)
      and not got.barNone:find("hshape-list", 1, true),
    "bar: no difference is an answer"
  )
  eq(count(got.long, "<li>"), 40, "list: a section is cut")
  ok(got.long:find("… and 5 more", 1, true), "list: and says by how much")
  ok(
    got.barFile:find("This page was opened from a file", 1, true)
      and not got.barFile:find("<select", 1, true),
    "bar: opened from a file it says why there is nothing to choose from"
  )
  ok(
    got.fileFetch:find("opened from a file", 1, true),
    "a link that carries a comparison says the same on a file page"
  )
  eq(
    vim.inspect(got.forgot),
    vim.inspect({ false, true }),
    "a comparison that failed is forgotten when asked again; an answer is kept"
  )
end
