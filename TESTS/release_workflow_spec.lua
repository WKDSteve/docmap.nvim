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

  -- SHA256SUMS: computed from the downloaded artifacts in `release-out`, before the release is created from that
  -- directory, so the file goes out with the assets it describes. Never from what is already on the release.
  publish = publish or ""
  local download = publish:find("actions/download-artifact@", 1, true)
  local sums = publish:find("sha256sum -- *", 1, true)
  local create = publish:find("gh release create standalone-latest release-out/*", 1, true)
  ok(sums ~= nil, "publish computes the sums with sha256sum over every downloaded asset")
  ok(
    download ~= nil and sums ~= nil and create ~= nil and download < sums and sums < create,
    "the sums are computed after the artifacts are downloaded and before the release is created"
  )
  ok(
    publish:find('mv "$RUNNER_TEMP/SHA256SUMS" release-out/SHA256SUMS', 1, true) ~= nil,
    "SHA256SUMS lands in release-out, so `release-out/*` uploads it with the assets"
  )
  ok(
    publish:find("sha256sum -c SHA256SUMS", 1, true) ~= nil,
    "publish checks the written SHA256SUMS against the files before uploading"
  )
  ok(
    publish:find("gh release download", 1, true) == nil,
    "the sums never come from the existing release"
  )

  local group = text:match("\nconcurrency:\n%s+group: ([^\n]+)\n%s+cancel%-in%-progress: true")
  ok(group ~= nil, "the workflow has a concurrency group that cancels an older run")
end
