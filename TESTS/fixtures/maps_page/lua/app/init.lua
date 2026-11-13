---@module 'app'
--- Fixture for the map sheets: a small tree with layers, markers and uneven documentation.
local M = {}

---Starts the app.
---@return nil
function M.start()
  require("app.core").boot()
  require("app.ui").open()
end

return M
