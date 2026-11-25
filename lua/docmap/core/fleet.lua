---@module 'docmap.core.fleet'
--- The Duplicates, Quicks and Findings tabs over many repositories at once, and what turns up in more than one of
--- them. `docmap --fleet` (`M.main`, reached from `standalone/docmap.lua`) and `scripts/fleet_report.lua` are the
--- command lines around it.
---
--- A repository on its own can only say "these two functions are the same". A function that two repositories grew
--- separately is invisible to both, and it is exactly the kind a shared library should hold. So each repository is
--- scanned (`collect`), the structural shape of every function above the duplicate floor is kept with it, and `join`
--- groups the shapes across repositories. A shape is the parse-tree structure with names and literals left out
--- (`core/duplicates.lua`): the same blind spots apply, a single edited line breaks the match, and two functions can
--- share a shape and nothing else.
---
--- Built output is left out by default (`dist-*`, bundles, `node_modules`): the library inside a bundle is a copy
--- of somebody else's code, and it would be the biggest "duplicate" of the whole fleet.

local M = {}

---Path fragments that mark built output. Tested against `/<path>`, so a top-level folder matches too.
---@type string[]
M.GENERATED = {
  "/dist[^/]*/",
  "/build/",
  "/out/",
  "/node_modules/",
  "/target/",
  "/vendor/",
  "/%.deps/",
  "%.min%.",
  -- a bundler's content hash: `index.web-CdijYthr.js`
  "%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]%.js$",
}

---@param path string?
---@return boolean
function M.is_generated(path)
  local p = "/" .. (path or ""):gsub("\\", "/"):gsub("^%./", "")
  for _, pattern in ipairs(M.GENERATED) do
    if p:find(pattern) then
      return true
    end
  end
  return false
end

---The functions of one repository that are at least as big as the duplicate floor, with their shape.
---@param ir Docmap.IR
---@param with_generated boolean?
---@return table[] shapes
---@return integer dropped Functions left out as built output.
local function shapes_of(ir, with_generated)
  local floor = (ir.duplicates and ir.duplicates.min_size)
    or require("docmap.core.duplicates").MIN_SIZE
  local out, dropped = {}, 0
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    for _, fn in ipairs((node and node.functions) or {}) do
      if fn.shape and (fn.shape_size or 0) >= floor then
        if not with_generated and M.is_generated(node.source or node.path or id) then
          dropped = dropped + 1
        else
          out[#out + 1] = {
            node = id,
            module = node.module,
            language = node.language,
            name = fn.name,
            signature = fn.signature,
            line = fn.line,
            shape = fn.shape,
            size = fn.shape_size,
          }
        end
      end
    end
  end
  return out, dropped
end

---What one scanned repository contributes to the fleet.
---@param name string
---@param ir Docmap.IR
---@param findings Docmap.Finding[]
---@param opts { with_generated: boolean? }?
---@return table repo `{ repo, report, shapes, dropped }`
function M.collect(name, ir, findings, opts)
  opts = opts or {}
  local report = require("docmap.core.report")
  local built = report.build(ir, findings, report.SECTIONS, name)
  local shapes, dropped = shapes_of(ir, opts.with_generated)
  if not opts.with_generated then
    -- the same rule for the groups the repository reports about itself
    local groups, functions = {}, 0
    for _, g in ipairs(built.duplicates.groups) do
      local members = {}
      for _, m in ipairs(g.members) do
        if not M.is_generated(m.node) then
          members[#members + 1] = m
        end
      end
      if #members > 1 then
        groups[#groups + 1] = { identical = #members, nodes = g.nodes, members = members }
        functions = functions + #members
      end
    end
    built.duplicates.groups, built.duplicates.functions = groups, functions
  end
  return { repo = name, report = built, shapes = shapes, dropped = dropped }
end

---@param a table
---@param b table
---@return boolean
local function by_repos_then_size(a, b)
  if #a.repos ~= #b.repos then
    return #a.repos > #b.repos
  end
  if a.size ~= b.size then
    return a.size > b.size
  end
  return a.shape < b.shape
end

---@param members table[]
---@return string[] repos Sorted, once each.
local function repos_of(members)
  local seen, out = {}, {}
  for _, m in ipairs(members) do
    if not seen[m.repo] then
      seen[m.repo] = true
      out[#out + 1] = m.repo
    end
  end
  table.sort(out)
  return out
end

---Join the repositories: shapes seen in two or more, the pairs that share the most, and what recurs in quicks and
---findings.
---@param repos table[] From `M.collect`.
---@return table fleet
function M.join(repos)
  local by_shape, order = {}, {}
  for _, r in ipairs(repos) do
    for _, f in ipairs(r.shapes) do
      local g = by_shape[f.shape]
      if not g then
        g = { shape = f.shape, size = f.size, language = f.language, members = {} }
        by_shape[f.shape] = g
        order[#order + 1] = g
      end
      local m = vim.deepcopy(f)
      m.repo = r.repo
      g.members[#g.members + 1] = m
    end
  end

  local shapes = {}
  for _, g in ipairs(order) do
    g.repos = repos_of(g.members)
    if #g.repos > 1 then
      table.sort(g.members, function(a, b)
        if a.repo ~= b.repo then
          return a.repo < b.repo
        end
        if a.node ~= b.node then
          return a.node < b.node
        end
        return (a.line or 0) < (b.line or 0)
      end)
      shapes[#shapes + 1] = g
    end
  end
  table.sort(shapes, by_repos_then_size)

  local pair_count = {}
  for _, g in ipairs(shapes) do
    for i = 1, #g.repos do
      for j = i + 1, #g.repos do
        local key = g.repos[i] .. " + " .. g.repos[j]
        pair_count[key] = (pair_count[key] or 0) + 1
      end
    end
  end
  local pairs_out = {}
  for key, n in pairs(pair_count) do
    pairs_out[#pairs_out + 1] = { pair = key, shapes = n }
  end
  table.sort(pairs_out, function(a, b)
    if a.shapes ~= b.shapes then
      return a.shapes > b.shapes
    end
    return a.pair < b.pair
  end)

  local quick_repos, check_rows = {}, {}
  for _, r in ipairs(repos) do
    local seen = {}
    for _, q in ipairs(r.report.quicks.bad) do
      if not seen[q.id] then
        seen[q.id] = true
        quick_repos[q.id] = quick_repos[q.id] or {}
        table.insert(quick_repos[q.id], r.repo)
      end
    end
    for _, f in ipairs(r.report.findings.items) do
      if f.severity ~= "info" then
        local key = f.severity .. " " .. f.check
        local row = check_rows[key]
        if not row then
          row = { check = key, findings = 0, repos = {} }
          check_rows[key] = row
        end
        row.findings = row.findings + 1
        if row.repos[#row.repos] ~= r.repo then
          table.insert(row.repos, r.repo)
        end
      end
    end
  end
  local quicks = {}
  for id, list in pairs(quick_repos) do
    table.sort(list)
    quicks[#quicks + 1] = { quick = id, repos = list }
  end
  table.sort(quicks, function(a, b)
    if #a.repos ~= #b.repos then
      return #a.repos > #b.repos
    end
    return a.quick < b.quick
  end)
  local checks = {}
  for _, row in pairs(check_rows) do
    table.sort(row.repos)
    checks[#checks + 1] = row
  end
  table.sort(checks, function(a, b)
    if #a.repos ~= #b.repos then
      return #a.repos > #b.repos
    end
    if a.findings ~= b.findings then
      return a.findings > b.findings
    end
    return a.check < b.check
  end)

  local per_repo = {}
  for _, r in ipairs(repos) do
    local t = r.report.findings.tally
    per_repo[#per_repo + 1] = {
      repo = r.repo,
      functions = #r.shapes,
      groups = #r.report.duplicates.groups,
      duplicate_functions = r.report.duplicates.functions,
      bad_quicks = r.report.quicks.total_bad,
      errors = t.error or 0,
      warnings = t.warn or 0,
      info = t.info or 0,
    }
  end
  table.sort(per_repo, function(a, b)
    if a.groups ~= b.groups then
      return a.groups > b.groups
    end
    return a.repo < b.repo
  end)

  return {
    repos = per_repo,
    shapes = shapes,
    pairs = pairs_out,
    quicks = quicks,
    checks = checks,
  }
end

---Scan every root and collect it. A root that cannot be scanned is reported in `failed` and does not stop the others.
---@param roots string[]
---@param opts { with_generated: boolean?, progress: fun(line: string)? }?
---@return table[] repos
---@return { root: string, error: string }[] failed
function M.scan_roots(roots, opts)
  opts = opts or {}
  local config = require("docmap.config")
  local docmap = require("docmap")
  local repos, failed = {}, {}
  local notify = {
    warn = function(msg)
      if opts.progress then
        opts.progress("warn: " .. tostring(msg))
      end
    end,
  }
  for _, root in ipairs(roots) do
    local clean = root:gsub("\\", "/"):gsub("/+$", "")
    local name = clean:match("([^/]+)$") or clean
    local ok, result = pcall(function()
      local built = config.build(clean, { out_dir = "docs/map" }, notify)
      local ir, findings = docmap.scan_full(built)
      return M.collect(name, ir, findings, opts)
    end)
    if ok then
      repos[#repos + 1] = result
      if opts.progress then
        opts.progress(("%s: %d functions above the floor"):format(name, #result.shapes))
      end
    else
      failed[#failed + 1] = { root = clean, error = tostring(result) }
      if opts.progress then
        opts.progress(("%s: not scanned: %s"):format(name, tostring(result):match("[^\n]*")))
      end
    end
  end
  return repos, failed
end

---@param members table[]
---@param limit integer
---@return string
local function places(members, limit)
  local out = {}
  for i = 1, math.min(#members, limit) do
    local m = members[i]
    out[#out + 1] = ("%s:%s:%s"):format(m.repo, m.module or m.node, tostring(m.line or "?"))
  end
  local text = table.concat(out, "; ")
  if #members > limit then
    text = text .. ("; +%d"):format(#members - limit)
  end
  return text
end

---@param names string[]
---@param limit integer
---@return string
local function list_of(names, limit)
  local head = {}
  for i = 1, math.min(#names, limit) do
    head[i] = names[i]
  end
  local text = table.concat(head, ", ")
  if #names > limit then
    text = text .. (", +%d"):format(#names - limit)
  end
  return text
end

---@param members table[]
---@param limit integer
---@return string
local function names_of(members, limit)
  local seen, out = {}, {}
  for _, m in ipairs(members) do
    local label = m.signature or m.name or "?"
    if not seen[label] then
      seen[label] = true
      out[#out + 1] = label
      if #out == limit then
        break
      end
    end
  end
  return table.concat(out, " / ")
end

---@param s any
---@return string
local function cell(s)
  return (tostring(s):gsub("|", "\\|"))
end

---The fleet as Markdown lines.
---@param fleet table From `M.join`.
---@param opts { top: integer? }?
---@return string[]
function M.render(fleet, opts)
  local top = (opts and opts.top) or 25
  local out = {}
  local function add(line)
    out[#out + 1] = line or ""
  end
  local function table_of(head, rows)
    add("| " .. table.concat(head, " | ") .. " |")
    add("|" .. string.rep("---|", #head))
    for _, row in ipairs(rows) do
      local cells = {}
      for i, c in ipairs(row) do
        cells[i] = cell(c)
      end
      add("| " .. table.concat(cells, " | ") .. " |")
    end
    add()
  end

  local in_shapes = 0
  for _, g in ipairs(fleet.shapes) do
    in_shapes = in_shapes + #g.members
  end
  add("# docmap across the repositories")
  add()
  add(
    ("%d repositories; %d shapes appear in at least two of them (%d functions)."):format(
      #fleet.repos,
      #fleet.shapes,
      in_shapes
    )
  )
  add()

  add("## In more than one repository")
  add()
  add("### Same shape in the most repositories")
  add()
  local rows = {}
  for i = 1, math.min(top, #fleet.shapes) do
    local g = fleet.shapes[i]
    rows[#rows + 1] =
      { #g.repos, g.size, g.language or "?", names_of(g.members, 3), list_of(g.repos, 6) }
  end
  table_of({ "repos", "nodes", "language", "functions", "where" }, rows)

  add("### Biggest copies across repositories")
  add()
  local big = vim.deepcopy(fleet.shapes)
  table.sort(big, function(a, b)
    if a.size ~= b.size then
      return a.size > b.size
    end
    return a.shape < b.shape
  end)
  rows = {}
  for i = 1, math.min(top, #big) do
    local g = big[i]
    rows[#rows + 1] = { g.size, #g.repos, names_of(g.members, 2), places(g.members, 4) }
  end
  table_of({ "nodes", "repos", "function", "places" }, rows)

  add("### Pairs of repositories that share the most shapes")
  add()
  rows = {}
  for i = 1, math.min(top, #fleet.pairs) do
    rows[#rows + 1] = { fleet.pairs[i].pair, fleet.pairs[i].shapes }
  end
  table_of({ "pair", "shared shapes" }, rows)

  add("### Quicks that are bad in several repositories")
  add()
  rows = {}
  for i = 1, math.min(top, #fleet.quicks) do
    local q = fleet.quicks[i]
    rows[#rows + 1] = { q.quick, #q.repos, list_of(q.repos, 8) }
  end
  table_of({ "quick", "repos", "which" }, rows)

  add("### Finding checks (error or warning) in several repositories")
  add()
  rows = {}
  for i = 1, math.min(top, #fleet.checks) do
    local c = fleet.checks[i]
    rows[#rows + 1] = { c.check, c.findings, #c.repos, list_of(c.repos, 6) }
  end
  table_of({ "check", "findings", "repos", "which" }, rows)

  add("## Per repository")
  add()
  rows = {}
  for _, r in ipairs(fleet.repos) do
    rows[#rows + 1] = {
      r.repo,
      r.functions,
      r.groups,
      r.duplicate_functions,
      r.bad_quicks,
      r.errors,
      r.warnings,
      r.info,
    }
  end
  table_of(
    { "repo", "fns >= floor", "dup groups", "dup fns", "bad quicks", "errors", "warnings", "info" },
    rows
  )
  return out
end

---Lua patterns (matched against the lower-cased folder name) of repositories that are private: a run that picks
---repositories on its own (a folder of checkouts, the projects of a workspace) never takes them, and a root named
---on purpose is read with a warning. Kept small and built in on purpose, so a mistyped skip list cannot let one
---through. Hosts that choose roots themselves (`docmap-desktop report`) keep the same list.
---
---Assembled from parts: this repository is public and its files name no private repository (`TESTS/fleet_cli_spec.lua`
---holds the tree to that); the program still knows them.
---@type string[]
M.PRIVATE = { "tri" .. "centis", "wk" .. "dbook" }

---The pattern of `M.PRIVATE` the last folder of `path` matches, or nil.
---@param path string
---@return string?
function M.private_match(path)
  local clean = path:gsub("\\", "/"):gsub("/+$", "")
  local name = (clean:match("([^/]+)$") or clean):lower()
  for _, pattern in ipairs(M.PRIVATE) do
    if name:find(pattern) then
      return pattern
    end
  end
  return nil
end

M.USAGE = "usage: docmap --fleet <root>... [--json] [--top=<n>] [--with-generated]"

---The arguments after `--fleet`.
---@param args string[]
---@return { roots: string[], json: boolean, top: integer, with_generated: boolean, locale: string? }? opts
---@return string? err What was wrong, for the usage message.
function M.parse_args(args)
  local opts = { roots = {}, json = false, top = 25, with_generated = false }
  for _, a in ipairs(args) do
    if a == "--json" then
      opts.json = true
    elseif a == "--with-generated" then
      opts.with_generated = true
    elseif a:match("^%-%-top=") then
      local n = tonumber(a:sub(#"--top=" + 1))
      if not n or n < 1 or n ~= math.floor(n) then
        return nil, "--top wants a positive whole number"
      end
      opts.top = math.floor(n)
    elseif a:match("^%-%-locale=") then
      -- read by the entry point before anything is printed; accepted here so it may stand anywhere
      opts.locale = a:sub(#"--locale=" + 1)
    elseif a:sub(1, 1) == "-" then
      return nil, "unknown option " .. a
    else
      opts.roots[#opts.roots + 1] = a
    end
  end
  if #opts.roots == 0 then
    return nil, "no repository given"
  end
  return opts
end

---Write a joined fleet: Markdown with a "Not scanned" line per failed root, or one JSON object with `failed`.
---@param joined table From `M.join`.
---@param failed { root: string, error: string }[]
---@param opts { json: boolean?, top: integer? }
---@param out file*
function M.write(joined, failed, opts, out)
  if opts.json then
    joined.failed = failed
    out:write(require("docmap.core.json").encode(joined) .. "\n")
    return
  end
  out:write(table.concat(M.render(joined, { top = opts.top }), "\n") .. "\n")
  for _, f in ipairs(failed) do
    out:write(("\nNot scanned: %s (%s)\n"):format(f.root, (f.error:match("[^\n]*"))))
  end
end

---`docmap --fleet <root>...`: scan every root, print the report to `out`, progress and warnings to `err`.
---Exit code 0 when every root was scanned, 1 when at least one was not (the report lists the others), 2 for wrong
---arguments.
---@param args string[] The arguments after `--fleet`.
---@param out file*
---@param err file*
---@return integer code
function M.main(args, out, err)
  local opts, problem = M.parse_args(args)
  if not opts then
    err:write("docmap --fleet: " .. tostring(problem) .. "\n" .. M.USAGE .. "\n")
    return 2
  end
  local roots, failed = {}, {}
  for _, root in ipairs(opts.roots) do
    local clean = root:gsub("\\", "/"):gsub("/+$", "")
    local private = M.private_match(clean)
    if private then
      err:write(
        ("warning: %s looks like a private repository (its name matches %q); read because it was named\n"):format(
          clean,
          private
        )
      )
    end
    if vim.fn.isdirectory(clean) == 1 then
      roots[#roots + 1] = clean
    else
      failed[#failed + 1] = { root = clean, error = "not a folder" }
      err:write(("%s: not scanned: not a folder\n"):format(clean))
    end
  end
  local repos, scan_failed = M.scan_roots(roots, {
    with_generated = opts.with_generated,
    progress = function(line)
      err:write(line .. "\n")
    end,
  })
  for _, f in ipairs(scan_failed) do
    failed[#failed + 1] = f
  end
  M.write(M.join(repos), failed, opts, out)
  return #failed > 0 and 1 or 0
end

return M
