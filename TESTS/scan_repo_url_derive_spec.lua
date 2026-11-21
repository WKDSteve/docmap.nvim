-- Test code: when something here comes back nil -- a fixture write, the
-- scanned IR -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/scan_repo_url_derive_spec.lua — `scan()`'s repo_url/branch
-- auto-derivation from a real git remote/branch (GS-16), when neither a
-- `.docmap.json`, a CLI flag nor the host supplied them.
--
-- Its own file, not part of config_file_spec.lua: the derivation itself
-- lives in `core/scan.lua`, not `config.build` (see that file's own
-- comment on why -- `config.build` is relied on as cheap by
-- `bindings/usrcmds/init.lua`'s per-keystroke completion, so a git
-- subprocess belongs in scan(), which already walks the whole tree once
-- per real scan).
--
-- Real git fixtures, not mocks: the point under test is that `scan()`
-- actually reaches a real "origin" remote and a real current branch, not
-- that some fake plumbing agrees with itself.

return function(H)
  local eq = H.eq
  local cfg = require("docmap.config")
  local scan = require("docmap.core.scan")

  local root_dir = (vim.fn.tempname():gsub("\\", "/"))

  ---A minimal repository: one Lua module, nothing else.
  ---@param name string
  ---@return string abs
  local function repo(name)
    local abs = root_dir .. "/" .. name
    vim.fn.mkdir(abs .. "/lua/thing", "p")
    local fd = assert(io.open(abs .. "/lua/thing/init.lua", "w"))
    fd:write("---@module 'thing'\nlocal M = {}\nreturn M\n")
    fd:close()
    return abs
  end

  ---@param dir string
  ---@param args string[]
  local function git_run(dir, args)
    local argv = {
      "git",
      "-c",
      "user.name=docs-spec",
      "-c",
      "user.email=docs-spec@example.invalid",
      "-C",
      dir,
    }
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait()
    assert(
      res.code == 0,
      ("fixture: git %s failed: %s"):format(table.concat(args, " "), res.stderr)
    )
  end

  local git_derived = repo("git_derived")
  git_run(git_derived, { "init", "-q", "-b", "feature/derived" })
  git_run(git_derived, { "remote", "add", "origin", "https://github.com/someone/derived-repo.git" })
  git_run(git_derived, { "add", "-A" })
  git_run(git_derived, { "commit", "-q", "-m", "init" })

  local ir = scan.scan(cfg.build(git_derived))
  eq(
    ir.meta.repo_url,
    "https://github.com/someone/derived-repo",
    "scan: repo_url auto-derives from the real 'origin' remote"
  )
  eq(ir.meta.branch, "feature/derived", "scan: branch auto-derives from the real current branch")

  -- An explicit override still wins over derivation -- config.build's merge
  -- order runs before scan() ever sees opts, same precedence as every other
  -- option.
  local overridden_ir = scan.scan(cfg.build(git_derived, { branch = "explicit" }))
  eq(overridden_ir.meta.branch, "explicit", "scan: an explicit branch still beats git derivation")

  -- Not a git repository at all: derivation finds nothing, scan()'s own
  -- `branch or "main"` fallback (not config.build's -- that one no longer
  -- has a static default, see DEFAULTS.lua) is what actually answers.
  local no_repo = repo("no_repo")
  local no_repo_ir = scan.scan(cfg.build(no_repo))
  eq(no_repo_ir.meta.repo_url, nil, "scan: repo_url stays nil outside a git repository")
  eq(no_repo_ir.meta.branch, "main", 'scan: branch falls back to "main" outside a git repository')

  -- ---------------------------------------------- no git process per scan
  -- The remote and the branch are read from `.git/config` and `.git/HEAD`
  -- (`core/git_files.lua`): a scan -- after every save with `watch = true` --
  -- must not start `git` for them. Counted through a `vim.system` stand-in
  -- that passes every other program through.
  local git_files = require("docmap.core.git_files")
  local real_system = vim.system
  local git_starts = {}
  ---@param fn fun()
  ---@return string[][] starts The git argv started while `fn` ran.
  local function count_git(fn)
    git_starts = {}
    vim.system = function(cmd, o, cb) ---@diagnostic disable-line: duplicate-set-field
      if type(cmd) == "table" and cmd[1] == "git" then
        git_starts[#git_starts + 1] = cmd
      end
      return real_system(cmd, o, cb)
    end
    local okc, err = pcall(fn)
    vim.system = real_system
    assert(okc, err)
    return git_starts
  end

  git_files.clear()
  local counted_ir
  local starts = count_git(function()
    counted_ir = scan.scan(cfg.build(git_derived))
  end)
  eq(#starts, 0, "scan: deriving remote and branch starts no git process")
  eq(
    counted_ir.meta.repo_url,
    "https://github.com/someone/derived-repo",
    "...and still finds the remote"
  )
  eq(counted_ir.meta.branch, "feature/derived", "...and the branch")

  local traffic_join = require("docmap.core.traffic_join")
  local traffic_repo
  starts = count_git(function()
    traffic_repo = traffic_join.repo({ root = git_derived })
  end)
  eq(#starts, 0, "traffic: the repository of :DocBrowse traffic is read without git")
  eq(traffic_repo, "someone/derived-repo", "...and is the remote's owner/repo")

  -- A linked worktree: `.git` is a file, the config lives in the common dir.
  local wt = root_dir .. "/derived_wt"
  git_run(git_derived, { "worktree", "add", "-q", "-b", "wt/branch", wt })
  starts = count_git(function()
    counted_ir = scan.scan(cfg.build(wt))
  end)
  eq(#starts, 0, "scan: a linked worktree is read without git as well")
  eq(counted_ir.meta.branch, "wt/branch", "...with the worktree's own branch")
  eq(
    counted_ir.meta.repo_url,
    "https://github.com/someone/derived-repo",
    "...and the shared remote"
  )

  -- A detached HEAD: git's short sha is the answer, asked once per HEAD.
  git_run(git_derived, { "checkout", "-q", "--detach" })
  local short = vim.trim(
    real_system({ "git", "-C", git_derived, "rev-parse", "--short", "HEAD" }, { text = true }):wait().stdout
  )
  starts = count_git(function()
    counted_ir = scan.scan(cfg.build(git_derived))
    scan.scan(cfg.build(git_derived))
  end)
  eq(counted_ir.meta.branch, short, "scan: a detached HEAD links git's short sha, as before")
  eq(#starts, 1, "...asked of git once for two scans of the same HEAD")
  git_run(git_derived, { "checkout", "-q", "feature/derived" })

  -- A config that rewrites URLs is left to git, which applies the rewrite.
  local rewrite = repo("rewrite")
  git_run(rewrite, { "init", "-q", "-b", "main" })
  git_run(rewrite, { "remote", "add", "origin", "gh:someone/rewritten" })
  git_run(rewrite, { "config", "url.https://github.com/.insteadOf", "gh:" })
  git_files.clear()
  starts = count_git(function()
    counted_ir = scan.scan(cfg.build(rewrite))
  end)
  eq(
    counted_ir.meta.repo_url,
    "https://github.com/someone/rewritten",
    "scan: an insteadOf rewrite is resolved by git"
  )
  eq(#starts, 1, "...with one git start, the remote only")

  -- The config reader itself.
  local url, unsure = git_files.config_url(
    '[core]\n\tbare = false\n[remote "upstream"]\n\turl = https://x/a/b\n[remote "origin"]\n'
      .. "\turl = git@github.com:o/r.git\n\turl = https://second/o/r\n",
    "origin"
  )
  eq(url, "git@github.com:o/r.git", "config: the first url of the named remote")
  eq(unsure, false, "...read with certainty")
  eq(git_files.config_url("[core]\n", "origin"), nil, "config: no such remote is nil")
  local _, inc =
    git_files.config_url('[include]\n\tpath = x\n[remote "origin"]\n\turl = u\n', "origin")
  eq(inc, true, "config: an include is left to git")
end
