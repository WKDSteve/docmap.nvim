---@module 'app.ui.window'
--- One window.
local store = require("app.core.store")
local text = require("app.util.text")
local M = {}

---Sets the title.
---@param s string The title.
---@return nil
function M.title(s)
  M.last = text.trim(s)
end

---Reloads the state.
---@return nil
function M.reload()
  store.load("x")
end

return M
