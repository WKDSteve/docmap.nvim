---@module 'docmap.bindings.usrcmds.git_async'
--- The git half of `:DocMap diff` and `:DocMap impact`, off the editor thread.
---
--- Both used to run `git show` (and `impact` a `git diff` before it) with
--- `vim.system(...):wait()`: 60-180 ms of a frozen editor per command on
--- Windows, longer under load. Now the command returns at once and answers
--- from the callback.
---
--- Asynchronous brings two duties a blocking call did not have:
---
--- * **A newer request wins.** Between the command and its answer the user can
---   run it again (another ref, a corrected typo). Each command owns one
---   `slot`; a request takes it, and an answer whose request no longer holds
---   the slot is dropped, so a late `diff` of the old ref never opens a buffer
---   over the new one.
--- * **A count to wait on.** Specs and sheets that ran the command and checked
---   right after now wait for `idle()`: no request is in flight.

local M = {}

---@type table<string, table>
local slots = {}

local inflight = 0

---@class Docmap.GitAsync.Result
---@field code integer Exit code; -1 when git could not be started.
---@field stdout string
---@field stderr string

---Take the slot `name` for a new request. The returned token stays `current`
---until the next `take` of the same slot or a `release`.
---@param name string
---@return table token
function M.take(name)
  local token = {}
  slots[name] = token
  return token
end

---@param name string
---@param token table
---@return boolean
function M.current(name, token)
  return slots[name] == token
end

---Give the slot up (the request answered), unless a newer one holds it.
---@param name string
---@param token table
function M.release(name, token)
  if slots[name] == token then
    slots[name] = nil
  end
end

---True when no git request of these commands is in flight.
---@return boolean
function M.idle()
  return inflight == 0
end

---Run `argv` in `cwd`; `on_done(result)` runs exactly once, on the main loop,
---also when the start itself fails (git not on PATH).
---@param argv string[]
---@param cwd string
---@param on_done fun(result: Docmap.GitAsync.Result)
function M.run(argv, cwd, on_done)
  inflight = inflight + 1
  local settled = false
  local function settle(result)
    vim.schedule(function()
      if settled then
        return
      end
      settled = true
      inflight = inflight - 1
      on_done(result)
    end)
  end
  local ok, err = pcall(vim.system, argv, { cwd = cwd, text = true }, function(proc)
    settle({
      code = proc.code or -1,
      stdout = proc.stdout or "",
      stderr = proc.stderr or "",
    })
  end)
  if not ok then
    settle({ code = -1, stdout = "", stderr = tostring(err) })
  end
end

---Run several requests at once and answer once, when the last one is done,
---with the results in the order of `argvs`.
---@param argvs string[][]
---@param cwd string
---@param on_done fun(results: Docmap.GitAsync.Result[])
function M.all(argvs, cwd, on_done)
  local results = {}
  -- Starts at one so an answer that arrives before the last start cannot
  -- report the whole set done; the extra count is taken back after the loop.
  local left = 1
  local function one_done()
    left = left - 1
    if left == 0 then
      on_done(results)
    end
  end
  for i, argv in ipairs(argvs) do
    left = left + 1
    M.run(argv, cwd, function(result)
      results[i] = result
      one_done()
    end)
  end
  one_done()
end

return M
