---@module 'look'
--- Fixture for the lookup sheet: one function whose snippet holds every kind the IR answers.
local store = require("look.store")
local dkjson = require("dkjson")
local M = {}

---Starts it.
---@param opts Look.Opts What to start with.
---@return string encoded
function M.start(opts)
  local first = store.load(opts.key)
  local old = store.old_load(opts.key)
  local gone = require("look.gone")
  local again = require("look.store").load(first)
  return dkjson.encode({ first, old, gone, again })
end

return M
