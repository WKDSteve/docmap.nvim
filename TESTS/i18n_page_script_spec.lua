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
-- The regions are listed below, each between two markers that are lines of the slice (no `to`: the end of the
-- slice), with the task that moved it. A task that moves another panel adds its region. `DATA` holds the
-- literals a region may keep, each with its reason, and an entry nothing needs any more fails the spec.

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
    {
      slice = "02_explorer_and_state",
      from = "  function godboltTrigger(kind, key){",
      to = "  function glossaryAnswer(tableName){",
      task = "i18n-page-tree-index-notes-quicks (the function cards)",
    },
    {
      slice = "02_explorer_and_state",
      from = "  function snippetHTML(fn, node){",
      to = "  // Artifact lives in out_dir",
      task = "i18n-page-tree-index-notes-quicks (the source snippet)",
    },
    {
      slice = "03_tree_findings_tabs_hierarchy",
      from = "  function renderDetail(n){",
      to = '    detailEl.innerHTML = h.join("");',
      task = "i18n-page-tree-index-notes-quicks (the Tree detail pane)",
    },
    {
      slice = "04_directed_views_and_notes",
      from = "  // Notes tab: Doxygen",
      task = "i18n-page-tree-index-notes-quicks (the Notes tab)",
    },
    {
      slice = "05_features_help_index",
      from = '  // Doxygen\'s "File Members"',
      task = "i18n-page-tree-index-notes-quicks (the Index tab)",
    },
    {
      slice = "04_directed_views_and_notes",
      from = "  function addExternals(built, maxDepth){",
      to = "  // Notes tab: Doxygen",
      task = "i18n-page-hierarchy-views (edges, boxes, legends, empty diagrams)",
    },
    {
      slice = "08_history_tree_treemap",
      from = "  // Tree and Treemap: the Hierarchy",
      task = "i18n-page-hierarchy-views (Tree, Treemap, the path line and notes)",
    },
    {
      slice = "10b_maps",
      from = "  var TINT_MODES = {",
      task = "i18n-page-hierarchy-views (tint, Coupling, Rings, Layers, Routes)",
    },
    {
      slice = "10_search_menus_popups",
      from = "  function renderLangBar(){",
      to = "  // Copy link",
      task = "i18n-page-hierarchy-views (the language legend)",
    },
    {
      slice = "10_search_menus_popups",
      from = "  // Context menu",
      to = "  // clipboard.writeText is unavailable",
      task = "i18n-page-hierarchy-views (the context menu)",
    },
    {
      slice = "10_search_menus_popups",
      from = "  function godboltTooLong(el, len){",
      to = '    el.classList.add("godi-off");',
      calls = 1,
      task = "i18n-page-hierarchy-views (the refusal of an over-long Compiler Explorer link)",
    },
    {
      slice = "11_quicks_compare_init",
      from = "  // Shape diff: two maps",
      task = "i18n-page-hierarchy-views (the map comparison)",
    },
    {
      slice = "06_analysis_tools",
      from = "  function anHead(cols){",
      task = "i18n-page-analysis-panels (every tool of the Analysis tab)",
    },
    {
      slice = "07_analysis_panels",
      from = "  // ── Checklist",
      to = '    return out.join("");\n  }',
      task = "i18n-page-analysis-panels (the Checklist)",
    },
    {
      slice = "08_history_tree_treemap",
      from = "  var histLoaded = false",
      to = "  // Tree and Treemap: the Hierarchy",
      task = "i18n-page-history-runtime-compare-features (History, a host that cannot answer)",
    },
    {
      slice = "07_analysis_panels",
      from = "  function drawAnalysisTelemetry(){",
      task = "i18n-page-history-runtime-compare-features (Telemetry, Startup, Loaded)",
    },
    {
      slice = "05_features_help_index",
      from = "  function featureCountLine(feats, theme){",
      to = "  var EXPLAIN = {",
      task = "i18n-page-history-runtime-compare-features (Features)",
    },
    {
      slice = "11_quicks_compare_init",
      from = "  // Compare — the marked objects",
      to = "  // Roving tabindex",
      task = "i18n-page-history-runtime-compare-features (Compare, Compiler Explorer)",
    },
  }

  -- Literals a region keeps although they read as text. Keyed by slice, then by the literal; the value says why.
  local KEYS = "a key name of KeyboardEvent.key, compared, never shown"
  local DATA = {
    ["04_directed_views_and_notes"] = {
      ["hedge hedge-dep external"] = "class names of an edge",
      ["hedge hedge-dep"] = "class names of an edge",
      ["hedge hedge-call"] = "class names of an edge",
      ["hedge hedge-call external"] = "class names of an edge",
      ["dep deferred"] = "class names of a legend swatch",
      ["dep external"] = "class names of a legend swatch",
      ["call weak"] = "class names of a legend swatch",
    },
    ["08_history_tree_treemap"] = {
      ["ArrowDown"] = KEYS,
      ["ArrowUp"] = KEYS,
      ["ArrowRight"] = KEYS,
      ["ArrowLeft"] = KEYS,
      ["Home"] = KEYS,
      ["End"] = KEYS,
      ["Enter"] = KEYS,
      ["tm-tile tm-solo"] = "class names of a treemap tile",
      ["htrunc hauto"] = "class names of the note under a diagram",
    },
    ["10b_maps"] = {
      ["ArrowDown"] = KEYS,
      ["ArrowUp"] = KEYS,
      ["ArrowRight"] = KEYS,
      ["ArrowLeft"] = KEYS,
      ["Home"] = KEYS,
      ["End"] = KEYS,
      ["Enter"] = KEYS,
      ["hedge hedge-dep hedge-quiet"] = "class names of an edge",
      ["hedge hedge-viol"] = "class names of an edge",
      ["htrunc hauto hring-note"] = "class names of the note under the Rings",
      ["htrunc hauto hmap-note"] = "class names of the note under the Layers",
      ["App Router"] = "the name Next.js gives the router, not a word of the page",
      ["Pages Router"] = "the name Next.js gives the router, not a word of the page",
      ["Next.js "] = "a product name before the router's name",
      ["hnode rt-"] = "class names of a route box",
    },
    ["06_analysis_tools"] = {
      ["LuaCATS"] = "where a tag comes from, the name of the annotation dialect",
      ["unsafe fn"] = "Rust's own words for an unsafe function",
      ["unsafe block"] = "Rust's own words for an unsafe block",
    },
    ["07_analysis_panels"] = {
      ["no namespace"] = "the host's reason, compared, never shown",
      ["no map generated yet"] = "the host's reason, compared, never shown",
      ["snapshot not found"] = "the host's reason, compared, never shown",
      ["no single root module prefix for this tree"] = "the host's reason, compared, never shown",
    },
    ["11_quicks_compare_init"] = {
      ["Enter"] = KEYS,
      ["hedge hedge-dep sd-del"] = "class names of a lost edge",
    },
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
    local b = a and (region.to and src:find(region.to, a, true) or (not region.to and #src + 1))
    ok(b, ("%s: the region ends at %q"):format(region.slice, tostring(region.to)))
    if a and b then
      local part = src:sub(a, b - 1)
      -- t() calls, and keys named for one (`EXPLAIN` lists keys and says them in one place).
      local calls = select(2, part:gsub("%f[%w_.]t%(", ""))
        + select(2, part:gsub('"page%.', ""))
        + select(2, part:gsub("i18nSpan%(", ""))
      ok(
        calls >= (region.calls or 3),
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

  -- The Notes tab says the line under each marker keyword from the catalog; its English is core/markers.lua's.
  local i18n = require("docmap.core.i18n")
  local notes = require("docmap.core.render.html.js.04_directed_views_and_notes")
  for _, kw in ipairs(require("docmap.core.markers").KEYWORDS) do
    local key = "page.notes.marker." .. kw.name:lower()
    ok(
      notes:find(("%s: %q"):format(kw.name, key), 1, true) ~= nil,
      "Notes: the keyword " .. kw.name .. " names its key"
    )
    eq(
      i18n.t(key, nil, "en"),
      kw.sub,
      "Notes: the English of " .. key .. " is the line markers.lua writes"
    )
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
