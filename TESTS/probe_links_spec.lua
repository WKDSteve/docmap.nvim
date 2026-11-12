-- TESTS/probe_links_spec.lua -- the editor-side probes of the committed map follow a link only while it stays inside
-- the project (`core/safe_fs`), like the CLI's readers.
--
-- Covered: `:DocMap open` (the opener), the `generate_all` autoload detection, and `:checkhealth`'s walkers over a
-- source or tests directory. Each case has a file or directory outside the project that holds a marker, and a twin
-- link that stays inside, so "refuse every link" cannot pass.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("docmap.config")
  local safe_fs = require("docmap.core.safe_fs")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_probe_links"
  local outside = base .. "/outside"

  local function project(name)
    local root = base .. "/" .. name
    H.write(root .. "/docs/map/module_map.json", { "{}" })
    H.write(root .. "/lua/a.lua", { "return {}" })
    return root
  end

  local function run()
    H.write(outside .. "/index.html", { "<html>OUTSIDE</html>" })
    H.write(outside .. "/map.json", { "{}" })
    H.write(outside .. "/src/x.lua", { "return 1" })
    H.write(outside .. "/src/y.lua", { "return 2" })

    -- ── :DocMap open ─────────────────────────────────────────────────────
    local opened = {}
    local real_open = package.loaded["lib.nvim.cross.open_default"]
    package.loaded["lib.nvim.cross.open_default"] = function(url)
      opened[#opened + 1] = url
    end
    local warned = {}
    local notify = {
      warn = function(msg)
        warned[#warned + 1] = msg
      end,
    }
    local function open_with(root)
      opened, warned = {}, {}
      local cfg = config.build(root, {})
      local opener = require("docmap.bindings.usrcmds.open").opener(cfg, notify, "DocMap", nil)
      return opener(nil)
    end

    local root_a = project("a")
    local leak = H.link(outside .. "/index.html", root_a .. "/docs/map/index.html", false)
    ok(leak, "the leaking page link can be made")
    eq(open_with(root_a), false, "open: a page that is a link out of the project is not opened")
    eq(#opened, 0, "open: ...nothing was handed to the browser")
    ok(
      warned[1] and warned[1]:find("No map generated", 1, true) ~= nil,
      "open: ...it counts as missing"
    )

    local root_b = project("b")
    H.write(root_b .. "/real_index.html", { "<html>INSIDE</html>" })
    local inside =
      H.link(H.canonical(root_b) .. "/real_index.html", root_b .. "/docs/map/index.html", false)
    ok(inside, "the inside page link can be made")
    eq(open_with(root_b), true, "open: a page that is a link inside the project is opened")
    eq(#opened, 1, "open: ...once")

    local root_c = project("c")
    H.write(root_c .. "/docs/map/index.html", { "<html>PLAIN</html>" })
    eq(open_with(root_c), true, "open: a plain page is opened")
    package.loaded["lib.nvim.cross.open_default"] = real_open

    -- ── generate_all autoload ────────────────────────────────────────────
    local docmap = require("docmap")
    local real_run = docmap.generate_all.run
    local missing_seen
    docmap.generate_all.run = function(missing)
      missing_seen = missing
    end
    local info = { info = function() end, error = function() end }
    local ga = require("docmap.bindings.usrcmds.generate_all")
    local leaking = project("d")
    vim.fn.delete(leaking .. "/docs/map/module_map.json")
    ok(
      H.link(outside .. "/map.json", leaking .. "/docs/map/module_map.json", false),
      "the leaking map link can be made"
    )
    local plain = project("e")
    ga.autoload(
      { projects = { { root = leaking, title = "leaking" }, { root = plain, title = "plain" } } },
      info
    )
    docmap.generate_all.run = real_run
    eq(
      #(missing_seen or {}),
      1,
      "autoload: only the project whose map is a leaking link counts as missing"
    )
    eq(missing_seen and missing_seen[1].title, "leaking", "autoload: ...and it is that one")

    -- ── health: the walkers ──────────────────────────────────────────────
    local health = require("docmap.editor.health")
    local root_h = project("h")
    local here = H.canonical(root_h)
    H.write(root_h .. "/real_src/m.lua", { "return 1" })
    local in_link = H.link(here .. "/real_src", root_h .. "/linked_in", true)
    local out_link = H.link(outside .. "/src", root_h .. "/linked_out", true)
    ok(in_link and out_link, "the directory links can be made")
    eq(health.count_lua(root_h, root_h .. "/lua"), 1, "health: a plain source directory is counted")
    eq(
      health.count_lua(root_h, root_h .. "/linked_in"),
      1,
      "health: a directory link that stays inside is followed"
    )
    eq(
      health.count_lua(root_h, root_h .. "/linked_out"),
      0,
      "health: a directory link out of the project counts as empty"
    )
    ok(safe_fs.is_dir(root_h, root_h .. "/linked_in"), "health: the inside link is a directory")
    ok(not safe_fs.is_dir(root_h, root_h .. "/linked_out"), "health: the outside link is not one")
    eq(
      next(health.languages_under(root_h, root_h .. "/linked_out")),
      nil,
      "health: no language is claimed through a leaking link"
    )
  end

  local finished, err = pcall(run)
  vim.fn.delete(base, "rf")
  if not finished then
    error(err, 0)
  end
end
