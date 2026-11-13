---@module 'app.core'
--- The core: state and rules.
local store = require("app.core.store")
local text = require("app.util.text")
local M = {}

---Boots the core.
---@return nil
function M.boot()
  store.load(text.trim(" a "))
end

function M.undocumented_one() end

return M
