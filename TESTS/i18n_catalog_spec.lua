-- TESTS/i18n_catalog_spec.lua — the catalog files keep the format docs/i18n.md states.
--
-- The gate on `lua/docmap/core/i18n/<locale>.json`:
--   * the files on disk and `i18n.LOCALES` name the same locales;
--   * a file is `{ locale, name, tier, messages }`, its `locale` is its own name, `en` alone is the source;
--   * one message per line, the keys sorted and written once (a JSON decoder keeps the last of two equal keys
--     without a word, which is how a text goes dead in a catalog), each in a known namespace;
--   * a message is a text or a table of plural categories with `other`;
--   * a translation has no key and no placeholder its source lacks, and the same shape (text or plural);
--   * a `maintained` or `contributed` locale is complete: every key of the source is translated.
-- And one behaviour: the packaged binary's bundle (`docmap.core.i18n.bundled`) wins over the files.

return function(H)
  local ok, eq = H.ok, H.eq

  local i18n = require("docmap.core.i18n")
  i18n._reset()

  local DIR = "lua/docmap/core/i18n"
  -- The first segment of a key says which surface owns the text (docs/i18n.md, "Keys").
  local NAMESPACES = {
    finding = true,
    report = true,
    check = true,
    editor = true,
    health = true,
    cli = true,
    page = true,
  }
  local TIERS = { source = true, maintained = true, contributed = true, machine = true }
  local CATEGORIES = { zero = true, one = true, two = true, few = true, many = true, other = true }

  -- ── Files and registry agree ─────────────────────────────────────────────
  local on_disk = {}
  for name, kind in vim.fs.dir(DIR) do
    local code = kind == "file" and name:match("^(.+)%.json$")
    if code then
      on_disk[code] = true
    end
  end
  for _, code in ipairs(i18n.LOCALES) do
    ok(
      on_disk[code],
      ("catalog: %s is in i18n.LOCALES and has no %s/%s.json"):format(code, DIR, code)
    )
    on_disk[code] = nil
  end
  eq(
    next(on_disk),
    nil,
    "catalog: a <locale>.json that i18n.LOCALES does not name: " .. tostring(next(on_disk))
  )
  eq(i18n.LOCALES[1], "en", "catalog: the source locale leads the list")

  ---The placeholders of a text, as a set.
  ---@param text string
  ---@return table<string, true>
  local function placeholders(text)
    local set = {}
    for name in text:gmatch("{([%w_]+)}") do
      set[name] = true
    end
    return set
  end

  ---Every text of one entry: the text itself, or each plural form.
  ---@param entry string|table<string, string>
  ---@return string[]
  local function texts(entry)
    if type(entry) == "string" then
      return { entry }
    end
    local out = {}
    for _, form in pairs(entry) do
      out[#out + 1] = form
    end
    return out
  end

  local source = assert(i18n.catalog("en"), "catalog: en.json loads")

  for _, code in ipairs(i18n.LOCALES) do
    local file = ("%s/%s.json"):format(DIR, code)
    local doc = i18n.catalog(code)
    ok(doc ~= nil, ("catalog: %s loads (%s)"):format(file, tostring(i18n.problems()[code])))
    if doc then
      eq(doc.locale, code, file .. ": `locale` is the file's own name")
      ok(type(doc.name) == "string" and doc.name ~= "", file .. ": `name` is the endonym")
      ok(TIERS[doc.tier], file .. ": `tier` is source, maintained, contributed or machine")
      eq(doc.tier == "source", code == "en", file .. ": en, and only en, is the source")

      -- The text of the file: one message per line, sorted, each key once.
      local seen, previous, count = {}, nil, 0
      local in_messages = false
      for _, line in ipairs(H.read_lines(file)) do
        if line:match('^  "messages": {$') then
          in_messages = true
        elseif in_messages and line:match("^  }$") then
          in_messages = false
        elseif in_messages then
          local key = line:match('^    "([^"]+)": ')
          ok(key ~= nil, file .. ': a line of `messages` that is no `"key": value`: ' .. line)
          if key then
            count = count + 1
            ok(not seen[key], file .. ": the key is written twice: " .. key)
            seen[key] = true
            ok(
              previous == nil or previous < key,
              file .. ": the keys are sorted; out of order: " .. key
            )
            previous = key
            ok(
              key:match("^[a-z]+%.[%w_.-]+$") and not key:match("%.%.") and not key:match("%.$"),
              file .. ": a key is dotted segments of letters, digits, `_` and `-`: " .. key
            )
            ok(
              NAMESPACES[key:match("^[^.]+")],
              file .. ": the key is in no known namespace: " .. key
            )
          end
        end
      end
      local decoded = 0
      for _ in pairs(doc.messages) do
        decoded = decoded + 1
      end
      eq(count, decoded, file .. ": as many message lines as decoded messages")

      for key, entry in pairs(doc.messages) do
        local where = ("%s: %s"):format(file, key)
        if type(entry) == "table" then
          ok(type(entry.other) == "string", where .. ": a plural message has the form `other`")
          for category, form in pairs(entry) do
            ok(CATEGORIES[category], where .. ": not a plural category: " .. tostring(category))
            ok(type(form) == "string" and form ~= "", where .. ": a plural form is a text")
          end
        else
          ok(
            type(entry) == "string" and entry ~= "",
            where .. ": a message is a text or a plural table"
          )
        end

        if code ~= "en" then
          local origin = source.messages[key]
          ok(origin ~= nil, where .. ": translates a key the source does not have")
          if origin ~= nil then
            eq(
              type(entry),
              type(origin),
              where .. ": text and plural message do not translate each other"
            )
            local allowed = {}
            for _, text in ipairs(texts(origin)) do
              for name in pairs(placeholders(text)) do
                allowed[name] = true
              end
            end
            for _, text in ipairs(texts(entry)) do
              for name in pairs(placeholders(text)) do
                ok(
                  allowed[name],
                  ("%s: the placeholder {%s} is not in the source text"):format(where, name)
                )
              end
            end
          end
        end
      end

      if code ~= "en" then
        local missing = {}
        for key in pairs(source.messages) do
          if doc.messages[key] == nil then
            missing[#missing + 1] = key
          end
        end
        table.sort(missing)
        print(("  catalog: %s translates %d of %d keys"):format(code, decoded, #i18n.keys()))
        if doc.tier == "maintained" or doc.tier == "contributed" then
          eq(
            #missing,
            0,
            ("%s: a %s locale is complete; untranslated: %s"):format(
              file,
              doc.tier,
              table.concat(missing, ", ")
            )
          )
        end
      end
    end
  end

  -- ── The bundle of the packaged binary wins over the files ───────────────
  package.preload["docmap.core.i18n.bundled"] = function()
    return {
      en = '{"locale":"en","name":"English","tier":"source","messages":{"page.x":"from the bundle"}}',
    }
  end
  i18n._reset()
  eq(i18n.t("page.x"), "from the bundle", "bundle: the catalog comes from the bundled module")
  eq(
    i18n.has("finding.missing-readme"),
    false,
    "bundle: and the file beside the module is not read"
  )
  package.preload["docmap.core.i18n.bundled"] = nil
  package.loaded["docmap.core.i18n.bundled"] = nil
  i18n._reset()
  ok(i18n.has("finding.missing-readme"), "bundle: without it the files are read again")

  -- A catalog that does not parse is no catalog, and the reason is kept for :checkhealth.
  package.preload["docmap.core.i18n.bundled"] = function()
    return { en = "{ not json" }
  end
  i18n._reset()
  eq(
    i18n.t("page.x"),
    "‹missing:page.x›",
    "broken catalog: a key renders as missing, nothing raises"
  )
  ok(
    tostring(i18n.problems().en):find("not valid JSON", 1, true),
    "broken catalog: the reason is reported"
  )
  package.preload["docmap.core.i18n.bundled"] = nil
  package.loaded["docmap.core.i18n.bundled"] = nil
  i18n._reset()
end
