---@module 'docmap.editor.health'
--- `:checkhealth documentation`.
---
--- Scoped to the things that actually go wrong, which is a shorter list than
--- it looks: an absent optional tool degrades to a stated finding rather than
--- an error, so the failure modes worth a health check are the ones that make
--- a command silently do the wrong thing — a missing dependency, an absent
--- treesitter Lua parser, and a map generated for a directory the user did
--- not mean.
---
--- That last one is the reason this exists at all. `:DocMap` defaults its root
--- to the **current working directory**, so "it mapped the wrong repository"
--- and "it says my tree has one module" are the same bug seen from two
--- angles, and neither is visible from the output. The configuration section
--- prints the resolved options and what is actually on disk under them.

local M = {}

local i18n = require("docmap.core.i18n")
local soft_require = require("docmap.core.soft_require")

-- vim.health shim (start/ok/warn/error/info exist on all supported versions).
local H = vim.health or {}
local h_start = H.start or H.report_start
local h_ok = H.ok or H.report_ok
local h_warn = H.warn or H.report_warn
local h_error = H.error or H.report_error
local h_info_raw = H.info or H.report_info

---An info line, with the advice `vim.health.info` has no parameter for.
---
---`warn` and `error` take advice as varargs and render it under the message;
---`info` takes the message and nothing else, so the second argument the calls
---below pass was being dropped on the floor -- none of that advice ever
---reached `:checkhealth`. It is rendered into the message here instead, in the
---shape `vim.health`'s own `format_report_message` gives a warning's advice
---(the report indents every line after the first by two), so an info line and
---a warning line read alike.
---@param msg string
---@param advice string[]? Rendered under the message, one line each.
local function h_info(msg, advice)
  if advice and #advice > 0 then
    msg = msg .. "\n- ADVICE:\n  - " .. table.concat(advice, "\n  - ")
  end
  h_info_raw(msg)
end

---The advice under a report line: one catalog text, one list entry per line of it.
---
---One text rather than a key per line: the lines are one paragraph broken to fit the report, and a translation
---has to be free to break it somewhere else.
---@param key string
---@param params table<string, any>?
---@return string[]
local function advice(key, params)
  return vim.split(i18n.t(key, params), "\n", { plain = true })
end

local MIN_NVIM = { 0, 10, 0 }

---The lib.nvim modules this plugin actually requires, as module paths rather
---than a single `lib.nvim` probe: `lib.nvim` has no `init.lua` for several of
---its namespaces, so "is lib.nvim installed" is not a question `require` can
---answer directly, and the useful answer is which piece is missing anyway.
---@type string[]
local DEPS = {
  "lib.nvim.notify",
  "lib.nvim.bindings.keymap",
  "lib.nvim.bindings.usercmd",
  "lib.nvim.bindings.autocmd",
  "lib.nvim.debounce",
  "ui.kit",
  "lib.nvim.fs.read",
  "lib.nvim.fs.mkdirp",
  "lib.nvim.fs.is_subpath",
  "lib.nvim.fs.collect_recursive",
  "lib.nvim.cross.open_default",
  "lib.nvim.cross.uv.spawn_capture",
}

local version_ok = require("lib.nvim.health").version_ok

---Count the `.lua` files under `dir`, recursively, without loading the scanner: the point of this check is to
---answer "is `source` pointing at anything" even when the scan itself is what is failing.
---
---Walks through `core/safe_fs`, like the scan does: a link is followed only while it stays inside `root`, so a
---source or tests directory that is a link out of the project counts as empty rather than being read (and a link
---back up the tree cannot make the walk run forever).
---@param root string
---@param dir string
---@return integer
local function count_lua(root, dir)
  local n = 0
  local ok, files = pcall(require("docmap.core.safe_fs").walk_files, root, dir)
  for _, f in ipairs(ok and files or {}) do
    if f:sub(-4) == ".lua" then
      n = n + 1
    end
  end
  return n
end

---Which language backends claim files under `dir`, by backend name.
---
---Asked of the registry per filename rather than by an extension table of
---its own: `is_source` is the backend's answer to "is this mine", and a
---second list here would be a second thing to keep in step — which is the
---drift this plugin exists to find.
---
---Bounded the same way `count_lua` is: no scanner, no config, so it still
---answers when a scan is what is broken.
---@param root string
---@param dir string
---@return table<string, boolean>
local function languages_under(root, dir)
  local seen = {}
  local registry = require("docmap.core.lang_registry")
  local ok, files = pcall(require("docmap.core.safe_fs").walk_files, root, dir)
  for _, f in ipairs(ok and files or {}) do
    local backend = registry.for_file(f:match("[^/]*$"))
    if backend then
      seen[backend.name] = true
    end
  end
  return seen
end

-- Exported for the same reason `serve.safe_sha` is: a rule about links that cannot be run without a whole health
-- report does not get tested.
M.count_lua = count_lua
M.languages_under = languages_under

function M.check()
  -- Environment ------------------------------------------------------------
  h_start(i18n.t("health.section.environment"))

  local v = vim.version()
  local versions = {
    version = ("%d.%d.%d"):format(v.major, v.minor, v.patch),
    required = ("%d.%d.%d"):format(MIN_NVIM[1], MIN_NVIM[2], MIN_NVIM[3]),
  }
  if version_ok(MIN_NVIM) then
    h_ok(i18n.t("health.nvim.ok", versions))
  else
    h_warn(i18n.t("health.nvim.too-old", versions), advice("health.nvim.too-old.advice"))
  end

  -- The Lua parser is not optional the way lua-language-server is: without it
  -- `functions.lua`, `calls.lua` and `symbols.lua` produce nothing, and the
  -- map still renders — a tree of modules with no functions in it, which
  -- looks like a scanner bug rather than a missing parser.
  local ok_parser = pcall(vim.treesitter.language.add, "lua")
  if not ok_parser then
    ok_parser = pcall(vim.treesitter.get_string_parser, "local M = {}", "lua")
  end
  if ok_parser then
    h_ok(i18n.t("health.parser.ok"))
  else
    h_error(i18n.t("health.parser.missing"), advice("health.parser.missing.advice"))
  end

  -- A catalog that does not load leaves its locale speaking English, which nothing else on screen explains.
  local catalog_problems = i18n.problems()
  local broken = vim.tbl_keys(catalog_problems)
  table.sort(broken)
  for _, locale in ipairs(broken) do
    local reason = catalog_problems[locale]
    -- The one line with an English text in the code: when the source catalog is the broken one, the sentence
    -- that says so cannot come out of it.
    h_warn(
      i18n.has("health.catalog.unreadable")
          and i18n.t("health.catalog.unreadable", { locale = locale, reason = reason })
        or ("interface catalog %s.json is not loaded: %s"):format(locale, reason)
    )
  end

  -- Dependencies -----------------------------------------------------------
  h_start(i18n.t("health.section.lib"))

  local missing = {}
  for _, mod in ipairs(DEPS) do
    if not soft_require.probe(mod) then
      missing[#missing + 1] = mod
    end
  end
  if #missing == 0 then
    h_ok(i18n.t("health.lib.ok", { count = #DEPS }))
  else
    h_error(
      i18n.t("health.lib.missing", { missing = #missing, count = #DEPS }),
      advice("health.lib.missing.advice", { modules = table.concat(missing, ", ") })
    )
  end

  -- Optional tools ---------------------------------------------------------
  h_start(i18n.t("health.section.tools"))

  if vim.fn.executable("git") == 1 then
    h_ok(i18n.t("health.git.ok"))
  else
    h_warn(i18n.t("health.git.missing"), advice("health.git.missing.advice"))
  end

  if vim.fn.executable("lua-language-server") == 1 then
    h_ok(i18n.t("health.luals.ok"))
  else
    -- The advice names `:Mason`, here and nowhere else on purpose. `:Mason` is
    -- how a Neovim user installs a language server, so saying it is genuinely
    -- helpful — and saying it *only* here matters: the same sentence in a
    -- committed HTML page or in docmap-desktop would be advice about a
    -- program the reader may not be running. Pointing at mason is a
    -- sentence; installing a toolchain on somebody's behalf is a
    -- different kind of program, and not one this plugin is.
    h_info(i18n.t("health.luals.missing"), advice("health.luals.missing.advice"))
  end

  -- Optional, and the *absence* case is the interesting one: without it
  -- `:DocMap pick` still works through lib.nvim's kit chooser, so this is
  -- an upgrade rather than a requirement. Reported at `info` for that
  -- reason — a missing tool that costs nothing is not a warning.
  local pickers = soft_require.probe("pickers.engines")
  if pickers then
    local engines = {}
    for _, name in ipairs({ "telescope", "fzf", "snacks" }) do
      local mod = soft_require.probe("pickers.engines." .. name)
      local ok_probe, yes = pcall(function()
        return mod and mod.available and mod.available()
      end)
      if ok_probe and yes then
        engines[#engines + 1] = name
      end
    end
    if #engines > 0 then
      h_ok(i18n.t("health.pickers.ok", { engines = table.concat(engines, ", ") }))
    else
      h_info(i18n.t("health.pickers.no-engine"), advice("health.pickers.no-engine.advice"))
    end
  else
    h_info(i18n.t("health.pickers.missing"), advice("health.pickers.missing.advice"))
  end

  local pdfport = soft_require.probe("pdfport")
  if pdfport and type(pdfport.can_create) == "function" and pdfport.can_create("markdown") then
    h_ok(i18n.t("health.pdfport.ok"))
  elseif pdfport then
    h_info(i18n.t("health.pdfport.no-producer"), advice("health.pdfport.no-producer.advice"))
  else
    h_info(i18n.t("health.pdfport.missing"), advice("health.pdfport.missing.advice"))
  end

  -- **Reported as an addition, never as a requirement**, and the wording
  -- carries the measurement: inline `code` in `:DocBrowse`'s detail pane is
  -- highlighted with or without this — 2 132 spans in this tree — while
  -- fenced blocks are four bodies out of a hundred and twenty-three. An
  -- "optional dependency missing" line that did not say so would send a
  -- reader to install something for a case they may not have.
  local cma = require("docmap.core.soft_require").probe("color_my_ascii")
  if cma and type(cma.fences) == "table" and type(cma.fences.list_blocks) == "function" then
    h_ok(i18n.t("health.color-my-ascii.ok"))
  elseif cma then
    h_info(
      i18n.t("health.color-my-ascii.no-fences"),
      advice("health.color-my-ascii.no-fences.advice")
    )
  else
    h_info(i18n.t("health.color-my-ascii.missing"), advice("health.color-my-ascii.missing.advice"))
  end

  -- No external dependency to probe, unlike pdfport above — call hierarchy
  -- is built entirely on Neovim's own LSP client (`vim.lsp.start()` with a
  -- function `cmd`, no external process) and `handle.callers`/`callees`,
  -- which already exist on every installed handle regardless of this
  -- option.
  --
  -- Reports whether the client is actually *running*, not merely that the
  -- option exists. The failure mode this covers is silent and easy to
  -- misread: with no client attached, `vim.lsp.buf.incoming_calls()` opens
  -- nothing, which looks exactly like "this function has no callers"
  -- rather than like a configuration problem. Asking Neovim's own client
  -- list is the only answer that cannot be wrong — an installed handle's
  -- `opts.callhierarchy` says what was *requested*, and the client attaches
  -- on `BufReadPost`, so a buffer opened before `setup()` ran has the
  -- option set and no client. See docs/call_hierarchy.md.
  local ch_clients = vim.lsp.get_clients({ name = "docmap-callhierarchy" })
  if #ch_clients > 0 then
    local buffers = 0
    for _, client in ipairs(ch_clients) do
      for _ in pairs(client.attached_buffers or {}) do
        buffers = buffers + 1
      end
    end
    h_ok(i18n.t("health.callhierarchy.running", { buffers = buffers }))
  else
    h_info(i18n.t("health.callhierarchy.detached"))
  end

  -- Same posture as call hierarchy directly above: no external dependency,
  -- nothing here that can be missing or broken.
  h_ok(i18n.t("health.diagnostics.available"))

  local telemetry_self = soft_require.probe("docmap.core.telemetry_self")
  local self_instance = telemetry_self and telemetry_self.instance()
  if self_instance then
    h_ok(i18n.t("health.telemetry.ok", { namespace = ("%q"):format(self_instance.namespace) }))
  elseif soft_require.probe("runtime-analysis.telemetry") then
    h_info(i18n.t("health.telemetry.idle"), advice("health.telemetry.idle.advice"))
  else
    h_info(i18n.t("health.telemetry.missing"), advice("health.telemetry.missing.advice"))
  end

  -- Commands ---------------------------------------------------------------
  h_start(i18n.t("health.section.commands"))

  local registered = {}
  for name in pairs(vim.api.nvim_get_commands({})) do
    if name == "DocMap" or name == "DocBrowse" or name:match("^Doc") then
      registered[#registered + 1] = name
    end
  end
  if #registered > 0 then
    table.sort(registered)
    h_ok(i18n.t("health.commands.registered", { commands = table.concat(registered, ", :") }))
  else
    h_warn(i18n.t("health.commands.none"), advice("health.commands.none.advice"))
  end

  -- What this plugin puts in the user's editor beyond the commands.
  --
  -- "Does this plugin install anything global?" is a fair question to be able
  -- to answer without grepping, and for an autocommand the honest answer is
  -- not derivable at runtime: `nvim_get_autocmds` shows what happens to be
  -- installed *now*, which for four autocmds created lazily by four different
  -- lifecycles is almost never the full set. So this reads the manifest in
  -- `bindings/autocmds.lua`, which states the whole surface including the
  -- parts not currently active.
  local manifest = soft_require.probe("docmap.bindings.autocmds")
  if manifest then
    local buffer_local, global = 0, 0
    for _, a in ipairs(manifest.list) do
      if a.scope == "buffer" then
        buffer_local = buffer_local + 1
      else
        global = global + 1
      end
    end
    h_info(
      i18n.t("health.autocmds.summary", { global = global, buffer_local = buffer_local }),
      vim.tbl_map(function(a)
        return ("%s (%s) — %s"):format(table.concat(a.events, ","), a.owner, a.lifetime)
      end, manifest.list)
    )
    h_info(i18n.t("health.keymaps.none-global"))
  end

  -- Configuration ----------------------------------------------------------
  --
  -- The section this file exists for. Every number below is what a `:DocMap`
  -- issued right now would act on.
  h_start(i18n.t("health.section.config"))

  -- Where `config.build`'s degradation warnings go in this host.
  --
  -- Same reason `scripts/action_run.lua` and `standalone/docmap.lua` each
  -- grew one: `build()` warns about an unrecognised option, a malformed
  -- `.docmap.json` and a typo'd `checks` code only through a `notify` it is
  -- handed, and this section exists specifically to make config degradation
  -- visible — passing none silenced exactly what it was written to report.
  local notify = {
    warn = function(msg)
      h_warn(i18n.t("health.config.warning", { message = tostring(msg) }))
    end,
  }

  local ok_cfg, cfg = pcall(function()
    return require("docmap.config").build(vim.fn.getcwd(), nil, notify)
  end)
  if not ok_cfg then
    h_error(i18n.t("health.config.load-failed", { error = tostring(cfg) }))
    return
  end

  h_info(i18n.t("health.config.root", { root = cfg.root }))
  local sources = require("docmap.config").sources(cfg)
  h_info(i18n.t("health.config.source", { sources = table.concat(sources, ", ") }))
  h_info(i18n.t("health.config.out-dir", { out_dir = tostring(cfg.out_dir) }))

  -- One report per root. A tree with `lua/` beside `src/` has two answers to
  -- "does the source directory exist and hold anything", and collapsing them
  -- into one would hide whichever half is broken.
  for _, src in ipairs(sources) do
    local source_dir = cfg.root .. "/" .. src
    if not require("docmap.core.safe_fs").is_dir(cfg.root, source_dir) then
      h_error(
        i18n.t("health.source.missing", { dir = source_dir }),
        advice("health.source.missing.advice")
      )
    else
      local n = count_lua(cfg.root, source_dir)
      if n == 0 then
        -- Not a warning for a non-Lua root: `src/` full of TypeScript is a
        -- perfectly good source root, and this counter only knows `.lua`.
        h_info(i18n.t("health.source.no-lua", { source = src }))
      else
        h_ok(
          i18n.t(
            n == 1 and "health.source.lua-one" or "health.source.lua-many",
            { source = src, count = n }
          )
        )
      end
    end
  end

  -- Language support ------------------------------------------------------
  --
  -- **The most likely reason a panel is empty in a non-Lua project, and
  -- until now the one thing this check said nothing about.** The
  -- environment section above probes the *Lua* parser, which was the whole
  -- story when there was one backend. There are twenty-three, and a Go or
  -- Python tree with no grammar installed produces a complete module tree
  -- with no functions in it — which reads as a scanner bug rather than as a
  -- missing grammar.
  --
  -- Scoped to the languages this tree actually contains, never all
  -- twenty-three: a report listing twenty-two absent grammars for a Lua
  -- repository is a wall nobody reads, and the one line that mattered would
  -- be in it somewhere.
  --
  -- **The correction that belongs beside it**, because the instinct this
  -- section answers is usually "so I need a linter per language": no. Every
  -- drift check in `core/check.lua` reads the IR this tool built and works
  -- in every language with nothing installed. A grammar buys *function-level
  -- data*; `lua-language-server` buys `@class`/`@alias` detail in Lua. Those
  -- are the only two external dependencies, and neither is a linter.
  h_start(i18n.t("health.section.languages"))

  local present = {}
  for _, src in ipairs(sources) do
    for name in pairs(languages_under(cfg.root, cfg.root .. "/" .. src)) do
      present[name] = true
    end
  end

  if not next(present) then
    h_info(i18n.t("health.languages.none"))
  else
    local registry = require("docmap.core.lang_registry")
    local report = {}
    for _, entry in ipairs(registry.report()) do
      report[entry.name] = entry
    end

    local names = {}
    for name in pairs(present) do
      names[#names + 1] = name
    end
    table.sort(names)

    local no_grammar = {}
    for _, name in ipairs(names) do
      local entry = report[name]
      if not entry then
        -- A backend that claims files but is switched off for this scan
        -- (`opts.languages`) has no report row. Silence would read as
        -- "supported"; it is the opposite.
        h_info(i18n.t("health.language.disabled", { language = name }))
      elseif entry.grammar_loaded == nil then
        h_ok(i18n.t("health.language.no-grammar-needed", { language = name }))
      elseif entry.grammar_loaded then
        h_ok(
          i18n.t(
            "health.language.grammar-loaded",
            { language = name, grammar = ("%q"):format(entry.grammar) }
          )
        )
      else
        no_grammar[#no_grammar + 1] = entry
        h_warn(
          i18n.t(
            "health.language.grammar-missing",
            { language = name, grammar = ("%q"):format(entry.grammar) }
          ),
          advice("health.language.grammar-missing.advice", { grammar = entry.grammar })
        )
      end
    end

    if #no_grammar == 0 then
      h_ok(i18n.t("health.languages.all-ok", { count = #names }))
    end

    h_info(
      i18n.t("health.languages.checks-need-none"),
      advice("health.languages.checks-need-none.advice")
    )
  end

  -- The one configuration mistake that produces a *plausible wrong answer*
  -- rather than an error.
  --
  -- `coverage.resolve` treats a missing `tests_dir` as "nothing is tested" by
  -- design — every function is simply left `tested = false`, which is the
  -- honest result for a tree with no tests. But it is indistinguishable from
  -- a tree whose tests are somewhere else: the Analysis tab then reports 0%
  -- test coverage for the whole map, and that reads as a badly tested
  -- repository rather than as a wrong path. Nothing else on the page says
  -- otherwise, so this is where it gets said.
  h_info(i18n.t("health.tests-dir.resolved", { dir = cfg.tests_dir or "TESTS" }))

  local tests_dir = cfg.root .. "/" .. (cfg.tests_dir or "TESTS")
  if not require("docmap.core.safe_fs").is_dir(cfg.root, tests_dir) then
    h_warn(
      i18n.t("health.tests-dir.missing", { dir = cfg.tests_dir or "TESTS" }),
      advice("health.tests-dir.missing.advice")
    )
  else
    -- Every `.lua` file, not just `*_spec.lua`: `coverage.lua`'s `lua_files`
    -- filters on the extension alone and nothing else, so a helper or a
    -- fixture under `tests_dir` contributes mentioned names exactly like a
    -- spec does. Counting only spec-shaped names here would report a smaller
    -- number than the one the coverage figure is actually derived from.
    local n = count_lua(cfg.root, tests_dir)
    if n == 0 then
      h_warn(
        i18n.t("health.tests-dir.empty", { dir = cfg.tests_dir or "TESTS" }),
        advice("health.tests-dir.empty.advice")
      )
    else
      h_ok(
        i18n.t(
          n == 1 and "health.tests-dir.lua-one" or "health.tests-dir.lua-many",
          { dir = cfg.tests_dir or "TESTS", count = n }
        )
      )
    end
  end

  -- How the *headless runner* finds lib.nvim, which is a different question
  -- from the one answered above.
  --
  -- The dependency section asks "does lib.nvim load right now", which a
  -- plugin-manager install satisfies. `TESTS/run.lua` and `scripts/ci.sh` do
  -- not run inside that editor — they are `nvim --headless -u NONE`, with no
  -- plugin manager and an empty rtp — so they resolve lib.nvim through
  -- LIB_NVIM_DIR, `.deps/lib.nvim`, or a sibling checkout. A contributor can
  -- pass everything above and still have `scripts/ci.sh tests` fail on its
  -- first line.
  local lib_candidates = {
    { label = "$LIB_NVIM_DIR", path = vim.env.LIB_NVIM_DIR },
    { label = ".deps/lib.nvim", path = cfg.root .. "/.deps/lib.nvim" },
    { label = "../lib.nvim", path = vim.fs.dirname(cfg.root) .. "/lib.nvim" },
  }
  local found_lib
  for _, c in ipairs(lib_candidates) do
    if c.path and vim.fn.isdirectory(c.path) == 1 then
      found_lib = c
      break
    end
  end
  if found_lib then
    h_ok(i18n.t("health.headless.ok", { source = found_lib.label }))
  else
    h_info(i18n.t("health.headless.missing"), advice("health.headless.missing.advice"))
  end

  -- Artifacts --------------------------------------------------------------
  h_start(i18n.t("health.section.artifacts"))

  -- Read the way the CLI reads the committed map (`core/artifact.lua`): an
  -- `out_dir` that is not a safe relative path, or a map behind a link that
  -- leaves the project, is reported with its reason rather than opened --
  -- opening it is what a hostile repository would have this report do.
  local safe_fs = require("docmap.core.safe_fs")
  local out_dir = require("docmap.core.safe_out_dir")(cfg.out_dir)
  if not out_dir then
    h_warn(
      i18n.t("health.artifacts.unsafe-out-dir", { out_dir = tostring(cfg.out_dir) }),
      advice("health.artifacts.unsafe-out-dir.advice")
    )
    return
  end
  local artifact = cfg.root .. "/" .. out_dir .. "/module_map.json"
  local raw, kind, why = safe_fs.read(cfg.root, artifact)
  if kind == "refused" then
    h_warn(
      i18n.t("health.artifacts.refused", { out_dir = cfg.out_dir, reason = tostring(why) }),
      advice("health.artifacts.refused.advice")
    )
    return
  end
  if not raw then
    h_info(
      i18n.t("health.artifacts.none", { out_dir = cfg.out_dir }),
      advice("health.artifacts.none.advice")
    )
    return
  end

  local ok_json, decoded = pcall(vim.json.decode, raw, { luanil = { object = true } })
  if not ok_json or type(decoded) ~= "table" or type(decoded.nodes) ~= "table" then
    h_error(
      i18n.t("health.artifacts.unreadable", { out_dir = cfg.out_dir }),
      advice("health.artifacts.unreadable.advice")
    )
    return
  end

  h_ok(i18n.t("health.artifacts.ok", { out_dir = cfg.out_dir, nodes = #decoded.nodes }))

  -- Staleness by mtime rather than by regenerating: `:DocMap check` is the
  -- authoritative answer and costs a full scan, which is not what a health
  -- check should spend. This is the cheap approximation, and it says so.
  -- The map was just read through `safe_fs`, so statting that path is no way
  -- out of the project either.
  local art_stat = vim.uv.fs_stat(artifact)
  local newest, newest_path = 0, nil
  -- Every source root. This asks "is the map older than the newest source
  -- file"; walking only one of two roots would answer it for half the tree
  -- and report the map fresh while the other half had moved on. The walk
  -- lists only files it has placed inside the project, so statting those is
  -- no way out of it.
  for _, src in ipairs(require("docmap.config").sources(cfg)) do
    for _, p in ipairs(safe_fs.walk_files(cfg.root, cfg.root .. "/" .. src)) do
      if p:sub(-4) == ".lua" then
        local st = vim.uv.fs_stat(p)
        if st and st.mtime.sec > newest then
          newest, newest_path = st.mtime.sec, p
        end
      end
    end
  end

  if art_stat and newest > art_stat.mtime.sec then
    h_warn(
      i18n.t("health.artifacts.stale"),
      advice("health.artifacts.stale.advice", { path = tostring(newest_path) })
    )
  elseif art_stat then
    h_ok(i18n.t("health.artifacts.fresh"))
  end

  -- The declared external tools (docs/install.json), reported out of the
  -- spec rather than listed a second time by hand. Silent when lib.nvim.deps
  -- is absent (an older lib.nvim) or this plugin ships no spec.
  local ok_deps, deps_health = pcall(require, "lib.nvim.deps.health")
  if ok_deps then
    h_start(i18n.t("health.section.declared-tools"))
    deps_health.report_for("docmap.nvim")
  end
end

return M
