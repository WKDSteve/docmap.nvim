-- Test code: a nil from a fixture read must crash and name itself.
---@diagnostic disable: need-check-nil
-- TESTS/lang_line_header_spec.lua — a leading `//` block is the summary in Rust, C and C++
--
-- The same rule as `lang_js_line_header_spec.lua`: the run starts the file, a blank line follows it, and it is no
-- pragma or license banner. Measured before: Rust `build.rs`/`main.rs` and every C++ file of a repository that
-- writes a plain `//` header reported `missing-summary`.

return function(H)
  local eq = H.eq
  local registry = require("docmap.core.lang_registry")
  local line_header = require("docmap.core.lang.line_header")

  eq(
    line_header.read("// One line.\n\nint x;\n"),
    "One line.",
    "line header: a block and a blank line"
  )
  eq(
    line_header.read("#!/usr/bin/env x\n\n// After shebang.\n\nfoo\n"),
    "After shebang.",
    "line header: after a shebang"
  )
  eq(
    line_header.read("// Touches.\nint x;\n"),
    nil,
    "line header: a block touching code documents the code"
  )
  eq(
    line_header.read("/// Doc of fn.\n\nfn x() {}\n"),
    nil,
    "line header: `///` is the language's own doc comment"
  )
  eq(
    line_header.read("// Copyright 2026 Someone\n\nint x;\n"),
    nil,
    "line header: a copyright banner says nothing"
  )
  eq(
    line_header.read("// The real summary.\n// Copyright 2026 Someone\n\nint x;\n"),
    "The real summary.",
    "line header: a banner line after the prose is dropped, the prose stays"
  )
  eq(
    line_header.read("#![deny(warnings)]\n// Not a header.\n\nfn x() {}\n"),
    nil,
    "line header: a Rust inner attribute is code, not a shebang to skip"
  )
  eq(
    line_header.read("// Only comment"),
    "Only comment",
    "line header: a block at the end of the file"
  )

  local function summary_of(lang, ext, lines)
    local backend = registry.get(lang)
    local path = H.tmpfile(ext)
    local fd = assert(io.open(path, "w"))
    fd:write(table.concat(lines, "\n") .. "\n")
    fd:close()
    local header = backend.parse_header(path)
    os.remove(path)
    return header.summary
  end

  local function has(lang)
    local ok_ts, loaded = pcall(vim.treesitter.language.add, lang == "cpp" and "cpp" or lang)
    return ok_ts and loaded
  end

  if has("rust") then
    eq(
      summary_of("rust", ".rs", { "// Build script: bundles the assets.", "", "fn main() {}" }),
      "Build script: bundles the assets.",
      "rust: a `//` block and a blank line is the summary"
    )
    eq(
      summary_of("rust", ".rs", { "// Build script.", "fn main() {}" }),
      "",
      "rust: a `//` block touching code is not"
    )
    eq(
      summary_of("rust", ".rs", { "//! Inner doc wins.", "", "// Not this.", "", "fn main() {}" }),
      "Inner doc wins.",
      "rust: `//!` still wins over a `//` block"
    )
  else
    print("n/a  line header rust: rust parser not installed")
  end

  if has("cpp") then
    eq(
      summary_of(
        "cpp",
        ".cpp",
        { "// Parses the request line.", "", '#include "a.h"', "", "int f() { return 1; }" }
      ),
      "Parses the request line.",
      "cpp: a `//` block before the includes is the summary"
    )
    eq(
      summary_of("cpp", ".cpp", { '#include "a.h"', "int f() { return 1; }" }),
      "",
      "cpp: no header, no summary"
    )
  else
    print("n/a  line header cpp: cpp parser not installed")
  end
end
