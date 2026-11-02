---@module 'kwfix'
--- Fixture for the keyword-card sheet: functions that carry tags, so the page renders keyword badges.
local M = {}

---Runs in the background.
---@async
---@return nil
function M.fetch() end

---The result must be used.
---@nodiscard
---@return integer
function M.count()
  return 1
end

return M
