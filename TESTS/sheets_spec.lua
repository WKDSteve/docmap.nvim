-- TESTS/sheets_spec.lua — the live checks of TESTS/sheets/*.sheet.lua (testing.sheet). Busted style on
-- purpose: each sheet is its own case named `sheet:<id>`, the name `testing sheets report` finds the result by.
-- @cache-inputs TESTS/sheets/ TESTS/fixtures/keyword_page/ TESTS/fixtures/maps_page/ TESTS/fixtures/routes_page/ lua/docmap/
---@diagnostic disable: undefined-global
-- luacheck: read globals describe it

local sheet = require("testing.sheet")
local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

-- The pages the browser sheets open are rendered here, each from a fixture tree (a sheet is data and starts no
-- program): TESTS/sheets/out/<name>.html, next to the screenshots (git-ignored). keyword-page carries tags,
-- maps-page a small layered tree with markers and uneven documentation (and its own .docmap.json), routes-page a
-- Next.js tree with an `app` and a `pages` directory (its routes need the tsx and typescript parsers; without
-- them the page is rendered all the same, with no route in it).
local PAGES = {
  { name = "keyword-page", fixture = "keyword_page", source = "lua" },
  { name = "maps-page", fixture = "maps_page", source = "lua/app" },
  { name = "routes-page", fixture = "routes_page", source = "src" },
}

local function render_pages()
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

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      if s.engine == "browser" then
        render_pages()
      end
      sheet.check(s, { root = root })
    end)
  end
end)
