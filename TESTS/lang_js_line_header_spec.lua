-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read -- this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/lang_js_line_header_spec.lua — a leading `//` comment is the file's summary
--
-- Most JS/TS repositories of this fleet open a file with a `//` block (never
-- `/** */`), so `missing-summary` fired for ~650 files that did have one.
-- A run of `//` lines counts as the file header when a blank line follows it;
-- one that touches the next statement documents that statement, and a pragma
-- or license banner says nothing about the file.

return function(H)
  local eq = H.eq

  local ok_js, has_js = pcall(vim.treesitter.language.add, "javascript")
  if not (ok_js and has_js) then
    print("n/a  lang.js line header: javascript parser not installed")
    return
  end

  local backend = require("docmap.core.lang_registry").get("js")

  ---@param lines string[]
  ---@return string summary
  local function summary_of(lines)
    local path = H.tmpfile(".js")
    local fd = assert(io.open(path, "w"))
    fd:write(table.concat(lines, "\n") .. "\n")
    fd:close()
    local header = backend.parse_header(path)
    os.remove(path)
    return header.summary
  end

  eq(
    summary_of({
      "// The acceptance view: one list of the open live checks.",
      "// A second line of detail.",
      "",
      "import { x } from './x';",
    }),
    "The acceptance view: one list of the open live checks.",
    "a `//` block followed by a blank line is the file summary"
  )

  eq(
    summary_of({
      "// Adds two numbers.",
      "export function add(a, b) { return a + b; }",
    }),
    "",
    "a `//` block touching the next statement documents that statement"
  )

  eq(
    summary_of({
      "// @ts-nocheck",
      "",
      "export const x = 1;",
    }),
    "",
    "a tool pragma is not a summary"
  )

  eq(
    summary_of({
      "// Copyright (c) 2026 Somebody.",
      "// Licensed under the MIT License.",
      "",
      "export const x = 1;",
    }),
    "",
    "a license banner is not a summary"
  )

  eq(
    summary_of({
      "/** The JSDoc wins. */",
      "",
      "// not this",
      "",
      "export const x = 1;",
    }),
    "The JSDoc wins.",
    "a JSDoc header is unchanged"
  )
end
