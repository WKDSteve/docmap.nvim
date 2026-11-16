-- TESTS/git_run_spec.lua — `standalone/git_run.lua`, the git runner of the
-- standalone build's `--api=` routes.
--
-- On Windows every git format with a `%` used to be refused, because cmd.exe
-- expands `%NAME%` even inside quotes (`standalone/shell_quote.lua`). That
-- took `--api=commits` (the commit list of docmap-desktop's map comparison)
-- and the stale check of `rules/judged` with it. The runner now moves such a
-- format into a named pretty format in a temporary git configuration. This
-- spec pins the rewrite itself on every host, and runs real git through the
-- host's shell: on Windows that is cmd.exe, which is the case that was broken.

return function(H)
  local eq, ok = H.eq, H.ok
  local git_run = require("standalone.git_run")
  local windows = package.config:sub(1, 1) == "\\"

  -- The rewrite --------------------------------------------------------------

  do
    local args, config = git_run.pretty_aliases({ "log", "-n", "5", "--format=%H\31%cs\30" })
    eq(args[4], "--pretty=docmap1", "git_run: a --format= value with a % becomes a named format")
    eq(args[1] .. args[2] .. args[3], "log-n5", "git_run: the other arguments stay as they were")
    ok(
      config and config:find('docmap1 = "tformat:%H%x1f%cs%x1e"', 1, true),
      "git_run: control bytes are spelled %xNN, kind tformat:"
    )
    for _, a in ipairs(args) do
      ok(not a:find("%", 1, true), "git_run: no argument keeps a % (" .. a .. ")")
    end
  end

  do
    local args, config = git_run.pretty_aliases({ "log", "--pretty=format:%h", "--format=>%cs" })
    eq(args[2], "--pretty=docmap1", "git_run: --pretty=format: is moved too")
    eq(args[3], "--pretty=docmap2", "git_run: each format gets its own name")
    ok(config and config:find('docmap1 = "format:%h"', 1, true), "git_run: format: keeps its kind")
    ok(
      config and config:find('docmap2 = "tformat:>%cs"', 1, true),
      "git_run: --format= is tformat:"
    )
  end

  do
    local args, config = git_run.pretty_aliases({ '--format=a"b\\%s' })
    ok(
      config and config:find('docmap1 = "tformat:a%x22b%x5c%s"', 1, true),
      "git_run: a quote and a backslash cannot end the quoted configuration value"
    )
    eq(args[1], "--pretty=docmap1", "git_run: and the argument is the name")
  end

  do
    local args, config = git_run.pretty_aliases({ "--pretty=%h" })
    eq(args[1], "--pretty=docmap1", "git_run: --pretty= with a placeholder is moved")
    ok(config and config:find('docmap1 = "tformat:%h"', 1, true), "git_run: as tformat:, like git")
    local named = git_run.pretty_aliases({ "--pretty=oneline" })
    eq(named[1], "--pretty=oneline", "git_run: a built-in format name stays")
  end

  do
    local args, config = git_run.pretty_aliases({ "diff", "--format=", "HEAD" })
    eq(config, nil, "git_run: nothing to move without a %")
    eq(args[2], "--format=", "git_run: an empty --format= stays")
  end

  do
    local out, err = git_run.run({ root = "." }, { "log", "--since=%PATH%" }, true)
    eq(out, nil, "git_run(windows): a % outside a format is still refused")
    ok(err and err:find("cmd.exe would expand", 1, true), "git_run(windows): with the reason")
  end

  -- The command line the vim shim's `vim.fn.system` builds as well ----------
  -- (`standalone/vim_shim.lua`). Before, the shim quoted its argument list
  -- itself and refused every git format with a `%` on Windows, the way
  -- `--api=commits` used to fail.

  do
    eq(git_run.is_git("git"), true, "git_run.is_git: git")
    eq(
      git_run.is_git("C:\\Program Files\\Git\\cmd\\GIT.EXE"),
      true,
      "git_run.is_git: a path to git.exe"
    )
    eq(git_run.is_git("/usr/bin/git"), true, "git_run.is_git: a POSIX path")
    eq(git_run.is_git("gitk"), false, "git_run.is_git: not gitk")
    eq(git_run.is_git(nil), false, "git_run.is_git: not nothing")

    local line, err = git_run.command_line({ "echo", "%PATH%" }, true)
    eq(line, nil, "command_line(windows): another program's % is still refused")
    ok(
      type(err) == "string" and err:find("cmd.exe would expand", 1, true),
      "command_line(windows): with the reason"
    )

    local posix = git_run.command_line({ "git", "log", "--format=%H" }, false)
    eq(posix, '"git" "log" "--format=%H"', "command_line(posix): a % is quoted as it is")

    if os.getenv("TEMP") or os.getenv("TMP") then
      local win, cleanup = git_run.command_line({ "git", "-C", "r", "log", "--format=%H" }, true)
      ok(
        win and not win:find("%", 1, true),
        "command_line(windows): no % reaches the line (" .. tostring(win) .. ")"
      )
      ok(
        win and win:find('"-c" "include.path=', 1, true),
        "command_line(windows): the format travels in a config"
      )
      ok(win and win:find('"--pretty=docmap1"$'), "command_line(windows): as a named format")
      local config = win and win:match('"include.path=([^"]+)"')
      local function exists(path)
        local fh = path and io.open(path, "rb")
        if fh then
          fh:close()
        end
        return fh ~= nil
      end
      ok(exists(config), "command_line(windows): the config exists until cleanup")
      if type(cleanup) == "function" then
        cleanup()
      end
      eq(exists(config), false, "command_line(windows): cleanup removes it")
    end
  end

  -- Real git, through this host's shell --------------------------------------

  if vim.fn.executable("git") ~= 1 then
    H.skip("git_run: no git on PATH")
    return
  end
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")
  local function git(...)
    local out = vim
      .system(
        vim.list_extend({
          "git",
          "-C",
          repo,
          "-c",
          "user.name=t",
          "-c",
          "user.email=t@t",
          "-c",
          "commit.gpgsign=false",
        }, { ... }),
        { text = true }
      )
      :wait()
    return vim.trim(out.stdout or "")
  end
  git("init", "-q")
  vim.fn.writefile({ "x" }, repo .. "/a.txt")
  git("add", "a.txt")
  git("commit", "-q", "-m", "one")
  local sha = git("rev-parse", "HEAD")
  local date = git("log", "-1", "--format=%cs")

  local out, err = git_run.run(
    { root = repo },
    { "log", "-n", "1", "--format=%H\31%cs\30" },
    windows
  )
  eq(err, nil, "git_run: a format with a % runs on this host")
  eq(out, sha .. "\31" .. date .. "\30\n", "git_run: and git expanded it, separators included")

  local relative = git_run.run({ root = repo }, { "log", "--format=>%cs", "--name-only" }, windows)
  ok(
    relative and relative:find(">" .. date, 1, true),
    "git_run: the format rules/judged uses answers"
  )

  -- The shim's way: the line `git_run.command_line` builds, run as
  -- `vim.fn.system` runs it (one more pair of quotes on Windows, which
  -- `cmd /c` strips). The shim itself cannot run here: under LuaJIT it cannot
  -- see an exit status and refuses (`fn.system/*` in the corpus covers PUC).
  do
    local line, cleanup =
      git_run.command_line({ "git", "-C", repo, "log", "-1", "--format=%H\31%cs" }, windows)
    ok(
      line,
      "command_line: git with a format builds a line on this host (" .. tostring(cleanup) .. ")"
    )
    if line then
      local full = line .. " 2>&1"
      if windows then
        full = '"' .. full .. '"'
      end
      local fh = assert(io.popen(full, "r"))
      local got = fh:read("*a")
      fh:close()
      local done = cleanup --[[@as fun()]]
      done()
      eq(
        got,
        sha .. "\31" .. date .. "\n",
        "command_line: and git expanded the format, as vim.fn.system runs it"
      )
    end
  end

  vim.fn.delete(repo, "rf")
end
