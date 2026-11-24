---@module 'docmap.core.report'
--- The analysis tabs as a report: what the Duplicates, Quicks and Findings tabs show, for one repository, as text or
--- as JSON, without writing anything. `--report` of `core/cli.lua` calls it, so a person can ask the same questions of
--- every repository they own with one loop (`docs/pipeline.md`, "Reporting from the command line").
---
--- Pure: an IR and its findings in, a table out. The sentences of the Quicks tab are not here, they are the page's
--- (the artifact keeps the numbers only, schema 5); the report prints the id, the polarity and the measured value of
--- each verdict, which is what a loop over many repositories sorts and compares.

local M = {}

---The sections of a report, in the order they are printed.
---@type string[]
M.SECTIONS = { "duplicates", "quicks", "findings" }

---Read `--report=<a,b>`: the sections asked for, or all of them when none is named.
---@param spec string? The part after `=`; `nil` or empty means all.
---@return string[]? sections
---@return string? err The unknown name, when there is one.
function M.parse_sections(spec)
  if not spec or spec == "" then
    return vim.deepcopy(M.SECTIONS)
  end
  local known = {}
  for _, name in ipairs(M.SECTIONS) do
    known[name] = true
  end
  local seen = {}
  for name in spec:gmatch("[^,]+") do
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      if not known[trimmed] then
        return nil, trimmed
      end
      seen[trimmed] = true
    end
  end
  -- Printed in the fixed order, whatever order they were asked in: two runs over two repositories line up.
  local ordered = {}
  for _, name in ipairs(M.SECTIONS) do
    if seen[name] then
      ordered[#ordered + 1] = name
    end
  end
  return ordered, nil
end

---@param ir Docmap.IR
---@return table
local function duplicates_of(ir)
  local d = ir.duplicates or { groups = {}, functions = 0, considered = 0, min_size = 0 }
  local groups = {}
  for _, g in ipairs(d.groups or {}) do
    local members = {}
    for _, m in ipairs(g.members or {}) do
      members[#members + 1] = {
        signature = m.signature,
        module = m.module,
        node = m.node,
        line = m.line,
      }
    end
    groups[#groups + 1] = { identical = #members, nodes = g.size, members = members }
  end
  return {
    groups = groups,
    functions = d.functions or 0,
    considered = d.considered or 0,
    min_size = d.min_size or 0,
  }
end

---@param ir Docmap.IR
---@return table
local function quicks_of(ir)
  local q = ir.quicks or { bad = {}, good = {}, total_bad = 0, total_good = 0 }
  local function rows(list)
    local out = {}
    for _, row in ipairs(list or {}) do
      out[#out + 1] = {
        id = row.id,
        tab = row.tab,
        value = row.value,
        unit = row.unit,
        weight = row.weight,
        distance = row.distance,
      }
    end
    return out
  end
  return {
    bad = rows(q.bad),
    good = rows(q.good),
    total_bad = q.total_bad or #(q.bad or {}),
    total_good = q.total_good or #(q.good or {}),
  }
end

---@param findings Docmap.Finding[]
---@return table
local function findings_of(findings)
  local fmt = require("docmap.core.findings")
  local i18n = require("docmap.core.i18n")
  local tally = { error = 0, warn = 0, info = 0 }
  local rows = {}
  for _, f in ipairs(findings or {}) do
    tally[f.severity] = (tally[f.severity] or 0) + 1
    rows[#rows + 1] = {
      severity = f.severity,
      check = f.check,
      node = f.node,
      -- The source locale, like every committed artifact: a JSON report compared between two runs must not depend
      -- on the `LANG` of the machine that wrote it.
      message = fmt.format(f, i18n.SOURCE),
    }
  end
  table.sort(rows, function(a, b)
    if a.check ~= b.check then
      return a.check < b.check
    end
    if (a.node or "") ~= (b.node or "") then
      return (a.node or "") < (b.node or "")
    end
    return a.message < b.message
  end)
  return { tally = tally, items = rows }
end

---Build the report of one repository.
---@param ir Docmap.IR
---@param findings Docmap.Finding[]
---@param sections string[] A subset of `M.SECTIONS`.
---@param repo string? The name to print for the repository (its folder name by default).
---@return table report
function M.build(ir, findings, sections, repo)
  local report = { repo = repo, title = ir.meta and ir.meta.title or nil }
  for _, name in ipairs(sections) do
    if name == "duplicates" then
      report.duplicates = duplicates_of(ir)
    elseif name == "quicks" then
      report.quicks = quicks_of(ir)
    elseif name == "findings" then
      report.findings = findings_of(findings)
    end
  end
  return report
end

---@param n integer
---@param word string
---@return string
local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

---The report as lines of text.
---@param report table From `M.build`.
---@return string[]
function M.render_text(report)
  local out = {}
  local function add(line)
    out[#out + 1] = line
  end
  add(("== %s =="):format(report.repo or report.title or "repository"))

  local d = report.duplicates
  if d then
    add("")
    add(
      ("Duplicates: %s covering %s (%d considered, floor %d nodes)"):format(
        plural(#d.groups, "group"),
        plural(d.functions, "function"),
        d.considered,
        d.min_size
      )
    )
    for _, g in ipairs(d.groups) do
      add(("  %d identical, %d nodes"):format(g.identical, g.nodes or 0))
      for _, m in ipairs(g.members) do
        add(
          ("    %s  %s:%s"):format(
            m.signature or "?",
            m.module or m.node or "?",
            tostring(m.line or "?")
          )
        )
      end
    end
  end

  local q = report.quicks
  if q then
    add("")
    add(("Quicks: %d bad, %d good"):format(q.total_bad, q.total_good))
    local function print_rows(label, rows)
      for _, r in ipairs(rows) do
        local value = r.value ~= nil and tostring(r.value) or "-"
        add(
          ("  %-4s %-28s %s%s  (tab %s, weight %s)"):format(
            label,
            r.id or "?",
            value,
            r.unit == "percent" and "%" or "",
            r.tab or "?",
            tostring(r.weight or "?")
          )
        )
      end
    end
    print_rows("bad", q.bad)
    print_rows("good", q.good)
  end

  local f = report.findings
  if f then
    add("")
    add(
      ("Findings: %d errors, %d warnings, %d info"):format(
        f.tally.error or 0,
        f.tally.warn or 0,
        f.tally.info or 0
      )
    )
    for _, row in ipairs(f.items) do
      -- Info is counted, not listed: a tree of a few thousand functions has thousands of them.
      if row.severity ~= "info" then
        add(("  [%s] %-22s %s"):format(row.severity, row.check, row.message))
      end
    end
  end
  return out
end

return M
