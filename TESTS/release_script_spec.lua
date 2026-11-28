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
  -- the checker is a variable so macOS (no GNU sha256sum) can use `shasum -a 256`; both must stay a real `-c` check
  ok(body and body:find('"${SHA256_CHECK[@]}"', 1, true) ~= nil, "fetch checks the sum")
  ok(text:find("SHA256_CHECK=(sha256sum -c -)", 1, true) ~= nil, "the GNU checker verifies with -c")
  ok(
    text:find("SHA256_CHECK=(shasum -a 256 -c -)", 1, true) ~= nil,
    "the macOS checker verifies with -c"
  )
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

  -- The Windows grammars link the C runtime statically (no VCRUNTIME140.dll), and the build checks their imports.
  local mt_at = text:find('export _CL_="${_CL_:+$_CL_ }-MT"', 1, true)
  local first_build = text:find('"$TSC" build', 1, true)
  ok(mt_at ~= nil, "the Windows grammar build passes -MT to cl through _CL_")
  ok(mt_at and first_build and mt_at < first_build, "...before the first grammar is built")
  ok(
    text:find('bash "$repo/scripts/check_dll_imports.sh" "$work/grammars"/*."$GSUF"', 1, true)
      ~= nil,
    "the build checks the imports of every grammar"
  )

  -- scripts/check_dll_imports.sh against a fake objdump that prints the file it is given.
  if vim.fn.executable("bash") ~= 1 then
    print("n/a  check_dll_imports: no bash on PATH")
    return
  end
  local dir = (vim.fn.tempname():gsub("\\", "/")) .. "-dll-imports"
  vim.fn.mkdir(dir, "p")
  H.write(dir .. "/objdump", { "#!/usr/bin/env bash", 'cat "$2"' })
  H.write(dir .. "/static.dll", {
    "The Import Tables",
    "\tDLL Name: KERNEL32.dll",
    "\tDLL Name: api-ms-win-crt-heap-l1-1-0.dll",
  })
  H.write(dir .. "/dynamic.dll", {
    "\tDLL Name: KERNEL32.dll",
    "\tDLL Name: VCRUNTIME140.dll",
  })
  local script = vim.fs.dirname(here) .. "/scripts/check_dll_imports.sh"
  ---@param files string[]
  ---@return integer code
  ---@return string stderr
  local function check(files)
    local cmd = { "bash", script }
    for _, file in ipairs(files) do
      cmd[#cmd + 1] = dir .. "/" .. file
    end
    local r = vim.system(cmd, { env = { OBJDUMP = dir .. "/objdump" }, text = true }):wait(30000)
    return r.code, r.stderr or ""
  end
  local code = check({ "static.dll" })
  H.eq(code, 0, "check_dll_imports: KERNEL32 and the UCRT API sets pass")
  local stderr
  code, stderr = check({ "static.dll", "dynamic.dll" })
  H.eq(code, 1, "check_dll_imports: VCRUNTIME140.dll fails the check")
  ok(
    stderr:find("dynamic.dll imports VCRUNTIME140.dll", 1, true) ~= nil,
    "...and names file and DLL"
  )
  code = check({})
  H.eq(code, 2, "check_dll_imports: no file is a usage error")
  vim.fn.delete(dir, "rf")
end
