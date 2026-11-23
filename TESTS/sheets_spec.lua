-- TESTS/sheets_spec.lua — the live checks of TESTS/sheets/*.sheet.lua (testing.sheet). Busted style on
-- purpose: each sheet is its own case named `sheet:<id>`, the name `testing sheets report` finds the result by.
-- @cache-inputs TESTS/sheets/ TESTS/shape_host.lua TESTS/telemetry_host.lua TESTS/fixtures/keyword_page/ TESTS/fixtures/maps_page/ TESTS/fixtures/routes_page/ TESTS/fixtures/lookup_page/ lua/docmap/
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
-- `/api/shape/...`. Each of them names the app `shape-host` of .testing.lua (TESTS/shape_host.lua, the real
-- `:DocMap serve` with git stood in for), which testing.sheet starts for that sheet on a free port and stops after
-- it. The host is a process of its own: a server inside this editor does not answer while the editor waits for the
-- browser. It gets this editor's runtimepath, so it finds docmap and its dependencies where this run found them.
vim.env.DOCMAP_SHAPE_HOST_RTP = vim.o.runtimepath

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      if s.engine == "browser" then
        render_pages()
      end
      local ran, why = pcall(sheet.check, s, { root = root })
      if not ran then
        error(why, 0)
      end
    end)
  end
end)
