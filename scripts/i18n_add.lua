-- scripts/i18n_add.lua -- add or replace messages in the shipped catalogs, in their sorted place.
--
--   nvim -l scripts/i18n_add.lua <additions.lua> [--remove]
--
-- `<additions.lua>` returns a table keyed by message key; each value names the text per locale:
--
--   return {
--     ["page.lookup.why"] = { en = "Why", de = "Warum" },
--     ["page.count.rows"] = { en = { one = "{count} row", other = "{count} rows" }, de = { ... } },
--   }
--
-- Every locale a value names is written to `lua/docmap/core/i18n/<locale>.json`: an existing key is replaced,
-- a new one goes into its sorted place, one message per line, the rest of the file byte for byte as it was.
-- With `--remove` the keys of the table are taken out of every catalog instead (the values are ignored).
-- Afterwards `core/i18n/bundled.lua` is regenerated (scripts/gen_i18n_bundle.lua), so the gate of the catalog
-- sees the files and their copy agree. docs/i18n.md, "Adding a text", is the contract this keeps.

local DIR = "lua/docmap/core/i18n/"

local args = _G.arg or {}
local source, remove = nil, false
for _, a in ipairs(args) do
  if a == "--remove" then
    remove = true
  else
    source = a
  end
end
if not source then
  io.stderr:write("usage: nvim -l scripts/i18n_add.lua <additions.lua> [--remove]\n")
  os.exit(2)
end

local additions = dofile(source)
assert(type(additions) == "table", "the additions file returns a table")

---A JSON string literal, escaped the way the catalogs are written (no escaped `/`, UTF-8 as it is).
---@param s string
---@return string
local function str(s)
  local out = s:gsub('[%c"\\]', function(c)
    if c == '"' then
      return '\\"'
    elseif c == "\\" then
      return "\\\\"
    elseif c == "\n" then
      return "\\n"
    elseif c == "\t" then
      return "\\t"
    end
    return ("\\u%04x"):format(c:byte())
  end)
  return '"' .. out .. '"'
end

local ORDER = { "zero", "one", "two", "few", "many", "other" }

---One value as the catalogs write it: a string, or a plural table on one line in CLDR order.
---@param v string|table
---@return string
local function value(v)
  if type(v) == "string" then
    return str(v)
  end
  local parts = {}
  for _, cat in ipairs(ORDER) do
    if v[cat] ~= nil then
      parts[#parts + 1] = str(cat) .. ": " .. str(v[cat])
    end
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function read(path)
  local f = assert(io.open(path, "rb"), "cannot read " .. path)
  local s = f:read("a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"), "cannot write " .. path)
  f:write(s)
  f:close()
end

local locales = {}
for name in vim.fs.dir(DIR) do
  local code = name:match("^(.+)%.json$")
  if code then
    locales[#locales + 1] = code
  end
end
table.sort(locales)

local changed = 0
for _, code in ipairs(locales) do
  local path = DIR .. code .. ".json"
  local text = read(path)
  local head, body, tail = text:match('^(.-"messages": {\n)(.-)\n(  }\n}\n?)$')
  assert(head, path .. ": the messages block is not where it is expected")
  -- One message per line: key -> the line without its trailing comma.
  local lines, keys = {}, {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local key = line:match('^    "([^"]+)": ')
    assert(key, path .. ": a line that is not one message: " .. line)
    lines[key] = line:gsub(",$", "")
    keys[#keys + 1] = key
  end
  local touched = false
  for key, per in pairs(additions) do
    if remove then
      if lines[key] then
        lines[key] = nil
        touched = true
      end
    elseif per[code] ~= nil then
      if not lines[key] then
        keys[#keys + 1] = key
      end
      lines[key] = '    "' .. key .. '": ' .. value(per[code])
      touched = true
    end
  end
  if touched then
    table.sort(keys)
    local out, seen = {}, {}
    for _, key in ipairs(keys) do
      if lines[key] and not seen[key] then
        seen[key] = true
        out[#out + 1] = lines[key]
      end
    end
    write(path, head .. table.concat(out, ",\n") .. "\n" .. tail)
    changed = changed + 1
    print(("%s: %d messages"):format(path, #out))
  end
end

if changed > 0 then
  local gen = dofile("scripts/gen_i18n_bundle.lua")
  write(gen.path, gen.current())
  print("wrote lua/docmap/core/i18n/bundled.lua")
end
