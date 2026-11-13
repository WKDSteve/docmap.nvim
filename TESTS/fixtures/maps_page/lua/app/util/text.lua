---@module 'app.util.text'
--- Text helpers.
local M = {}

---Trims blanks.
---@param s string The text.
---@return string trimmed
function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- PERF: builds a table per call
---Splits at blanks.
---@param s string The text.
---@return string[] words
function M.words(s)
  return vim.split(s, " ")
end

return M
