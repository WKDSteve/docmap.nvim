-- TESTS/fleet_cli_spec.lua — `docmap --fleet <root>...`: the report over many repositories from the engine binary.
--
-- `core/fleet.lua` `M.main` is what `standalone/docmap.lua --fleet` runs (the host `docmap-desktop report` calls
-- it). Its arguments, the built-in list of private repositories, the exit codes and the output are checked here
-- in the editor; the same call through the real entry point under a PUC Lua (with `lfs` and `dkjson`) runs below
-- when one is on PATH, else it prints an n/a line.

---A file-like sink for `M.main`.
---@return table sink
---@return fun(): string text
local function sink()
  local parts = {}
  return {
    write = function(_, s)
      parts[#parts + 1] = s
    end,
  }, function()
    return table.concat(parts)
  end
end

return function(H)
  local ok, eq = H.ok, H.eq
  local fleet = require("docmap.core.fleet")

  -- arguments
  local opts =
    fleet.parse_args({ "a", "--json", "--top=3", "--with-generated", "b", "--locale=de" })
  ok(opts ~= nil, "valid arguments parse")
  ok(opts and vim.deep_equal(opts.roots, { "a", "b" }), "roots in order, options anywhere")
  eq(opts and opts.json, true, "--json")
  eq(opts and opts.top, 3, "--top")
  eq(opts and opts.with_generated, true, "--with-generated")
  local defaults = fleet.parse_args({ "a" })
  eq(defaults and defaults.top, 25, "--top defaults to 25")
  eq(defaults and defaults.json, false, "Markdown by default")
  for _, bad in ipairs({ "--top=0", "--top=x", "--top=1.5", "--top=-2" }) do
    local none, err = fleet.parse_args({ "a", bad })
    ok(none == nil and tostring(err):find("--top", 1, true), bad .. " is refused")
  end
  local none, err = fleet.parse_args({ "a", "--dir=x" })
  ok(
    none == nil and tostring(err):find("unknown option --dir=x", 1, true),
    "an unknown option is refused"
  )
  none, err = fleet.parse_args({ "--json" })
  ok(none == nil and err == "no repository given", "no root is refused")

  -- the private list: the last folder, any case, never a parent folder
  eq(fleet.private_match("E:/repos/WKDBook-Tricentis"), "tricentis", "WKDBook-Tricentis is private")
  eq(
    fleet.private_match("E:\\repos\\tricentis-vault\\"),
    "tricentis",
    "backslashes and a trailing slash"
  )
  eq(fleet.private_match("/x/wkdbook"), "wkdbook", "wkdbook in lower case")
  eq(
    fleet.private_match("/home/tricentis/docmap.nvim"),
    nil,
    "a private parent folder does not count"
  )
  eq(fleet.private_match("docmap.nvim"), nil, "an ordinary name is not private")

  -- A function big enough (>= 40 tree nodes) to count; both repositories carry it under other names.
  local function body(name, local_a)
    return {
      "local M = {}",
      "",
      ("function M.%s(items)"):format(name),
      ("  local %s = {}"):format(local_a),
      "  for index, item in ipairs(items) do",
      "    if item ~= '' and #item > 2 then",
      ("      %s[#%s + 1] = { at = index, text = item:upper(), size = #item }"):format(
        local_a,
        local_a
      ),
      "    elseif item == '-' then",
      ("      %s[#%s + 1] = { at = index, text = item, size = 1 }"):format(local_a, local_a),
      "    end",
      "  end",
      ("  table.sort(%s, function(a, b)"):format(local_a),
      "    if a.size ~= b.size then",
      "      return a.size > b.size",
      "    end",
      "    return a.at < b.at",
      "  end)",
      ("  return %s"):format(local_a),
      "end",
      "",
      "return M",
    }
  end
  local base = (vim.fn.tempname():gsub("\\", "/"))
  local one, two = base .. "/one", base .. "/two"
  H.write(one .. "/lua/one/a.lua", body("collect", "found"))
  H.write(two .. "/lua/two/b.lua", body("gather", "hits"))

  -- main: Markdown, progress on err, exit 0
  local out, out_text = sink()
  local errs, err_text = sink()
  eq(fleet.main({ one, two, "--top=5" }, out, errs), 0, "two readable roots: exit 0")
  ok(out_text():find("# docmap across the repositories", 1, true), "the report goes to out")
  ok(out_text():find("one + two", 1, true), "it names the pair that shares the shape")
  ok(
    err_text():find("one: 1 functions above the floor", 1, true),
    "progress goes to err: " .. err_text()
  )
  ok(not out_text():find("functions above the floor", 1, true), "and not to out")

  -- main: JSON
  out, out_text = sink()
  errs = sink()
  eq(fleet.main({ "--json", one, two }, out, errs), 0, "--json: exit 0")
  local decoded_ok, decoded = pcall(vim.json.decode, out_text())
  ok(decoded_ok, "--json writes one JSON object")
  eq(decoded_ok and #decoded.shapes, 1, "one shared shape in the JSON")
  eq(decoded_ok and #decoded.failed, 0, "nothing failed")

  -- main: a root that is not there is reported and makes the exit code 1; the others are still in the report
  out, out_text = sink()
  errs = sink()
  eq(fleet.main({ one, base .. "/missing" }, out, errs), 1, "an unreadable root: exit 1")
  ok(
    out_text():find("Not scanned: " .. base .. "/missing (not a folder)", 1, true),
    "the report says which"
  )
  ok(out_text():find("| one |", 1, true), "the readable root is still reported")

  -- main: a named private root is read, with a warning
  local private = base .. "/WKDBook-x"
  H.write(private .. "/lua/p/a.lua", { "return {}" })
  out = sink()
  errs, err_text = sink()
  eq(fleet.main({ private }, out, errs), 0, "a named private root is read")
  ok(
    err_text():find("warning: " .. private .. " looks like a private repository", 1, true),
    "with a warning"
  )

  -- main: wrong arguments, exit 2 and the usage line on err, nothing on out
  out, out_text = sink()
  errs, err_text = sink()
  eq(fleet.main({}, out, errs), 2, "no root: exit 2")
  ok(err_text():find(fleet.USAGE, 1, true), "the usage line on err")
  eq(out_text(), "", "nothing on out")

  -- the real entry point under a PUC Lua
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local lua = dofile(root .. "/scripts/puc_lua.lua").find()
  if not lua then
    print(
      "n/a  no PUC Lua 5.3+ with lfs and dkjson on PATH (the --fleet run of standalone/docmap.lua)"
    )
  else
    local run = vim
      .system({ lua, root .. "/standalone/docmap.lua", "--fleet", one, two }, { cwd = root, text = true })
      :wait(120000)
    eq(run.code, 0, "standalone --fleet: exit 0 (" .. tostring(run.stderr) .. ")")
    ok(
      (run.stdout or ""):find("2 repositories;", 1, true),
      "standalone --fleet: the report on stdout (" .. tostring(run.stdout) .. ")"
    )
    ok(
      (run.stderr or ""):find("one: %d+ functions above the floor"),
      "standalone --fleet: progress on stderr"
    )
    local usage_run = vim
      .system({ lua, root .. "/standalone/docmap.lua", "--fleet" }, { cwd = root, text = true })
      :wait(60000)
    eq(usage_run.code, 2, "standalone --fleet without a root: exit 2")
    local caps_run = vim
      .system({ lua, root .. "/standalone/docmap.lua", "--capabilities" }, { cwd = root, text = true })
      :wait(60000)
    local caps_ok, caps = pcall(vim.json.decode, caps_run.stdout or "")
    ok(
      caps_ok and vim.tbl_contains(caps.capabilities or {}, "fleet"),
      "standalone --capabilities lists 'fleet' (" .. tostring(caps_run.stdout) .. ")"
    )
  end

  vim.fn.delete(base, "rf")
end
