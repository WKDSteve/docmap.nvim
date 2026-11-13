---@module 'docmap.core.features'
--- Reads a repo's own `docs/FEATURES/` folder into
--- `Docmap.Features.Result` for the Features tab.
---
--- See `docs/features_format.md` for the full field guide this parser
--- implements — a `##`-per-feature, `- **Key:** value`-metadata convention
--- deliberately closest to `markdown.nvim`'s own real `docs/FEATURES/`, the
--- one of three independently-invented shapes found across this user's
--- plugins that is both ordinary prose and mechanically recognizable
--- line-by-line, no CommonMark parser needed — same "cheap reliable reading
--- beats a general one" discipline `core/deps.lua`'s require-extraction and
--- `lib.nvim.deps.spec`'s fenced-block parsing already use.
---
--- No validation, unlike `core/tools.lua`: that format feeds an installer,
--- so a missing `why` is a real defect. This one feeds a reader, and
--- `markdown.nvim`'s own real `docs/FEATURES/headings.md` already mixes
--- `Module`/`Keymaps`/`Config` with one-off keys in the same file — a
--- whitelist would reject working documentation that predates this parser.
--- A theme file with zero `##` sections, or a feature with zero metadata
--- bullets, is not an error; both are real, valid states.

local M = {}

local safe_fs = require("docmap.core.safe_fs")

---Both of these go through `core/safe_fs.lua`: the folder and the files in it
---are the repository's to name, and a link among them must not lead out of the
---project.
---@param root string
---@param path string
---@return boolean
local function is_dir(root, path)
  return safe_fs.is_dir(root, path)
end

---@param root string
---@param path string
---@return string|nil
local function read_file(root, path)
  local fd = safe_fs.open(root, path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Candidate folder names, in resolution order — uppercase preferred,
--- matching `docs/BINDINGS.md`'s own convention, same "first match wins"
--- shape `lib.nvim.deps.spec`'s `SPEC_FILES` uses for install.json/
--- INSTALL.md.
---
--- The *default* list, since `opts.features_dir` — a repository whose prose
--- lives under `documentation/` rather than `docs/` — replaces it. Still a
--- list either way: "first match wins" is what lets a project keep both
--- spellings on a case-sensitive filesystem while it renames one.
local CANDIDATE_FOLDERS = { "docs/FEATURES", "docs/features" }

--- Files that come first inside a features folder, in this order, before the
--- rest sorts alphabetically.
---
--- `core` first because it is the answer to "why would I install this" — the
--- handful of features the plugin exists for, ahead of the ones it grew. Then
--- `FEATURES`, which is where a repo that has outgrown a single file keeps the
--- overview of everything that is *not* singled out. Everything else follows
--- in name order, as before.
---
--- Matched case-insensitively against the theme name (the file name without
--- `.md`), so `CORE.md`, `core.md` and `Core.md` all land in the same slot.
local LEADING_THEMES = { "core", "features" }

---Sort key for a theme file: leading themes by their position in
---`LEADING_THEMES`, everything else after them.
---@param theme string File name without `.md`.
---@return integer
local function theme_rank(theme)
  local lowered = theme:lower()
  for i, leading in ipairs(LEADING_THEMES) do
    if lowered == leading then
      return i
    end
  end
  return #LEADING_THEMES + 1
end

---One `- **Key:** value` bullet.
---@param line string Already right-trimmed.
---@return string|nil key
---@return string value Empty string when there is no key, and when the bullet has a key with nothing after the colon. Never nil, so a caller that checked `key` does not have to check this one too.
local function match_bullet(line)
  -- The colon sits *inside* the bold markers (`**Key:**`), not after them
  -- (`**Key**:`) — confirmed against markdown.nvim's own real
  -- `docs/FEATURES/headings.md`, which is what this format is modelled on.
  local key, value = line:match("^%-%s*%*%*([^*:]+):%*%*%s*(.*)$")
  if not key then
    return nil, ""
  end
  return (key:match("^%s*(.-)%s*$")), (value:match("^%s*(.-)%s*$"))
end

---Split into lines, `\n`-terminated tail included so the last real line is
---never dropped — same idiom `core/deps.lua`'s `extract_source` uses.
---@param text string
---@return string[]
local function to_lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
  -- The trailing empty string from a file that already ends in "\n" is not
  -- a real line and would otherwise read as a spurious paragraph break.
  if out[#out] == "" then
    out[#out] = nil
  end
  return out
end

---Everything from `start_idx` to `end_idx` (inclusive) that belongs to one
---feature: a summary (the leading run of non-bullet prose lines) and a
---metadata block (the contiguous run of bullets immediately after it).
---
---A bullet's own value routinely wraps onto an **indented** continuation
---line — confirmed against markdown.nvim's real `docs/FEATURES/headings.md`,
---where `- **Module:** ...(` regularly continues on the next line with a
---2-space-indented function list. Such a line is folded into the value of
---the bullet it continues, not treated as ending the run. A **blank** line,
---or a non-bullet line with **no** leading indent (a new flush-left
---paragraph — prose written after the metadata, with no blank separator),
---ends the run for good: neither case is a continuation of anything.
---@param lines string[]
---@param start_idx integer
---@param end_idx integer
---@return string|nil summary
---@return Docmap.Features.Meta[] meta
---@return integer|nil body_start_idx The line right after the metadata run ended — where a `Tab: true` feature's rich body begins. `nil` when the run never started (no bullets at all; see `parse_file`'s promoted-feature handling for what that means for `body`).
local function parse_body(lines, start_idx, end_idx)
  local summary_parts = {}
  ---@type Docmap.Features.Meta[]
  local meta = {}
  -- Parallel to `meta`, by index -- keeps Meta.value a plain string
  -- throughout instead of holding a table in it between passes.
  ---@type table<integer, string[]>
  local value_parts = {}
  -- "before" the first bullet, "in" a contiguous bullet run, or "after" one
  -- that has ended — once "after", every remaining line is inert.
  local state = "before"
  local body_start_idx = nil

  for i = start_idx, end_idx do
    local raw = lines[i]
    local trimmed = raw:match("^%s*(.-)%s*$")
    local key, value = match_bullet(trimmed)

    if state == "before" then
      if key then
        meta[#meta + 1] = { key = key, value = value }
        value_parts[#meta] = { value }
        state = "in"
      elseif trimmed ~= "" then
        summary_parts[#summary_parts + 1] = trimmed
      end
    elseif state == "in" then
      if key then
        meta[#meta + 1] = { key = key, value = value }
        value_parts[#meta] = { value }
      elseif trimmed == "" then
        state = "after"
        body_start_idx = i + 1
      elseif raw:match("^%s") then
        local parts = value_parts[#meta]
        parts[#parts + 1] = trimmed
      else
        state = "after"
        body_start_idx = i
      end
    end
  end

  for j, m in ipairs(meta) do
    m.value = table.concat(value_parts[j], " ")
  end

  return (#summary_parts > 0 and table.concat(summary_parts, " ") or nil), meta, body_start_idx
end

---One theme file: `# Title` + intro prose (optional) before the first `##`,
---then one `Docmap.Features.Entry` per `## <name>` section.
---@param root string
---@param path string Absolute path.
---@param rel string Repo-relative path, for `Docmap.Features.File.path`.
---@param theme string Filename without extension, as the author wrote it.
---@return Docmap.Features.File|nil `nil` when the file could not be read.
local function parse_file(root, path, rel, theme)
  local text = read_file(root, path)
  if not text then
    return nil
  end
  local lines = to_lines(text)

  -- Section boundaries first: every `## ` line, plus a sentinel one past
  -- the end so the last section's body has a real stop index.
  ---@type { name: string, line: integer, start_idx: integer }[]
  local headings = {}
  for i, line in ipairs(lines) do
    local name = line:match("^##%s+(.-)%s*$")
    if name then
      headings[#headings + 1] = { name = name, line = i, start_idx = i + 1 }
    end
  end

  -- Everything before the first `##` (skipping a leading `# Title` line, if
  -- any) is the file's own intro — optional, same as a feature's own
  -- summary is optional.
  local first_section_line = headings[1] and headings[1].line or (#lines + 1)
  local intro_start = 1
  if lines[1] and lines[1]:match("^#%s") then
    intro_start = 2
  end
  local intro = parse_body(lines, intro_start, first_section_line - 1)

  ---@type Docmap.Features.Entry[]
  local entries = {}
  for i, h in ipairs(headings) do
    local end_idx = (headings[i + 1] and headings[i + 1].line - 1) or #lines
    local summary, meta, body_start_idx = parse_body(lines, h.start_idx, end_idx)

    -- `Tab: true` is a control directive, not something a reader wants to
    -- see rendered as an ordinary "Tab: true" metadata row — pulled out of
    -- `meta` here rather than filtered client-side, so the IR never carries
    -- a bullet the page is going to hide again.
    local tab = false
    ---@type Docmap.Features.Meta[]
    local visible_meta = {}
    for _, m in ipairs(meta) do
      if m.key:lower() == "tab" and m.value:lower() == "true" then
        tab = true
      else
        visible_meta[#visible_meta + 1] = m
      end
    end

    -- The rich body only exists for a promoted feature — a card never
    -- renders it, so there is no reason to carry it for every other feature
    -- in the tree. `body_start_idx` is only ever nil here because `tab`
    -- itself is a bullet (see the loop above): a promoted feature always
    -- has at least one, so `parse_body` never falls back to folding the
    -- whole section into `summary` the way a truly bullet-less feature
    -- would. `body` stays nil when nothing actually follows the metadata
    -- block — a promoted feature can be title+summary+metadata only, same
    -- as an ordinary card; that's a real state, not a parse failure.
    local body = nil
    if tab and body_start_idx and body_start_idx <= end_idx then
      local body_lines = {}
      for li = body_start_idx, end_idx do
        body_lines[#body_lines + 1] = lines[li]
      end
      local joined = table.concat(body_lines, "\n"):match("^%s*(.-)%s*$")
      if joined ~= "" then
        body = joined
      end
    end

    entries[#entries + 1] = {
      name = h.name,
      line = h.line,
      summary = summary,
      meta = visible_meta,
      tab = tab,
      body = body,
    }
  end

  return { path = rel, theme = theme, intro = intro, entries = entries }
end

---Single-file fallback: `docs/FEATURES.md` instead of `docs/FEATURES/`.
---
---A small plugin has no reason to spread a dozen features over a folder, and
---nine of the sibling repos had picked the single file — where `resolve` used
---to return nil, so the Features tab said "no features" for a perfectly good
---catalogue. The parse is identical: `parse_file` does not care whether its
---file has siblings.
---
---The folder wins when a repo has both, so a repo splitting a grown
---`FEATURES.md` into themes can leave the old file in place until it is done.
---@param normalized string Repo root, forward slashes, no trailing separator.
---@param candidates string[] The folder candidates; each gets `.md` appended.
---@return Docmap.Features.Result|nil
local function resolve_single_file(normalized, candidates)
  for _, candidate in ipairs(candidates) do
    local rel = candidate .. ".md"
    local abs = normalized .. "/" .. rel
    if safe_fs.stat(normalized, abs) then
      local theme = candidate:match("([^/]+)$") or candidate
      local file = parse_file(normalized, abs, rel, theme)
      if file then
        return { folder = rel, intro = nil, files = { file } }
      end
      return nil
    end
  end
  return nil
end

---@param root string Repo root (`ctx.cfg.root` / `opts.root`).
---@param dirs string|string[]|nil `opts.features_dir`. Absent means `CANDIDATE_FOLDERS`.
---@return Docmap.Features.Result|nil result `nil` when this repo ships neither a features folder nor a single features file.
function M.resolve(root, dirs)
  local normalized = (root:gsub("\\", "/"):gsub("/+$", ""))

  local candidates = require("docmap.config").dir_list(dirs, CANDIDATE_FOLDERS)

  local folder
  for _, candidate in ipairs(candidates) do
    if is_dir(normalized, normalized .. "/" .. candidate) then
      folder = candidate
      break
    end
  end
  if not folder then
    return resolve_single_file(normalized, candidates)
  end
  local abs_folder = normalized .. "/" .. folder

  -- README.md (or readme.md) is the folder's own intro, read separately —
  -- never itself a theme file, the same way a plugin's top-level README is
  -- never scanned as a module.
  local intro
  for _, name in ipairs({ "README.md", "readme.md" }) do
    local text = read_file(normalized, abs_folder .. "/" .. name)
    if text then
      local trimmed = text:match("^%s*(.-)%s*$")
      intro = trimmed ~= "" and trimmed or nil
      break
    end
  end

  ---@type Docmap.Features.File[]
  local files = {}
  do
    ---@type string[]
    local names = {}
    for _, e in ipairs(safe_fs.entries(normalized, abs_folder)) do
      if e.type == "file" and e.name:match("%.md$") and e.name:lower() ~= "readme.md" then
        names[#names + 1] = e.name
      end
    end
    -- `core` first, then `FEATURES`, then the rest by name — see
    -- `LEADING_THEMES`. Name order alone put ARCHITECTURE above CORE, which
    -- is the opposite of the order somebody reads them in.
    table.sort(names, function(a, b)
      local ra, rb = theme_rank(a:gsub("%.md$", "")), theme_rank(b:gsub("%.md$", ""))
      if ra ~= rb then
        return ra < rb
      end
      return a < b
    end)
    for _, name in ipairs(names) do
      local theme = name:gsub("%.md$", "")
      local file = parse_file(normalized, abs_folder .. "/" .. name, folder .. "/" .. name, theme)
      if file then
        files[#files + 1] = file
      end
    end
  end

  return { folder = folder, intro = intro, files = files }
end

-- ---------------------------------------------------------------- the way back
--
-- A `- **Module:** …` bullet names where a feature lives. Read forwards it
-- links a feature card to a node; `M.index` reads the same bullets backwards,
-- so a module or a function can say which features describe it. No new
-- metadata: the values below are what authors already write.
--
--   `core/annotate.lua` (`M.candidates`, `M.plan`), `bindings/usrcmds/annotate.lua`
--   `lib.nvim.bindings.usercmd` (`create`)
--   [`adapter/oil.lua`](../../lua/filetree/adapter/oil.lua) — `filetypes = {"oil"}`
--
-- A backticked token outside parentheses names a file or a module; the
-- backticked tokens in the parentheses after it name members of that file.
-- Anything that is neither (the `filetypes = …` above, prose, a link target)
-- is passed over: this reads a convention, it does not police a sentence.

---The backticked tokens of a `Module:` value, each with the parenthesis depth
---it sits at. A link target `](…)` is skipped whole, so the parentheses of a
---Markdown link do not read as a member list.
---@param value string
---@return { text: string, depth: integer }[]
local function module_tokens(value)
  local out = {}
  local depth = 0
  local i, n = 1, #value
  while i <= n do
    local c = value:sub(i, i)
    if c == "`" then
      local close = value:find("`", i + 1, true)
      if not close then
        break
      end
      out[#out + 1] = { text = value:sub(i + 1, close - 1), depth = depth }
      i = close + 1
    elseif c == "]" and value:sub(i + 1, i + 1) == "(" then
      local close = value:find(")", i + 2, true)
      i = (close or n) + 1
    else
      if c == "(" then
        depth = depth + 1
      elseif c == ")" and depth > 0 then
        depth = depth - 1
      end
      i = i + 1
    end
  end
  return out
end

---What a token would have to look like to be a claim about this tree: a path
---with a file extension. `filetypes = {"oil"}` and `:Cmd sub` are neither.
---@param token string
---@return boolean
local function looks_like_path(token)
  return token:match("^[%w_%-./]+%.%a%w*$") ~= nil and token:find("/", 1, true) ~= nil
end

---@param name string
---@return string|nil bare The last segment of `M.plan`, `mod:method`, `fn()`; nil when the token is not an identifier at all.
local function bare_member(name)
  local bare = name:gsub("%s*%(.*%)$", ""):match("([^.:]+)$")
  if bare and bare:match("^[%a_][%w_]*$") then
    return bare
  end
  return nil
end

---Lookup tables over the scanned tree, built once per `M.index`.
---@param ir Docmap.IR
---@return { by_path: table<string, string>, by_module: table<string, string>, paths: { path: string, id: string, stem: string }[], modules: { module: string, id: string }[], exts: table<string, true> }
local function node_lookup(ir)
  local by_path, by_module, paths, modules, exts = {}, {}, {}, {}, {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node then
      for _, p in ipairs({ node.source or false, node.path or false }) do
        if type(p) == "string" and p ~= "" then
          p = p:gsub("\\", "/")
          if not by_path[p] then
            by_path[p] = id
            paths[#paths + 1] = {
              path = p,
              id = id,
              -- The path as a module name would spell it: no extension, no `/init`.
              stem = "/" .. p:gsub("%.%a%w*$", ""):gsub("/init$", ""),
            }
            local ext = p:match("%.(%a%w*)$")
            if ext then
              exts[ext:lower()] = true
            end
          end
        end
      end
      if type(node.module) == "string" and node.module ~= "" and not by_module[node.module] then
        by_module[node.module] = id
        modules[#modules + 1] = { module = node.module, id = id }
      end
    end
  end
  return { by_path = by_path, by_module = by_module, paths = paths, modules = modules, exts = exts }
end

---The node a file or module token names: the exact path or module name, else
---the first node (in tree order) whose path ends in `/token` or whose module
---name ends in `.token`. A suffix is how these bullets are written
---(`core/check.lua` for `lua/docmap/core/check.lua`); the boundary keeps
---`check.lua` from matching `precheck.lua`.
---@param lookup table
---@param token string
---@return string|nil node_id
local function resolve_node(lookup, token)
  token = token:gsub("\\", "/")
  if lookup.by_path[token] then
    return lookup.by_path[token]
  end
  if lookup.by_module[token] then
    return lookup.by_module[token]
  end
  local tail = "/" .. token
  for _, p in ipairs(lookup.paths) do
    if #p.path > #tail and p.path:sub(-#tail) == tail then
      return p.id
    end
  end
  if token:match("^[%a_][%w_.]*$") then
    tail = "." .. token
    for _, m in ipairs(lookup.modules) do
      if #m.module > #tail and m.module:sub(-#tail) == tail then
        return m.id
      end
    end
    -- A module name is also a path: `lib.nvim.cross.uv` is the directory
    -- `lua/lib/nvim/cross/uv`, whether or not anything in it carries an
    -- `@module` tag saying so.
    tail = "/" .. token:gsub("%.", "/")
    for _, p in ipairs(lookup.paths) do
      if p.stem:sub(-#tail) == tail then
        return p.id
      end
    end
  end
  return nil
end

---Whether a dotted token that resolved to nothing still claims to be inside
---this tree: some proper prefix of it is a module of the map. That is the rule
---`docs.missing_member` uses, and it keeps `vim.fn.expand` or another
---repository's `lib.nvim.git.refs` from being reported.
---@param lookup table
---@param token string
---@return boolean
local function claims_this_tree(lookup, token)
  if not token:match("^[%a_][%w_]*%.[%w_.]+$") then
    return false
  end
  local prefix = token
  while true do
    prefix = prefix:match("^(.*)%.[^.]+$")
    if not prefix then
      return false
    end
    if lookup.by_module[prefix] then
      return true
    end
  end
end

---Every function called `bare` in `node_id` or, when the node has none, at
---the nearest level below it that has one. A bullet often names a directory
---module (`lib.nvim.window` (`make_scratch`)) whose functions live one file
---down.
---
---Level by level, and the first level with a match ends the search: a
---`close` three directories down is not what `window` (`close`) means when
---`window/init.lua`'s neighbour has one.
---@param ir Docmap.IR
---@param node_id string
---@param bare string
---@return string[] keys `nodeId#fnName`, in tree order.
local function member_keys(ir, node_id, bare)
  local keys = {}
  local level = { node_id }
  while #level > 0 and #keys == 0 do
    local below = {}
    for _, id in ipairs(level) do
      local node = ir.nodes[id]
      if node then
        for _, fn in ipairs(node.functions or {}) do
          if bare_member(fn.name) == bare then
            keys[#keys + 1] = id .. "#" .. fn.name
          end
        end
        for _, child in ipairs(node.children or {}) do
          below[#below + 1] = child
        end
      end
    end
    level = below
  end
  return keys
end

---The reverse index of the `Module:` bullets.
---
---Sets two fields on `result` (and returns it): `refs`, keyed like
---`ir.docs.refs` (a node id for a module, `nodeId#fnName` for a function),
---each listing the features that name it; and `unresolved`, the file and
---module tokens that claim a place in this tree and name nothing in it. Both
---are left off when empty, so a tree without `Module:` bullets carries the
---artifact it always did.
---
---**Only the file or module token is ever reported.** Measured over
---fourteen repositories (2026-11-13): the member lists in the parentheses
---produced 70 misses in seven of them, nearly all not functions at all
---(`opts.env`, `false`, a method of an instance, a function of the page's
---script). A member that is not found is therefore not indexed, and that is
---all. The file and module tokens of the same fourteen resolve without a
---single miss once the three rules below are in: a real file that is no
---module, a path of a language the map does not hold, and `module.member`
---written as one dotted name.
---
---A function a bullet names is also filed under its module: "which features
---touch this file" is the module question, and it should not depend on
---whether the author went on to list members.
---@param result Docmap.Features.Result|nil
---@param ir Docmap.IR
---@param root string|nil Repo root. With it, a path token that names a real file which is no module (`docs/install.json`) is not reported.
---@return Docmap.Features.Result|nil
function M.index(result, ir, root)
  if not result then
    return nil
  end
  local lookup = node_lookup(ir)
  local normalized = root and (root:gsub("\\", "/"):gsub("/+$", "")) or nil
  local function is_real_file(token)
    return normalized ~= nil and safe_fs.stat(normalized, normalized .. "/" .. token) ~= nil
  end
  -- A path is only a claim about this map when the map holds files of that
  -- kind at all: `relay/nav.go` in a tree scanned for Lua is a real file the
  -- map never looked at, not a stale name.
  local function stale_path(token)
    local ext = token:match("%.(%a%w*)$")
    return looks_like_path(token) and ext ~= nil and lookup.exts[ext:lower()] == true
  end
  ---@return string|nil owner
  ---@return string|nil member
  local function member_of_module(token)
    local prefix, member = token:match("^([%a_][%w_.]*)%.([%a_][%w_]*)$")
    if not prefix then
      return nil, nil
    end
    local owner = resolve_node(lookup, prefix)
    if owner and #member_keys(ir, owner, member) > 0 then
      return owner, member
    end
    return nil, nil
  end
  ---@type table<string, Docmap.Features.Ref[]>
  local refs = {}
  ---@type table<string, true>
  local seen = {}
  ---@type Docmap.Features.Unresolved[]
  local unresolved = {}

  local function file_ref(key, file, entry)
    local mark = key .. "\0" .. file.path .. "\0" .. entry.line
    if seen[mark] then
      return
    end
    seen[mark] = true
    refs[key] = refs[key] or {}
    table.insert(refs[key], { file = file.path, line = entry.line })
  end

  for _, file in ipairs(result.files) do
    for _, entry in ipairs(file.entries) do
      for _, meta in ipairs(entry.meta) do
        if meta.key:lower() == "module" then
          ---@type string|nil
          local current = nil
          for _, token in ipairs(module_tokens(meta.value)) do
            if token.depth == 0 then
              current = resolve_node(lookup, token.text)
              if current then
                file_ref(current, file, entry)
                -- The first node a feature names is where its card links
                -- to. Resolved here so both directions agree: the page's
                -- own matching knows paths only, not module names.
                entry.node = entry.node or current
              elseif member_of_module(token.text) then
                -- `sandbox.resolve_engine_name`: a module and one member,
                -- written as one dotted name.
                local owner, member = member_of_module(token.text)
                file_ref(owner, file, entry)
                entry.node = entry.node or owner
                for _, key in ipairs(member_keys(ir, owner, member)) do
                  file_ref(key, file, entry)
                end
                current = owner
              elseif
                (stale_path(token.text) and not is_real_file(token.text))
                or claims_this_tree(lookup, token.text)
              then
                unresolved[#unresolved + 1] = {
                  file = file.path,
                  line = entry.line,
                  feature = entry.name,
                  text = token.text,
                }
              end
            elseif current then
              local bare = bare_member(token.text)
              if bare then
                for _, key in ipairs(member_keys(ir, current, bare)) do
                  file_ref(key, file, entry)
                end
              end
            end
          end
        end
      end
    end
  end

  -- Files and entries are walked in their fixed order, so every list is
  -- already sorted by (file order, line): the artifact is byte-compared.
  result.refs = next(refs) and refs or nil
  result.unresolved = #unresolved > 0 and unresolved or nil
  return result
end

return M
