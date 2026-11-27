-- TESTS/release_workflow_spec.lua — the release workflow replaces `standalone-latest` only from a run that ran to the end.
--
-- `publish` waits for the macOS job without requiring it, which once read `always() && ...`: a run cancelled while the
-- macOS job was still building (up to 40 minutes) still replaced the release, and without a concurrency group an older
-- run could delete and recreate `standalone-latest` after a newer one, leaving an older engine in it.

return function(H)
  local ok = H.ok
  local here = vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
  local f = assert(io.open(vim.fs.dirname(here) .. "/.github/workflows/release-engine.yml", "rb"))
  local text = f:read("*a")
  f:close()

  local publish = text:match("\n  publish:\n(.-)\n  [%w_-]+:\n")
    or text:match("\n  publish:\n(.*)$")
  ok(publish ~= nil, "the workflow has its publish job")
  local cond = publish and publish:match("\n    if: ([^\n]+)") or ""
  ok(cond:find("!cancelled()", 1, true) ~= nil, "publish runs only in a run that was not cancelled")
  ok(
    cond:find("always()", 1, true) == nil,
    "publish does not run with always() (that includes a cancelled run)"
  )
  ok(
    cond:find("needs.linux.result == 'success'", 1, true) ~= nil,
    "publish requires the linux build"
  )
  ok(
    cond:find("needs.windows.result == 'success'", 1, true) ~= nil,
    "publish requires the windows build"
  )

  local group = text:match("\nconcurrency:\n%s+group: ([^\n]+)\n%s+cancel%-in%-progress: true")
  ok(group ~= nil, "the workflow has a concurrency group that cancels an older run")
end
