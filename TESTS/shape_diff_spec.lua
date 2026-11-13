-- Test code: when something here comes back nil, this file must crash and name it.
---@diagnostic disable: need-check-nil, missing-fields
-- TESTS/shape_diff_spec.lua — two maps compared on the Hierarchy tab.
--
-- Two halves:
--   * `diff.shape` against hand-built maps: what is added, removed and moved, where a removed node is
--     anchored, and what is said when a map is too old to compare;
--   * the route `shape/<a>[/<b>]` of `core/api.lua`: what reaches git, and every way there is nothing to show.

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
end
