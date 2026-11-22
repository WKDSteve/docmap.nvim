-- TESTS/usrcmds_git_async_spec.lua — `:DocMap diff` and `:DocMap impact` do not wait for git.
--
-- `usrcmds_git_spec.lua` runs both commands against a real repository; this file pins *how* they run, which a real
-- git cannot show deterministically: a `vim.system` stand-in whose `wait()` throws (any return to a blocking call
-- is an error) and whose processes end only when the case says so. That makes "the command returned before git
-- answered", "impact asks both questions at once and answers once" and "a newer request drops the older answer"
-- plain assertions instead of timing guesses.

return function(H)
  H.with_restore(nil, function()
    local eq, ok = H.eq, H.ok
    local git_async = require("docmap.bindings.usrcmds.git_async")
    local diff_cmd = require("docmap.bindings.usrcmds.diff")
    local impact_cmd = require("docmap.bindings.usrcmds.impact")

    local real_system = vim.system
    ---@type { argv: string[], cwd: string, on_exit: fun(r: table) }[]
    local starts = {}
    local fail_spawn = false

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(argv, opts, on_exit)
      if fail_spawn then
        error("ENOENT: no such file or directory (cmd): 'git'")
      end
      starts[#starts + 1] = { argv = argv, cwd = opts and opts.cwd, on_exit = on_exit }
      return {
        wait = function()
          error("the editor waited for git: " .. table.concat(argv, " "))
        end,
        kill = function() end,
      }
    end

    ---End start `i` with `code`/`stdout`/`stderr`, the way vim.system's callback is called (off the main loop).
    local function finish(i, code, stdout, stderr)
      starts[i].on_exit({ code = code, stdout = stdout or "", stderr = stderr or "" })
    end

    local function settle()
      return vim.wait(2000, git_async.idle, 5)
    end

    local function fake_ctx()
      local calls = { info = {}, warn = {} }
      return {
        cfg = { root = "/fixture/root", out_dir = "docs/map" },
        handle = {
          ir = function()
            error("no answer reached the comparison in this file")
          end,
        },
        command_name = "DocMap",
        notify = {
          info = function(msg)
            calls.info[#calls.info + 1] = msg
          end,
          warn = function(msg)
            calls.warn[#calls.warn + 1] = msg
          end,
        },
      },
        calls
    end

    local function reset()
      starts = {}
      fail_spawn = false
    end

    local ok_all, err = pcall(function()
      -- ========================================================= diff: returns before git answers
      do
        reset()
        local ctx, calls = fake_ctx()
        diff_cmd.run(ctx, "v1")
        eq(#starts, 1, "diff: one git start")
        eq(
          table.concat(starts[1].argv, " "),
          "git show v1:docs/map/module_map.json",
          "diff: the map at the ref"
        )
        eq(starts[1].cwd, "/fixture/root", "diff: in the root of the command")
        ok(not git_async.idle(), "diff: the request is in flight after the command returned")
        eq(#calls.info + #calls.warn, 0, "diff: nothing is said before git answers")

        finish(1, 128, "", "fatal: invalid object name 'v1'")
        ok(settle(), "diff: the answer settles")
        eq(#calls.warn, 1, "diff: the answer arrives as one warning")
        ok(calls.warn[1]:find("Cannot read", 1, true) ~= nil, "diff: naming the read failure")
        ok(
          calls.warn[1]:find("invalid object name", 1, true) ~= nil,
          "diff: with git's own complaint"
        )
      end

      -- ========================================================= diff: a newer request wins
      do
        reset()
        local ctx1, calls1 = fake_ctx()
        local ctx2, calls2 = fake_ctx()
        diff_cmd.run(ctx1, "old")
        diff_cmd.run(ctx2, "new")
        eq(#starts, 2, "diff twice: two starts")
        finish(2, 0, "not json")
        finish(1, 0, "not json either")
        ok(settle(), "diff twice: both answers settle")
        eq(#calls1.info + #calls1.warn, 0, "diff twice: the older request's late answer is dropped")
        eq(#calls2.warn, 1, "diff twice: the newer request answers")
        ok(calls2.warn[1]:find("new", 1, true) ~= nil, "diff twice: for its own ref")
      end

      -- ========================================================= impact: both at once, one answer
      do
        reset()
        local ctx, calls = fake_ctx()
        impact_cmd.run(ctx, "HEAD")
        eq(#starts, 2, "impact: diff and show start together, before either answers")
        eq(starts[1].argv[2], "diff", "impact: the changed lines")
        eq(
          table.concat(starts[2].argv, " "),
          "git show HEAD:docs/map/module_map.json",
          "impact: the committed map"
        )
        eq(#calls.info + #calls.warn, 0, "impact: nothing is said before git answers")

        finish(1, 0, "")
        vim.wait(50, function()
          return false
        end, 5)
        eq(#calls.info + #calls.warn, 0, "impact: one answer in is not the answer")
        ok(not git_async.idle(), "impact: the second request is still in flight")

        finish(2, 0, "{}")
        ok(settle(), "impact: both answers settle")
        eq(#calls.info, 1, "impact: one message for the two requests")
        ok(calls.info[1]:find("Nothing changed", 1, true) ~= nil, "impact: an empty diff says so")
      end

      -- ========================================================= impact: answers in either order, newer wins
      do
        reset()
        local ctx1, calls1 = fake_ctx()
        local ctx2, calls2 = fake_ctx()
        impact_cmd.run(ctx1, "a")
        impact_cmd.run(ctx2, "b")
        eq(#starts, 4, "impact twice: four starts")
        finish(4, 0, "{}")
        finish(2, 0, "{}")
        finish(3, 128, "", "fatal: bad revision 'b'")
        finish(1, 128, "", "fatal: bad revision 'a'")
        ok(settle(), "impact twice: all answers settle")
        eq(
          #calls1.info + #calls1.warn,
          0,
          "impact twice: the older request's late answer is dropped"
        )
        eq(#calls2.warn, 1, "impact twice: the newer request answers once")
        ok(
          calls2.warn[1]:find("Cannot diff", 1, true) ~= nil,
          "impact twice: with its own diff failure"
        )
      end

      -- ========================================================= git cannot be started
      do
        reset()
        fail_spawn = true
        local ctx, calls = fake_ctx()
        diff_cmd.run(ctx, "HEAD")
        eq(#calls.info + #calls.warn, 0, "no git: still answered on a later tick")
        ok(settle(), "no git: the failed start settles")
        eq(#calls.warn, 1, "no git: one warning")
        ok(calls.warn[1]:find("ENOENT", 1, true) ~= nil, "no git: naming why")

        local ctx2, calls2 = fake_ctx()
        impact_cmd.run(ctx2, "HEAD")
        ok(settle(), "no git: impact settles too")
        eq(#calls2.warn, 1, "no git: impact warns once")
      end
    end)

    vim.system = real_system
    if not ok_all then
      error(err, 0)
    end
  end)
end
