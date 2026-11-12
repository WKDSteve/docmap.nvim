---@module 'docmap.core.lang.glossary.c'
--- C's keyword glossary for the in-snippet hover. Data, not code; see `glossary/lua.lua` for the rules every
--- glossary follows.
---
--- Claimed by `.c` and `.h` only: C++ has its own backend and its own keywords, and a `const` or `static` that means
--- something else there must not be explained with C's answer (a missing decoration is the honest degradation).
--- Keywords plus the library functions a reader meets constantly and cannot guess the contract of (`malloc`,
--- `free`, `strncpy`, `memcpy`, `printf`). Preprocessor directives start with `#`, which the word tokenizer does
--- not see; `define`, `ifdef`, `ifndef` and `include` are explained as the words after it.

local M = {}

---@type Docmap.Glossary.Reference
M.reference = {
  label = "cppreference: C language",
  url = "https://en.cppreference.com/w/c/",
}

---@type Docmap.Glossary.Syntax
M.syntax = {
  line_comment = "//",
  block_comment = { "/*", "*/" },
  strings = { { '"', '"' }, { "'", "'" } },
  escape = "\\",
}

---@type table<string, Docmap.Glossary.Entry>
M.keywords = {
  -- Storage and qualifiers
  ["static"] = {
    summary = "At file scope: the name is private to this file. Inside a function: the variable keeps its value between calls.",
    note = "Two unrelated meanings under one word.",
  },
  ["extern"] = {
    summary = "Declares a name that is defined in another file, without defining it here.",
  },
  ["const"] = {
    summary = "The value cannot be changed through this name.",
    note = "Placement matters in pointers: `const char *p` is a pointer to constant data, `char *const p` is a constant pointer.",
  },
  ["volatile"] = {
    summary = "Every access really happens: the compiler may not cache or drop it (hardware registers, signal handlers).",
    note = "It does not make an access atomic or ordered between threads.",
  },
  ["register"] = {
    summary = "A hint to keep the variable in a register; modern compilers ignore it, and you cannot take its address.",
  },
  ["restrict"] = {
    summary = "A promise that this pointer is the only way to reach that object, which lets the compiler optimise.",
  },
  ["inline"] = { summary = "A hint to expand the function at the call site." },
  ["auto"] = {
    summary = "The default storage class of a local variable (C23 also uses it for type inference).",
  },

  -- Types
  ["struct"] = {
    summary = "A type made of named members laid out in order, possibly with padding.",
  },
  ["union"] = {
    summary = "A type whose members share the same memory; only the one last written is valid to read.",
  },
  ["enum"] = { summary = "A set of named integer constants." },
  ["typedef"] = { summary = "Gives a type another name; it creates no new type." },
  ["sizeof"] = {
    summary = "The size in bytes of a type or an expression, as a compile-time constant (except for a variable-length array).",
    note = "On a function parameter declared as an array, it is the size of a pointer.",
  },
  ["void"] = {
    summary = "No value: a function that returns nothing, or with `*` a pointer to data of unknown type.",
  },
  ["char"] = {
    summary = "The smallest addressable unit, one byte. Whether it is signed is up to the platform.",
  },
  ["short"] = { summary = "An integer at least 16 bits wide." },
  ["int"] = { summary = "The natural integer of the platform, at least 16 bits." },
  ["long"] = {
    summary = "An integer at least 32 bits wide (64 on most Unix platforms, 32 on Windows).",
  },
  ["unsigned"] = {
    summary = "Integer without a sign: arithmetic wraps around instead of being undefined on overflow.",
  },
  ["signed"] = { summary = "Integer with a sign; overflowing it is undefined behaviour." },
  ["float"] = { summary = "A single-precision floating-point number." },
  ["double"] = { summary = "A double-precision floating-point number." },
  ["size_t"] = {
    summary = "The unsigned integer type of object sizes and array indices, the result of `sizeof`.",
  },
  ["NULL"] = { summary = "The null pointer constant: a pointer that points at nothing." },
  ["bool"] = { summary = "Boolean type (`<stdbool.h>`, or a keyword since C23)." },

  -- Control flow
  ["if"] = { summary = "A conditional; zero is false and anything else is true." },
  ["else"] = { summary = "The branch taken when the condition was false." },
  ["for"] = { summary = "A loop with an initialiser, a condition and a step." },
  ["while"] = { summary = "Loops while the condition holds, tested before each pass." },
  ["do"] = {
    summary = "Starts a `do ... while` loop, whose body always runs once before the test.",
  },
  ["switch"] = { summary = "Jumps to the `case` matching an integer value." },
  ["case"] = {
    summary = "One label of a `switch`.",
    note = "Execution falls through into the next case unless a `break` stops it.",
  },
  ["default"] = { summary = "The label a `switch` jumps to when no `case` matched." },
  ["break"] = { summary = "Leaves the innermost loop or `switch`." },
  ["continue"] = { summary = "Skips to the next pass of the innermost loop." },
  ["goto"] = {
    summary = "Jumps to a label in the same function; the usual idiom is a single cleanup label at the end.",
  },
  ["return"] = { summary = "Returns from the function, with a value unless it is `void`." },

  -- Preprocessor (the word after `#`)
  ["include"] = {
    summary = 'Pastes another file in at this point; `<...>` searches system paths, `"..."` the project first.',
  },
  ["define"] = {
    summary = "Defines a macro: textual replacement before the compiler sees the code.",
    note = "Parenthesise every parameter and the whole body, and beware a parameter that is used twice and has side effects.",
  },
  ["ifdef"] = { summary = "Keeps the following code only if the macro is defined." },
  ["ifndef"] = {
    summary = "Keeps the following code only if the macro is not defined; the opening line of an include guard.",
  },
  ["endif"] = { summary = "Ends a conditional-compilation block." },
  ["pragma"] = {
    summary = "A compiler-specific instruction; `#pragma once` is the common include guard.",
  },

  -- Library functions with a contract worth knowing
  ["malloc"] = {
    summary = "Allocates the given number of bytes, uninitialised, and returns a pointer or NULL.",
    note = "Check for NULL, and `free` it exactly once.",
  },
  ["calloc"] = {
    summary = "Allocates and zeroes an array of `n` elements; checks the multiplication for overflow.",
  },
  ["realloc"] = {
    summary = "Resizes an allocation, possibly moving it, and returns the new pointer.",
    note = "On failure it returns NULL and leaves the old block alone, so do not assign it back to the only pointer.",
  },
  ["free"] = {
    summary = "Releases memory from `malloc`, `calloc` or `realloc`. Freeing it twice, or a pointer from elsewhere, is undefined.",
  },
  ["memcpy"] = {
    summary = "Copies bytes between non-overlapping areas; for overlapping ones use `memmove`.",
  },
  ["memmove"] = { summary = "Copies bytes between areas that may overlap." },
  ["memset"] = { summary = "Fills memory with a byte value." },
  ["strlen"] = {
    summary = "The length of a NUL-terminated string, not counting the terminator; it scans the whole string.",
  },
  ["strcpy"] = {
    summary = "Copies a string including its terminator, with no bounds check: a classic buffer overflow.",
  },
  ["strncpy"] = {
    summary = "Copies at most `n` bytes of a string.",
    note = "It does not NUL-terminate when the source is `n` bytes or longer, and it pads with zeros when shorter.",
  },
  ["strcmp"] = {
    summary = "Compares two strings; returns zero when they are equal, negative or positive otherwise.",
  },
  ["printf"] = {
    summary = "Prints formatted text to standard output; the format string must match the argument types.",
  },
  ["snprintf"] = {
    summary = "Formats into a buffer of a given size and always terminates it; returns the length it wanted.",
  },
  ["fopen"] = {
    summary = "Opens a file and returns a `FILE *`, or NULL on failure (check `errno`).",
  },
  ["fclose"] = { summary = "Closes a `FILE *`, flushing what is buffered." },
  ["assert"] = {
    summary = "Aborts with a message when the condition is false; compiled out when `NDEBUG` is defined.",
  },
}

return M
