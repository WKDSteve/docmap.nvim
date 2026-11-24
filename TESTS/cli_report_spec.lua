-- TESTS/cli_report_spec.lua — `--report`: the Duplicates, Quicks and Findings tabs on stdout, nothing written.

-- luacheck: ignore 122
-- (the end-to-end part swaps io.stdout/io.stderr to read the CLI output, and restores them.)
return function(H)
  local ok = H.ok
  local report = require("docmap.core.report")

  -- Which sections, and in which order.
  local all = report.parse_sections(nil)
  ok(#all == 3 and all[1] == "duplicates" and all[3] == "findings", "no spec means every section")
  local two = report.parse_sections("findings,duplicates,findings")
  ok(
    #two == 2 and two[1] == "duplicates" and two[2] == "findings",
    "asked sections come back once each, in the printed order"
  )
  local none, bad = report.parse_sections("quicks,nope")
  ok(none == nil and bad == "nope", "an unknown section is named, not skipped")

  -- The pure half, over a hand-made IR.
  local ir = {
    meta = { title = "demo" },
    duplicates = {
      considered = 9,
      functions = 2,
      min_size = 40,
      groups = {
        {
          shape = "s",
          size = 52,
          members = {
            { node = "a.lua", module = "a", name = "f", signature = "f(x)", line = 3 },
            { node = "b.lua", module = "b", name = "g", signature = "g(x)", line = 8 },
          },
        },
      },
    },
    quicks = {
      bad = { { id = "duplicates", tab = "analysis", unit = "count", value = 1, weight = 60 } },
      good = { { id = "module-summary", tab = "tree", unit = "percent", value = 100, weight = 80 } },
      total_bad = 1,
      total_good = 1,
    },
  }
  local findings = {
    { severity = "warn", check = "missing-summary", node = "a.lua" },
    { severity = "info", check = "missing-summary", node = "b.lua" },
  }
  local built = report.build(ir, findings, report.SECTIONS, "demo")
  ok(built.repo == "demo", "the repository name is carried")
  ok(#built.duplicates.groups == 1, "one duplicate group")
  ok(
    built.duplicates.groups[1].identical == 2 and built.duplicates.groups[1].nodes == 52,
    "the group says how many are identical and how big they are"
  )
  ok(built.quicks.total_bad == 1 and built.quicks.bad[1].id == "duplicates", "the quick verdicts")
  ok(
    built.findings.tally.warn == 1 and built.findings.tally.info == 1,
    "the findings are tallied by severity"
  )
  local only = report.build(ir, findings, { "quicks" }, "demo")
  ok(
    only.quicks and not only.duplicates and not only.findings,
    "a section not asked for is absent, not empty"
  )

  local text = table.concat(report.render_text(built), "\n")
  ok(text:find("== demo ==", 1, true), "text names the repository")
  ok(text:find("Duplicates: 1 group covering 2 functions", 1, true), "text says the duplicates")
  ok(text:find("2 identical, 52 nodes", 1, true), "text shows the group header")
  ok(text:find("f(x)  a:3", 1, true), "text shows a member with its place")
  ok(text:find("Quicks: 1 bad, 1 good", 1, true), "text says the quicks")
  ok(text:find("Findings: 0 errors, 1 warnings, 1 info", 1, true), "text says the findings")
  ok(text:find("[warn] missing-summary", 1, true), "text lists a warning")
  ok(not text:find("[info]", 1, true), "info is counted, not listed")

  -- End to end through `cli.run`: output on stdout, exit codes, nothing written.
  local config = require("docmap.config")
  local cli = require("docmap.core.cli")
  local root = (vim.fn.tempname():gsub("\\", "/"))
  H.write(root .. "/lua/demo/a.lua", { "local M = {}", "function M.a() end", "return M" })
  local function run(argv)
    local built_opts = config.build(root, { source = "lua", out_dir = "docs/map" })
    local real_out, real_err = io.stdout, io.stderr
    local out, err = {}, {}
    local function sink_to(list)
      return {
        write = function(self, ...)
          for _, part in ipairs({ ... }) do
            list[#list + 1] = tostring(part)
          end
          return self
        end,
      }
    end
    io.stdout, io.stderr = sink_to(out), sink_to(err)
    local ran, code = pcall(cli.run, built_opts, argv)
    io.stdout, io.stderr = real_out, real_err
    ok(ran, "cli.run did not raise: " .. tostring(code))
    return code, table.concat(out), table.concat(err)
  end

  local code, out = run({ "--report=quicks,findings", "--json" })
  ok(code == 0, "--report exits 0, the report is the answer")
  local decoded, doc = pcall(vim.json.decode, out)
  ok(decoded and type(doc) == "table", "--json prints one JSON object")
  ok(doc.quicks and doc.findings and not doc.duplicates, "only the asked sections are in it")
  ok(doc.repo == root:match("([^/]+)$"), "the repository is the folder name")
  ok(vim.fn.isdirectory(root .. "/docs") == 0, "--report writes nothing")

  local text_code, text_out = run({ "--report" })
  ok(text_code == 0 and text_out:find("Duplicates:", 1, true), "plain --report prints text")

  local bad_code, _, bad_err = run({ "--report=nope" })
  ok(bad_code == 2, "an unknown section is a refusal (exit 2)")
  ok(bad_err:find("nope", 1, true), "the refusal names the section")

  vim.fn.delete(root, "rf")
end
