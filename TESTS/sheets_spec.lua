-- TESTS/sheets_spec.lua — the live checks of TESTS/sheets/*.sheet.lua (testing.sheet). Busted style on
-- purpose: each sheet is its own case named `sheet:<id>`, the name `testing sheets report` finds the result by.
-- @cache-inputs TESTS/sheets/ TESTS/fixtures/keyword_page/ lua/docmap/
---@diagnostic disable: undefined-global
-- luacheck: read globals describe it

local sheet = require("testing.sheet")
local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

-- The page the browser sheets open is rendered here, from a fixture module that carries tags (a sheet is
-- data and starts no program): TESTS/sheets/out/keyword-page.html, next to the screenshots (git-ignored).
local function render_keyword_page()
  local fixture = root .. "/TESTS/fixtures/keyword_page"
  local docmap = require("docmap")
  local opts = require("docmap.config").build(fixture, { source = "lua" })
  local ir, findings = docmap.scan_full(opts)
  local html = docmap.render.html(ir, findings, opts)
  vim.fn.mkdir(root .. "/TESTS/sheets/out", "p")
  local f = assert(io.open(root .. "/TESTS/sheets/out/keyword-page.html", "wb"))
  f:write(html)
  f:close()
end

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      if s.engine == "browser" then
        render_keyword_page()
      end
      sheet.check(s, { root = root })
    end)
  end
end)
