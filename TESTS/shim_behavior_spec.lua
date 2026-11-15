-- TESTS/shim_behavior_spec.lua — the shim answering the same questions as
-- the editor it stands in for.
--
-- **The blind spot this closes.** `shim_contract_spec.lua` compares *names*:
-- every `vim.*` path and every method `core/` calls, against what the shim
-- provides. That catches an absent function — the shape `node:start()` and
-- `vim.pesc` both had when they reached a release. It cannot catch the other
-- shape: a function that exists, returns a plausible value, and returns a
-- *different* one than Neovim would. `vim.fs.dirname("a/b/")` answering
-- `"a"` where the editor says `"a/b"` is not a crash anywhere; it is a
-- scanner that quietly attributes a file to the wrong module.
--
-- **Why this runs here and not only in the standalone gate.** The shim is
-- plain Lua, and `shim_contract_spec.lua` already proved it can be *loaded*
-- inside Neovim (fake `lfs`/`dkjson` through `package.preload`, `_G.vim`
-- unset for the duration so the shim does not hand back the editor's own
-- table). A thing that can be loaded can be called — so the real `vim.*` and
-- the shim can be driven side by side, here, in the `tests` gate that always
-- runs. That matters more than it sounds: the `standalone` gate skips
-- wherever PUC Lua or one of its two rocks is missing, which is most
-- machines, and three real defects have already walked through that gap.
--
-- **What this deliberately does not answer**, because honesty about a gate's
-- reach is the whole lesson of this corner of the tree:
--
--   * `vim.json.decode`. Decoding is still dkjson's, and no fake for it here
--     could be anything but `vim.json` wearing a hat — the comparison would
--     be `vim.json.decode` against itself. Those cases are tagged
--     `needs = "puc"` and answered by `standalone/selfcheck_behavior.lua`
--     under the real rock; `dkjson` is *refused* here rather than faked, so
--     a case that loses its tag fails loudly instead of quietly agreeing
--     with itself. (Encoding is a different story: the shim writes scalars
--     itself now, exactly so that the bytes which end up in the artifact can
--     be compared here rather than behind the skip.)
--   * Real `lfs`. The filesystem cases below run the shim's own logic — the
--     `.`/`..` filtering, the mode mapping — against an `lfs` adapter built
--     on `vim.uv`. That tests the shim, not the rock; the PUC runner closes
--     the remaining seam.
--   * LuaJIT versus PUC 5.4 semantics. Everything here runs under the
--     editor's LuaJIT. The PUC runner replays the same corpus on the other
--     interpreter.
--   * `vim.uv.hrtime` (documented as CPU time, not wall time) and
--     `vim.treesitter` (a deliberately inert stub). Both are *intended*
--     differences, stated in `standalone/vim_shim.lua`'s own header.
--   * The stdpath cases follow `NVIM_APPNAME` and the `XDG_*` variables: the
--     shim implements both (measured against the editor on Windows), so the
--     comparison holds whatever the environment the suite runs in.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local cases = dofile(root .. "/TESTS/fixtures/shim_behavior_cases.lua")
  local fixture = root .. "/TESTS/fixtures/shim_fs"

  ok(vim.fn.isdirectory(fixture) == 1, "shim behavior: the committed fs fixture is there")
  ok(#cases.cases > 40, "shim behavior: corpus loaded (" .. #cases.cases .. " cases)")

  -- ---------------------------------------------------------------------
  -- An `lfs` the shim can run on, built on `vim.uv`.
  --
  -- Faithful to the two details the shim's own code depends on: `lfs.dir`
  -- raises on a directory it cannot open (the shim `pcall`s it and degrades
  -- to an empty iterator), and it yields `.` and `..` like the real rock
  -- (the shim filters them — a filter that is only exercised if they are
  -- actually there).
  -- ---------------------------------------------------------------------
  local function lfs_on_uv()
    return {
      -- The shim's Windows branch changes directory around a `dir` listing
      -- (see `windows_census` there) and puts it back. Only ever reached on a
      -- Windows host here; real, so that listing lists the right directory.
      chdir = function(path)
        return pcall(vim.uv.chdir, path) and true or nil
      end,
      attributes = function(path, what)
        -- Loud rather than nil: the shim asks for `"mode"` and nothing else,
        -- and a silently-nil answer to some future third argument would look
        -- exactly like "file not found".
        assert(
          what == "mode"
            or what == "ino"
            or what == "dev"
            or what == "size"
            or what == "modification"
            or what == "permissions",
          "lfs adapter: only the `mode`, `ino`, `dev`, `size`, `modification` and `permissions` attributes are implemented"
        )
        local st = vim.uv.fs_stat(path)
        if not st then
          return nil
        end
        if what == "mode" then
          return st.type
        elseif what == "modification" then
          return st.mtime.sec
        elseif what == "permissions" then
          -- `rwxr-xr-x`, as lfs spells it, out of libuv's own bits
          local out, bits = {}, st.mode % 512
          for i = 8, 0, -1 do
            local on = math.floor(bits / 2 ^ i) % 2 == 1
            local letter = ("rwx"):sub(3 - i % 3, 3 - i % 3)
            out[#out + 1] = on and letter or "-"
          end
          return table.concat(out)
        end
        return st[what]
      end,
      -- `lstat`: what the shim's `**` asks so that a link is not entered, and
      -- (`target`) what `uv.fs_readlink` asks to read where a link points.
      symlinkattributes = function(path, what)
        assert(
          what == "mode" or what == "target",
          "lfs adapter: only the `mode` and `target` attributes are implemented"
        )
        if what == "target" then
          return (vim.uv.fs_readlink(path))
        end
        local st = vim.uv.fs_lstat(path)
        if not st then
          return nil
        end
        return st.type == "link" and "link" or st.type
      end,
      dir = function(dir)
        local handle = vim.uv.fs_scandir(dir)
        if not handle then
          error("lfs adapter: cannot open " .. tostring(dir), 0)
        end
        local pending = { ".", ".." }
        return function()
          if #pending > 0 then
            return table.remove(pending, 1)
          end
          return vim.uv.fs_scandir_next(handle)
        end
      end,
      mkdir = function(path)
        local made = vim.uv.fs_mkdir(path, 493)
        return made and true or nil
      end,
      -- The working directory, which `fnamemodify(":p")` joins relative paths
      -- onto. Native separators, like the rock.
      currentdir = function()
        return vim.uv.cwd()
      end,
    }
  end

  -- dkjson, on the other hand, is not adapted but refused: see this file's
  -- header. A json case that forgot its `needs = "puc"` tag must fail loudly
  -- here rather than quietly compare `vim.json` with itself.
  local function dkjson_refusing()
    local function refuse()
      error("shim behavior spec: json is answered by the PUC runner, not here", 0)
    end
    return {
      encode = refuse,
      decode = refuse,
      null = setmetatable({}, {
        __tostring = function()
          return "null"
        end,
      }),
    }
  end

  -- ---------------------------------------------------------------------
  -- Load the shim. Same dance as `shim_contract_spec.lua`, same reasons,
  -- and the same care about putting `_G.vim` back before anything can
  -- longjmp out of here: leaving it nil takes down every later spec in the
  -- run, and the failure looks like anything but this file.
  -- ---------------------------------------------------------------------
  --
  -- `package.loaded` is cleared as well as `package.preload`, and that is not
  -- belt and braces. `shim_contract_spec.lua` runs first and loads the shim
  -- with a *deliberately empty* fake `lfs` — `attributes` answers nil,
  -- `dir` yields nothing — which is all that spec needs, because it only
  -- reads names. `require` caches by module name, so without this the
  -- filesystem half of the corpus quietly ran against that empty fake and
  -- reported the fixture directory as missing: seven cases red, and none of
  -- them about the shim.
  local saved_vim = _G.vim
  local saved_preload = { lfs = package.preload.lfs, dkjson = package.preload.dkjson }
  local saved_loaded = { lfs = package.loaded.lfs, dkjson = package.loaded.dkjson }
  package.loaded.lfs, package.loaded.dkjson = nil, nil
  package.preload.lfs = lfs_on_uv
  package.preload.dkjson = dkjson_refusing
  -- The shim reads this module on Windows (`pcall`-required, so absent here
  -- it would only degrade); on a Windows host it must be there for the
  -- listing cases below to mean anything.
  local saved_popup = package.preload["lib.nvim.notify.popup"]
  local saved_win_links = package.preload["standalone.win_links"]
  local saved_win_links_loaded = package.loaded["standalone.win_links"]
  package.loaded["standalone.win_links"] = nil
  package.preload["standalone.win_links"] = function()
    return dofile(root .. "/standalone/win_links.lua")
  end

  local chunk, load_err = loadfile(root .. "/standalone/vim_shim.lua")
  ok(chunk ~= nil, "shim behavior: vim_shim.lua loads as a chunk — " .. tostring(load_err))

  local shim
  if chunk then
    _G.vim = nil
    local ran, result = pcall(chunk)
    _G.vim = saved_vim
    package.preload.lfs = saved_preload.lfs
    package.preload.dkjson = saved_preload.dkjson
    package.loaded.lfs = saved_loaded.lfs
    package.loaded.dkjson = saved_loaded.dkjson
    package.preload["standalone.win_links"] = saved_win_links
    package.loaded["standalone.win_links"] = saved_win_links_loaded
    -- the shim preloads a stand-in for the editor's toast; this is the editor, keep its own
    package.preload["lib.nvim.notify.popup"] = saved_popup
    ok(ran, "shim behavior: vim_shim.lua runs on the uv-backed lfs — " .. tostring(result))
    if ran then
      shim = result
    end
  end
  ok(shim ~= nil and shim ~= saved_vim, "shim behavior: got the shim's table, not Neovim's own")
  if not shim then
    return
  end

  -- ---------------------------------------------------------------------
  -- The comparison itself.
  -- ---------------------------------------------------------------------
  local mismatches, compared, deferred = {}, 0, 0
  -- A case whose path the *editor* does not have is a typo in the corpus, and
  -- it fails in the one direction nobody notices: both sides answer `missing`,
  -- the case agrees with itself, and it reads as coverage. Collected
  -- separately from real mismatches so the message says which it is.
  local unresolved = {}

  -- The same folder can answer to two names: an app packaged for Windows gets
  -- `AppData\Local` redirected, so a run standing in `...\AppData\Local\x` gets
  -- `...\Packages\<app>\LocalCache\Local\x` from Neovim's realpath and the name it stands
  -- under from the shim's. That is where the run stands, not how the shim behaves, so
  -- exactly that one prefix is evened out. Comparing the targets instead would also pass
  -- a shim that leaves `..` in a path.
  local function slashes(path)
    return (path:gsub("\\", "/"))
  end
  local cwd = slashes(saved_vim.fn.getcwd())
  local real_cwd = slashes(saved_vim.uv.fs_realpath(cwd) or cwd)
  ---@param answer string
  ---@return string
  local function even_out_cwd(answer)
    local from, to = answer:find(real_cwd, 1, true)
    if real_cwd == cwd or not from then
      return answer
    end
    return answer:sub(1, from - 1) .. cwd .. answer:sub(to + 1)
  end

  for _, case in ipairs(cases.sorted()) do
    if case.needs == "puc" then
      -- Still resolved against the editor, even though the shim side waits
      -- for the PUC runner: a typo must not hide behind the tag either.
      local answer = cases.evaluate(vim, cases.materialize(case), fixture)
      if answer == "missing" or answer:sub(1, 13) == "unknown-kind:" then
        unresolved[#unresolved + 1] = case.id .. " -> " .. answer
      end
      deferred = deferred + 1
    else
      -- Materialised twice on purpose: a mutating implementation must not be
      -- able to hand the other side something it has already written into.
      local want, want_detail = cases.evaluate(vim, cases.materialize(case), fixture)
      local got, got_detail = cases.evaluate(shim, cases.materialize(case), fixture)
      compared = compared + 1
      if want == "missing" or want:sub(1, 13) == "unknown-kind:" then
        unresolved[#unresolved + 1] = case.id .. " -> " .. want
      elseif even_out_cwd(want) ~= even_out_cwd(got) then
        local line = ("%s\n      neovim: %s\n      shim:   %s"):format(case.id, want, got)
        if case.why then
          line = line .. "\n      case:   " .. case.why
        end
        if want_detail or got_detail then
          line = line
            .. ("\n      raised: neovim=%s shim=%s"):format(
              tostring(want_detail):gsub("\n.*", ""),
              tostring(got_detail):gsub("\n.*", "")
            )
        end
        mismatches[#mismatches + 1] = line
      end
    end
  end

  table.sort(unresolved)
  eq(
    table.concat(unresolved, ", "),
    "",
    "shim behavior: every case names a vim.* path this Neovim has and a kind "
      .. "the runner knows — a typo in either agrees with itself and checks "
      .. "nothing"
  )

  ok(compared > 40, "shim behavior: compared " .. compared .. " cases against the real vim.*")
  eq(
    table.concat(mismatches, "\n    "),
    "",
    -- The first case on the first line: a report that keeps one line per failure still names it.
    "shim behavior: every compared case answers what Neovim answers, first: "
      .. ((mismatches[1] or "none"):gsub("%s*\n%s*", " | "))
      .. "\n    "
  )

  -- The deferred half is stated rather than assumed: a corpus that quietly
  -- stopped tagging its json cases would look like a bigger run, not a
  -- smaller one.
  ok(
    deferred > 0,
    "shim behavior: "
      .. deferred
      .. " cases are left to the PUC runner (real dkjson, and `system`'s exit status)"
  )

  -- `uv.fs_realpath/short-name` agrees with itself (nil == nil) on a volume
  -- that makes no 8.3 names, so it is said out loud whether it compared an
  -- alias at all: `dir /x` in the fixture folder tells. Where the alias is
  -- there, the editor must have resolved it -- otherwise the case checked
  -- nothing and must not read as coverage.
  if vim.fn.has("win32") == 1 then
    local sub = fixture .. "/sub"
    local listed = vim
      .system({ "cmd.exe", "/d", "/c", "dir /x /a" }, { cwd = sub, text = true })
      :wait()
    local stdout = listed.stdout or ""
    if listed.code == 0 and stdout:find("LONGFO~1", 1, true) then
      local real = vim.uv.fs_realpath(sub .. "/longfo~1/f.txt")
      ok(
        real ~= nil and (real:gsub("\\", "/")):find("/longfoldername/f.txt$") ~= nil,
        "shim behavior: uv.fs_realpath/short-name compared a real alias (editor: "
          .. tostring(real)
          .. ")"
      )
    else
      io.stdout:write(
        "shim behavior: uv.fs_realpath/short-name skipped: volume makes no 8.3 names\n"
      )
    end
  end

  -- ---------------------------------------------------------------------
  -- What the shim refuses, and `vim.env`. None of it can be a corpus case:
  -- either the editor *answers* where the shim declines, or the answer is a
  -- raise whose message is not comparable. Each refusal is a decision (the
  -- shim's rule is "checked, not guessed"), so each is pinned.
  -- ---------------------------------------------------------------------
  local function raises(fn, ...)
    return not pcall(fn, ...)
  end
  ok(
    raises(shim.fn.glob, fixture .. "/sub/", false, true),
    "shim refuses a glob pattern ending in a separator"
  )
  ok(raises(shim.fn.glob, fixture .. "/*", true, true), "shim refuses glob's nosuf")
  ok(
    raises(shim.fn.strchars, "abc", 1),
    "shim refuses strchars' skipcc (composing characters need a table)"
  )
  ok(raises(shim.fn.strchars, "abc", true), "shim refuses a true skipcc")
  ok(not raises(shim.fn.strchars, "abc", 0), "shim accepts skipcc = 0, the editor's default")
  ok(raises(shim.fn.fnamemodify, "~/x", ":p"), 'shim refuses ":p" on a "~" path')
  ok(
    raises(shim.fn.fnamemodify, "a", ":h"),
    "shim refuses a fnamemodify modifier it does not implement"
  )
  ok(
    raises(shim.fn.readfile, fixture .. "/a.txt", "x"),
    "shim refuses a readfile flag it does not implement"
  )
  ok(
    raises(shim.fn.system, { "git", "--version" }, "stdin"),
    "shim refuses system's stdin argument"
  )
  -- Under the editor's LuaJIT a failed command and a successful one both close
  -- as a bare `true`, so the shim must raise rather than report a status it
  -- cannot know. (On PUC Lua the `fn.system/*` cases answer for the real thing.)
  ok(
    raises(shim.fn.system, { "git", "--version" }),
    "shim.fn.system refuses to guess an exit status on LuaJIT"
  )

  eq(shim.env.DOCMAP_SHIM_SURELY_UNSET, nil, "shim.env answers nil for an unset variable")
  eq(shim.env.PATH, vim.env.PATH, "shim.env reads the process environment")
  ok(
    raises(function()
      shim.env.DOCMAP_SHIM_ANY = "x"
    end),
    "shim.env refuses assignment instead of silently doing nothing"
  )

  -- ---------------------------------------------------------------------
  -- `uv.fs_mkdir`, which the corpus cannot carry: it writes, so it needs a
  -- path that is different on every run and can therefore never appear in a
  -- shared expectations file. Both halves of the contract `lib.nvim.fs.
  -- mkdirp` relies on: a fresh directory succeeds, an existing one does not.
  -- ---------------------------------------------------------------------
  local scratch = vim.fn.tempname()
  vim.fn.mkdir(scratch, "p")
  local function mkdir_answer(surface, path)
    local made = surface.uv.fs_mkdir(path, 493)
    return cases.canon(made)
  end
  eq(
    mkdir_answer(shim, scratch .. "/fresh-shim"),
    mkdir_answer(vim, scratch .. "/fresh-real"),
    "shim behavior: uv.fs_mkdir on a new directory"
  )
  eq(
    mkdir_answer(shim, scratch),
    mkdir_answer(vim, scratch),
    "shim behavior: uv.fs_mkdir on a directory that already exists"
  )
  vim.fn.delete(scratch, "rf")

  -- The writing half (`rules/accept`, `rules/waive`), outside the corpus for the same reason as `fs_mkdir`: each
  -- step changes the disk. One script of steps, run on each surface in a folder of its own, the answers compared
  -- step by step: a new file made exclusively, written, flushed, closed and read back; `wx` on a name that exists;
  -- `w` over it; a rename over an existing file and onto a new name; an unlink of a file and of a missing one; the
  -- `mode` of the file `lib.nvim.fs.write.atomic` replaces (`% 4096`). Errors are compared by their code (the part
  -- before the colon), not their wording.
  local function code_of(err)
    return err and tostring(err):match("^(%u+)") or nil
  end
  local function read_all(path)
    local fh = io.open(path, "rb")
    if not fh then
      return nil
    end
    local text = fh:read("*a")
    fh:close()
    return text
  end
  local function write_answers(surface, dir)
    local uv = surface.uv
    vim.fn.mkdir(dir, "p")
    local out = {}
    local function step(name, ...)
      out[#out + 1] = name .. " = " .. cases.canon({ ... })
    end
    local fd, err = uv.fs_open(dir .. "/a.txt", "wx", 420)
    step("open wx new", fd ~= nil, code_of(err))
    if fd then
      step("write", uv.fs_write(fd, "abc", 0))
      step("fsync", uv.fs_fsync(fd) and true or false)
      step("close", uv.fs_close(fd))
    end
    step("read back", read_all(dir .. "/a.txt"))
    local again, again_err = uv.fs_open(dir .. "/a.txt", "wx", 420)
    step("open wx existing", again ~= nil, code_of(again_err))
    local fd2 = uv.fs_open(dir .. "/a.txt", "w", 420)
    if fd2 then
      uv.fs_write(fd2, "xy", 0)
      uv.fs_close(fd2)
    end
    step("open w truncates", read_all(dir .. "/a.txt"))
    step("mode of a file", uv.fs_stat(dir .. "/a.txt").mode % 4096)
    local fd3 = uv.fs_open(dir .. "/b.txt", "wx", 420)
    if fd3 then
      uv.fs_write(fd3, "new", 0)
      uv.fs_close(fd3)
    end
    local renamed, rename_err = uv.fs_rename(dir .. "/b.txt", dir .. "/a.txt")
    step(
      "rename over a file",
      renamed and true or false,
      code_of(rename_err),
      read_all(dir .. "/a.txt")
    )
    step("rename left no source", uv.fs_stat(dir .. "/b.txt") == nil)
    local moved = uv.fs_rename(dir .. "/a.txt", dir .. "/c.txt")
    step("rename to a new name", moved and true or false, read_all(dir .. "/c.txt"))
    local listing = {}
    for name in vim.fs.dir(dir) do
      listing[#listing + 1] = name
    end
    table.sort(listing)
    step("nothing left beside it", table.concat(listing, ","))
    local unlinked = uv.fs_unlink(dir .. "/c.txt")
    step("unlink", unlinked and true or false)
    local gone, gone_err = uv.fs_unlink(dir .. "/c.txt")
    step("unlink missing", gone and true or false, code_of(gone_err))
    local nowhere, nowhere_err = uv.fs_open(dir .. "/no/such/d.txt", "wx", 420)
    step("open wx in a missing folder", nowhere ~= nil, code_of(nowhere_err))
    return out
  end
  local write_scratch = vim.fn.tempname() .. "-shim-write"
  local shim_steps = write_answers(shim, write_scratch .. "/shim")
  local real_steps = write_answers(vim, write_scratch .. "/real")
  for i = 1, math.max(#shim_steps, #real_steps) do
    eq(shim_steps[i], real_steps[i], "shim behavior: write step " .. i)
  end
  vim.fn.delete(write_scratch, "rf")

  -- What the writers ask of the process and the host, compared where an answer can be: `os_getpid` is a positive
  -- whole number that stays the same, `os_uname().sysname` is the editor's on Windows and Linux (the two systems
  -- the engine is built for), `in_fast_event` is false outside a callback, `wait` with a condition that holds
  -- answers at once and one that never holds answers `false, -1` after its time.
  local pid = shim.uv.os_getpid()
  ok(
    type(pid) == "number" and pid > 0 and pid % 1 == 0,
    "shim behavior: uv.os_getpid is a positive whole number"
  )
  eq(shim.uv.os_getpid(), pid, "shim behavior: uv.os_getpid stays the same in one process")
  eq(shim.uv.os_uname().sysname, vim.uv.os_uname().sysname, "shim behavior: uv.os_uname().sysname")
  eq(shim.in_fast_event(), vim.in_fast_event(), "shim behavior: in_fast_event outside a callback")
  local function always()
    return true
  end
  local function never()
    return false
  end
  eq(
    cases.canon({ shim.wait(50, always, 10) }),
    cases.canon({ vim.wait(50, always, 10) }),
    "shim behavior: wait with a condition that holds"
  )
  eq(
    cases.canon({ shim.wait(30, never, 10) }),
    cases.canon({ vim.wait(30, never, 10) }),
    "shim behavior: wait with a condition that never holds"
  )

  -- ---------------------------------------------------------------------
  -- Every shim function reachable from the corpus. A new entry in the shim
  -- with no case is a function nobody has compared — the same argument
  -- `shim_contract_spec.lua` makes about an unclassified method name, one
  -- level down.
  -- ---------------------------------------------------------------------
  -- `uv.fs_scandir_next` is deliberately absent: the scandir cases name it in
  -- `next_path` and drive it, so it counts as covered rather than excused.
  local COVERED_ELSEWHERE = {
    ["uv.fs_mkdir"] = "compared above, outside the corpus: it writes",
    ["uv.hrtime"] = "documented as CPU time, not wall time — an intended difference",
    ["treesitter"] = "deliberately inert in the parser-less build, top to bottom",
    ["loop"] = "the same table as uv, by assignment — enumerated once, as uv",
    ["NIL"] = "a sentinel, not a function",
    ["uv.fs_fstat"] = "run by the `read_fd` cases of uv.fs_open, on the handle that opened",
    ["uv.fs_read"] = "run by the `read_fd` cases of uv.fs_open, in blocks, to the empty read",
    ["uv.fs_close"] = "run by the `read_fd` cases of uv.fs_open, which compare what it returns",
    ["empty_dict"] = "run by the islist/decoded-empty-object case (PUC runner), against a decoded {}",
    ["uv.fs_write"] = "compared above, outside the corpus: the write steps",
    ["uv.fs_fsync"] = "compared above, outside the corpus: the write steps (a flush, said in the shim)",
    ["uv.fs_unlink"] = "compared above, outside the corpus: the write steps",
    ["uv.fs_rename"] = "compared above, outside the corpus: the write steps",
    ["uv.os_getpid"] = "a number of this process: held to its shape above, not to the editor's own pid",
    ["uv.os_uname"] = "compared above: sysname",
    ["in_fast_event"] = "compared above, outside a callback",
    ["wait"] = "compared above: a condition that holds and one that never does",
    ["notify"] = "writes a line to stderr: an output, not an answer to compare",
    ["version"] = "this is not a Neovim and says so (`none`): an intended difference",
  }
  -- The entries above that name a *table*: the walk stops at them instead of
  -- listing what is inside.
  local NOT_A_FUNCTION = { treesitter = true, loop = true, NIL = true }

  local has_case = {}
  for _, case in ipairs(cases.cases) do
    has_case[case.path] = true
    if case.next_path then
      has_case[case.next_path] = true
    end
  end

  local function walk(tbl, prefix, out, depth)
    if depth > 3 then
      return
    end
    for key, value in pairs(tbl) do
      if type(key) == "string" then
        local path = prefix == "" and key or (prefix .. "." .. key)
        if type(value) == "function" then
          out[#out + 1] = path
        elseif type(value) == "table" and not NOT_A_FUNCTION[path] then
          walk(value, path, out, depth + 1)
        end
      end
    end
  end

  local provided = {}
  walk(shim, "", provided, 1)
  local uncompared = {}
  for _, path in ipairs(provided) do
    if not has_case[path] and not COVERED_ELSEWHERE[path] then
      uncompared[#uncompared + 1] = path
    end
  end
  table.sort(uncompared)
  eq(
    table.concat(uncompared, ", "),
    "",
    "shim behavior: every function the shim provides has at least one case, "
      .. "or a stated reason it is compared elsewhere"
  )

  -- And the exception list must not rot in the other direction: an entry for
  -- something the corpus has since grown a case for is a stale claim.
  for path, why in pairs(COVERED_ELSEWHERE) do
    if not NOT_A_FUNCTION[path] then
      ok(
        has_case[path] == nil,
        "shim behavior: "
          .. path
          .. " has a case now — drop it from the exception list ("
          .. why
          .. ")"
      )
    end
  end
  -- ---------------------------------------------------------------------
  -- Properties of `glob` that are bounds, not parity with the editor: a
  -- walk must terminate on a tree that loops, and must not run away on a deep
  -- one. Neither can be a corpus case (the editor's own answer depends on its
  -- depth limit), so they are asserted directly on the shim.
  -- ---------------------------------------------------------------------
  do
    local base = vim.fn.tempname()
    vim.fn.mkdir(base .. "/a/b", "p")
    vim.fn.writefile({ "x" }, base .. "/a/b/hit.txt")
    local made_link = vim.uv.fs_symlink(base, base .. "/a/b/loop", { dir = true })
    local found = shim.fn.glob(base .. "/**/hit.txt", false, true)
    eq(
      #found,
      1,
      "shim glob: `**` finds the file once" .. (made_link and ", through a symlink loop" or "")
    )
    if made_link then
      local listed = shim.fn.glob(base .. "/a/b/*", false, true)
      eq(#listed, 2, "shim glob: a symlinked directory is still listed, only not entered")
    end

    local deep = base .. "/deep"
    local parts = {}
    for i = 1, 70 do
      parts[i] = "d"
    end
    local deep_dir = deep .. "/" .. table.concat(parts, "/")
    vim.fn.mkdir(deep_dir, "p")
    vim.fn.writefile({ "x" }, deep_dir .. "/bottom.txt")
    vim.fn.writefile({ "x" }, deep .. "/d/top.txt")
    local deep_found = shim.fn.glob(deep .. "/**/*.txt", false, true)
    eq(#deep_found, 1, "shim glob: `**` stops at its depth limit (the 70-deep file is not reached)")
    vim.fn.delete(base, "rf")
  end

  -- ---------------------------------------------------------------------
  -- `fn.has` on the hosts this run is not on. The corpus compares it with
  -- the editor, and that only ever checks the branch of the host it runs on:
  -- on Windows and Linux "mac" is 0 on both sides, so a shim answering 0 for
  -- "mac" everywhere stays green there and fails on macOS CI alone. Here the
  -- shim is loaded once per simulated host -- the separator in
  -- `package.config` is what it reads to decide Windows, and a stubbed
  -- `io.popen` answers its `uname -s` -- and asked directly.
  -- ---------------------------------------------------------------------
  do
    -- luacheck: ignore 122
    -- (`package.config` and `io.popen` are swapped for the length of one load
    -- and put back, as in `shim_links_spec.lua`.)

    ---@param sep string The directory separator the simulated host reports.
    ---@param uname string? What `uname -s` prints there; nil: no `uname` at all.
    ---@return string answers, integer asked How often `uname` was run.
    local function has_on(sep, uname)
      local saved = {
        vim = _G.vim,
        config = package.config,
        popen = io.popen,
        lfs = package.preload.lfs,
        dkjson = package.preload.dkjson,
        lfs_loaded = package.loaded.lfs,
        dkjson_loaded = package.loaded.dkjson,
        popup = package.preload["lib.nvim.notify.popup"],
      }
      local asked = 0
      local ran, answer = pcall(function()
        local host_chunk = assert(loadfile(root .. "/standalone/vim_shim.lua"))
        package.loaded.lfs, package.loaded.dkjson = nil, nil
        package.preload.lfs = lfs_on_uv
        package.preload.dkjson = dkjson_refusing
        package.config = sep .. saved.config:sub(2)
        io.popen = function(cmd)
          asked = asked + 1
          assert(tostring(cmd):find("uname", 1, true), "only `uname` is expected here: " .. cmd)
          if uname == nil then
            return nil
          end
          return {
            read = function()
              return uname
            end,
            close = function()
              return true
            end,
          }
        end
        _G.vim = nil
        local host = host_chunk()
        local out = {}
        for _, feature in ipairs({ "win32", "mac", "unix", "nvim" }) do
          out[#out + 1] = feature .. "=" .. tostring(host.fn.has(feature))
        end
        return table.concat(out, " ")
      end)
      _G.vim = saved.vim
      package.config = saved.config
      io.popen = saved.popen
      package.preload.lfs, package.preload.dkjson = saved.lfs, saved.dkjson
      package.loaded.lfs, package.loaded.dkjson = saved.lfs_loaded, saved.dkjson_loaded
      package.preload["lib.nvim.notify.popup"] = saved.popup
      return ran and answer or ("raised: " .. tostring(answer)), asked
    end

    local answers, asked = has_on("/", "Darwin\n")
    eq(answers, "win32=0 mac=1 unix=1 nvim=0", "shim fn.has on a simulated macOS")
    eq(asked, 1, "shim fn.has: macOS is recognised by asking `uname` once")

    answers = has_on("/", "Linux\n")
    eq(answers, "win32=0 mac=0 unix=1 nvim=0", "shim fn.has on a simulated Linux")

    answers = has_on("/", nil)
    eq(answers, "win32=0 mac=0 unix=1 nvim=0", "shim fn.has on a Unix without `uname`")

    answers, asked = has_on("\\", "Darwin\n")
    eq(answers, "win32=1 mac=0 unix=0 nvim=0", "shim fn.has on a simulated Windows")
    eq(asked, 0, "shim fn.has: Windows never asks `uname`")
  end
end
