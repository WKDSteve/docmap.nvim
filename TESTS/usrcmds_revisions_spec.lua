-- TESTS/usrcmds_revisions_spec.lua — the ref completion of `:DocMap diff`/`churn` never starts git synchronously.
--
-- The refs are fetched in the background (`git.refs_async`) once the command line shows `diff `/`churn `, and the
-- `<Tab>` that follows reads them from the cache. Pinned against stand-ins: `git.refs` (the synchronous one) throws,
-- `git.refs_async` answers when the case says so, and the command line is whatever the case sets.

return function(H)
  local eq, ok = H.eq, H.ok
  local function same(actual, expected, msg)
    ok(
      vim.deep_equal(actual, expected),
      ("%s (expected %s, got %s)"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end
  local git = require("lib.nvim.git")
  local usrcmds = require("docmap.bindings.usrcmds")
  local cache = require("lib.nvim.cache.memory").namespace("docmap.revisions", { ttl = 5 })

  local CMD, BROWSE = "DocMapRevSpec", "DocBrowseRevSpec"
  local root = (vim.fn.tempname():gsub("\\", "/")) .. "_revisions"

  local real_refs, real_refs_async, real_getcmdline = git.refs, git.refs_async, vim.fn.getcmdline
  ---@type { dir: string, opts: table, on_done: fun(refs: string[], err: string|nil), stopped: boolean }[]
  local queries = {}
  local cmdline = ""

  local function reset()
    queries = {}
    cache.clear()
    cmdline = ""
  end

  ---The command line now reads `line`, as typing it would leave it.
  local function type_line(line)
    cmdline = line
    vim.api.nvim_exec_autocmds("CmdlineChanged", { pattern = ":" })
  end

  local function leave_line()
    vim.api.nvim_exec_autocmds("CmdlineLeave", { pattern = ":" })
    cmdline = ""
  end

  local function run()
    ---@diagnostic disable-next-line: duplicate-set-field
    git.refs = function()
      error("the completion started git synchronously")
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    git.refs_async = function(dir, opts, on_done)
      local q = { dir = dir, opts = opts, on_done = on_done, stopped = false }
      queries[#queries + 1] = q
      return {
        stop = function()
          q.stopped = true
        end,
      }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getcmdline = function()
      return cmdline
    end

    usrcmds.setup({
      root = root,
      command_name = CMD,
      browse_command_name = BROWSE,
      telemetry = false,
    })

    -- typed normally: the refs are on their way before the <Tab>, which then starts nothing
    reset()
    type_line(CMD .. " di")
    eq(#queries, 0, "revisions: no query before the verb is complete")
    type_line(CMD .. " diff ")
    eq(#queries, 1, "revisions: `diff ` starts one background query")
    eq(queries[1].dir, root, "revisions: ...for the command's repository")
    eq(queries[1].opts.limit, 50, "revisions: ...capped like before")
    type_line(CMD .. " diff m")
    type_line(CMD .. " diff ma")
    eq(#queries, 1, "revisions: further keys start no second query")
    queries[1].on_done({ "main", "v1" }, nil)
    same(
      vim.fn.getcompletion(CMD .. " diff m", "cmdline"),
      { "main" },
      "revisions: <Tab> offers the branch from the background answer"
    )
    eq(#queries, 1, "revisions: ...without a query of its own")
    leave_line()

    -- typed at once (the sheet's `m<Tab>`): the <Tab> waits for the query already on its way, not for a second one
    reset()
    type_line(CMD .. " diff ")
    eq(#queries, 1, "revisions: the fast line starts its query")
    vim.defer_fn(function()
      queries[1].on_done({ "main" }, nil)
    end, 20)
    same(
      vim.fn.getcompletion(CMD .. " diff m", "cmdline"),
      { "main" },
      "revisions: a <Tab> before the answer gets it once it arrives"
    )
    eq(#queries, 1, "revisions: ...and started no second query")
    leave_line()

    -- no background query (the line never matched, e.g. an abbreviated command): still no synchronous git
    reset()
    vim.defer_fn(function()
      if queries[1] then
        queries[1].on_done({ "main", "topic" }, nil)
      end
    end, 20)
    same(
      vim.fn.getcompletion(CMD .. " churn main..t", "cmdline"),
      { "main..topic" },
      "revisions: a <Tab> without a background query starts one and waits for it"
    )
    eq(#queries, 1, "revisions: ...exactly one")
    leave_line()

    -- `churn ` asks too; another command does not
    reset()
    type_line(BROWSE .. " diff ")
    eq(#queries, 0, "revisions: another command's `diff ` starts nothing")
    leave_line()
    type_line(CMD .. " churn ")
    eq(#queries, 1, "revisions: `churn ` starts the background query")

    -- leaving the line drops the query: git is stopped, a late answer fills nothing
    leave_line()
    ok(queries[1].stopped, "revisions: leaving the line stops the query")
    queries[1].on_done({ "late" }, nil)
    eq(cache.get(root), nil, "revisions: ...and its late answer is dropped")
    type_line(CMD .. " churn ")
    eq(#queries, 2, "revisions: the next line asks again")
    leave_line()

    -- a failed query is not cached; the <Tab> offers nothing rather than throwing
    reset()
    type_line(CMD .. " diff ")
    queries[1].on_done({}, "git for-each-ref failed")
    eq(cache.get(root), nil, "revisions: a failed query is not cached")
    vim.defer_fn(function()
      queries[2].on_done({}, "git for-each-ref failed")
    end, 20)
    same(
      vim.fn.getcompletion(CMD .. " diff m", "cmdline"),
      {},
      "revisions: ...the <Tab> asks once more and offers nothing"
    )
    eq(#queries, 2, "revisions: ...with one query of its own")
    leave_line()
  end

  -- `with_restore` also removes what `setup()` leaves behind (its augroup)
  local finished, err = pcall(H.with_restore, nil, run)
  git.refs, git.refs_async, vim.fn.getcmdline = real_refs, real_refs_async, real_getcmdline
  pcall(vim.api.nvim_del_augroup_by_name, "docmap.revisions." .. CMD)
  pcall(vim.api.nvim_del_user_command, CMD)
  pcall(vim.api.nvim_del_user_command, BROWSE)
  cache.clear()
  if not finished then
    error(err, 0)
  end
end
