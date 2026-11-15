-- TESTS/i18n_page_script_spec.lua — the panels of the page that speak through the catalog hold no English.
--
-- The pattern of `i18n_messages_spec.lua` (c), applied to the page's script: a region of a slice that has been
-- moved into the catalog (docs/i18n.md, "The generated page") is read as JavaScript, and every string literal in
-- it that reads as interface text is an offence. A text belongs in `en.json` and is said with `t(key, params)`.
--
-- What counts as interface text, after the markup inside a literal is taken out (tags, attributes, entities):
--   * a word that starts upper case and goes on lower case ("Why", "Fields"), or
--   * two words with a space between them ("not known").
-- A literal of one lower-case word is not seen ("call", "mouseover", a class name, a key): the check cannot tell
-- a word shown to the reader from a word handed to the DOM, and says so here rather than pretending. A literal
-- that is the first argument of `t(`, `I18N.t(` or `I18N.has(` is a key and is passed.
--
-- The regions are listed below, each between two markers that are lines of the slice, with the task that moved
-- it. A task that moves another panel adds its region. `DATA` holds the literals a region may keep, each with
-- its reason, and an entry nothing needs any more fails the spec.

return function(H)
  local ok, eq = H.ok, H.eq

  local REGIONS = {
    {
      slice = "01_marks_and_dimming",
      from = "  // The lookup layer",
      to = "  var FENCE_EXT = {",
      task = "i18n-page-explanations-and-lookup-cards",
    },
    {
      slice = "02_explorer_and_state",
      from = "  function glossaryAnswer(tableName){",
      to = "  // Which spans of a snippet are *not* code.",
      task = "i18n-page-explanations-and-lookup-cards",
    },
    {
      slice = "05_features_help_index",
      from = "  var EXPLAIN = {",
      to = "  // The second level",
      task = "i18n-page-explanations-and-lookup-cards",
    },
    {
      slice = "11_quicks_compare_init",
      from = "  var QUICKS = IR.quicks",
      to = "  // =====================================================================\n  // Compare",
      task = "i18n-page-tree-index-notes-quicks (the Quicks panel)",
    },
  }

  -- Literals a region keeps although they read as text. Keyed by slice, then by the literal; the value says why.
  local DATA = {
    ["05_features_help_index"] = {
      ["sigpop explainpop"] = "two class names of the card's element",
      ["Escape"] = "a key name of KeyboardEvent.key, compared, never shown",
    },
  }

  ---The string literals of a piece of JavaScript, each with the code in front of it on its line.
  ---Comments are skipped; so are regular expression literals, told from a division by what precedes them.
  ---@param src string
  ---@return { text: string, before: string }[]
  local function literals(src)
    local out, i, n = {}, 1, #src
    local last = "" -- the last significant character outside strings and comments
    local function line_before(pos)
      local start = pos
      while start > 1 and src:sub(start - 1, start - 1) ~= "\n" do
        start = start - 1
      end
      return src:sub(start, pos - 1)
    end
    while i <= n do
      local c = src:sub(i, i)
      local two = src:sub(i, i + 1)
      if two == "//" then
        i = (src:find("\n", i, true) or n) + 1
      elseif two == "/*" then
        i = (select(2, src:find("*/", i + 2, true)) or n) + 1
      elseif c == '"' or c == "'" or c == "`" then
        local j, buf = i + 1, {}
        while j <= n do
          local d = src:sub(j, j)
          if d == "\\" then
            buf[#buf + 1] = src:sub(j + 1, j + 1)
            j = j + 2
          elseif d == c then
            break
          else
            buf[#buf + 1] = d
            j = j + 1
          end
        end
        out[#out + 1] = { text = table.concat(buf), before = line_before(i) }
        last = c
        i = j + 1
      elseif c == "/" and (last == "" or last:find("[%(,=:%[!&|%?{};]")) then
        -- A regular expression literal: to its closing slash, past escapes and character classes.
        local j, class = i + 1, false
        while j <= n do
          local d = src:sub(j, j)
          if d == "\\" then
            j = j + 1
          elseif d == "[" then
            class = true
          elseif d == "]" then
            class = false
          elseif d == "/" and not class then
            break
          end
          j = j + 1
        end
        last = "/"
        i = j + 1
      else
        if not c:find("%s") then
          last = c
        end
        i = i + 1
      end
    end
    return out
  end

  ---What is left of a literal once the markup in it is taken out.
  ---@param s string
  ---@return string
  local function words_of(s)
    s = s:gsub("<[^>]*>", " ")
    s = s:gsub('[%w-]+%s*=%s*"[^"]*"?', " "):gsub("[%w-]+%s*=%s*'[^']*'?", " ")
    s = s:gsub("</?%a+", " "):gsub("&#?%w+;", " "):gsub(">", " ")
    return s
  end

  local function reads_as_text(s)
    return s:find("%f[%a]%u%l") ~= nil or s:find("%a%a+%s+%a%a+") ~= nil
  end

  local used = {}
  local seen_literals = 0
  for _, region in ipairs(REGIONS) do
    local src = require("docmap.core.render.html.js." .. region.slice)
    local a = src:find(region.from, 1, true)
    ok(a ~= nil, ("%s: the region starts at %q"):format(region.slice, region.from))
    local b = a and src:find(region.to, a, true)
    ok(b ~= nil, ("%s: the region ends at %q"):format(region.slice, region.to))
    if a and b then
      local part = src:sub(a, b - 1)
      -- t() calls, and keys named for one (`EXPLAIN` lists keys and says them in one place).
      local calls = select(2, part:gsub("%f[%w_.]t%(", "")) + select(2, part:gsub('"page%.', ""))
      ok(
        calls >= 3,
        ("%s: the region says its texts through t() (%d calls)"):format(region.slice, calls)
      )
      for _, lit in ipairs(literals(part)) do
        seen_literals = seen_literals + 1
        local is_key = lit.before:find("t%(%s*$") or lit.before:find("I18N%.has%(%s*$")
        local text = words_of(lit.text)
        if not is_key and reads_as_text(text) then
          local allowed = DATA[region.slice] and DATA[region.slice][lit.text]
          if allowed then
            used[region.slice .. "\0" .. lit.text] = true
          end
          ok(
            allowed ~= nil,
            ("%s (%s): English outside t(): %q — a catalog key with the text in en.json and de.json"):format(
              region.slice,
              region.task,
              lit.text
            )
          )
        end
      end
    end
  end
  ok(seen_literals >= 100, "the walk saw the literals of the regions (got " .. seen_literals .. ")")
  for slice, entries in pairs(DATA) do
    for text in pairs(entries) do
      ok(
        used[slice .. "\0" .. text],
        ("DATA: %s keeps %q, which no region holds any more"):format(slice, text)
      )
    end
  end

  -- The tokenizer itself, on the cases it has to tell apart.
  local probe = literals([[
    var a = t("page.x"), b = "Plain words", c = '<div class="kw">'; // "Comment words"
    var r = /["']Not a literal/; /* "Block words" */ var d = x / 2 + "Div words";
  ]])
  local texts = {}
  for _, l in ipairs(probe) do
    texts[#texts + 1] = l.text
  end
  eq(
    table.concat(texts, "|"),
    'page.x|Plain words|<div class="kw">|Div words',
    "literals: strings found, comments and regular expressions skipped"
  )
  eq(
    vim.trim(words_of('<span class="kw-n">' .. "' + n + '")),
    "' + n + '",
    "markup: tags and attributes go"
  )
  ok(reads_as_text("Why") and reads_as_text("not known"), "text: a capital word, two words")
  ok(
    not reads_as_text("mouseover") and not reads_as_text("kw-word"),
    "text: one lower-case word is not"
  )
end
