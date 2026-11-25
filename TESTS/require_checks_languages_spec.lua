-- Test code: when something here comes back nil, this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/require_checks_languages_spec.lua — `require-cycle` and `require-not-declared` over what a language
-- does not order or does not share:
--   * a Rust parent beside its `mod child;` and the child's `use super::…` is the normal module tree;
--   * a TypeScript `import type` is erased at compile time;
--   * a file under `lua/telescope/_extensions/` plugs into Telescope's namespace, it does not own it;
--   * a Kotlin package `io.x` says nothing about what a Python `import io` means.
-- A loop of ordinary Lua requires must still be reported, in the same run, or the checks above would pass
-- on a check that reports nothing at all.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("docmap.core.scan")
  local check = require("docmap.core.check")

  local function has(lang)
    return (pcall(vim.treesitter.language.add, lang))
  end

  ---@param files table<string, string[]>
  ---@return string root
  local function tree(files)
    local root = vim.fn.tempname()
    for rel, lines in pairs(files) do
      vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
      local fh = assert(io.open(root .. "/" .. rel, "w"))
      fh:write(table.concat(lines, "\n") .. "\n")
      fh:close()
    end
    return root
  end

  ---@param root string
  ---@param opts table
  ---@param name string
  ---@return table[]
  local function findings_of(root, opts, name)
    opts = vim.tbl_extend("force", { root = root }, opts)
    local out = {}
    for _, f in ipairs(check.run(scan.scan(opts), opts)) do
      if f.check == name then
        out[#out + 1] = f
      end
    end
    return out
  end

  -- A real load-time loop stays a finding.
  local lua_loop = tree({
    ["lua/loop/a.lua"] = {
      "---@module 'loop.a'",
      'local b = require("loop.b")',
      "return { b = b }",
    },
    ["lua/loop/b.lua"] = {
      "---@module 'loop.b'",
      'local a = require("loop.a")',
      "return { a = a }",
    },
  })
  ok(
    #findings_of(lua_loop, { source = "lua/loop", lua_root = "lua" }, "require-cycle") > 0,
    "a loop of plain Lua requires is still a cycle"
  )

  -- Rust.
  if has("rust") then
    local rust = tree({
      ["src/lib.rs"] = { "mod child;", "pub struct Thing;" },
      ["src/child.rs"] = { "use super::Thing;", "pub fn f() -> Option<Thing> { None }" },
    })
    eq(
      #findings_of(rust, { source = "src" }, "require-cycle"),
      0,
      "a Rust parent's `mod child;` and the child's `use super::` are no cycle"
    )
  else
    print("n/a  require checks: rust parser not installed")
  end

  -- TypeScript.
  if has("typescript") then
    local function ts(kind)
      return tree({
        ["src/a.ts"] = {
          ("import %s { B } from './b';"):format(kind),
          "export interface A { b: B }",
        },
        ["src/b.ts"] = {
          ("import %s { A } from './a';"):format(kind),
          "export interface B { a: A }",
        },
      })
    end
    eq(
      #findings_of(ts("type"), { source = "src" }, "require-cycle"),
      0,
      "two files importing each other's types only are no cycle"
    )
    ok(
      #findings_of(ts(""), { source = "src" }, "require-cycle") > 0,
      "the same two files with a value import are one"
    )
  else
    print("n/a  require checks: typescript parser not installed")
  end

  -- A Telescope extension.
  local ext = tree({
    ["lua/demo/init.lua"] = { "---@module 'demo'", "return {}" },
    ["lua/telescope/_extensions/demo.lua"] = {
      "---@module 'telescope._extensions.demo'",
      'local pickers = require("telescope.pickers")',
      'local gone = require("demo.nowhere")',
      "return { pickers, gone }",
    },
  })
  local rnd = findings_of(ext, { source = "lua", lua_root = "lua" }, "require-not-declared")
  eq(#rnd, 1, "only the miss inside the tree's own namespace is reported, not Telescope's")
  ok(
    rnd[1] and rnd[1].params.module == "demo.nowhere",
    "the one reported is the typo of the tree's own module"
  )

  -- A Kotlin package against a Python import.
  if has("python") and has("kotlin") then
    local mixed = tree({
      ["android/io/app/Main.kt"] = { "package io.app", "class Main" },
      ["tools/check.py"] = { "import io", "print(io)" },
    })
    eq(
      #findings_of(mixed, { source = { "android", "tools" } }, "require-not-declared"),
      0,
      "`import io` in Python is not a miss against a Kotlin package `io`"
    )
  else
    print("n/a  require checks: python or kotlin parser not installed")
  end
end
