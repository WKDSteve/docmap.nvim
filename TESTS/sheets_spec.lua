-- TESTS/sheets_spec.lua — the live checks of TESTS/sheets/*.sheet.lua (testing.sheet). Busted style on
-- purpose: each sheet is its own case named `sheet:<id>`, the name `testing sheets report` finds the result by.
-- @cache-inputs TESTS/sheets/ TESTS/shape_host.lua TESTS/fixtures/keyword_page/ TESTS/fixtures/maps_page/ TESTS/fixtures/routes_page/ TESTS/fixtures/lookup_page/ lua/docmap/
---@diagnostic disable: undefined-global
-- luacheck: read globals describe it

local sheet = require("testing.sheet")
local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

-- The pages the browser sheets open are rendered here, each from a fixture tree (a sheet is data and starts no
-- program): TESTS/sheets/out/<name>.html, next to the screenshots (git-ignored). keyword-page carries tags,
-- maps-page a small layered tree with markers and uneven documentation (and its own .docmap.json), routes-page a
-- Next.js tree with an `app` and a `pages` directory (its routes need the tsx and typescript parsers; without
-- them the page is rendered all the same, with no route in it), lookup-page one function whose snippet holds
-- every kind of the lookup layer.
local PAGES = {
  { name = "keyword-page", fixture = "keyword_page", source = "lua" },
  { name = "maps-page", fixture = "maps_page", source = "lua/app" },
  { name = "routes-page", fixture = "routes_page", source = "src" },
  { name = "lookup-page", fixture = "lookup_page", source = "lua/look" },
}

-- Once per run: the fixtures do not change between two sheets, and scanning them again for each one is time
-- taken from the limit of this file.
local rendered = false
local function render_pages()
  if rendered then
    return
  end
  rendered = true
  local docmap = require("docmap")
  vim.fn.mkdir(root .. "/TESTS/sheets/out", "p")
  for _, page in ipairs(PAGES) do
    local fixture = root .. "/TESTS/fixtures/" .. page.fixture
    local opts = require("docmap.config").build(fixture, { source = page.source })
    local ir, findings = docmap.scan_full(opts)
    local html = docmap.render.html(ir, findings, opts)
    local f = assert(io.open(root .. "/TESTS/sheets/out/" .. page.name .. ".html", "wb"))
    f:write(html)
    f:close()
  end
end

-- The shape-diff sheets need what a file page does not have: a host that answers `/api/commits` and
-- `/api/shape/...`. TESTS/shape_host.lua is that host (the real `:DocMap serve`, git stood in for), run as a
-- process of its own on a fixed port: a server inside this editor does not answer while the editor waits for
-- the browser.
local SHAPE_PORT = 38417

---Start the host of the shape-diff sheets; returns what stops it.
---@return fun()
local function start_shape_host()
  local out = {}
  local child = vim.system({
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "-l",
    root .. "/TESTS/shape_host.lua",
    root,
    vim.o.runtimepath,
    tostring(SHAPE_PORT),
  }, {
    text = true,
    stdout = function(_, data)
      out[#out + 1] = data or ""
    end,
  })
  local function stop()
    child:kill(9)
    child:wait(5000)
  end
  local ready = vim.wait(20000, function()
    return table.concat(out):find("\n", 1, true) ~= nil
  end, 50)
  local line = vim.trim(table.concat(out))
  if not ready or not vim.startswith(line, "ready ") then
    stop()
    error("sheets: the shape host did not start on port " .. SHAPE_PORT .. ": " .. line, 0)
  end
  return stop
end

---The sheets that need the shape host, by id. It is started for the first of them and stopped after the last:
---starting it is a scan and a render, and each sheet has ten seconds for everything.
local HOSTED = { ["shape-diff"] = true, ["shape-diff-nodes"] = true }
local hosted_left, stop_host = 0, nil

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    local hosted = s ~= nil and HOSTED[s.id] == true
    if hosted then
      hosted_left = hosted_left + 1
    end
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      if s.engine == "browser" then
        render_pages()
      end
      if hosted then
        stop_host = stop_host or start_shape_host()
      end
      local ran, why = pcall(sheet.check, s, { root = root })
      if hosted then
        hosted_left = hosted_left - 1
        -- A run that selects only some of the hosted sheets never gets here; the host then ends on its own.
        if hosted_left == 0 and stop_host then
          stop_host()
          stop_host = nil
        end
      end
      if not ran then
        error(why, 0)
      end
    end)
  end
end)
