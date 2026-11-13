---@module 'app.core.store'
--- Keeps the state.
local text = require("app.util.text")
local window = require("app.ui.window")
local M = {}

-- FIXME: loses the last entry on reload
-- BUG: the key is not escaped
function M.load(key)
  window.title(text.trim(key))
end

-- TODO: persist
function M.save() end

function M.drop() end

return M
