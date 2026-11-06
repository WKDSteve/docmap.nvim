-- The minimum Neovim version is promised in four places and exercised in one:
-- the extra leg of .github/workflows/ci.yml. A promise no job runs drifts
-- silently, so this spec fails when the floor moves in only some of them.

---@param rel string path relative to the repository root
---@return string
local function read(rel)
  local f = assert(io.open(vim.fn.getcwd() .. "/" .. rel, "rb"), "missing file: " .. rel)
  local text = f:read("*a")
  f:close()
  return text
end

return function(H)
  local ok = H.ok

  local minor = read(".github/workflows/ci.yml"):match("nvim:%s*v0%.(%d+)%.%d+")
  -- The plain call raises: the lines below cannot run without a version.
  assert(minor, "ci.yml has no leg pinned to the minimum version")

  local v = vim.pesc("0." .. minor)
  ok(read("README.md"):find("Neovim%-" .. v .. "%%2B"), "README.md badge")
  ok(read("doc/docmap.txt"):find("Neovim " .. v .. "%+"), "doc/docmap.txt")
  ok(read("docs/installation.md"):find("Neovim " .. v .. "%+"), "docs/installation.md")
  ok(read("docs/requirements.md"):find("%*%*" .. v .. "%+%*%*"), "docs/requirements.md")
end
