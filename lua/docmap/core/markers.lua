---@module 'docmap.core.markers'
--- Marker comments — `-- TODO:`, `// FIXME:`, `# PERF:` — collected from
--- source text.
---
--- **Why this is not `functions.lua`'s job.** The Notes tab has always shown
--- `---@todo`, `---@bug` and friends, and those are *annotations on a
--- function*: they arrive attached to a signature, and the tab could show
--- them beside one. A marker comment is attached to a line. It sits wherever
--- the author was standing when they wrote it — inside a branch, above a
--- config table, at the end of a line of code — and most of them are nowhere
--- near a function's doc block. Nothing in the annotation pipeline could
--- have found them, which is why a repository full of `-- TODO:` reported
--- "Nothing carries ---@todo in this map" and was telling the truth in the
--- least useful way available.
---
--- **The keyword set is `todo-comments.nvim`'s**, deliberately, alias for
--- alias. That plugin is what puts these markers on screen in the editor
--- they were typed in, and a map that recognised a different set would
--- disagree with the author's own highlighting — a marker coloured in the
--- buffer and absent from the map reads as the map being broken, and it
--- would be.
---
--- **Language-specific by construction.** What opens a comment is a fact
--- about a language, so it comes from the backend (`line_comments` /
--- `block_comments`) rather than from a list here. A keyword is only a
--- marker if it is *inside a comment*: matching `TODO:` anywhere on the line
--- would collect it out of string literals, and a map that reports a
--- to-do that is really a log message is worse than one that misses it.
---
--- See `@types/init.lua` for `Docmap.MarkerNote`.

local M = {}

---Canonical keyword, then the spellings that mean the same thing.
---
---Order matters twice: it is the order the Notes tab renders sections in,
---and — because `FIX` is a prefix of `FIXME` — the alias lists are matched
---longest-first below rather than in this table's own order.
---@type { name: string, aliases: string[], sub: string }[]
M.KEYWORDS = {
  {
    name = "TODO",
    aliases = {},
    sub = "Work the author left for later, marked in a comment rather than in an annotation.",
  },
  {
    name = "FIX",
    aliases = { "FIXME", "FIXIT", "BUG", "ISSUE" },
    sub = "Something known to be wrong at the line it sits on.",
  },
  {
    name = "HACK",
    aliases = {},
    sub = "Code the author already knows is the wrong shape, kept on purpose.",
  },
  {
    name = "WARN",
    aliases = { "WARNING", "XXX" },
    sub = "A trap for whoever edits this next.",
  },
  {
    name = "PERF",
    aliases = { "OPTIM", "PERFORMANCE", "OPTIMIZE" },
    sub = "A cost the author measured or suspected, recorded where it is paid.",
  },
  {
    name = "NOTE",
    aliases = { "INFO" },
    sub = "Context that is true but not derivable from the code around it.",
  },
  {
    name = "TEST",
    aliases = { "TESTING", "PASSED", "FAILED" },
    sub = "What covers this line, or what does not.",
  },
}

---Every spelling mapped to its canonical keyword, longest first.
---
---Built once at load rather than per file: this is a fixed table, and the
---alternative is rebuilding it ~150 times in a walk of this repository.
---The two search patterns per spelling are built here too, not per comment
---line: `match_marker` runs for every comment line of every file.
---@type { word: string, name: string, plain_pat: string, author_pat: string }[]
local SPELLINGS = (function()
  local out = {}
  local function add(word, name)
    out[#out + 1] = {
      word = word,
      name = name,
      plain_pat = "%f[%w]" .. word .. "%s*:",
      author_pat = "%f[%w]" .. word .. "%s*%([^)]*%)%s*:",
    }
  end
  for _, kw in ipairs(M.KEYWORDS) do
    add(kw.name, kw.name)
    for _, alias in ipairs(kw.aliases) do
      add(alias, kw.name)
    end
  end
  -- Longest first so `FIXME:` is not reported as `FIX` with a stray `ME:`
  -- in front of its text.
  table.sort(out, function(a, b)
    if #a.word ~= #b.word then
      return #a.word > #b.word
    end
    return a.word < b.word
  end)
  return out
end)()

---Escape a comment token for use in a Lua pattern.
---
---`--` and `/*` are both made of magic characters, and a backend is free to
---name any token it likes, so nothing here may assume which.
---@param s string
---@return string
local function esc(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

---Comment syntax for a backend, with the shape this module needs.
---
---A backend that states nothing gets nothing scanned rather than a guess:
---`#` is a comment in Python and a preprocessor directive in C, and picking
---one for a language that never said would attribute markers to lines that
---have none.
---@param backend Docmap.LangBackend?
---@return { line: string[], block: { [1]: string, [2]: string }[] }?
local function syntax(backend)
  if not backend then
    return nil
  end
  local line = backend.line_comments or {}
  local block = backend.block_comments or {}
  if #line == 0 and #block == 0 then
    return nil
  end
  return { line = line, block = block }
end

---Find where a comment starts on this line, given no block is already open.
---
---The *earliest* opener wins, not the first one in the backend's list: in
---`/* // */` the line comment is inside the block, and taking `//` because
---it was listed first would misread the rest of the line.
---@param text string
---@param syn { line: string[], block: { [1]: string, [2]: string }[] }
---@return integer? at Byte index of the first character after the opener.
---@return { [1]: string, [2]: string }? block The block opened, if it was a block.
local function comment_start(text, syn)
  local at, after, block = nil, nil, nil
  for _, tok in ipairs(syn.line) do
    local s = text:find(esc(tok))
    if s and (not at or s < at) then
      at, after, block = s, s + #tok, nil
    end
  end
  for _, pair in ipairs(syn.block) do
    local s = text:find(esc(pair[1]))
    -- `<=`, not `<`: in Lua both `--` and `--[[` start at the same byte, and
    -- reading that line as a line comment would lose the block's end token —
    -- so a marker three lines into a `--[[ ... ]]` region would never be
    -- found. The more specific opener wins a tie.
    if s and (not at or s <= at) then
      at, after, block = s, s + #pair[1], pair
    end
  end
  return after, block
end

---Read one marker out of the comment part of a line, if there is one.
---
---`KEYWORD:` and `KEYWORD(author):` are both accepted — the author form is
---`todo-comments.nvim`'s, and dropping the author would turn "ask Stefan"
---into an anonymous note.
---@param comment string The line from the comment opener onward.
---@return string? name Canonical keyword.
---@return string? word The spelling actually used.
---@return string? author
---@return string? text
local function match_marker(comment)
  -- Every accepted form ends its keyword with a `:`. A line without one --
  -- most of a doc comment -- cannot hold a marker, and this runs once per
  -- comment line of every file: on lib.nvim it was 9% of a `generate`
  -- before this early out.
  if not comment:find(":", 1, true) then
    return nil
  end

  -- Inline code inside a comment is a *mention* of a marker, not a marker:
  -- this module's own header contains the line "`-- TODO:`, `// FIXME:`,
  -- `-- PERF:`", and the first version of it reported three open items in
  -- prose describing the feature. Blanked to spaces rather than deleted so
  -- every byte offset below still refers to the real line.
  local masked = comment
  if comment:find("`", 1, true) then
    masked = comment:gsub("`[^`]*`", function(m)
      return string.rep(" ", #m)
    end)
  end

  local best
  for _, sp in ipairs(SPELLINGS) do
    -- `%f[%w]` is a frontier pattern: it forbids a preceding word character
    -- so `AUTOTODO:` is not a todo, while still allowing the keyword to
    -- follow a space, a dash, or the comment opener itself. The plain find
    -- first: a keyword that is not on the line at all needs no pattern.
    local at
    if masked:find(sp.word, 1, true) then
      at = masked:find(sp.plain_pat)
      if not at then
        at = masked:find(sp.author_pat)
      end
    end
    -- **Leftmost wins**, and only then longest. Iterating longest-first and
    -- returning the first hit made the reported keyword depend on how many
    -- letters it has rather than on where it sits, so a line mentioning both
    -- `TODO` and `FIXME` was filed under FIX regardless of which came first.
    if at and (not best or at < best.at or (at == best.at and #sp.word > #best.word)) then
      best = { at = at, sp = sp }
    end
  end
  if not best then
    return nil
  end

  local sp = best.sp
  local tail = comment:sub(best.at)
  local author, text = tail:match("^" .. sp.word .. "%s*%(([^)]*)%)%s*:%s*(.*)$")
  if author then
    return sp.name, sp.word, author ~= "" and author or nil, vim.trim(text)
  end
  local plain = tail:match("^" .. sp.word .. "%s*:%s*(.*)$")
  if plain then
    return sp.name, sp.word, nil, vim.trim(plain)
  end
  return nil
end

---@type table<string, vim.treesitter.Query|false>
local comment_queries = {}

---One query per grammar that captures every comment node it has.
---
---**Why a query and not a walk.** The first version visited every node of
---every file from Lua (`node:type()` and `iter_children()` per node) and was
---7% of a `generate` over lib.nvim on its own; a query walks the tree in C
---and hands back only the comments. Built from the names in `nodes` that
---this grammar actually defines -- a query naming a node type the grammar
---lacks does not parse at all, so each name is probed on its own. Cached per
---grammar, including the answer "none of them" (`false`).
---@param grammar string
---@param nodes table<string, boolean>
---@return vim.treesitter.Query?
local function comment_query(grammar, nodes)
  local cached = comment_queries[grammar]
  if cached ~= nil then
    return cached or nil
  end
  local names = vim.tbl_keys(nodes)
  table.sort(names)
  local known = {}
  for _, name in ipairs(names) do
    if pcall(vim.treesitter.query.parse, grammar, "(" .. name .. ") @c") then
      known[#known + 1] = "(" .. name .. ")"
    end
  end
  ---@type vim.treesitter.Query|false
  local query = false
  if #known > 0 then
    local ok, q =
      pcall(vim.treesitter.query.parse, grammar, "[" .. table.concat(known, " ") .. "] @c")
    query = ok and q or false
  end
  comment_queries[grammar] = query
  return query or nil
end

---Ask the parser which parts of the file are comments.
---
---**The accurate path, and the reason the text scanner below is a fallback
---rather than the design.** Comment syntax matched textually cannot know
---that `"-- TODO: x"` inside a string literal is data: `--` opens a comment
---everywhere else on the line, and this repository's own renderer — which
---writes JavaScript inside Lua strings and documents the marker syntaxes it
---recognises — was reported as carrying three open to-dos that do not
---exist. A grammar knows the difference; a regular expression cannot be
---made to.
---
---`nil` when there is no grammar for this backend or it is not installed,
---which is a real and supported state (the standalone binary ships without
---grammars unless `DOCMAP_TS_DIR` points at them). The caller falls back to
---the text scanner rather than reporting nothing.
---@param src string
---@param backend Docmap.LangBackend?
---@return { text: string, row: integer }[]? comments Each with its 0-based start row.
local function parsed_comments(src, backend)
  if not backend or not backend.grammar then
    return nil
  end
  -- Inside a scan this is the tree the backend's own `scan_file` just parsed
  -- for the same source (see `core/ts_parse.lua`).
  local tree_root = require("docmap.core.ts_parse").root(src, backend.grammar)
  if not tree_root then
    return nil
  end

  local out = {}

  ---What a grammar calls a comment.
  ---
  ---Not one name: Lua and Zig produce `comment`, Java produces
  ---`line_comment` and `block_comment`, and this set is the difference
  ---between a backend reporting its markers and reporting none. It failed
  ---in the quiet direction — the parser answered with an empty list, which
  ---reads as "this file has no comments" rather than as "this grammar was
  ---not understood", so the text fallback never ran either. Found by
  ---`backend_contract_spec.lua`, which is why that spec proves the token
  ---*works* rather than that it is declared.
  ---
  ---**The last three arrived together, and in the same quiet direction.**
  ---The parity audit (`scripts/parity.lua`) walked every backend's fixture
  ---looking for nodes that begin with a declared comment token and are not
  ---in this set, and found one per grammar in three languages: Haskell's
  ---`haddock` (a `-- |` block, which swallows the plain `--` lines that
  ---follow it, so a marker on the second line of a documented declaration
  ---was invisible), Kotlin's `multiline_comment` (every `/* */` and every
  ---KDoc block — declared in `block_comments` and never read), and Dart's
  ---`documentation_comment` (`///`, which is where a Dart author writes
  ---almost everything). All three are the *doc* comment of their language,
  ---which is precisely where a `TODO:` about a declaration goes.
  ---
  ---`backend_contract_spec.lua` could not have caught these: it proves the
  ---token works by building the smallest file that could hold a marker, and
  ---the smallest file always lands in a plain `comment` node. Finding them
  ---needed a file with a *documented declaration* in it.
  local COMMENT_NODES = {
    comment = true,
    line_comment = true,
    block_comment = true,
    haddock = true,
    multiline_comment = true,
    documentation_comment = true,
  }

  local query = comment_query(backend.grammar, COMMENT_NODES)
  if not query then
    return out
  end

  -- Collected first, then reduced to the outermost nodes: a grammar may nest
  -- one comment node in another (a `haddock` block around plain comments),
  -- and the outer one carries the whole text. The Lua tree walk this
  -- replaced stopped descending at the first comment node; a query reports
  -- both, in an order that is not specified for two nodes starting at the
  -- same byte, so the reduction sorts instead of trusting the order.
  ---@type { s: integer, e: integer, row: integer }[]
  local spans = {}
  for _, node in query:iter_captures(tree_root, src) do
    local srow, _, sbyte = node:start()
    local _, _, ebyte = node:end_()
    spans[#spans + 1] = { s = sbyte, e = ebyte, row = srow }
  end
  table.sort(spans, function(a, b)
    if a.s ~= b.s then
      return a.s < b.s
    end
    return a.e > b.e
  end)
  local covered = -1
  for _, sp in ipairs(spans) do
    if sp.s >= covered then
      -- The node's own bytes, not the lines it sits on. Taking whole lines
      -- would put the code back in — and `local s = "TODO: x" -- TODO: real`
      -- would report the string literal, since the leftmost keyword wins.
      out[#out + 1] = { text = src:sub(sp.s + 1, sp.e), row = sp.row }
      covered = sp.e
    end
  end
  return out
end

---Drop a block comment's closing delimiter off the end of a marker's text.
---
---Only the parser path needs this. The text scanner below already slices a
---line at the closer before it ever reaches `match_marker`, but a parsed
---comment node carries its *whole* span — delimiters included — so
---`/* TODO: cap it */` came out as the text "cap it */". The closer is
---punctuation belonging to the comment, not to the note, and it was being
---rendered into the Notes tab.
---
---Anchored to the end and applied once: a note that legitimately ends in
---`*/` cannot be told apart from one that does not, and the only reading
---that is right more often is "this is the delimiter".
---`text` is typed optional because `match_marker`'s fourth return is: a
---marker with a name always has one, but saying so here would need an
---assertion at the only call site to prove what the branch already knows.
---@param text string?
---@param syn { line: string[], block: { [1]: string, [2]: string }[] }
---@return string
local function strip_closer(text, syn)
  if not text or text == "" then
    return ""
  end
  for _, block in ipairs(syn.block) do
    local closer = block[2]
    if #text >= #closer and text:sub(-#closer) == closer then
      return vim.trim(text:sub(1, -#closer - 1))
    end
  end
  return text
end

---Collect marker comments from source text.
---
---Takes text rather than a path so the caller that already read the file
---for something else does not read it twice, and so a spec can hand it a
---string. `scan_source` over `scan_file` for the same reason
---`deps.extract_source` is shaped that way.
---@param src string
---@param backend Docmap.LangBackend?
---@return Docmap.MarkerNote[]
function M.scan_source(src, backend)
  local syn = syntax(backend)
  if not syn then
    return {}
  end

  -- The parser first, and only its output when it answers: a file whose
  -- grammar is installed gets comment boundaries that are correct rather
  -- than plausible.
  local parsed = parsed_comments(src, backend)
  if parsed then
    local out = {}
    for _, c in ipairs(parsed) do
      local offset = 0
      for line in (c.text .. "\n"):gmatch("([^\n]*)\n") do
        local name, word, author, note = match_marker(line)
        if name then
          out[#out + 1] = {
            kind = name,
            word = word,
            author = author,
            text = strip_closer(note, syn),
            line = c.row + offset + 1,
          }
        end
        offset = offset + 1
      end
    end
    -- Tree order is not line order for a file whose comments hang off
    -- different branches, and the Notes tab reads top to bottom.
    table.sort(out, function(a, b)
      return a.line < b.line
    end)
    return out
  end

  local out = {}
  local line_no = 0
  -- Which block comment is currently open, so a marker on the third line of
  -- a `--[[ ... ]]` is found. Without this, a block-commented-out region is
  -- invisible here — and commenting a region out is one of the more common
  -- reasons a `-- TODO:` exists in the first place.
  local open_block = nil

  for text in (src .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local rest, comment = text, nil

    if open_block then
      local close = rest:find(esc(open_block[2]))
      if close then
        comment = rest:sub(1, close - 1)
        rest = rest:sub(close + #open_block[2])
        open_block = nil
      else
        comment = rest
        rest = ""
      end
    end

    if not open_block and rest ~= "" then
      local at, block = comment_start(rest, syn)
      -- An odd number of backticks before the opener means the opener is
      -- itself inside a code span, so it is prose rather than a comment.
      -- This module's own renderer is the case that found it: `html.lua`
      -- writes JavaScript inside Lua strings and documents the syntaxes it
      -- recognises, and a line reading ``-- These read `-- TODO:` ...`` was
      -- read as a Lua comment — because it contains `--` — and reported as
      -- five open to-dos with mangled text. A confidently wrong to-do list
      -- is worse than a short one.
      if at and select(2, rest:sub(1, at - 1):gsub("`", "")) % 2 == 1 then
        at = nil
      end
      if at then
        local tail = rest:sub(at)
        if block then
          local close = tail:find(esc(block[2]))
          if close then
            tail = tail:sub(1, close - 1)
          else
            open_block = block
          end
        end
        comment = comment and (comment .. " " .. tail) or tail
      end
    end

    if comment then
      local name, word, author, note = match_marker(comment)
      if name then
        out[#out + 1] = {
          kind = name,
          word = word,
          author = author,
          text = note,
          line = line_no,
        }
      end
    end
  end

  return out
end

---Collect marker comments from a file.
---@param path string Absolute path.
---@param backend Docmap.LangBackend?
---@return Docmap.MarkerNote[]
function M.scan_file(path, backend)
  local fd = io.open(path, "rb")
  if not fd then
    return {}
  end
  local src = fd:read("*a")
  fd:close()
  return M.scan_source(src, backend)
end

return M
