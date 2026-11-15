-- TESTS/i18n_messages_spec.lua — every message a person reads comes out of the catalog (docs/i18n.md).
--
-- The gate on the three surfaces that speak in sentences: the editor messages, `:checkhealth`, and the report
-- of the engine. Read off the sources as text, so a message added tomorrow is covered without this file being
-- told:
--   (a) a key a source names is in `en.json`. A key is any string literal shaped like one in the namespaces
--       `editor.`, `health.`, `cli.` and `report.`, which also covers `cond and "a.b" or "a.c"`. A literal that
--       is continued with `..` is the front of a computed key and has to be the front of one key at least;
--   (b) a key of those namespaces in `en.json` is named by a source: a text nothing prints is dead weight in
--       every translation;
--   (c) a call that prints (a `notify` instance, `vim.health`, `io.stdout`/`io.stderr`) hands over no English
--       of its own: outside `i18n.t(...)` its arguments hold no string literal with a letter in it.
--
-- And `:checkhealth` is run once as a whole, since no other spec prints it: no text missing from the catalog,
-- no placeholder left unfilled, and a catalog that failed to load is named.
--
-- What (c) cannot see, said here rather than implied: a sentence built into a variable first and printed
-- later (`notify.warn(err)` with `err` from another module), and whether the parameters inside `t(...)` are
-- data or prose. Both are review's to catch. The cases it sees and has to let through are in `DATA` below,
-- each with its reason, and an entry nothing needs any more fails the spec.

return function(H)
  local ok, eq = H.ok, H.eq

  local i18n = require("docmap.core.i18n")
  i18n._reset()
  local messages = assert(i18n.catalog("en"), "messages: en.json loads").messages

  local NAMESPACES = { editor = true, health = true, cli = true, report = true }

  -- Not interface text, so not held to (c): the generated page has its own catalog route, and the MCP server
  -- answers a program.
  local OUT_OF_SCOPE = { "^lua/docmap/core/render/", "^lua/docmap/mcp/" }

  -- The calls that put text in front of a person. `notify%.` matches `ctx.notify.warn(` too.
  local SINKS = {
    "notify%.warn%(",
    "notify%.info%(",
    "notify%.error%(",
    "vim%.notify%(",
    "vim%.notify_once%(",
    "nvim_echo%(",
    "nvim_err_writeln%(",
    "h_start%(",
    "h_ok%(",
    "h_warn%(",
    "h_error%(",
    "h_info%(",
    "vim%.health%.[%a_]+%(",
    "io%.stdout:write%(",
    "io%.stderr:write%(",
  }

  -- Calls whose literals are no message: a key and its parameters, or a module name.
  local CATALOG_CALLS = { "i18n%.t%(", "i18n%.has%(", "advice%(", "require%(" }

  -- Literals with letters that a printing call may hold all the same, by file. The value says why.
  local DATA = {
    ["lua/docmap/editor/health.lua"] = {
      ["interface catalog %s.json is not loaded: %s"] = "reports a broken source catalog, so it cannot be read from it",
    },
    ["standalone/docmap.lua"] = {
      ["standalone/docmap.lua: %s not found (probed require('%s')).\\n"] = "printed while docmap.nvim, and with it the catalog, may be the thing that is missing",
      ["  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\\n"] = "the same line's second half",
      ["standalone/docmap.lua: "] = "the program's name in front of an `--api=` error a host reads",
    },
  }

  ---A source with its comments blanked, and the same again with the string bodies blanked too.
  ---
  ---Both keep every byte's position, so an offset found in one is the same place in the other: calls are
  ---looked for where neither a comment nor a string can fake one, and the literals are read from the spans.
  ---@param text string
  ---@return string bare Comments and string bodies are spaces.
  ---@return { from: integer, to: integer, body: string }[] strings Quoted literals, in order.
  local function lex(text)
    local out, strings = {}, {}
    local i, n = 1, #text
    while i <= n do
      local at = text:find("[-\"'%[]", i)
      if not at then
        out[#out + 1] = text:sub(i)
        break
      end
      out[#out + 1] = text:sub(i, at - 1)
      local c = text:sub(at, at)
      local stop
      if c == "-" then
        if text:sub(at, at + 1) ~= "--" then
          out[#out + 1] = c
          stop = at
        else
          local level = text:match("^%-%-%[(=*)%[", at)
          if level then
            stop = select(2, text:find("]" .. level .. "]", at, true)) or n
          else
            stop = (text:find("\n", at, true) or n + 1) - 1
          end
          out[#out + 1] = (text:sub(at, stop):gsub("[^\n]", " "))
        end
      elseif c == "[" then
        local level = text:match("^%[(=*)%[", at)
        if level then
          stop = select(2, text:find("]" .. level .. "]", at, true)) or n
          out[#out + 1] = (text:sub(at, stop):gsub("[^\n]", " "))
        else
          out[#out + 1] = c
          stop = at
        end
      else
        local j = at + 1
        while j <= n do
          local d = text:sub(j, j)
          if d == "\\" then
            j = j + 2
          elseif d == c or d == "\n" then
            break
          else
            j = j + 1
          end
        end
        stop = math.min(j, n)
        strings[#strings + 1] = { from = at, to = stop, body = text:sub(at + 1, stop - 1) }
        out[#out + 1] = c .. (" "):rep(stop - at - 1) .. c
      end
      i = stop + 1
    end
    return table.concat(out), strings
  end

  ---The offset of the `)` that closes the `(` at `open`.
  ---@param bare string
  ---@param open integer
  ---@return integer
  local function closing(bare, open)
    local depth, i = 0, open
    while true do
      local at = bare:find("[()]", i)
      if not at then
        return #bare
      end
      depth = depth + (bare:sub(at, at) == "(" and 1 or -1)
      if depth == 0 then
        return at
      end
      i = at + 1
    end
  end

  ---True when a literal says something: a letter is left once escapes and format directives are gone.
  ---@param body string
  ---@return boolean
  local function has_words(body)
    local rest = body:gsub("\\.", ""):gsub("%%[-+ #0-9.]*%a", "")
    return rest:find("%a") ~= nil
  end

  local files = vim.fs.find(function(name)
    return name:sub(-4) == ".lua"
  end, { path = "lua/docmap", type = "file", limit = math.huge })
  files[#files + 1] = "standalone/docmap.lua"
  table.sort(files)
  ok(#files > 100, "messages: the sources are found (" .. #files .. " files)")

  local used, prefixes = {}, {}
  local sinks_seen, allowed_seen = 0, {}

  for _, path in ipairs(files) do
    local file = path:gsub("\\", "/")
    local bare, strings = lex(assert(H.slurp(file), file .. " is readable"))

    -- (a) every key a source names exists.
    for _, s in ipairs(strings) do
      local namespace = s.body:match("^(%l+)%.[%w_.-]*$")
      -- `health.lua` is a file name, not a key.
      if namespace and NAMESPACES[namespace] and not s.body:match("%.lua$") then
        if bare:match("^%s*%.%.", s.to + 1) or s.body:sub(-1) == "." then
          local front = false
          for key in pairs(messages) do
            if key:sub(1, #s.body) == s.body then
              front = true
              break
            end
          end
          ok(front, ("%s: no key in en.json starts with %q"):format(file, s.body))
          prefixes[#prefixes + 1] = s.body
        else
          ok(messages[s.body] ~= nil, ("%s: the key %q is not in en.json"):format(file, s.body))
        end
        used[s.body] = true
      end
    end

    -- (c) a printing call hands over catalog text.
    local scoped = true
    for _, pattern in ipairs(OUT_OF_SCOPE) do
      scoped = scoped and not file:match(pattern)
    end
    if scoped then
      -- The spans whose literals are no message.
      local catalog = {}
      for _, pattern in ipairs(CATALOG_CALLS) do
        local from = 1
        while true do
          local at, open = bare:find(pattern, from)
          if not at or not open then
            break
          end
          catalog[#catalog + 1] = { from = open, to = closing(bare, open) }
          from = open + 1
        end
      end
      for _, pattern in ipairs(SINKS) do
        local from = 1
        while true do
          local at, open = bare:find(pattern, from)
          if not at or not open then
            break
          end
          from = open + 1
          -- `local function h_info(msg, advice)` declares a sink, it does not call one.
          local declared = bare:sub(math.max(1, at - 9), at - 1):match("function%s+$")
          if not declared then
            sinks_seen = sinks_seen + 1
            local close = closing(bare, open)
            for _, s in ipairs(strings) do
              if s.from > open and s.to < close and has_words(s.body) then
                local inside = false
                for _, span in ipairs(catalog) do
                  inside = inside or (s.from > span.from and s.to < span.to)
                end
                local reason = (DATA[file] or {})[s.body]
                if reason then
                  allowed_seen[file .. "\0" .. s.body] = true
                end
                local line = select(2, bare:sub(1, s.from):gsub("\n", "")) + 1
                ok(
                  inside or reason ~= nil,
                  ("%s:%d: a message that is not in the catalog: %q"):format(file, line, s.body)
                )
              end
            end
          end
        end
      end
    end
  end

  ok(sinks_seen > 150, "messages: the printing calls are found (" .. sinks_seen .. ")")
  print(("  messages: %d printing calls read"):format(sinks_seen))

  for file, entries in pairs(DATA) do
    for body in pairs(entries) do
      ok(
        allowed_seen[file .. "\0" .. body],
        ("%s: DATA lets a literal through that no printing call holds any more: %q"):format(
          file,
          body
        )
      )
    end
  end

  -- (b) every key of these namespaces is named by a source.
  local dead = {}
  for key in pairs(messages) do
    if NAMESPACES[key:match("^[^.]+")] and not used[key] then
      local computed = false
      for _, front in ipairs(prefixes) do
        computed = computed or key:sub(1, #front) == front
      end
      if not computed then
        dead[#dead + 1] = key
      end
    end
  end
  table.sort(dead)
  eq(table.concat(dead, ", "), "", "messages: a key in en.json that no source names")

  -- ── :checkhealth, run ────────────────────────────────────────────────────
  -- The one surface no other spec prints as a whole. Run against this checkout with `vim.health` replaced, so
  -- a key that is missing or a placeholder nobody filled shows up as the text a person would have read.

  ---Every line one `:checkhealth` writes: the report calls in order, each advice line as a line of its own.
  ---@return { kind: string, text: string }[]
  local function checkhealth()
    local lines = {}
    local function sink(kind)
      return function(msg, advice)
        lines[#lines + 1] = { kind = kind, text = tostring(msg) }
        for _, hint in ipairs(type(advice) == "table" and advice or {}) do
          lines[#lines + 1] = { kind = "advice", text = tostring(hint) }
        end
      end
    end
    -- Both modules bind `vim.health`'s functions when they load, so both are loaded afresh for the run and
    -- put back after it: a later spec must not report into this one's list.
    local BOUND = { "docmap.editor.health", "lib.nvim.deps.health" }
    local saved, loaded = vim.health, {}
    for _, name in ipairs(BOUND) do
      loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    vim.health = {
      start = sink("start"),
      ok = sink("ok"),
      warn = sink("warn"),
      error = sink("error"),
      info = sink("info"),
    }
    local ran, err = pcall(function()
      require("docmap.editor.health").check()
    end)
    vim.health = saved
    for _, name in ipairs(BOUND) do
      package.loaded[name] = loaded[name]
    end
    ok(ran, "health: check() runs: " .. tostring(err))
    return lines
  end

  local healthy = checkhealth()
  ok(#healthy > 20, "health: the report has its lines (" .. #healthy .. ")")
  eq(healthy[1].kind, "start", "health: the report opens with a section")
  eq(healthy[1].text, "docmap.nvim: environment", "health: English is what it was")
  for _, line in ipairs(healthy) do
    ok(
      not line.text:find("‹", 1, true),
      "health: a text that is not in the catalog: " .. line.text
    )
    ok(not line.text:find("{[%l_]+}"), "health: a placeholder nobody filled: " .. line.text)
    ok(
      not line.text:find("interface catalog", 1, true),
      "health: a healthy catalog is not mentioned: " .. line.text
    )
  end

  -- A catalog that does not load is named, with the reason.
  package.preload["docmap.core.i18n.bundled"] = function()
    return { en = "{ not json" }
  end
  i18n._reset()
  local named
  for _, line in ipairs(checkhealth()) do
    if line.kind == "warn" and line.text:find("interface catalog en.json", 1, true) then
      named = line.text
    end
  end
  ok(
    named and named:find("is not loaded: not valid JSON", 1, true),
    "health: a catalog that failed to load is a warning with its reason: " .. tostring(named)
  )
  package.preload["docmap.core.i18n.bundled"] = nil
  package.loaded["docmap.core.i18n.bundled"] = nil
  i18n._reset()
end
