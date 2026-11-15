-- TESTS/i18n_page_spec.lua — the static markup of the generated page says nothing the catalog does not hold.
--
-- The gate on the first layer of the page that speaks through the catalog (docs/i18n.md, "The generated page"):
-- everything `core/render/html.lua` writes itself, before any script runs. A page is rendered from a fixture and
-- its static markup is walked:
--   * every text with a letter in it sits in an element that names its catalog key (`data-i18n`, or
--     `data-i18n-tail` behind a count), and is byte for byte the English text of that key; the exceptions are the
--     subject, each named below (the project title, a finding's check and severity, the tool's own name);
--   * every `title`, `placeholder` and `aria-label` names its key the same way (`data-i18n-<attribute>`);
--   * so a text added to html.lua without a key fails here, and so does a key whose English drifted from the
--     markup.
-- And around it:
--   * every catalog key the page's script names exists, and every `page.*` key is used by the renderer or the
--     script (no dead text);
--   * the page embeds every shipped catalog, narrowed to its own namespaces, and offers only the locales the
--     whole page speaks;
--   * a finding rides on the page as key and parameters beside its English sentence.
-- What a script draws later (the panels) is not seen from here: those texts move into the catalog panel by
-- panel, each with its own check. The page in a real window is TESTS/sheets/interface-language.sheet.lua.

return function(H)
  local ok, eq = H.ok, H.eq

  local i18n = require("docmap.core.i18n")
  local docmap = require("docmap")
  i18n._reset()

  local root = vim.fn.getcwd():gsub("\\", "/")
  local fixture = root .. "/TESTS/fixtures/maps_page"
  local opts = require("docmap.config").build(fixture, { source = "lua/app" })
  local ir, findings = docmap.scan_full(opts)
  -- One finding that brings its own prose, as `opts.extra_checks` does: it has no key to ride on.
  findings[#findings + 1] =
    { severity = "info", check = "their-check", node = nil, message = "their own words" }
  local html = docmap.render.html(ir, findings, opts)

  ---The English text of a key, as the page shows it.
  ---@param key string
  ---@param params table?
  ---@return string
  local function en(key, params)
    return i18n.t(key, params, "en")
  end

  ---Undo the escaping of markup: the named entities the renderer writes, and numeric ones.
  ---@param s string
  ---@return string
  local function unescape(s)
    s = s:gsub("&#(%d+);", function(n)
      return vim.fn.nr2char(tonumber(n), true)
    end)
    s = s:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">")
    return (s:gsub("&amp;", "&"))
  end

  ---The value of one attribute of a start tag, unescaped; nil when the tag has none.
  ---@param tag string
  ---@param name string
  ---@return string?
  local function attr(tag, name)
    local value = tag:match("%s" .. name:gsub("%-", "%%-") .. '="([^"]*)"')
    return value and unescape(value) or nil
  end

  ---The parameters a tag hands to its texts.
  ---@param tag string
  ---@return table?
  local function params_of(tag)
    local raw = attr(tag, "data-i18n-params")
    return raw and vim.json.decode(raw) or nil
  end

  -- ── The static markup: from <body> to the first embedded block ──────────
  local from = assert(html:find("<body>", 1, true), "the page has a body")
  local to =
    assert(html:find('<script type="application/json"', from, true), "the page embeds its data")
  local body = html:sub(from + #"<body>", to - 1)
  -- The startup flamegraph is a measurement somebody else drew, kept in a <template>.
  body = body:gsub("<template.-</template>", "")

  local VOID = { input = true, br = true, hr = true, img = true, meta = true, link = true }
  -- Text that is the subject, not the interface, by the element it sits in.
  local function is_subject(tag)
    local name = tag:match("^<(%w+)")
    local class = attr(tag, "class") or ""
    return name == "h1" -- the project's title
      or class:find("brand", 1, true) ~= nil -- "docmap.nvim", the tool's own name
      or class:find("sev", 1, true) ~= nil -- error / warn / info: the grade as the report spells it
      or class:find("kw", 1, true) ~= nil -- the id of a check
      or attr(tag, "data-finding") ~= nil -- the sentence of a finding, checked below
  end

  local stack, texts, attrs = {}, 0, 0
  local pos = 1
  while true do
    local lt, gt = body:find("<[^>]+>", pos)
    local text = body:sub(pos, (lt or #body + 1) - 1)
    if text:find("%a") then
      local parent = stack[#stack] or "<body>"
      texts = texts + 1
      local key, tail = attr(parent, "data-i18n"), attr(parent, "data-i18n-tail")
      if key then
        eq(
          unescape(text),
          en(key, params_of(parent)),
          "static text is the English of its key " .. key
        )
      elseif tail then
        local count = tonumber(body:sub(1, pos - 1):match("(%d+)</b>$"))
        ok(count ~= nil, "a tail text follows a count in <b>: " .. tail)
        eq(
          unescape(text),
          " " .. en(tail, { count = count }),
          "the label behind a count is the English of " .. tail
        )
      else
        ok(is_subject(parent), ("static text without a catalog key: %q in %s"):format(text, parent))
      end
    end
    if not lt then
      break
    end
    local tag = body:sub(lt, gt)
    if tag:sub(1, 2) == "</" then
      stack[#stack] = nil
    elseif tag:sub(1, 2) ~= "<!" then
      for _, name in ipairs({ "title", "placeholder", "aria-label" }) do
        local value = attr(tag, name)
        if value and value:find("%a") then
          attrs = attrs + 1
          local key = attr(tag, "data-i18n-" .. name)
          ok(key ~= nil, ("a static %s without a catalog key: %q in %s"):format(name, value, tag))
          if key then
            eq(
              value,
              en(key, params_of(tag)),
              ("the %s is the English of its key %s"):format(name, key)
            )
          end
        end
      end
      for key in tag:gmatch('data%-i18n[%w-]*="([%w_.-]+)"') do
        ok(i18n.has(key), "the markup names a key the catalog does not have: " .. key)
      end
      if not VOID[tag:match("^<(%w+)")] and tag:sub(-2) ~= "/>" then
        stack[#stack + 1] = tag
      end
    end
    pos = gt + 1
  end
  eq(
    #stack,
    0,
    "the walk closed every element it opened (else the checks above looked at the wrong parents)"
  )
  ok(texts >= 80, "the walk saw the texts of the chrome (got " .. texts .. ")")
  ok(attrs >= 20, "and its tooltips and labels (got " .. attrs .. ")")

  -- ── No case change in the stylesheet ─────────────────────────────────────
  -- Catalog text carries its own case (docs/i18n.md, "What is translated"): `text-transform` would upper-case a
  -- German or a Turkish label by English rules. The severity is the one exception, the subject as the report
  -- spells it.
  local css = require("docmap.core.render.html.css")
  local SUBJECT_CASE = { [".sev"] = true }
  local transforms = 0
  for selector, decls in css:gsub("/%*.-%*/", ""):gmatch("([^{}]+){([^{}]*)}") do
    local value = decls:match("text%-transform%s*:%s*([%w-]+)")
    if value then
      transforms = transforms + 1
      selector = vim.trim(selector)
      ok(
        SUBJECT_CASE[selector] ~= nil,
        ("the stylesheet changes the case of %s (text-transform:%s): write the label in its case in the catalog"):format(
          selector,
          value
        )
      )
    end
  end
  eq(transforms, 1, "the walk over the stylesheet found the one rule it allows")

  -- ── Keys of the script, and no dead text ─────────────────────────────────
  local src = H.html_source()
  for key in src:gmatch('"(page%.[%w_.-]*[%w_-])"') do
    ok(i18n.has(key), "the page names a key the catalog does not have: " .. key)
  end
  for _, key in ipairs(i18n.keys("page.")) do
    ok(src:find('"' .. key .. '"', 1, true), "a page key nothing uses: " .. key)
  end
  ok(
    src:find('t("finding." + f.key, f.params)', 1, true),
    "a finding is said from its key and parameters"
  )

  -- ── What rides on the page ───────────────────────────────────────────────
  local embedded =
    vim.json.decode(assert(html:match('<script type="application/json" id="i18n">(.-)</script>')))
  eq(embedded.source, "en", "embedded: the source locale is named")
  local offered = {}
  for i, locale in ipairs(embedded.locales) do
    eq(locale.code, i18n.LOCALES[i], "embedded: every shipped locale, in order")
    ok(embedded.catalogs[locale.code] ~= nil, "embedded: with its catalog: " .. locale.code)
    offered[#offered + 1] = locale.offered and locale.code or nil
  end
  -- German is embedded and reached by `lang=`, and joins this list when every panel of the page speaks through
  -- the catalog (task docmap.nvim/i18n-generated-page): until then a browser that asks for German gets English,
  -- not a page that is German in its header and English below it.
  eq(
    table.concat(offered, ","),
    "en",
    "embedded: only the locales the whole page speaks are offered"
  )
  for code, messages in pairs(embedded.catalogs) do
    for key in pairs(messages) do
      ok(
        key:match("^page%.") or key:match("^finding%.") or key:match("^report%."),
        ("embedded: %s carries a key the page does not read: %s"):format(code, key)
      )
    end
  end
  eq(embedded.catalogs.en["page.tab.hierarchy"], "Hierarchy", "embedded: the English text")
  eq(embedded.catalogs.de["page.tab.hierarchy"], "Hierarchie", "embedded: and the German one")

  local data = vim.json.decode(
    assert(html:match('<script type="application/json" id="findings%-data">(.-)</script>'))
  )
  eq(#data, #findings, "findings: all of them ride on the page")
  local with_key = 0
  for i, f in ipairs(data) do
    local cell = html:match('<td class="msg" data%-finding="' .. (i - 1) .. '">(.-)</td>')
    eq(
      unescape(cell or ""),
      f.message,
      "findings: row " .. i .. " shows the English sentence it carries"
    )
    if f.key then
      with_key = with_key + 1
      eq(
        i18n.t("finding." .. f.key, f.params, "en"),
        f.message,
        "findings: key and parameters say the same"
      )
    end
  end
  eq(with_key, #findings - 1, "findings: every finding of the catalog carries its key")
  eq(data[#data].key, nil, "findings: prose of a foreign check carries none")
  eq(data[#data].message, "their own words", "findings: and keeps its words")

  -- The runtime is in front of the script that uses it.
  local runtime =
    assert(html:find("function docmapI18n(data){", 1, true), "the page carries the runtime")
  local first_use = assert(html:find("var I18N = docmapI18n(", 1, true), "and the script builds it")
  ok(runtime < first_use, "the runtime is defined before it is used")
end
