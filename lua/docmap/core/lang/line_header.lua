---@module 'docmap.core.lang.line_header'
--- The prose of a leading run of `//` line comments, read as a file header.
---
--- Rust, C and C++ have a stricter file-level convention (`//!`, `@file`), and the repositories mostly do not use
--- it: they open a file with a plain `//` block. The same rule the JavaScript backend applies: the run starts the
--- file (after a shebang and blank lines), is followed by a blank line or the end of the file, and is not a
--- pragma or a license banner. A run that touches the next line documents that line, not the file.
---
--- Text, not a syntax tree: the shape is the same in every `//` language and needs no grammar.

local M = {}

---A line that is not prose about the file: a tool pragma, a license or a copyright banner.
---@param line string
---@return boolean
local function is_pragma_line(line)
  return line:match("^SPDX") ~= nil
    or line:match("^[Cc]opyright") ~= nil
    or line:match("^%(c%)") ~= nil
    or line:match("^[Ll]icen[sc]e") ~= nil
    or line:match("^clang%-format") ~= nil
    or line:match("^NOLINT") ~= nil
    or line:match("^%-%*%-") ~= nil
end

---@param src string
---@return string|nil prose Comment lines joined with newlines, `//` stripped.
function M.read(src)
  local lines = {}
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  local i = 1
  if lines[i] and lines[i]:match("^#!%s*/") then
    i = i + 1
  end
  while lines[i] and lines[i]:match("^%s*$") do
    i = i + 1
  end
  local prose = {}
  while lines[i] do
    local body = lines[i]:match("^//+(.*)$")
    -- `///` and `//!` are doc comments of the language, read by its own rules.
    if not body or lines[i]:match("^///") or lines[i]:match("^//!") then
      break
    end
    prose[#prose + 1] = (body:gsub("^%s", ""):gsub("%s+$", ""))
    i = i + 1
  end
  if #prose == 0 then
    return nil
  end
  -- Followed by a blank line or the end of the file, not by the statement it documents.
  if lines[i] and not lines[i]:match("^%s*$") and lines[i] ~= "" then
    return nil
  end
  -- A REUSE `SPDX-License-Identifier` line opens the block by convention; the prose that follows it is the header.
  while prose[1] and prose[1]:match("^SPDX") do
    table.remove(prose, 1)
  end
  if #prose == 0 or is_pragma_line(prose[1]) then
    return nil
  end
  for k = #prose, 1, -1 do
    if is_pragma_line(prose[k]) then
      table.remove(prose, k)
    end
  end
  while prose[1] == "" do
    table.remove(prose, 1)
  end
  while prose[#prose] == "" do
    table.remove(prose)
  end
  if #prose == 0 then
    return nil
  end
  return table.concat(prose, "\n")
end

return M
