-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "docmap",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  -- TESTS/sheets_spec.lua is busted style: one case per test sheet (`sheet:<id>`, testing sheets report).
  dialect = { ["TESTS/sheets_spec.lua"] = "busted", ["*"] = "h" },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "runtime-analysis.nvim", "ui.nvim", "testing.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "none",
  -- A browser sheet over a served page starts a host process, a chromium and a page load: served-runtime-detail came
  -- within half a second of the default 10 s on an idle machine.
  timeouts = { case_ms = 30000 },
  -- Guards (safety nets, see testing.nvim docs/GUARDS.md).
  guards = {
    -- TESTS/sheets/out holds the page the browser sheets open and their screenshots (git-ignored)
    fs = { mode = "error", allow = { "TESTS/sheets/out" } },
    -- The specs run in one editor (isolated = "none") and leave no state behind: each takes
    -- H.snapshot() at its start and H.restore() / H.wipe_new() at its end (TESTS/harness.lua).
    state = {
      mode = "error",
      -- The Kit* highlight groups (KitNormal, KitAccent, ... and the window-scoped KitNormal_N,
      -- KitBorder_N, KitTitle_N) belong to the ui kit of lib.nvim, which ui.nvim drives: the first
      -- kit surface a spec opens (docmap_browse_spec) defines them once per process, and the kit
      -- relies on them existing afterwards (it re-links them on ColorScheme), so a spec must not
      -- delete them. docmap.nvim defines no Kit* group of its own.
      ignore_highlights = { "Kit" },
    },
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- shim_behavior_spec runs io.popen('"git" "--version" 2>&1'); the guard reads the program of
    -- such a doubly quoted shell line as git (the extra outer pair of quotes that cmd /c wants is
    -- no part of the first word), so "git" in guard_allow.spawn below covers it.
    process_net = "error",
  },
  -- What the guards let through on purpose.
  guard_allow = {
    -- The specs build tmp repositories (git init/commit/rev-parse), the docmap reads the git
    -- remote/branch, the plugin spawns a headless nvim and the language parsers, and the
    -- fixture cleanup removes directories with rm, and the link specs make a
    -- directory junction on Windows with `cmd /C mklink /J` (TESTS/harness.lua, H.link).
    -- The shim (standalone/vim_shim.lua), which shim_behavior_spec runs, shells out twice: `uname
    -- -s` on Unix to tell macOS from Linux, and on Windows the cmd line `set "DIRCMD=" & dir
    -- /a:l ...` to list links. The guard judges a shell string by its first word, hence `set`.
    -- git_run_spec runs the standalone git runner, whose shell line starts `cd <root> && git ...`.
    -- standalone_telemetry_spec runs the standalone engine under a PUC Lua (lua, lua5.4, lua5.3).
    -- release_script_spec runs scripts/check_dll_imports.sh with bash against a fake objdump.
    spawn = {
      "git",
      "nvim",
      "node",
      "rm",
      "cmd",
      "uname",
      "set",
      "cd",
      "lua",
      "lua5.4",
      "lua5.3",
      "bash",
    },
    -- Fixtures of the generate-all spec live below .deps/generate-all-*; the callhierarchy spec
    -- makes the runtime append to the Neovim LSP log in the state directory.
    -- Not listed: the telemetry store runtime-analysis.nvim writes below stdpath('state'). The
    -- telemetry specs point it at a temp directory of their own (H.telemetry_store in
    -- TESTS/harness.lua), so they pass however XDG_STATE_HOME is set.
    fs = {
      ".deps",
      vim.fn.stdpath("state") .. "/lsp.log",
    },
  },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  -- Not listed on purpose: NVIM_* (the validator refuses names with that prefix, and one refused
  -- entry voids the whole list) and XDG_*_HOME (the child gets its own sandbox values, and
  -- shim_behavior_spec compares the shim with the editor of the same process, so both read those).
  -- TESTS/testing_config_spec.lua keeps the list valid.
  env_allow = {
    -- backend_contract_spec points a language backend at a parser library with these.
    "DOCMAP_CSHARP_PARSER",
    "DOCMAP_DART_PARSER",
    "DOCMAP_ELIXIR_PARSER",
    "DOCMAP_ERLANG_PARSER",
    "DOCMAP_GO_PARSER",
    "DOCMAP_HASKELL_PARSER",
    "DOCMAP_JAVA_PARSER",
    "DOCMAP_KOTLIN_PARSER",
    "DOCMAP_PHP_PARSER",
    "DOCMAP_PYTHON_PARSER",
    "DOCMAP_RUBY_PARSER",
    "DOCMAP_RUST_PARSER",
  },
  -- The programs the test sheets run against (testing.sheet.app). `shape-host` is the host of the shape-diff
  -- sheets (TESTS/shape_host.lua: `:DocMap serve` over the maps-page fixture, git stood in for). Port 0, so two
  -- runs on one machine never share one; its first stdout line, the URL, is `${host}` of the sheet. Its files go
  -- to `${temp}`, a folder of the run.
  sheets = {
    apps = {
      ["shape-host"] = {
        run = { "nvim", "--headless", "-u", "NONE", "-l", "TESTS/shape_host.lua", "${temp}", "0" },
        ready = { stdout = "^http://", as = "host", timeout_ms = 30000 },
      },
      -- `:DocMap serve` over the lookup-page fixture with a telemetry store of known content (TESTS/telemetry_host.lua).
      -- The store lives below stdpath("state"), so that is moved into the run's folder; the host refuses to write
      -- anywhere else.
      ["telemetry-host"] = {
        run = {
          "nvim",
          "--headless",
          "-u",
          "NONE",
          "-l",
          "TESTS/telemetry_host.lua",
          "${temp}",
          "0",
        },
        env = { XDG_STATE_HOME = "${temp}/state" },
        ready = { stdout = "^http://", as = "host", timeout_ms = 30000 },
      },
    },
  },
  -- gated: a failed conformance check makes `scripts/test.sh conformance` exit 1 (docs/CONFORMANCE.md of testing.nvim)
  conformance = {
    gate = true,
    waivers = {
      {
        check = "K6",
        level = "warn",
        text = "TESTS does not exist",
        reason = "the conformance child editor runs in an empty temp directory and the health check resolves tests_dir against the cwd; with the project as cwd the directory exists and the check passes",
        expires = "2027-04-14",
      },
    },
  },
  -- The pipeline `scripts/ci.sh` (a shim for `testing ci`) and the workflow jobs run. `scripts/ci.sh <gate>` runs one
  -- step (`tests` is the step `suite`); `--fast` is the pre-push profile.
  ci = {
    default = "full",
    profiles = {
      fast = { "stylua", "luacheck" },
      full = { "fast", "suite", "conformance", "map", "standalone", "workflow-in-sync" },
    },
    -- The GitHub workflow, generated: `testing init --workflow=public --force` writes .github/workflows/ci.yml from
    -- this (testing.nvim docs/WORKFLOW-CI.md); the step workflow-in-sync keeps the two together.
    workflow = {
      name = "docmap.nvim",
      layout = "hosted",
      -- the steps that depend on the platform: the windows and macOS legs run only these
      platform = { "suite", "conformance" },
      -- `testing ci land`: a check branch ci/** runs the hosted legs, main moves to a commit only once it is green there
      land = true,
      -- TESTS/min_version_spec.lua keeps this version, the docs and the comment above the matrix together
      min_nvim = { version = "0.11.4", why = "the version floor docs/ promises" },
      -- the browser sheets (TESTS/sheets/*.sheet.lua with a page): the version mdview.nvim pins
      playwright = { version = "1.64.1", used_by = "the browser sheets" },
      -- the screenshots of the browser sheets, red or green, from the full ubuntu leg (sheet-shots-ubuntu, 14 days)
      artifacts = {
        {
          name = "sheet-shots",
          path = "TESTS/sheets/out/**/*.png",
          why = "what the page looked like is the evidence a sheet leaves behind",
        },
      },
      checkouts = {
        {
          repo = "WKDSteve/rules.nvim",
          ref = "ci-verified",
          why = "the real-engine half of TESTS/rules_api_spec.lua and the rules.nvim engine of the step standalone",
        },
      },
      packages = {
        {
          name = "tree-sitter-cli",
          npm = { "tree-sitter-cli@0.27.1" },
          why = "builds the grammars of the call specs (scripts/ci-setup.sh parsers)",
        },
      },
      setup = {
        {
          run = { "bash", "scripts/ci-setup.sh", "parsers" },
          legs = "hosted",
          why = "the javascript, typescript, tsx, go, python and rust grammars, pinned by commit, into .deps/ts-parsers: without them the call specs skip, and they are the only gates of their resolvers",
        },
        {
          run = { "bash", "scripts/ci-setup.sh", "linux" },
          why = "PUC Lua 5.4 with lfs and dkjson for the step standalone, and ../lib.nvim for the step map",
        },
      },
      publish = {
        why = "images.nvim checks out docmap.nvim at ci-verified",
      },
    },
    steps = {
      ["workflow-in-sync"] = { preset = "workflow-in-sync" },
      -- `standalone` is in the list because it was not: the parser-less build sat outside the only gate that reads
      -- Lua for unused locals and undefined globals.
      luacheck = { preset = "luacheck", args = { "lua", "TESTS", "scripts", "standalone" } },
      map = { run = { "nvim", "--headless", "-l", "scripts/gen_map.lua", "--check" } },
      -- the standalone build under a PUC Lua (not LuaJIT). Without lfs and dkjson (or without the rules.nvim engine
      -- where that part is optional) it skips itself and exits 77: the step is `skipped`, the run partial, no proof
      standalone = {
        run = { "nvim", "-n", "-i", "NONE", "--headless", "-l", "scripts/ci.lua", "standalone" },
        skip_exit = 77,
      },
    },
  },
}
