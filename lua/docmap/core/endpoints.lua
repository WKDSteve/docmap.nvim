---@module 'docmap.core.endpoints'
--- Routes, both halves of `docs/ecosystem.md` §3.1's split.
---
--- **Call-based** route registrations — Express/Fastify/Koa-shaped
--- `app.get(path, handler)` calls — are recognized in an already-parsed
--- JS/TS/TSX tree (`extract`, below) and listed by the Endpoints panel.
---
--- **File-based** routing is the other half and deliberately not a list: a
--- route's parent directory carries real structure there, and flattening it
--- would lose the fact worth showing. `file_routes`, at the end of this file,
--- reads the Next.js `app` and `pages` conventions off the paths of the
--- scanned nodes and returns route trees for the Routes view of the
--- Hierarchy; its recognition rule is stated there.
---
--- ## What is recognized, stated narrowly
---
--- `IDENTIFIER.METHOD("/path", ...handler)` where METHOD is a lowercase HTTP
--- verb (`get`/`post`/`put`/`delete`/`patch`/`options`/`head`) or `all`, and
--- the first argument is a string literal starting with `/`. Nothing checks
--- what IDENTIFIER is bound to — the same reasoning `core/plugins.lua`'s
--- `looks_like_repo` gives for a bare-string heuristic: a call shaped exactly
--- like a route registration, with a path-shaped first argument, is already
--- a narrow and specific signal, and requiring a verified `express()`/
--- `Router()` binding first would trade a real, cheap recognizer for a
--- variable-flow analysis this repository does not otherwise do anywhere.
--- The accepted risk, stated rather than hidden: an unrelated object whose
--- own `.get(path, handler)`-shaped method happens to match (a cache, a
--- router-like abstraction) would false-positive — not verified against a
--- real Express application; `docs/ecosystem.md`'s own stated limit ("every
--- framework-syntax claim above is unverified") still applies here.
---
--- `app.use(...)` is not recognized: `use` is not in the method set, since it
--- mounts middleware — optionally with no path at all — rather than
--- registering one route.
---
--- With more than two arguments (middleware chained before the final
--- handler, `app.post(path, authMiddleware, createUser)`), the *last*
--- argument is taken as the handler — the one that actually produces the
--- response, which is the one worth a reader's attention; the middleware
--- before it is real but not this recognizer's concern.
---
--- ## What "framework" means here
---
--- Not guessed from the call shape — Express, Fastify and Koa (via
--- `koa-router`) all accept the identical `app.get(path, handler)` shape, so
--- nothing about the call itself says which one it is. Read instead from
--- this file's own already-extracted `requires`: if the file required
--- `express`/`fastify`/`koa`/`koa-router`/`connect`/`restify`/`hapi`/
--- `@hapi/hapi`, every route in it is labelled with that package;
--- otherwise `framework` is `nil` — the call shape matched, but nothing
--- here claims to know whose convention it is.
---
--- ## What "documented" means
---
--- True only when the handler is a *named* reference (`getUser`, not an
--- inline `function(req, res) {...}` or arrow expression) that resolves to
--- one of this same file's own scanned functions with a non-empty summary.
--- An inline handler has no separate declaration to check, so it is
--- `false` — not "unknown" pretending to be "undocumented."

local M = {}

local HTTP_METHODS = {
  get = true,
  post = true,
  put = true,
  delete = true,
  patch = true,
  options = true,
  head = true,
  all = true,
}

local FRAMEWORK_BY_IMPORT = {
  express = "express",
  fastify = "fastify",
  koa = "koa",
  ["koa-router"] = "koa",
  connect = "connect",
  restify = "restify",
  hapi = "hapi",
  ["@hapi/hapi"] = "hapi",
}

---Parsed queries are per-grammar, same reason `core/lang/ecma.lua` caches
---its own call/identifier queries this way (there, via `lib.lua.memo`).
---@param lang string
local route_query = require("lib.lua.memo").fn(function(lang)
  return vim.treesitter.query.parse(
    lang,
    [[
    (call_expression
      function: (member_expression
        property: (property_identifier) @method)
      arguments: (arguments) @args) @call
    ]]
  )
end, { size = 8 })

---@param requires Docmap.RawRequire[]
---@return string?
local function detect_framework(requires)
  for _, r in ipairs(requires or {}) do
    local known = FRAMEWORK_BY_IMPORT[r.module]
    if known then
      return known
    end
  end
  return nil
end

---@param fns Docmap.FunctionInfo[]
---@return table<string, Docmap.FunctionInfo>
local function index_by_name(fns)
  local by_name = {}
  for _, fn in ipairs(fns) do
    by_name[fn.name] = fn
  end
  return by_name
end

---Every call-based route registration in an already-parsed JS/TS/TSX tree.
---@param root TSNode
---@param src string
---@param lang string
---@param fns Docmap.FunctionInfo[] This file's own already-scanned functions, for the `documented` cross-reference.
---@param requires Docmap.RawRequire[] This file's own already-extracted imports, for `framework`.
---@return Docmap.EndpointSpec[]
function M.extract(root, src, lang, fns, requires)
  local framework = detect_framework(requires)
  local by_name = index_by_name(fns)
  local out = {}

  local query = route_query(lang)
  local id_by_name = {}
  for id, name in ipairs(query.captures) do
    id_by_name[name] = id
  end

  for _, match in query:iter_matches(root, src) do
    local method_nodes = match[id_by_name.method]
    local args_nodes = match[id_by_name.args]
    local call_nodes = match[id_by_name.call]
    local method_node = method_nodes and method_nodes[1]
    local args_node = args_nodes and args_nodes[1]
    local call_node = call_nodes and call_nodes[1]

    if method_node and args_node and call_node then
      local method = vim.treesitter.get_node_text(method_node, src)
      if HTTP_METHODS[method] then
        local path_node = args_node:named_child(0)
        if path_node and path_node:type() == "string" then
          local content = path_node:named_child(0)
          local path = content and vim.treesitter.get_node_text(content, src)
          if path and path:sub(1, 1) == "/" then
            local n = args_node:named_child_count()
            local handler_node = n >= 2 and args_node:named_child(n - 1) or nil
            local handler = handler_node
                and handler_node:type() == "identifier"
                and vim.treesitter.get_node_text(handler_node, src)
              or nil

            local srow = call_node:range()
            out[#out + 1] = {
              method = method,
              path = path,
              handler = handler,
              line = srow + 1,
              framework = framework,
              documented = (
                handler ~= nil
                and by_name[handler] ~= nil
                and by_name[handler].summary ~= ""
              ),
            }
          end
        end
      end
    end
  end

  table.sort(out, function(a, b)
    return a.line < b.line
  end)
  return out
end

-- =====================================================================
-- File-based routing: the other half
-- =====================================================================
--
-- A call-based route is one line in one file; a file-based route is a
-- place in a directory tree, and what a reader wants from it is the tree:
-- which segment nests in which, what a layout wraps, where the dynamic
-- parts are. So this half is not found per file during the parse. It reads
-- the paths of the nodes the scan already has and returns route trees, which
-- the Routes view of the page's Hierarchy draws. No file is opened here.
--
-- ## What is recognized: the Next.js conventions, both routers
--
-- **App Router.** A directory named `app` is a route root when a file named
-- `page` or `route` (`.js`, `.jsx`, `.ts`, `.tsx`) lies in or below it. Of
-- several nested `app` directories the topmost is the root. Below it:
--
--   * a route exists where a `page` (a page) or a `route` (a request handler)
--     is; `layout`, `template`, `loading`, `error`, `global-error`,
--     `not-found`, `default`, `forbidden` and `unauthorized` are noted on
--     their segment; every other file is a colocated helper and ignored;
--   * `[id]` is a dynamic segment, `[...rest]` a catch-all, `[[...rest]]` an
--     optional catch-all;
--   * `(name)` is a route group: it organizes files and is no part of the
--     URL, so what is below it keeps the URL it would have without it;
--   * `@name` is a parallel-route slot and `(.)x`, `(..)x`, `(...)x`
--     intercept another route: both are drawn with what they hold, without a
--     URL of their own (a slot renders into the layout above it at that
--     route's URL, an interceptor answers at the URL of the route it
--     intercepts), so neither is counted as a route a second time;
--   * `_name` is a private folder: it and everything below it is no route.
--
-- **Pages Router.** A directory named `pages` is a route root only with
-- evidence, because many projects have a `pages` folder that routes nothing
-- (a Vite app with a router library): it must hold `_app` or `_document`,
-- or a file in or below it must import `next` or `next/...`. Then every
-- JS/TS file below it is a route: `about.tsx` is `/about`, `index` is its
-- directory, the bracket forms mean what they mean above, `api/` holds
-- request handlers, and `_app`, `_document`, `_error` are noted on the root.
--
-- Of an `app` and a `pages` segment on one path the first decides, so
-- `pages/app/x.tsx` is the route `/app/x` and not a second root.
--
-- ## What "framework" means here
--
-- `"next"` when a file in or below the root imports `next` or `next/...`
-- (read from the nodes' `requires_external`), or, for a `pages` root, when
-- `_app`/`_document` is there. An `app` root without such an import is still
-- drawn, because `page`/`route` files under `app` are a narrow shape, with
-- `framework` nil: the shape matched and nothing says whose convention it is.
--
-- ## What is not recognized
--
-- SvelteKit (`+page.svelte`), Nuxt (`pages/*.vue`) and Remix (dots in file
-- names): their route files are `.svelte`/`.vue` files or need a table of
-- their own, and the scan has no node for a file no language backend reads.
-- A route tree missing every page that has no script beside it would be
-- worse than none. Also not read: `pageExtensions` and `basePath` from
-- `next.config.*`, `middleware`, and whether an `app` and a `pages` root
-- claim the same URL.
--
-- Checked against two real trees (an App Router project of Next 14 with eight
-- routes, a Pages Router project of Next 13 with five): the routes found are
-- the ones the directories hold. Neither has a dynamic segment, a group or a
-- slot; those forms are covered by the fixture only.

local ROUTE_EXT = { js = true, jsx = true, ts = true, tsx = true }

---What a file of the App Router is to its segment, by its name without the
---extension.
local APP_FILES = {
  page = true,
  route = true,
  layout = true,
  template = true,
  loading = true,
  error = true,
  ["global-error"] = true,
  ["not-found"] = true,
  default = true,
  forbidden = true,
  unauthorized = true,
}

---The files of the Pages Router that are no route, noted on the root.
local PAGES_SPECIAL = { _app = "app", _document = "document", _error = "error" }

---@param path string
---@return string[]
local function split(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  return parts
end

---What kind of segment a directory or file name is.
---@param name string
---@return Docmap.RouteKind
local function segment_kind(name)
  if name:match("^%(%.+%)") then
    return "intercept"
  end
  if name:match("^%(.+%)$") then
    return "group"
  end
  if name:sub(1, 1) == "@" then
    return "slot"
  end
  if name:match("^%[%[%.%.%..+%]%]$") then
    return "optional"
  end
  if name:match("^%[%.%.%..+%]$") then
    return "catchall"
  end
  if name:match("^%[.+%]$") then
    return "dynamic"
  end
  return "static"
end

---@param requires string[]?
---@return boolean
local function imports_next(requires)
  for _, mod in ipairs(requires or {}) do
    if mod == "next" or mod:sub(1, 5) == "next/" then
      return true
    end
  end
  return false
end

---One segment of a route tree.
---@alias Docmap.RouteKind "root"|"static"|"dynamic"|"catchall"|"optional"|"group"|"slot"|"intercept"

---@class Docmap.RouteNode
---@field segment string The directory or file name as written (`[slug]`, `(shop)`); the root's own path for a root.
---@field kind Docmap.RouteKind
---@field dir string Path of the segment, relative to the scanned root's parent like a node path. For a file route of the Pages Router the path without the extension.
---@field node string? Id of the map's node for that directory, when there is one: what the Hierarchy re-centers on.
---@field url string? The URL pattern, when a page or a handler makes this segment a route.
---@field handler boolean? True when the route is a request handler (`route.*`, or below `pages/api`), not a page.
---@field files table<string, string> What the segment holds: role (`page`, `layout`, `route`, ...) to node id.
---@field children Docmap.RouteNode[] Sorted: groups, static, dynamic, catch-all, optional, slots, intercepting.

---One route tree: an `app` or a `pages` directory.
---@class Docmap.RouteRoot : Docmap.RouteNode
---@field router "app"|"pages"
---@field framework string? `"next"` with evidence, nil when only the shape matched.
---@field routes integer How many routes the tree has.

---@class Docmap.Routes
---@field roots Docmap.RouteRoot[] Sorted by directory.
---@field routes integer All routes of all roots.

local KIND_RANK = {
  group = 1,
  static = 2,
  dynamic = 3,
  catchall = 4,
  optional = 5,
  slot = 6,
  intercept = 7,
}

---The file-based route trees of a scanned tree, or nil when it has none.
---Reads node paths and `requires_external` only.
---@param ir Docmap.IR
---@return Docmap.Routes?
function M.file_routes(ir)
  -- Every JS/TS file the map has a node for, and every directory. A node's
  -- file is its `source`: for a directory module that is the index file
  -- inside it, which is exactly what makes `pages/blog/index.tsx` one node.
  local files, dir_node = {}, {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    local path = (node.path or id):gsub("^%./", "")
    if node.kind ~= "file" then
      dir_node[path] = id
    end
    local source = node.source and node.source:gsub("^%./", "")
      or (node.kind == "file" and path or nil)
    local stem, ext = (source or ""):match("([^/]+)%.([%w]+)$")
    if source and stem and ROUTE_EXT[ext] then
      files[#files + 1] = {
        id = id,
        parts = split(source:match("^(.*)/[^/]+$") or ""),
        stem = stem,
        next = imports_next(node.requires_external),
      }
    end
  end
  if #files == 0 then
    return nil
  end

  -- Which root a file belongs to: the first `app` or `pages` on its path.
  local candidates = {} -- root dir -> { router, files, evidence... }
  for _, file in ipairs(files) do
    for i, part in ipairs(file.parts) do
      if part == "app" or part == "pages" then
        local dir = table.concat(file.parts, "/", 1, i)
        local root = candidates[dir]
        if not root then
          root = { dir = dir, router = part, depth = i, files = {} }
          candidates[dir] = root
        end
        root.files[#root.files + 1] = file
        break
      end
    end
  end

  local roots = {}
  for _, cand in pairs(candidates) do
    local uses_next, is_route_tree = false, false
    for _, file in ipairs(cand.files) do
      uses_next = uses_next or file.next
      local direct = #file.parts == cand.depth
      if cand.router == "app" then
        is_route_tree = is_route_tree or file.stem == "page" or file.stem == "route"
      elseif direct and (file.stem == "_app" or file.stem == "_document") then
        is_route_tree = true
      end
    end
    if cand.router == "pages" then
      cand.framework = (is_route_tree or uses_next) and "next" or nil
      is_route_tree = is_route_tree or uses_next
    else
      cand.framework = uses_next and "next" or nil
    end
    if is_route_tree then
      roots[#roots + 1] = cand
    end
  end
  if #roots == 0 then
    return nil
  end
  table.sort(roots, function(a, b)
    return a.dir < b.dir
  end)

  local total = 0
  local out = {}
  for _, cand in ipairs(roots) do
    ---@type Docmap.RouteRoot
    local root = {
      segment = cand.dir,
      kind = "root",
      dir = cand.dir,
      node = dir_node[cand.dir],
      files = {},
      children = {},
      router = cand.router,
      framework = cand.framework,
      routes = 0,
    }
    local by_dir = { [cand.dir] = root }

    ---The node of a segment path below the root, made on the way down.
    ---@param names string[]
    ---@return Docmap.RouteNode
    local function reach(names)
      local at, dir = root, cand.dir
      for _, name in ipairs(names) do
        dir = dir .. "/" .. name
        local child = by_dir[dir]
        if not child then
          child = {
            segment = name,
            kind = segment_kind(name),
            dir = dir,
            node = dir_node[dir],
            files = {},
            children = {},
          }
          by_dir[dir] = child
          at.children[#at.children + 1] = child
        end
        at = child
      end
      return at
    end

    for _, file in ipairs(cand.files) do
      local names = {}
      for i = cand.depth + 1, #file.parts do
        names[#names + 1] = file.parts[i]
      end
      if cand.router == "app" then
        local private = false
        for _, name in ipairs(names) do
          private = private or name:sub(1, 1) == "_"
        end
        if APP_FILES[file.stem] and not private then
          reach(names).files[file.stem] = file.id
        end
      elseif #names == 0 and PAGES_SPECIAL[file.stem] then
        root.files[PAGES_SPECIAL[file.stem]] = file.id
      else
        if file.stem ~= "index" then
          names[#names + 1] = file.stem
        end
        reach(names).files.page = file.id
      end
    end

    -- The URL of every segment that is a route, and the order of the children.
    ---@param node Docmap.RouteNode
    ---@param url string? nil in and below a slot or an intercepting segment
    ---@param api boolean
    local function finish(node, url, api)
      if node.kind == "intercept" or node.kind == "slot" then
        url = nil
      elseif url and node.kind ~= "root" and node.kind ~= "group" then
        url = (url == "/" and "" or url) .. "/" .. node.segment
      end
      api = api or (cand.router == "pages" and node.dir == cand.dir .. "/api")
      if node.files.page or node.files.route then
        node.url = url
        if node.files.route or api then
          node.handler = true
        end
        if url then
          root.routes = root.routes + 1
        end
      end
      table.sort(node.children, function(a, b)
        if KIND_RANK[a.kind] ~= KIND_RANK[b.kind] then
          return KIND_RANK[a.kind] < KIND_RANK[b.kind]
        end
        return a.segment < b.segment
      end)
      for _, child in ipairs(node.children) do
        finish(child, url, api)
      end
    end
    finish(root, "/", false)

    total = total + root.routes
    out[#out + 1] = root
  end

  return { roots = out, routes = total }
end

return M
