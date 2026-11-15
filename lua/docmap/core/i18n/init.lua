---@module 'docmap.core.i18n'
--- The interface catalog: one JSON file per locale, and the Lua `t(key, params)` that reads it.
---
--- **The contract is `docs/i18n.md`**, with `docs/i18n-catalog.schema.json` as the shape of a catalog file and
--- `TESTS/fixtures/i18n/cases.json` as the golden cases both runtimes answer alike: this module and the page's
--- JavaScript runtime (`core/render/html/i18n_js.lua`). What is decided there and only carried out here:
---
---   * a catalog is `{ locale, name, tier, messages }`, `messages` a flat table of key to string, or key to a
---     table of plural categories (`one`, `other`, ...) chosen by the parameter `count`;
---   * placeholders are named (`{from} requires {to}`), never positional, so a translation can reorder them;
---   * a key the active locale lacks falls back to the English source string, and a key no catalog has renders
---     as `‹missing:key›`: visible, never blank;
---   * the interface is translated, the subject (module names, paths, docstring prose) never is. A caller hands
---     user text in as a parameter; it is substituted literally and never looked up.
---
--- **Standalone-safe.** No editor API: the engine (`standalone/docmap.lua`) loads this under PUC Lua with the
--- shim's `vim.json`. A source checkout reads the catalogs from the directory of this file; the packaged binary
--- has no such directory, so `scripts/package.lua` stages them as the Lua module `docmap.core.i18n.bundled`
--- (a table of locale code to JSON text), and that module wins when it exists.
---
--- **The active locale starts as English and changes only when a host says so** (`M.configure`): the editor in
--- `setup()`, the engine from `--locale`. A caller that never configures gets English, which is what keeps every
--- artifact renderer and every spec independent of the machine's `LANG`.

local M = {}

---The source locale: every string is written here first, every other catalog translates it.
M.SOURCE = "en"

---The locales this build ships, in the order a picker shows them. The one place a locale is named:
---`i18n_catalog_spec.lua` fails when a `<code>.json` beside this file is missing here, or the other way round.
local SHIPPED = { "en", "de" }

---The shipped locales as the runtime goes by them: a copy of the list above, which a spec may replace
---(`M._use`) and `M._reset` restores.
---@type string[]
M.LOCALES = {}
for i, code in ipairs(SHIPPED) do
  M.LOCALES[i] = code
end

---@class Docmap.I18n.Catalog
---@field locale string The locale code, the file's own name without `.json`.
---@field name string The endonym shown in a picker (`Deutsch`, never `German`).
---@field tier "source"|"maintained"|"contributed"|"machine" How far the translation can be trusted.
---@field messages table<string, string|table<string, string>> Key to text, or key to plural categories.

---@type table<string, Docmap.I18n.Catalog|false> Loaded catalogs; `false` for one that could not be read.
local cache = {}

---@type table<string, string> Why a catalog could not be read, by locale code.
local problems = {}

---The module the packaged binary carries its catalogs in. A name in a variable, not in the `require` below: the
---module exists in no source tree, and the map's own check would report a require nothing declares.
local BUNDLED = "docmap.core.i18n.bundled"

local active = M.SOURCE
local debug_mode = false

---The directory this file lives in, with a trailing slash.
---@return string
local function here()
  local source = debug.getinfo(1, "S").source
  return (source:gsub("^@", ""):gsub("\\", "/"):match("^(.*/)") or "./")
end

---The JSON text of one catalog: from the bundle when this is the packaged binary, from disk otherwise.
---@param code string
---@return string? text
---@return string? err
local function read(code)
  local has_bundle, bundle = pcall(require, BUNDLED)
  if has_bundle and type(bundle) == "table" then
    if type(bundle[code]) == "string" then
      return bundle[code]
    end
    return nil, "not in the bundle"
  end
  local path = here() .. code .. ".json"
  local fd = io.open(path, "rb")
  if not fd then
    return nil, "cannot open " .. path
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

---True for a locale code this build ships.
---@param code any
---@return boolean
local function shipped(code)
  for _, known in ipairs(M.LOCALES) do
    if known == code then
      return true
    end
  end
  return false
end

---One catalog, or nil when the locale is not shipped or its file cannot be read.
---
---Read once per process. A catalog that does not parse is no catalog: its locale falls back to English as a
---whole, and `M.problems()` says why, so `:checkhealth` can name the file.
---@param code string
---@return Docmap.I18n.Catalog?
function M.catalog(code)
  if cache[code] ~= nil then
    return cache[code] or nil
  end
  if not shipped(code) then
    return nil
  end
  local text, err = read(code)
  local doc
  if text then
    local decoded, value = pcall(vim.json.decode, text)
    if not decoded then
      err = "not valid JSON: " .. tostring(value)
    elseif type(value) ~= "table" or type(value.messages) ~= "table" then
      err = "no `messages` table"
    else
      doc = value
    end
  end
  if not doc then
    cache[code] = false
    problems[code] = err or "unreadable"
    return nil
  end
  cache[code] = doc
  return doc
end

---Why a shipped catalog could not be loaded, by locale code. Empty on a healthy install.
---@return table<string, string>
function M.problems()
  for _, code in ipairs(M.LOCALES) do
    M.catalog(code)
  end
  return problems
end

---The shipped locale a language tag means, or nil when none does.
---
---Takes what the hosts hand over: a BCP 47 tag (`de-AT`), a POSIX locale (`de_DE.UTF-8`, `de_DE@euro`) or a bare
---code. The exact region wins when it is shipped (`pt-BR`), the base language otherwise (`de-AT` reads `de`).
---`C` and `POSIX` mean no preference, which is nil like every other tag this build has no catalog for.
---@param tag any
---@return string?
function M.normalize(tag)
  if type(tag) ~= "string" then
    return nil
  end
  local bare = tag:gsub("[.@].*$", ""):gsub("_", "-")
  local lang, rest = bare:match("^(%a%a%a?)(.*)$")
  if not lang or (rest ~= "" and rest:sub(1, 1) ~= "-") then
    return nil
  end
  lang = lang:lower()
  local region = rest:match("^%-(%a%a)$") or rest:match("^%-(%a%a)%-")
  if region then
    local exact = lang .. "-" .. region:upper()
    if shipped(exact) then
      return exact
    end
  end
  return shipped(lang) and lang or nil
end

---The locale a host should start in: the first of `candidates` that names a shipped locale, else English.
---
---The caller lists its sources in order of authority (`opts.locale`, `$DOCMAP_LOCALE`, `v:lang`, `$LANG`);
---this function knows no environment of its own, which is what keeps it the same under Neovim and PUC Lua.
---@param ... any Tags, most authoritative first; nil and non-strings are skipped.
---@return string
function M.resolve(...)
  -- Varargs and `select`, not a list: an unset source is a nil in the middle, and `#` of such a list is anyone's guess.
  for i = 1, select("#", ...) do
    local code = M.normalize((select(i, ...)))
    if code then
      return code
    end
  end
  return M.SOURCE
end

---Set the active locale and the debug mode of this process.
---
---`locale` is a tag as `M.normalize` reads it; one that names no shipped locale leaves English active, since a
---typo in a config must not blank the interface. `debug` marks every fallback (`‹en› ` before the text).
---@param opts { locale?: string, debug?: boolean }?
---@return string locale The locale now active.
function M.configure(opts)
  opts = opts or {}
  if opts.locale ~= nil then
    active = M.normalize(opts.locale) or M.SOURCE
  end
  if opts.debug ~= nil then
    debug_mode = opts.debug and true or false
  end
  return active
end

---@return string
function M.locale()
  return active
end

---The CLDR plural category of `n` in a locale.
---
---The subset this build can prove: languages whose only split is `one` (the integer 1) against `other`, and
---everything else as `other`. A locale with `few`/`many` gets its rule with the task that ships the first such
---language (`i18n-plural-machinery`); until then its catalog can only say `other`, which is at least never a
---wrong singular.
---@param locale string
---@param n any
---@return string
function M.plural_category(locale, n)
  local lang = tostring(locale):match("^%a+") or ""
  local one_other = { en = true, de = true, nl = true, sv = true, it = true, es = true }
  if one_other[lang] and n == 1 then
    return "one"
  end
  return "other"
end

---Substitute `{name}` placeholders from `params`.
---
---A placeholder with no matching parameter is left standing rather than replaced with the empty string: a
---template and its call site drifting apart is a defect, and `{who}` sitting visibly in the output says so where
---a silent gap would not.
---
---Values are substituted literally, and a **function** replacement is what makes that true: `gsub` interprets
---`%1`/`%%` only in a replacement *string*, never in what a replacement function returns.
---@param template string
---@param params table<string, any>?
---@return string
function M.interpolate(template, params)
  if not params then
    return template
  end
  return (
    template:gsub("{([%w_]+)}", function(name)
      local value = params[name]
      if value == nil then
        return "{" .. name .. "}"
      end
      return tostring(value)
    end)
  )
end

---The template of `key` in one catalog: the string itself, or the plural form `count` selects.
---@param code string
---@param key string
---@param params table<string, any>?
---@return string?
local function template(code, key, params)
  local doc = M.catalog(code)
  local entry = doc and doc.messages[key]
  if type(entry) == "string" then
    return entry
  end
  if type(entry) == "table" then
    local form = entry[M.plural_category(code, params and params.count)]
    if type(form) ~= "string" then
      form = entry.other
    end
    return type(form) == "string" and form or nil
  end
  return nil
end

---True when the source catalog knows `key`. `t` cannot say: it answers a missing key with a marker.
---@param key string
---@return boolean
function M.has(key)
  local doc = M.catalog(M.SOURCE)
  return doc ~= nil and doc.messages[key] ~= nil
end

---One interface string.
---
---Looked up in `locale` (the active one when omitted), then in the English source, and rendered as
---`‹missing:key›` when neither has it. In debug mode a string that came from the fallback carries `‹en› ` in
---front, so a half-finished locale is countable on screen.
---@param key string
---@param params table<string, any>? Named values; `count` also selects the plural form.
---@param locale string? A tag as `M.normalize` reads it (English when it names no shipped locale). Renderers of
---committed artifacts pass `M.SOURCE`.
---@return string
function M.t(key, params, locale)
  local code = locale and (M.normalize(locale) or M.SOURCE) or active
  local found = template(code, key, params)
  if found then
    return M.interpolate(found, params)
  end
  local source = code ~= M.SOURCE and template(M.SOURCE, key, params) or nil
  if source then
    return (debug_mode and "‹en› " or "") .. M.interpolate(source, params)
  end
  return "‹missing:" .. tostring(key) .. "›"
end

---The keys of the source catalog under a prefix, sorted.
---@param prefix string? `"finding."` lists the findings; nil lists everything.
---@return string[]
function M.keys(prefix)
  local out = {}
  local doc = M.catalog(M.SOURCE)
  for key in pairs(doc and doc.messages or {}) do
    if not prefix or key:sub(1, #prefix) == prefix then
      out[#out + 1] = key
    end
  end
  table.sort(out)
  return out
end

---What the generated page embeds: every shipped catalog, so one artifact speaks every language and switches at
---runtime (`docs/i18n.md`, "One artifact, every language").
---
---`prefixes` narrows the messages to the namespaces the page reads; the editor's and the report's strings would
---be dead weight in every artifact.
---
---`offered` names the locales the page shows in its picker and takes from the browser; the others are embedded
---all the same and reached by `?lang=` (the renderer says why: `core/render/html.lua`, `PAGE_OFFERED`).
---@param prefixes string[]
---@param offered table<string, true>? Locale codes; none offered when omitted.
---@return { source: string, locales: { code: string, name: string, tier: string, offered: boolean }[], catalogs: table<string, table<string, any>> }
function M.for_page(prefixes, offered)
  local locales, catalogs = {}, {}
  for _, code in ipairs(M.LOCALES) do
    local doc = M.catalog(code)
    if doc then
      locales[#locales + 1] = {
        code = code,
        name = doc.name,
        tier = doc.tier,
        offered = offered ~= nil and offered[code] == true,
      }
      local messages = {}
      for key, entry in pairs(doc.messages) do
        for _, prefix in ipairs(prefixes) do
          if key:sub(1, #prefix) == prefix then
            messages[key] = entry
            break
          end
        end
      end
      catalogs[code] = messages
    end
  end
  return { source = M.SOURCE, locales = locales, catalogs = catalogs }
end

---Forget every loaded catalog and return to English without debug marks. For specs.
function M._reset()
  cache = {}
  problems = {}
  active = M.SOURCE
  debug_mode = false
  M.LOCALES = {}
  for i, code in ipairs(SHIPPED) do
    M.LOCALES[i] = code
  end
end

---Run on catalogs handed in, not on the files: what the golden cases need (`i18n_runtime_spec.lua`). For specs;
---`M._reset()` returns to the shipped catalogs.
---@param catalogs table<string, table<string, any>> Locale code to its `messages`.
function M._use(catalogs)
  M._reset()
  M.LOCALES = {}
  for code, messages in pairs(catalogs) do
    M.LOCALES[#M.LOCALES + 1] = code
    cache[code] = { locale = code, name = code, tier = "source", messages = messages }
  end
  table.sort(M.LOCALES)
end

return M
