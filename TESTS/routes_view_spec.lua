-- TESTS/routes_view_spec.lua — file-based routing as a Hierarchy view: the Next.js `app` and `pages` conventions,
-- read off the paths of the scanned nodes (`core/endpoints.lua`, `file_routes`) and drawn as a tree.
--
-- Three parts:
--   * the recognition runs in Lua over hand-made trees of nodes, so it needs no parser: what is a route root, what a
--     segment is, which URL a route answers at, what is no route;
--   * the fixture TESTS/fixtures/routes_page is scanned for real when the tsx and typescript parsers are installed,
--     and the page rendered from it carries the route trees (skipped without the parsers);
--   * the page: the wiring is pinned as text, and the layout (which boxes, what each says, where a click leads) runs
--     in `node` with a small payload in place of the page (skipped without `node`).
-- The behaviour in a real window is TESTS/sheets/routes-view.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq
  local endpoints = require("docmap.core.endpoints")
  local cwd = (vim.fn.getcwd():gsub("\\", "/"))

  ---A tree of nodes as the scan leaves it: file nodes for the paths given, a namespace node for every directory
  ---on the way. `imports` maps a path to what that file requires from outside the map.
  ---@param paths string[]
  ---@param imports table<string, string[]>?
  ---@return Docmap.IR
  local function tree(paths, imports)
    local ir = { nodes = {}, order = {}, edges = {}, root = "", meta = {} }
    local function add(id, node)
      if not ir.nodes[id] then
        node.id = id
        ir.nodes[id] = node
        ir.order[#ir.order + 1] = id
      end
    end
    for _, path in ipairs(paths) do
      local dir = ""
      for part in path:gmatch("([^/]+)/") do
        dir = dir == "" and part or (dir .. "/" .. part)
        add(dir, { kind = "namespace", path = dir })
      end
      add(path, {
        kind = "file",
        path = path,
        source = path,
        requires_external = (imports or {})[path] or {},
      })
    end
    ---@diagnostic disable-next-line: return-type-mismatch
    return ir
  end

  ---The routes of a tree as lines, one per segment: indentation, segment, kind, URL, roles.
  local function lines(routes)
    if not routes then
      return "none"
    end
    local out = {}
    local function show(n, depth)
      local roles = {}
      for role in pairs(n.files) do
        roles[#roles + 1] = role
      end
      table.sort(roles)
      out[#out + 1] = ("%s%s %s %s%s {%s}"):format(
        ("  "):rep(depth),
        n.segment,
        n.kind,
        n.url or "-",
        n.handler and " handler" or "",
        table.concat(roles, ",")
      )
      for _, child in ipairs(n.children) do
        show(child, depth + 1)
      end
    end
    for _, root in ipairs(routes.roots) do
      out[#out + 1] = ("== %s %s %s %d"):format(
        root.dir,
        root.router,
        root.framework or "-",
        root.routes
      )
      show(root, 0)
    end
    return table.concat(out, "\n")
  end

  -- ── The App Router ───────────────────────────────────────────────────────
  local app = endpoints.file_routes(tree({
    "web/app/layout.tsx",
    "web/app/page.tsx",
    "web/app/(shop)/layout.tsx",
    "web/app/(shop)/cart/page.jsx",
    "web/app/blog/page.tsx",
    "web/app/blog/helpers.ts",
    "web/app/blog/[slug]/page.tsx",
    "web/app/blog/[slug]/loading.tsx",
    "web/app/blog/[slug]/not-found.tsx",
    "web/app/docs/[[...path]]/page.tsx",
    "web/app/files/[...rest]/page.tsx",
    "web/app/api/health/route.ts",
    "web/app/dash/page.tsx",
    "web/app/dash/@side/page.tsx",
    "web/app/dash/@side/deep/page.tsx",
    "web/app/feed/(.)photo/page.tsx",
    "web/app/_lib/page.tsx",
    "web/app/blog/_parts/page.tsx",
    "web/app/app/page.tsx",
    "web/app/pages/page.tsx",
    "web/app/notes/page.lua",
    "web/lib/util.ts",
  }, { ["web/app/page.tsx"] = { "react", "next/link" } }))
  eq(
    lines(app),
    table.concat({
      "== web/app app next 10",
      "web/app root / {layout,page}",
      "  (shop) group - {layout}",
      "    cart static /cart {page}",
      "  api static - {}",
      "    health static /api/health handler {route}",
      "  app static /app {page}",
      "  blog static /blog {page}",
      "    [slug] dynamic /blog/[slug] {loading,not-found,page}",
      "  dash static /dash {page}",
      "    @side slot - {page}",
      "      deep static - {page}",
      "  docs static - {}",
      "    [[...path]] optional /docs/[[...path]] {page}",
      "  feed static - {}",
      "    (.)photo intercept - {page}",
      "  files static - {}",
      "    [...rest] catchall /files/[...rest] {page}",
      "  pages static /pages {page}",
    }, "\n"),
    "routes: the App Router. A route is where a page or a route file is; a group is not in the URL; a slot and "
      .. "an interceptor are drawn without a URL and not counted; a private folder, a colocated helper and a file "
      .. "no JS backend reads are no route; of nested `app` directories the topmost is the root, and a `pages` "
      .. "below it is a segment"
  )
  eq(
    app.roots[1].children[4].children[1].node,
    "web/app/blog/[slug]",
    "routes: a segment knows the map's node of its directory"
  )
  eq(
    app.roots[1].children[4].children[1].files.loading,
    "web/app/blog/[slug]/loading.tsx",
    "routes: a role names the file's node"
  )
  eq(app.routes, 10, "routes: the total over all roots")

  local unlabelled = endpoints.file_routes(tree({ "app/page.tsx", "app/about/page.tsx" }))
  eq(
    lines(unlabelled),
    "== app app - 2\napp root / {page}\n  about static /about {page}",
    "routes: an `app` directory with page files is drawn without an import of next, and no framework is claimed"
  )
  eq(
    lines(endpoints.file_routes(tree({ "app/layout.tsx", "app/widgets/button.tsx" }))),
    "none",
    "routes: an `app` directory without a page or a route file is no route root"
  )

  -- ── The Pages Router ─────────────────────────────────────────────────────
  local pages_paths = {
    "pages/_app.tsx",
    "pages/_document.tsx",
    "pages/index.tsx",
    "pages/about.tsx",
    "pages/posts/index.tsx",
    "pages/posts/[id].tsx",
    "pages/docs/[...slug].js",
    "pages/api/ping.ts",
    "pages/api/users/[id].ts",
    "pages/app/x.tsx",
    "components/Nav.tsx",
  }
  local pages = endpoints.file_routes(tree(pages_paths))
  eq(
    lines(pages),
    table.concat({
      "== pages pages next 8",
      "pages root / {app,document,page}",
      "  about static /about {page}",
      "  api static - {}",
      "    ping static /api/ping handler {page}",
      "    users static - {}",
      "      [id] dynamic /api/users/[id] handler {page}",
      "  app static - {}",
      "    x static /app/x {page}",
      "  docs static - {}",
      "    [...slug] catchall /docs/[...slug] {page}",
      "  posts static /posts {page}",
      "    [id] dynamic /posts/[id] {page}",
    }, "\n"),
    "routes: the Pages Router. Every file is a route, `index` is its directory, `api/` holds handlers, `_app` "
      .. "and `_document` are noted on the root, and an `app` below `pages` is a segment, not a second root"
  )
  eq(
    lines(endpoints.file_routes(tree({ "src/pages/Home.tsx", "src/pages/Settings.tsx" }))),
    "none",
    "routes: a `pages` folder without `_app`, `_document` or an import of next routes nothing (a router library does)"
  )
  eq(
    lines(endpoints.file_routes(tree({ "src/pages/home.tsx" }, {
      ["src/pages/home.tsx"] = { "next/head" },
    }))),
    "== src/pages pages next 1\nsrc/pages root - {}\n  home static /home {page}",
    "routes: an import of next is evidence enough for a `pages` root"
  )

  -- a directory module (index.tsx is the directory's own node) and ids that begin with `./`
  local dotted = { nodes = {}, order = {}, edges = {}, root = ".", meta = {} }
  for _, n in ipairs({
    { id = ".", kind = "namespace", path = "." },
    {
      id = "./pages",
      kind = "module",
      path = "./pages",
      source = "pages/index.tsx",
      requires_external = { "next" },
    },
    {
      id = "./pages/_app.tsx",
      kind = "file",
      path = "./pages/_app.tsx",
      source = "pages/_app.tsx",
    },
    {
      id = "./pages/about.tsx",
      kind = "file",
      path = "./pages/about.tsx",
      source = "pages/about.tsx",
    },
  }) do
    dotted.nodes[n.id] = n
    dotted.order[#dotted.order + 1] = n.id
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  local from_dotted = endpoints.file_routes(dotted)
  eq(
    lines(from_dotted),
    "== pages pages next 2\npages root / {app,page}\n  about static /about {page}",
    "routes: the index file of a directory module is that directory's route"
  )
  eq(
    from_dotted.roots[1].node .. " " .. from_dotted.roots[1].files.page,
    "./pages ./pages",
    "routes: node ids are kept as the map has them"
  )

  eq(
    lines(endpoints.file_routes(tree({ "lua/app/init.lua", "lua/app/page.lua", "src/main.ts" }))),
    "none",
    "routes: a tree without the conventions has no route tree"
  )
  ---@diagnostic disable-next-line: param-type-mismatch
  eq(endpoints.file_routes({ nodes = {}, order = {} }), nil, "routes: an empty map has none")

  -- both routers side by side, sorted by directory
  local both =
    endpoints.file_routes(tree({ "src/pages/_app.tsx", "src/pages/old.tsx", "src/app/page.tsx" }))
  eq(
    both.roots[1].dir .. " " .. both.roots[2].dir .. " " .. both.routes,
    "src/app src/pages 2",
    "routes: an `app` and a `pages` directory are two trees"
  )

  -- the module reads no file: the standalone build runs it under the shim
  local src_lua = assert(H.slurp(cwd .. "/lua/docmap/core/endpoints.lua"))
  local body = src_lua:sub(assert(src_lua:find("function M.file_routes", 1, true)))
  ok(
    body:find("io%.open") == nil and body:find("vim%.") == nil,
    "routes: file_routes opens no file and uses nothing of the editor"
  )

  -- ── The fixture, scanned for real ────────────────────────────────────────
  local function has_parser(lang)
    local added_ok, added = pcall(vim.treesitter.language.add, lang)
    return added_ok and added
  end
  if has_parser("tsx") and has_parser("typescript") then
    local docmap = require("docmap")
    local opts =
      require("docmap.config").build(cwd .. "/TESTS/fixtures/routes_page", { source = "src" })
    local ir, findings = docmap.scan_full(opts)
    local scanned = endpoints.file_routes(ir)
    eq(
      lines(scanned),
      table.concat({
        "== src/app app next 8",
        "src/app root / {layout,page}",
        "  (marketing) group - {layout}",
        "    about static /about {page}",
        "  api static - {}",
        "    health static /api/health handler {route}",
        "  blog static /blog {page}",
        "    [slug] dynamic /blog/[slug] {loading,page}",
        "  dashboard static /dashboard {layout,page}",
        "    @stats slot - {page}",
        "  docs static - {}",
        "    [[...path]] optional /docs/[[...path]] {page}",
        "  photos static - {}",
        "    (.)view intercept - {page}",
        "  shop static - {}",
        "    [...filters] catchall /shop/[...filters] {page}",
        "== src/pages pages next 4",
        "src/pages root - {app}",
        "  api static - {}",
        "    ping static /api/ping handler {page}",
        "  legacy static /legacy {page}",
        "  posts static /posts {page}",
        "    [id] dynamic /posts/[id] {page}",
      }, "\n"),
      "routes fixture: the scanned Next.js tree has the twelve routes its directories hold"
    )
    local html = docmap.render.html(ir, findings, opts)
    local i = html:find('id="ir"', 1, true)
    local from = html:find(">", i, true) + 1
    local to = html:find("</script>", from, true) - 1
    local raw = html:sub(from, to):gsub("<" .. string.char(92) .. "/", "</")
    local payload = vim.json.decode(raw, { luanil = { object = true, array = true } })
    eq(
      type(payload.routes) == "table" and payload.routes.routes,
      12,
      "routes payload: the page carries the route trees"
    )
    eq(#payload.routes.roots, 2, "routes payload: one tree per router directory")
  else
    print("n/a  routes fixture: the tsx and typescript parsers are not installed")
  end
  -- a page of a tree without routes carries none (maps_page is Lua, so this needs no parser)
  do
    local docmap = require("docmap")
    local opts =
      require("docmap.config").build(cwd .. "/TESTS/fixtures/maps_page", { source = "lua/app" })
    local ir, findings = docmap.scan_full(opts)
    local html = docmap.render.html(ir, findings, opts)
    ok(
      html:find('"routes":', 1, true) == nil,
      "routes payload: a page of a tree without routes carries no `routes`"
    )
  end

  -- ── The wiring ───────────────────────────────────────────────────────────
  local src = H.html_source()
  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "routes: " .. msg)
  end
  has('data-view="routes" data-explain="view.routes">Routes</button>', "a Routes button")
  has("rings: 1, layers: 1, routes: 1, coupling: 1 };", "a known view")
  has('else if(view === "routes") built = layoutRoutes(hcenter);', "drawHierarchy hands it off")
  has('if(view === "routes") return routeBoxSpec(key);', "a segment's box is the view's own")
  has('"view.routes":', "the view explains itself")
  has(
    'routes = require("docmap.core.endpoints").file_routes(ir),',
    "the payload carries the route trees"
  )
  has("No file-based routes in this map.", "a map without routes says what the view reads")
  has(
    '<a href="#tab=hierarchy&view=routes">the Routes view of the Hierarchy</a> draws them.',
    "the Endpoints panel points at the view"
  )
  ok(
    src:find("unbuilt concept", 1, true) == nil,
    "routes: the Endpoints panel no longer calls file-based routing unbuilt"
  )
  ok(
    src:find(
      'function isAltView(v){ return v === "tree" || v === "treemap" || v === "coupling"; }',
      1,
      true
    ) ~= nil,
    "routes: it draws in the zooming diagram, with zoom and export"
  )

  -- ── The layout, in node ──────────────────────────────────────────────────
  if vim.fn.executable("node") == 0 then
    return
  end
  local slice = require("docmap.core.render.html.js.10b_maps")
  local program = table.concat({
    "var PAD = 20, BOX_W = 168, BOX_H = 52, GAP_X = 16, MAX_HNODES = 90;",
    "var IR = { nodes: [], edges: [], root: 'src' }, byId = {}, depOut = {}, depIn = {}, findByNode = {};",
    "['src', 'src/app', 'src/app/blog', 'src/app/blog/[slug]', 'src/app/page.tsx', 'src/app/blog/page.tsx',",
    " 'src/app/blog/[slug]/page.tsx', 'src/app/(shop)', 'src/app/api/health/route.ts', 'src/pages',",
    " 'src/pages/old.tsx'].forEach(function(id){ byId[id] = { id: id }; });",
    'var state = { tab: "hierarchy", view: "routes", hidden: [] };',
    "var hstage = { classList: { toggle: function(){} } }, hboxes = {};",
    "var haltBody = { addEventListener: function(){} }, haltBar = {};",
    "var document = { getElementById: function(){ return { addEventListener: function(){} }; } };",
    "function esc(s){ return String(s).replace(/</g, '&lt;'); } function navigate(){} function isHidden(){ return false; }",
    slice,
    "var out = {};",
    "out.none = layoutRoutes('src').count;",
    "function seg(segment, kind, dir, more){ var n = { segment: segment, kind: kind, dir: dir, files: {}, children: [] };",
    "  Object.keys(more || {}).forEach(function(k){ n[k] = more[k]; }); return n; }",
    "var slug = seg('[slug]', 'dynamic', 'src/app/blog/[slug]', { node: 'src/app/blog/[slug]', url: '/blog/[slug]',",
    "  files: { page: 'src/app/blog/[slug]/page.tsx', loading: 'gone.tsx' } });",
    "var blog = seg('blog', 'static', 'src/app/blog', { node: 'src/app/blog', url: '/blog',",
    "  files: { page: 'src/app/blog/page.tsx' }, children: [slug] });",
    "var shop = seg('(shop)', 'group', 'src/app/(shop)', { node: 'src/app/(shop)', files: { layout: 'l.tsx' } });",
    "var health = seg('health', 'static', 'src/app/api/health', { url: '/api/health', handler: true,",
    "  files: { route: 'src/app/api/health/route.ts' } });",
    "var api = seg('api', 'static', 'src/app/api', { children: [health] });",
    "var appRoot = seg('src/app', 'root', 'src/app', { node: 'src/app', url: '/', router: 'app', framework: 'next',",
    "  routes: 4, files: { page: 'src/app/page.tsx', layout: 'x.tsx' }, children: [shop, api, blog] });",
    "var old = seg('old', 'static', 'src/pages/old', { url: '/old', files: { page: 'src/pages/old.tsx' } });",
    "var pagesRoot = seg('src/pages', 'root', 'src/pages', { node: 'src/pages', router: 'pages', routes: 1,",
    "  children: [old] });",
    "IR.routes = { roots: [appRoot, pagesRoot], routes: 5 };",
    "routeIndex = null;",
    "var all = layoutRoutes('src');",
    "out.layers = all.layers.map(function(l){ return l.join(' '); }).join(' | ');",
    "out.count = all.count + '/' + all.truncated + '/' + all.centerKey;",
    "out.path = all.path;",
    "out.edges = all.edges.map(function(e){ return e.from.slice(6) + '>' + e.to.slice(6) + ':' + e.marker; }).join(' ');",
    "function spec(n){ var s = routeBoxSpec('route:' + n.dir); return [s.cls, s.html, s.title, s.nodeId, s.recenter].join(' ## '); }",
    "out.root = spec(appRoot); out.slug = spec(slug); out.shop = spec(shop); out.health = spec(health);",
    "out.api = spec(api); out.old = spec(old); out.pagesRoot = spec(pagesRoot);",
    "out.unknown = routeBoxSpec('route:nowhere');",
    -- a center inside a route tree shows that segment and what is below it, by its directory or by one of its files
    "var sub = layoutRoutes('src/app/blog');",
    "out.sub = sub.layers.map(function(l){ return l.join(' '); }).join(' | ') + ' ## ' + sub.centerKey + ' ## ' + sub.path;",
    "out.byFile = layoutRoutes('src/app/blog/[slug]/page.tsx').centerKey;",
    "out.byRootFile = layoutRoutes('src/app/page.tsx').centerKey;",
    "out.legend = routeLegend().length;",
    -- the cap of the diagram views holds here too
    "var wide = seg('src/app', 'root', 'src/app', { router: 'app', routes: 200 });",
    "for(var k = 0; k < 200; k++) wide.children.push(seg('p' + k, 'static', 'src/app/p' + k, { url: '/p' + k }));",
    "IR.routes = { roots: [wide], routes: 200 }; routeIndex = null;",
    "var capped = layoutRoutes('src');",
    "out.capped = capped.count + ' ' + capped.truncated;",
    "console.log(JSON.stringify(out));",
  }, "\n")
  local tmp = vim.fn.tempname() .. ".js"
  H.write(tmp, vim.split(program, "\n", { plain = true }))
  local result = vim.system({ "node", tmp }, { text = true }):wait()
  pcall(os.remove, tmp)
  eq(result.code, 0, "routes: the slice runs on its own — " .. vim.trim(result.stderr or ""))
  local got = vim.json.decode(result.stdout or "{}")

  eq(got.none, 0, "routes: a page without `routes` draws nothing (and says what the view reads)")
  eq(
    got.layers,
    "route:src/app route:src/pages | route:src/app/(shop) route:src/app/api route:src/app/blog route:src/pages/old"
      .. " | route:src/app/api/health route:src/app/blog/[slug]",
    "routes: with the center outside every route tree all trees are drawn, a layer per depth"
  )
  eq(got.count, "8/false/null", "routes: a forest has no middle")
  eq(got.path, "2 route trees · 5 routes", "routes: the path counts trees and routes")
  eq(
    got.edges,
    "src/app>src/app/(shop):tree src/app>src/app/api:tree src/app>src/app/blog:tree src/pages>src/pages/old:tree"
      .. " src/app/api>src/app/api/health:tree src/app/blog>src/app/blog/[slug]:tree",
    "routes: a segment is joined to what it contains"
  )
  eq(
    got.root,
    'hnode rt-root rt-route ## <div class="hnm">src/app</div><div class="hline">App Router · 4 routes</div>'
      .. " ## src/app\npage at /\nNext.js App Router\npage: src/app/page.tsx\nlayout: x.tsx"
      .. " ## src/app/page.tsx ## src/app",
    "routes: a root names its router and counts its routes; a click re-centers on its directory"
  )
  eq(
    got.slug,
    'hnode rt-dynamic rt-route ## <div class="hnm">[slug]</div><div class="hline">/blog/[slug]</div>'
      .. " ## src/app/blog/[slug]\npage at /blog/[slug]\ndynamic segment"
      .. "\npage: src/app/blog/[slug]/page.tsx\nloading: gone.tsx"
      .. " ## src/app/blog/[slug]/page.tsx ## src/app/blog/[slug]",
    "routes: a route says its segment as written and its URL; the tooltip lists its files"
  )
  eq(
    got.shop,
    'hnode rt-group ## <div class="hnm">(shop)</div><div class="hline">group · not in the URL</div>'
      .. " ## src/app/(shop)\nno route of its own: it holds layout\ngroup · not in the URL\nlayout: l.tsx"
      .. " ##  ## src/app/(shop)",
    "routes: a group says that it is none and what it holds; a file the map has no node for opens nothing"
  )
  eq(
    got.health,
    'hnode rt-static rt-route rt-handler ## <div class="hnm">health</div>'
      .. '<div class="hline">/api/health · handler</div>'
      .. " ## src/app/api/health\nrequest handler at /api/health\nroute: src/app/api/health/route.ts"
      .. " ## src/app/api/health/route.ts ## src/app/api/health/route.ts",
    "routes: a handler is told from a page; without a directory node a click centers on its file"
  )
  eq(
    got.api,
    'hnode rt-static ## <div class="hnm">api</div><div class="hline">segment</div>'
      .. " ## src/app/api\nno route of its own: it only groups what is below it ##  ## ",
    "routes: a plain directory on the way is a segment and no route"
  )
  eq(
    got.old,
    'hnode rt-static rt-route ## <div class="hnm">old</div><div class="hline">/old</div>'
      .. " ## src/pages/old\npage at /old\npage: src/pages/old.tsx ## src/pages/old.tsx ## src/pages/old.tsx",
    "routes: a file route of the Pages Router"
  )
  eq(
    got.pagesRoot,
    'hnode rt-root ## <div class="hnm">src/pages</div><div class="hline">Pages Router · 1 route</div>'
      .. " ## src/pages\nthe shape of a Next.js route directory; no file in it imports next"
      .. " ## src/pages ## src/pages",
    "routes: a root without evidence of the framework claims none; without a page it opens its directory"
  )
  eq(got.unknown, vim.NIL, "routes: a key that is no segment has no box")
  eq(
    got.sub,
    "route:src/app/blog | route:src/app/blog/[slug] ## route:src/app/blog ## src/app/blog · /blog · routes",
    "routes: a center inside a tree shows that segment and what is below it"
  )
  eq(
    got.byFile,
    "route:src/app/blog/[slug]",
    "routes: a center on a route's file finds its segment"
  )
  eq(got.byRootFile, "route:src/app", "routes: so does the root's own page")
  eq(got.legend, 3, "routes: the legend says what the marks mean")
  eq(got.capped, "90 true", "routes: the cap of the diagram views holds")
end
