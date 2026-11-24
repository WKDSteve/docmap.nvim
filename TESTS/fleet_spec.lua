-- TESTS/fleet_spec.lua — the tabs over many repositories, and what two of them share.

return function(H)
  local ok = H.ok
  local fleet = require("docmap.core.fleet")

  -- Built output is recognised by its path, source folders are not.
  ok(
    fleet.is_generated("ui/dist-web/assets/index.web-CdijYthr.js"),
    "a dist-* folder is built output"
  )
  ok(fleet.is_generated("./ui/dist/app.js"), "a leading ./ does not hide it")
  ok(fleet.is_generated("node_modules/x/y.js"), "node_modules is built output")
  ok(fleet.is_generated("static/app.min.js"), "a minified file is built output")
  ok(not fleet.is_generated("lua/demo/a.lua"), "a source file is not")
  ok(not fleet.is_generated("src/distance.lua"), "a name that merely starts with dist is not")

  -- A function big enough (>= 40 tree nodes) to count; both repositories carry it under other names.
  local function body(name, local_a)
    return {
      "local M = {}",
      "",
      "---@param items string[]",
      "---@return table",
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
  local one, two, three = base .. "/one", base .. "/two", base .. "/three"
  H.write(one .. "/lua/one/a.lua", body("collect", "found"))
  H.write(two .. "/lua/two/b.lua", body("gather", "hits"))
  -- a function only this repository has (above the floor, another shape): it must not show up as shared
  H.write(three .. "/lua/three/c.lua", {
    "local M = {}",
    "",
    "function M.only_here(a, b, c)",
    "  local total = 0",
    "  while a < b do",
    "    total = total + (a % 2 == 0 and a * c or a - c)",
    "    a = a + 1",
    "  end",
    "  repeat",
    "    total = total - 1",
    "  until total < 0 or c == nil",
    "  if total > 100 then",
    "    return { total, a, b, c, tostring(total), #tostring(a) }",
    "  end",
    "  return total",
    "end",
    "",
    "return M",
  })
  -- built output with the same function: must not count
  H.write(two .. "/dist/bundle.js", { "function a(){}" })

  local repos, failed = fleet.scan_roots({ one, two, three, base .. "/missing" })
  ok(#repos == 3, "three repositories scanned, got " .. #repos)
  ok(#failed == 0 or #failed == 1, "a root that is not there is reported, not fatal")

  local joined = fleet.join(repos)
  ok(#joined.shapes == 1, "one shape is in two repositories, got " .. #joined.shapes)
  local g = joined.shapes[1]
  ok(
    g and #g.repos == 2 and g.repos[1] == "one" and g.repos[2] == "two",
    "it names both repositories"
  )
  ok(g and g.size >= 40, "the shape is above the floor")
  ok(g and #g.members == 2, "two members, one per repository")
  ok(#joined.pairs == 1 and joined.pairs[1].pair == "one + two", "the pair is listed")
  ok(#joined.repos == 3, "every scanned repository has a row")

  local lines = table.concat(fleet.render(joined), "\n")
  ok(lines:find("1 shapes appear in at least two", 1, true), "the text counts the shared shapes")
  ok(lines:find("one + two", 1, true), "the text names the pair")
  ok(lines:find("one:[%w_./]+:%d+"), "the text names a place (repo:module:line)")
  ok(lines:find("two:[%w_./]+:%d+"), "and the place in the other repository")

  -- Nothing is written into a scanned repository.
  ok(vim.fn.isdirectory(one .. "/docs") == 0, "scanning writes nothing into the repository")

  -- Built output is dropped and said: the same shape under `dist/` is not a third repository.
  -- (`dist-web`, not `dist`: the scan already skips a folder called exactly `dist`)
  H.write(three .. "/lua/three/dist-web/gen.lua", body("generated", "made"))
  local again = fleet.scan_roots({ one, two, three })
  local joined_again = fleet.join(again)
  ok(
    #joined_again.shapes == 1 and #joined_again.shapes[1].repos == 2,
    "built output does not join the shape"
  )
  local kept = fleet.scan_roots({ three }, { with_generated = true })
  ok(
    #kept[1].shapes == 2 and kept[1].dropped == 0,
    ("with_generated keeps it (shapes %d, dropped %d)"):format(#kept[1].shapes, kept[1].dropped)
  )
  local dropped = fleet.scan_roots({ three })
  ok(
    #dropped[1].shapes == 1 and dropped[1].dropped == 1,
    ("by default it is dropped and counted (shapes %d, dropped %d)"):format(
      #dropped[1].shapes,
      dropped[1].dropped
    )
  )

  vim.fn.delete(base, "rf")
end
