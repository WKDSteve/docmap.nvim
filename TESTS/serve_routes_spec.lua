-- TESTS/serve_routes_spec.lua -- `:DocMap serve` declares its routes to `lib.nvim.net.server` and nothing else.
--
-- The socket, the Host check, the query whitelist and the teardown are `lib.nvim.net.server`'s (its own spec
-- covers them against a real connection; the suite's network guard does not let this one connect). What is
-- docmap's, and pinned here against a stand-in for that server: which routes exist and in which order, what each
-- validator lets through, what each handler answers, that the port option reaches the server, and that stopping
-- stops the handle it started.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("docmap.config")
  local server = require("lib.nvim.net.server")
  local serve = require("docmap.editor.serve")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_serve_routes"

  local function run()
    H.write(base .. "/docs/map/index.html", { "<html>INDEX</html>" })
    H.write(base .. "/docs/map/module_map.json", { "{}" })

    local real_start = server.start
    local captured, stopped = nil, 0
    ---@diagnostic disable-next-line: duplicate-set-field
    server.start = function(opts)
      captured = opts
      return {
        port = 4242,
        url = "http://127.0.0.1:4242/",
        stop = function()
          stopped = stopped + 1
        end,
      }
    end
    local finished, err = pcall(function()
      local cfg = config.build(base, {})
      local url = serve.start(cfg)
      eq(url, "http://127.0.0.1:4242/", "serve: the URL is the one the server reported")
      eq(captured.port, nil, "serve: no serve_port, so the OS picks the port")

      local routes = captured.routes
      eq(#routes, 4, "serve: four routes: ping, validate (POST), api, static")
      eq(routes[1].path, "/api/ping", "serve: ping comes first, so the api pattern never sees it")
      local code, ctype, body = routes[1].handler()
      eq(code, 200, "serve: ping answers")
      eq(ctype, "application/json", "serve: ping is json")
      eq(vim.json.decode(body).docmap, true, "serve: ping says it is a docmap server")

      -- the one POST route: the answer of `rules/validate` is the request body
      local validate = routes[2]
      eq(validate.path, "/api/rules/validate", "serve: the validate route has its own path")
      eq(validate.method, "POST", "serve: ...and is POST only")
      eq(validate.body_required, true, "serve: ...and needs a body")
      eq(vim.tbl_count(validate.query), 1, "serve: ...which takes only `select`")
      -- the body is handed on as the answer, and `select` as the rule; the engine itself is `core.api`'s
      local core_api = require("docmap.core.api")
      local real_answer = core_api.answer
      local seen
      ---@diagnostic disable-next-line: duplicate-set-field
      core_api.answer = function(name, c, param)
        seen = { name = name, answer = c.rules_answer, param = param, root = c.root }
        return { available = false, reason = "stub" }
      end
      local vok, vcode =
        pcall(validate.handler, { query = { select = "DEP-07" }, body = '{"results":[]}' })
      core_api.answer = real_answer
      ok(vok, "serve: the validate handler runs")
      eq(vcode, 200, "serve: validate answers 200")
      eq(seen.name, "rules/validate", "serve: ...as the rules/validate route")
      eq(seen.answer, '{"results":[]}', "serve: ...with the request body as the answer")
      eq(seen.param, "DEP-07", "serve: ...and `select` as the rule id")
      eq(cfg.rules_answer, nil, "serve: the server's own config is not changed by a request")

      -- the api route: any name goes on to core.api, which says no to the unknown ones
      local api = routes[3]
      eq(api.pattern, "^/api/(.+)$", "serve: the api route takes everything under /api/")
      ok(api.captures[1]("commit/abcdef0"), "serve: a commit route name passes the capture check")
      ok(not api.captures[1]("a\nb"), "serve: a control character in the name is refused")
      ok(not api.captures[1](("x"):rep(600)), "serve: an overlong name is refused")
      for _, key in ipairs({ "snapshot", "n", "select" }) do
        ok(api.query[key] ~= nil, "serve: the api route declares the query key " .. key)
      end
      eq(vim.tbl_count(api.query), 3, "serve: ...and no other query key")
      local nope_code = api.handler({ params = { "no-such-endpoint" }, query = {} })
      eq(nope_code, 404, "serve: an unknown api route is a 404 from core.api")
      local bad_commit = api.handler({ params = { "commit/not-a-sha" }, query = {} })
      eq(bad_commit, 404, "serve: a commit name that is no sha never reaches git")

      -- the static route
      local static = routes[4]
      eq(static.pattern, "^/([^/]*)$", "serve: the static route is one bare segment")
      ok(static.captures[1](""), "serve: the empty name (index) is accepted")
      ok(static.captures[1]("module_map.json"), "serve: a plain file name is accepted")
      ok(not static.captures[1]("a\\b"), "serve: a backslash is refused")
      ok(not static.captures[1]("a..b"), "serve: a dot-dot is refused")
      -- `?theme=` is how the page is told its theme from outside; an undeclared key is a 400 from the server.
      eq(
        vim.tbl_count(static.query or {}),
        1,
        "serve: the static route declares exactly one query key"
      )
      for _, v in ipairs({ "light", "dark", "system" }) do
        ok(static.query.theme(v), "serve: ?theme=" .. v .. " is let through")
      end
      for _, v in ipairs({ "", "Light", "blue", "light;x" }) do
        ok(not static.query.theme(v), "serve: ?theme=" .. v .. " is refused")
      end
      local icode, itype, ibody = static.handler({ params = { "" }, query = {} })
      eq(icode, 200, "serve: the index is served")
      eq(itype, "text/html; charset=utf-8", "serve: ...as html")
      ok(ibody:find("INDEX", 1, true) ~= nil, "serve: ...with the file's content")
      eq(
        static.handler({ params = { "missing.txt" }, query = {} }),
        404,
        "serve: a missing file is a 404"
      )

      -- stop goes to the handle
      eq(serve.stop(), true, "serve: stop reports that it stopped something")
      eq(stopped, 1, "serve: ...by stopping the server handle")
      eq(serve.stop(), false, "serve: a second stop is a no-op")
      eq(stopped, 1, "serve: ...it does not stop the handle again")

      -- a fixed port is handed on; a bad one never reaches the server
      captured = nil
      serve.start(config.build(base, { serve_port = 5151 }))
      eq(captured.port, 5151, "serve: serve_port reaches the server")
      serve.stop()
      captured = nil
      local bad_url, bad_err = serve.start(config.build(base, { serve_port = 70000 }))
      eq(bad_url, nil, "serve: an out-of-range port is refused")
      ok(bad_err and bad_err:find("serve_port", 1, true) ~= nil, "serve: ...naming serve_port")
      eq(captured, nil, "serve: ...before anything was started")

      -- a failed bind is reported with the port
      server.start = function()
        return nil, "cannot bind 127.0.0.1: address in use"
      end
      local _, bind_err = serve.start(config.build(base, { serve_port = 5151 }))
      ok(
        bind_err and bind_err:find("bind failed on port 5151", 1, true) ~= nil,
        "serve: a taken port says so"
      )
      eq(serve.is_running(), false, "serve: ...and nothing is recorded as running")
    end)
    server.start = real_start
    serve.stop()
    if not finished then
      error(err, 0)
    end
  end

  local finished, err = pcall(run)
  vim.fn.delete(base, "rf")
  if not finished then
    error(err, 0)
  end
end
