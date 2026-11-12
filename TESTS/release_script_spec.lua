-- TESTS/release_script_spec.lua — what scripts/build_engine_release.sh takes from the network is pinned.
--
-- lua.org resets connections and once handed over a cut tarball that `tar` read straight from a pipe: five of six
-- runs of the release workflow were red on 2026-11-12, and a tarball that is not the one meant would have been built
-- into the engine without a word. dkjson and luastatic came from `master`, whatever it held that day. Every
-- download now goes through `fetch` (retried, written to a file, checked against a sha256), and a file from GitHub
-- names a commit.

return function(H)
  local ok = H.ok
  local here = vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
  local f = assert(io.open(vim.fs.dirname(here) .. "/scripts/build_engine_release.sh", "rb"))
  local text = f:read("*a")
  f:close()

  local curls, in_fetch = 0, 0
  local body = text:match("\nfetch%(%) {\n(.-)\n}\n")
  ok(body ~= nil, "the script has its fetch helper")
  ok(body and body:find("sha256sum -c -", 1, true) ~= nil, "fetch checks the sum")
  ok(body and body:find("--retry", 1, true) ~= nil, "fetch retries a broken download")
  for line in text:gmatch("[^\n]+") do
    if not line:match("^%s*#") and line:find("curl ", 1, true) then
      curls = curls + 1
      if body and body:find(line, 1, true) then
        in_fetch = in_fetch + 1
      end
    end
  end
  ok(curls == in_fetch, ("every curl is the one in fetch (%d of %d)"):format(in_fetch, curls))
  ok(
    not text:find("curl[^\n]*|%s*tar"),
    "nothing from the network is unpacked straight from a pipe"
  )
  for line in text:gmatch("[^\n]+") do
    if not line:match("^%s*#") and line:find("^fetch ") then
      ok(line:find('"%$[%u_]+_SHA256"%s*$') ~= nil, "a download names its pinned sum: " .. line)
    end
    if not line:match("^%s*#") and line:find("raw.githubusercontent.com", 1, true) then
      ok(
        not line:find("/master/", 1, true),
        "a file from GitHub names a commit, not master: " .. line
      )
    end
  end
  for name in text:gmatch("\n([%u_]+_SHA256)=") do
    ok(
      text:find("\n" .. name .. "=" .. string.rep("%x", 64) .. "\n") ~= nil,
      name .. " is a sha256"
    )
  end
end
