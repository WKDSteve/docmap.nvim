---@module 'standalone.docmap'
--- Neovim-free CLI entry point — the "standalone CLI, parser-less MVP":
--- the module tree, require graph and
--- every check/renderer that does not need per-function facts, running under
--- plain `lua`/`luajit`, no Neovim process anywhere. Deliberately mirrors
--- `scripts/gen_map.lua` (same `ensure()` dependency search, same
--- `docmap.config.build`/`docmap.core.cli.run` call shape) —
--- read that file first if this one looks unfamiliar; the difference is only
--- in how the Neovim-only bits (`vim.uv.cwd`, `vim.opt.runtimepath`,
--- `vim.cmd("cq ...")`) get replaced.
---
---   lua standalone/docmap.lua <root> [--source=lua/x] [--repo-url=U]
---                                    [--branch=B] [--check] [--lenient]
---
--- No `--full` (LuaLS enrichment shells out to `lua-language-server` via
--- `vim.system`, an editor-process capability this build does not have) and
--- no `opts.badge`/`opts.pdf` wiring beyond what `core/cli.lua` itself
--- already does — same MVP boundary `vim_shim.lua`'s header documents.
---
--- **Function-level data is no longer part of that boundary.** With a
--- `lua-tree-sitter` rock installed and `$DOCMAP_TS_DIR` pointing at a
--- directory of compiled grammars, `standalone/treesitter.lua` replaces the
--- inert parser stub and this build produces a byte-identical artifact to
--- `nvim --headless -l scripts/gen_map.lua`. Without either, it degrades to
--- the parser-less MVP exactly as before rather than failing.

require("standalone.vim_shim") -- installs _G.vim before anything requires it

local root = (arg[1] or "."):gsub("\\", "/"):gsub("/+$", "")

-- `--capabilities` is recognised in the **root** position, and that is not a
-- style choice.
--
-- Every unrecognised `--flag` *after* the root falls through to
-- `core/cli.run` as an ordinary argv entry. So an older binary asked "do you
-- support X?" that way does not answer — it **generates the map**, writing
-- into the caller's repository and exiting 0 with output that is not JSON.
-- Measured, not imagined: that is exactly what the shipped binary did the
-- first time it was handed `--api=telemetry`, and a viewer polling a panel
-- would have rewritten a user's `docs/map` on every fetch.
--
-- A flag in root position is the one probe that is safe against both
-- versions: an older binary rejects it with its usage line, before doing any
-- work, and a newer one answers after its dependencies are on the path. So
-- "this engine has no capabilities" and "this engine is too old" are a
-- single observation, which is what a host actually needs.
local capabilities_only = (root == "--capabilities")

-- this file lives at <repo>/standalone/docmap.lua; its own repo root is
-- always on package.path so `docmap.*` resolves regardless of the
-- scanned root above (which is normally a *different* directory).
local self_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]")) or "."
local self_root = self_dir .. "/.."

---Put a dependency's `lua/` on `package.path`, if it is not already
---reachable — same three-candidate search `scripts/gen_map.lua#ensure` uses,
---adapted from `vim.opt.runtimepath`/`vim.env` (Neovim-only) to
---`package.path`/`os.getenv`.
---@param modname string
---@param dirname string
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = os.getenv(dirname:upper():gsub("[.-]", "_") .. "_DIR")
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = self_root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = self_root .. "/../" .. dirname
  for _, dir in ipairs(candidates) do
    package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
    if pcall(require, modname) then
      return
    end
  end
  io.stderr:write(
    ("standalone/docmap.lua: %s not found (probed require('%s')).\n"):format(dirname, modname)
  )
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(
      dirname:upper():gsub("[.-]", "_"),
      dirname
    )
  )
  os.exit(1)
end

---Same three-candidate search as `ensure()`, but soft: does not exit when
---nothing is found.
---
---**Necessary, not sufficient — measured, not assumed.** `telemetry_join.
---lua`'s own `M.load` already treats "runtime-analysis.nvim is not
---installed" the same as "installed, but nothing was ever collected" —
---`available:false, reason:"no data"` either way — so a missing path here
---reads as a correct-looking answer even when it is not. This call is what
---lets a real checkout be *found* at all; it does not, on its own, make
---`--api=telemetry` succeed against real data. Traced against this
---machine's own real telemetry (63 KB of real collected data,
---`docmap.nvim`'s own self-instrumentation):
---`runtime-analysis.telemetry` itself loads, but its own
---`require("lib.nvim.bindings.autocmd")` pulls in `lib.lua.lazy`, a *different*
---`lib.*` sub-namespace than `lib.nvim.*` — and `scripts/bundle_manifest.
---lua`'s `bucket()` only recognises `^lib%.nvim`, so that module is never
---staged into the compiled binary even when the measuring run finds it.
---A full fix needs `bucket()` widened, plus `RUNTIME_ANALYSIS_NVIM_DIR` set
---for the *build's* manifest-measuring step, not just at run time — left
---for a following change rather than guessed at here. Until then this
---degrades exactly the way an absent checkout always has: honestly, with a
---stated reason, never a wrong answer.
---
---`ensure()` above is the wrong shape for this regardless — `lib.nvim`/
---`docmap.nvim` are load-bearing and a missing one should stop the
---build cold; `runtime-analysis.nvim` is optional everywhere else this join
---already runs, and should degrade the same way here, not fail loudly for a
---dependency every other caller treats as soft.
---@param modname string
---@param dirname string
local function ensure_soft(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = os.getenv(dirname:upper():gsub("[.-]", "_") .. "_DIR")
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = self_root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = self_root .. "/../" .. dirname
  for _, dir in ipairs(candidates) do
    package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
    local loaded, err = pcall(require, modname)
    if loaded then
      return
    end
    -- Found but it does not load (one of its own requires fails): that is the answer, and `--api=telemetry` reports
    -- it. Looking on would let a later checkout hide the failure of the one the environment named.
    local not_found = "module '" .. modname .. "' not found"
    if tostring(err):sub(1, #not_found) ~= not_found then
      return
    end
  end
  -- Silent otherwise, on purpose: `--api=telemetry` says why (`telemetry_join.availability`: not found, or does
  -- not load, with the one-line error) and `--capabilities` leaves `telemetry` out, which a host sees without
  -- reading stderr.
end

package.path = self_root .. "/lua/?.lua;" .. self_root .. "/lua/?/init.lua;" .. package.path
ensure("lib.nvim.fs.read", "lib.nvim")
ensure("docmap.core.cli", "docmap.nvim")
-- One call, not one per module: both `runtime-analysis.telemetry` and
-- `runtime-analysis.loaded` (loaded/snapshots routes) live in the same
-- checkout, so putting it on package.path once resolves both.
ensure_soft("runtime-analysis.telemetry", "runtime-analysis.nvim")
-- `rules.nvim`'s engine, for the `rules/*` routes (`core/rules_api.lua`). Soft for the same reason: a binary built
-- without it answers those routes with a reason and says so in `--capabilities` (`rules` is absent there), rather
-- than refusing to start for a dependency only one tab of the app needs.
ensure_soft("rules.settings", "rules.nvim")

-- The language of everything below, decided before the first line is printed: the usage line, and the warnings
-- `config.build` hands to `notify`. `--locale=`, then `$DOCMAP_LOCALE`, else English, and never `$LANG`: hosts
-- and CI scripts read this output as text (`docs/i18n.md`, "Choosing a language"). The flag is looked for in
-- every position, the root's included, and stays in `argv`: `core/cli.run` reads it again, which is idempotent.
local i18n = require("docmap.core.i18n")
do
  ---@type string?
  local locale_flag
  for i = 1, #arg do
    local a = arg[i]
    if a:match("^%-%-locale=") then
      locale_flag = a:sub(#"--locale=" + 1)
    end
  end
  i18n.configure({ locale = i18n.resolve(locale_flag, os.getenv("DOCMAP_LOCALE")) })
end

-- Below the dependency search rather than above it since the usage line comes out of the catalog, which is
-- only reachable once this repository's `lua/` is on the path. Still before any work is done.
if not capabilities_only and root:sub(1, 1) == "-" then
  io.stderr:write(i18n.t("cli.usage") .. "\n")
  os.exit(2)
end

-- What a host asks before trusting this binary with anything else.
--
-- Answered here rather than parsed out of a `--help` string, and read off
-- `core/api.routes` and `core/lang_registry.report()` rather than restated,
-- so a route or a language backend added there is advertised without this
-- file being told.
--
-- `languages` is what lets a host stop guessing why a map came back thin.
-- Pointed at a mostly-Python repository, this engine produces a valid,
-- nearly empty map; a host that knows the backend list can say so before
-- generating rather than showing the empty result as a success. Note the
-- three-valued `grammar_loaded` (see `lang_registry.report`): true, false
-- and absent are three different states, and a host that flattens them
-- reports a healthy backend as broken.
if capabilities_only then
  local names = {}
  for name in pairs(require("docmap.core.api").routes) do
    names[#names + 1] = name
  end
  table.sort(names)
  -- `rules` is claimed only when `rules.nvim`'s engine is really loadable here: the `rules/*` routes are always
  -- listed (they answer `available = false` without it), so the route list alone cannot tell a host whether this
  -- build can run rules. An older engine has neither, and that is the same answer: no `rules`.
  local caps = { "api", "languages", "schema" }
  -- `telemetry`: `runtime-analysis.telemetry` loads here, so `--api=telemetry` can read a store. Without it the
  -- route answers with the reason (`reason_code`), and a host sees that without asking the route.
  if require("docmap.core.telemetry_join").availability() == "ok" then
    caps[#caps + 1] = "telemetry"
  end
  local rules_api = require("docmap.core.rules_api")
  if rules_api.engine() then
    caps[#caps + 1] = "rules"
    -- `rules-agent`: `rules/plan` and `rules/validate` can answer (`rules.nvim`'s agent functions are here too)
    if rules_api.agent_engine() then
      caps[#caps + 1] = "rules-agent"
      -- `rules-attach`: `rules/attach` can say whether one file may go into a request (the same planner)
      caps[#caps + 1] = "rules-attach"
      -- `rules-write`: `rules/accept` and `rules/waive` can write a verdict and a waiver into the project, through
      -- `rules.nvim`'s own writers (`docs/hosting.md`, "rules/accept and rules/waive")
      if rules_api.write_engine() then
        caps[#caps + 1] = "rules-write"
      end
    end
  end
  print(require("docmap.core.json").encode({
    capabilities = caps,
    -- Which artifact schema this build writes. The release is rolling
    -- (`standalone-latest`), so there is no version number to report that
    -- would not be fiction; the schema is what actually decides whether
    -- two artifacts are comparable, and it is bumped deliberately.
    schema = require("docmap.core.scan").SCHEMA,
    -- Which build this is. Present only in a bundled binary --
    -- `scripts/package.lua` writes it at bundle time and never into the
    -- source tree, so a run from a checkout answers `nil` rather than
    -- claiming a provenance it does not have.
    build = (function()
      local ok, b = pcall(require, "docmap.build")
      return ok and b or nil
    end)(),
    routes = names,
    languages = require("docmap.core.lang_registry").report(),
  }))
  os.exit(0)
end

local argv = {}
-- `--repo-url`/`--branch` are options rather than defaults because this CLI
-- is generic over any root, while `scripts/gen_map.lua` is one repository's
-- own wrapper and can hardcode both. Without them the two produce maps that
-- differ in `meta.repo_url` — correct on each side, and an apples-to-oranges
-- comparison when checking that this build is byte-faithful to a Neovim run.
--
-- A real Neovim host's `core/scan.lua` can auto-derive both from `root`'s
-- git remote/branch when neither flag is given (GS-16) -- this binary
-- cannot: it runs under plain PUC Lua with no `vim.system`, so `scan()`'s
-- derivation attempt (`pcall`-guarded) finds nothing to call and leaves
-- both unset, exactly as before that existed. Left unexplicit here rather
-- than hidden behind a comment claiming parity the two builds do not have.
-- `--snapshot=` carries `core.api.answer`'s single optional `param`
-- whatever the chosen route interprets it as — a snapshot name for
-- `telemetry`/`loaded`, a commit count for `commits`, unused otherwise.
-- One flag rather than one per route because exactly one route ever reads
-- it at a time; see each route's own doc comment in `core/api.lua` for
-- which it is.
--
-- `--exclude=`/`--languages=` are read here *as well as* in `core/cli.run`,
-- and the duplication is deliberate. `config.build` below derives
-- `opts.source` from whichever backends are enabled, and it runs before
-- `cli.run` ever sees an argument -- so a caller narrowing to one language
-- would otherwise be walked from a directory a disabled backend named.
-- They stay in `argv` too: `cli.run` is the one place that parses them for
-- every host, and reading them twice is idempotent where reading them late
-- is not.
local source, repo_url, branch, out_dir, api_route, api_snapshot
local exclude, languages, trust = {}, {}, {}
local answer_file
-- the options the flags of `rules/accept` and `rules/waive` fill (`rules_api.WRITE_FLAGS`), read the same way as in
-- `standalone/rules_api.lua`
local write_opts = {}
local write_flag = require("docmap.core.rules_api").write_flag
for i = 2, #arg do
  local a = arg[i]
  local src = a:match("^%-%-source=(.+)$")
  local exc = a:match("^%-%-exclude=(.+)$")
  local langs = a:match("^%-%-languages=(.+)$")
  if exc then
    exclude[#exclude + 1] = exc
  end
  if langs then
    for name in langs:gmatch("[^,]+") do
      local trimmed = name:match("^%s*(.-)%s*$")
      if trimmed ~= "" then
        languages[#languages + 1] = trimmed
      end
    end
  end
  local url = a:match("^%-%-repo%-url=(.+)$")
  local br = a:match("^%-%-branch=(.+)$")
  local out = a:match("^%-%-out%-dir=(.+)$")
  local api = a:match("^%-%-api=(.+)$")
  -- `--select=` is `--snapshot=` under the name `rules/run` reads it by (the selection of rules to run); one value
  -- either way, `core.api.answer`'s single `param`. `--trust=<folder>` (repeatable): a folder whose rulesets may run
  -- their `lua_predicate` checks (`core/rules_api.lua`); the host decides what it trusts, this only passes it on.
  local snap = a:match("^%-%-snapshot=(.+)$") or a:match("^%-%-select=(.+)$")
  local trusted = a:match("^%-%-trust=(.+)$")
  -- `--answer=<file>`: the model's answer `rules/validate` checks. A file, not stdin: a host that forgets to close
  -- a pipe would leave this process waiting for ever, a missing file is an answer with a reason.
  local answer = a:match("^%-%-answer=(.+)$")
  if trusted then
    trust[#trust + 1] = trusted
  elseif write_flag(a) then
    local key, value = write_flag(a)
    write_opts[key] = value
  elseif answer then
    answer_file = answer
  elseif src then
    -- Comma-separated, matching `scripts/action_run.lua`'s own reading of the
    -- same option and for the reason stated there: a repository can hold two
    -- languages in two places, one starting directory means the walk never
    -- *visits* the other, and a comma in a source directory name is not a
    -- case anyone has. A single entry stays a plain string, so a one-root
    -- repository produces byte-identical output to every run before this.
    local list = {}
    for part in src:gmatch("[^,]+") do
      local trimmed = part:match("^%s*(.-)%s*$")
      if trimmed ~= "" then
        list[#list + 1] = trimmed
      end
    end
    source = #list == 1 and list[1] or (#list > 0 and list or nil)
  elseif url then
    repo_url = url
  elseif br then
    branch = br
  elseif out then
    out_dir = out
  elseif api then
    api_route = api
  elseif snap then
    api_snapshot = snap
  else
    argv[#argv + 1] = a
  end
end

--- Where `config.build`'s warnings go in a build with no editor in it.
---
--- Without this they went nowhere. `build()` takes a `lib.nvim.notify`-shaped
--- instance and this entry point passed none, so an unrecognised option, a
--- malformed `.docmap.json` or a typo'd `checks` key were all silently
--- ignored — in exactly the host where a person is least able to guess that
--- something was ignored, since `docmap-desktop` runs this binary and shows
--- only its output.
---
--- `stderr`, not stdout: stdout carries the run's own report, which
--- `scripts/ci.lua` and the app both parse.
---
--- Only `.warn` is implemented, because only `.warn` is called. A wider
--- fake would be claiming a contract this file does not honour.
local notify = {
  warn = function(msg)
    io.stderr:write(i18n.t("cli.warning", { message = tostring(msg) }) .. "\n")
  end,
}

local opts = require("docmap.config").build(root, {
  source = source, -- nil: config.build auto-detects, same as scripts/gen_map.lua's callers that omit it
  -- `nil` rather than an empty table for both: `config.build` merges
  -- overrides shallowly, and `{}` would be a real value that reads as "the
  -- caller said something" everywhere downstream. It does not.
  exclude = #exclude > 0 and exclude or nil,
  languages = #languages > 0 and languages or nil,
  repo_url = repo_url,
  branch = branch,
  -- `--out-dir` exists for the parity gate in `scripts/ci.lua`: comparing this
  -- build's output against the committed map must not overwrite the committed
  -- map to do it. Left nil, `config.build`'s own default applies as before.
  out_dir = out_dir,
}, notify)

-- **`layers` used to be hardcoded here, and it was a bug rather than a
-- shortcut.** This CLI is generic over any root — it is what `docmap-desktop`
-- runs for every project in somebody's list — and the three rules it carried
-- were *this* repository's own architecture, applied to every tree it was
-- ever pointed at. They matched nothing elsewhere, so the damage was not
-- wrong findings; it was that no other project could state any rules of its
-- own, because a generic CLI had no way to be handed one.
--
-- `config.build` now reads `<root>/.docmap.json`, which is where this
-- repository's three rules live. Every other repository gets its own, or
-- none, which is what it always should have been. See `config/file.lua`.

-- `--api=<route>`: answer one of the generated page's own `/api/*` routes
-- and print its JSON, instead of generating anything.
--
-- This is what makes the app a real host rather than a viewer. The page
-- already fetches these routes and already handles their answers; what it
-- never had outside Neovim was anything on the other end. `docmap-desktop`
-- runs a small HTTP server that forwards `/api/*` here — Rust is transport
-- only, and the join logic stays in Lua, owned once by `core/api.lua` and
-- shared with `editor/serve.lua`'s in-editor server.
--
-- One route per invocation, deliberately: a request is one question, and a
-- process that answered several would need a protocol to say which answer
-- is which. stdout carries exactly the JSON, so the caller does not have to
-- find where it starts.
if api_route then
  local windows = (package.config:sub(1, 1) == "\\")

  -- The runner and its quoting live in `standalone/git_run.lua` and
  -- `standalone/shell_quote.lua`, unit-tested there directly
  -- (`TESTS/git_run_spec.lua`, `TESTS/shell_quote_spec.lua`) instead of only
  -- through this file's own `lfs`-gated CI gate.
  local git_run = require("standalone.git_run")
  opts.git = function(o, args)
    return git_run.run(o, args, windows)
  end
  opts.rules_trust = trust
  opts.rules_answer_file = answer_file
  for key, value in pairs(write_opts) do
    opts[key] = value
  end

  local api = require("docmap.core.api")
  local result, api_err = api.answer(api_route, opts, api_snapshot)
  if not result then
    io.stderr:write("standalone/docmap.lua: " .. tostring(api_err) .. "\n")
    os.exit(2)
  end
  io.stdout:write(require("docmap.core.json").encode(result) .. "\n")
  os.exit(0)
end

local code = require("docmap.core.cli").run(opts, argv)
os.exit(code)
