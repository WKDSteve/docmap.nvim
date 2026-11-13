---@module 'look.store'
--- Keeps what the fixture loads.
local M = {}

---Loads a key.
---@param key string The key.
---@return string value
function M.load(key)
  return key
end

---The old way to load a key.
---@deprecated use M.load
---@param key string The key.
---@return string value
function M.old_load(key)
  return M.load(key)
end

return M
