---@module 'app.ui'
--- The windows.
local window = require("app.ui.window")
local M = {}

---Opens the main window.
---@return nil
function M.open()
  window.title("app")
end

return M
