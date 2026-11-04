-- TESTS/map_merge_spec.lua — a pull in a shared checkout, with only the generated map dirty.
--
-- CI commits the regenerated map on main, and a session regenerates the same files in the shared
-- working tree. `git pull --rebase --autostash` then exits 0 and leaves conflict markers in the map and
-- the autostash behind. `merge=ours` in `.gitattributes` keeps the upstream map instead: it is generated,
-- so nothing is lost. Played through with this repository's real `.gitattributes`.

return function(H)
  local eq, ok = H.eq, H.ok
  local MAP = { "docs/map/index.html", "docs/map/module_map.json", "docs/map/overview.md" }

  local attributes = assert(io.open(".gitattributes", "rb"))
  local attributes_text = attributes:read("*a")
  attributes:close()

  local base = vim.fn.tempname()
  vim.fn.mkdir(base, "p")

  ---@param cwd string
  ---@param args string[]
  ---@return string stdout
  ---@return integer code
  local function git(cwd, args)
    local cmd = {
      "git",
      "-c",
      "user.name=t",
      "-c",
      "user.email=t@example.invalid",
      "-c",
      "commit.gpgsign=false",
      -- the machine's global hooks are not part of this
      "-c",
      "core.hooksPath=" .. base .. "/no-hooks",
      "-c",
      "merge.ours.driver=true",
    }
    vim.list_extend(cmd, args)
    local done = vim.system(cmd, { cwd = cwd, text = true }):wait(30000)
    return (done.stdout or "") .. (done.stderr or ""), done.code
  end

  local function must(cwd, args)
    local out, code = git(cwd, args)
    eq(code, 0, table.concat(args, " ") .. ": " .. out)
    return out
  end

  ---@param path string
  ---@param text string
  local function write(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
  end

  ---@param path string
  ---@return string
  local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local up, bot, session = base .. "/up.git", base .. "/bot", base .. "/session"
  must(base, { "init", "-q", "--bare", "-b", "main", up })
  must(base, { "clone", "-q", up, bot })
  must(bot, { "checkout", "-q", "-b", "main" })
  write(bot .. "/.gitattributes", attributes_text)
  write(bot .. "/lua/x.lua", "code\n")
  for _, rel in ipairs(MAP) do
    write(bot .. "/" .. rel, "map v1\n")
  end
  must(bot, { "add", "-A" })
  must(bot, { "commit", "-q", "-m", "base" })
  must(bot, { "push", "-q", "origin", "HEAD:main" })
  must(base, { "clone", "-q", "-b", "main", up, session })

  for _, rel in ipairs(MAP) do
    eq(
      vim.trim(must(session, { "check-attr", "merge", "--", rel })),
      rel .. ": merge: ours",
      "the map is merged as generated"
    )
    write(bot .. "/" .. rel, "map v2 from the bot\n")
    write(session .. "/" .. rel, "map v2 from a session\n")
  end
  must(bot, { "add", "-A" })
  must(bot, { "commit", "-q", "-m", "docs(map): regenerate" })
  must(bot, { "push", "-q", "origin", "HEAD:main" })

  must(session, { "pull", "-q", "--rebase", "--autostash", "origin", "main" })
  for _, rel in ipairs(MAP) do
    eq(read(session .. "/" .. rel), "map v2 from the bot\n", "the map of upstream stays: " .. rel)
  end
  eq(must(session, { "status", "--short" }), "", "nothing is left over: no conflict")
  eq(must(session, { "stash", "list" }), "", "and no stash")

  -- What is not generated still goes through a real merge: only the map gives way.
  write(session .. "/lua/x.lua", "code\nown work\n")
  write(session .. "/" .. MAP[1], "map v3 from a session\n")
  write(bot .. "/lua/y.lua", "theirs\n")
  write(bot .. "/" .. MAP[1], "map v3 from the bot\n")
  must(bot, { "add", "-A" })
  must(bot, { "commit", "-q", "-m", "more" })
  must(bot, { "push", "-q", "origin", "HEAD:main" })
  must(session, { "pull", "-q", "--rebase", "--autostash", "origin", "main" })
  eq(read(session .. "/lua/x.lua"), "code\nown work\n", "own work stays")
  ok(
    must(session, { "status", "--short" }):find("lua/x.lua", 1, true) ~= nil,
    "as a change of the working tree"
  )
  eq(must(session, { "stash", "list" }), "", "with no stash")

  vim.fn.delete(base, "rf")
end
