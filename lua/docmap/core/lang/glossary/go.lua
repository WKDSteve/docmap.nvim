---@module 'docmap.core.lang.glossary.go'
--- Go's keyword glossary for the in-snippet hover. Data, not code; see `glossary/lua.lua` for the rules every
--- glossary follows.
---
--- The entries that carry Go-specific meaning: receivers, `defer`, goroutines and channels, the blank identifier,
--- and the exported-by-capitalisation rule. Channel arrows (`<-`) and `:=` are symbols the word tokenizer cannot
--- see, so `chan`, `select` and `go` carry that explanation.

local M = {}

---@type Docmap.Glossary.Reference
M.reference = {
  label = "The Go Programming Language Specification",
  url = "https://go.dev/ref/spec",
}

---@type Docmap.Glossary.Syntax
M.syntax = {
  line_comment = "//",
  block_comment = { "/*", "*/" },
  strings = { { '"', '"' }, { "`", "`" }, { "'", "'" } },
  escape = "\\",
}

---@type table<string, Docmap.Glossary.Entry>
M.keywords = {
  -- Declarations
  ["package"] = {
    summary = "Names the package this file belongs to; every file of a directory has the same one.",
    note = "A name starting with a capital letter is exported from the package; lower-case names are private to it.",
  },
  ["import"] = {
    summary = "Makes another package's exported names available under the package name.",
  },
  ["func"] = {
    summary = "Declares a function. With a receiver before the name (`func (s *Server) Run()`) it is a method of that type.",
  },
  ["var"] = { summary = "Declares a variable, zero-valued unless initialised." },
  ["const"] = {
    summary = "Declares a constant; untyped constants take whatever numeric type the context needs.",
  },
  ["type"] = { summary = "Declares a new named type, or an alias with `=`." },
  ["struct"] = { summary = "A type made of named fields." },
  ["interface"] = {
    summary = "A set of method signatures. Any type that has those methods satisfies it, with no `implements`.",
    note = "`interface{}` (or `any`) is satisfied by every type.",
  },
  ["map"] = {
    summary = "A hash table from keys to values.",
    note = "Reading a missing key gives the zero value; use the two-value form `v, ok := m[k]` to tell. A nil map can be read but not written.",
  },
  ["chan"] = {
    summary = "A typed channel that goroutines use to pass values, written to and read with `<-`.",
    note = "An unbuffered channel makes the sender wait for a receiver.",
  },
  ["any"] = { summary = "An alias for `interface{}`: a value of any type." },
  ["nil"] = {
    summary = "The zero value of pointers, slices, maps, channels, functions and interfaces.",
  },
  ["iota"] = {
    summary = "In a `const` block, a counter that starts at 0 and increases on each line.",
  },

  -- Control flow
  ["if"] = {
    summary = "A conditional. It may start with a short statement: `if err := f(); err != nil {`.",
  },
  ["else"] = { summary = "The branch taken when the condition was false." },
  ["for"] = {
    summary = "Go's only loop: `for init; cond; post`, `for cond`, `for {}` and `for k, v := range x`.",
  },
  ["range"] = {
    summary = "Iterates a slice, array, string, map or channel, giving the index (or key) and the value.",
    note = "The loop variable is per iteration since Go 1.22; before that, closures captured one shared variable.",
  },
  ["switch"] = {
    summary = "Runs the first matching `case`. There is no fall-through unless a case says `fallthrough`.",
  },
  ["case"] = { summary = "One branch of a `switch` or `select`." },
  ["default"] = { summary = "The branch of a `switch` or `select` taken when no case matched." },
  ["fallthrough"] = {
    summary = "Continues into the next `case` of a `switch` instead of leaving it.",
  },
  ["break"] = { summary = "Leaves the innermost `for`, `switch` or `select`." },
  ["continue"] = { summary = "Skips to the next pass of the loop." },
  ["goto"] = { summary = "Jumps to a label in the same function." },
  ["return"] = { summary = "Returns from the function, with values or, for named results, bare." },

  -- Concurrency and cleanup
  ["go"] = {
    summary = "Starts a function call as a goroutine: it runs concurrently and the caller does not wait.",
    note = "The arguments are evaluated now, in the calling goroutine.",
  },
  ["select"] = {
    summary = "Waits on several channel operations and runs the case that is ready first.",
    note = "With a `default` case it never blocks.",
  },
  ["defer"] = {
    summary = "Schedules a call to run when the surrounding function returns, last deferred first.",
    note = "Arguments are evaluated at the `defer` statement, not when it runs. In a loop, deferred calls pile up until the function ends.",
  },

  -- Builtins and conventions
  ["make"] = {
    summary = "Creates a slice, map or channel: `make([]int, n)`, `make(map[K]V)`, `make(chan T, n)`.",
  },
  ["new"] = { summary = "Allocates a zero value of a type and returns a pointer to it." },
  ["len"] = { summary = "The length of a string, array, slice, map or channel." },
  ["cap"] = { summary = "The capacity of a slice, array or buffered channel." },
  ["append"] = {
    summary = "Adds elements to a slice and returns the result, which may be a new array.",
    note = "Always assign it back: `s = append(s, x)`.",
  },
  ["copy"] = { summary = "Copies elements from one slice to another, up to the shorter length." },
  ["delete"] = { summary = "Removes a key from a map; a missing key is not an error." },
  ["close"] = {
    summary = "Closes a channel: receivers drain it and then get zero values; sending on it panics.",
  },
  ["panic"] = { summary = "Stops normal execution and unwinds the stack, running deferred calls." },
  ["recover"] = {
    summary = "Stops a panic in progress and returns its value; only useful inside a deferred function.",
  },
  ["error"] = {
    summary = "The built-in interface for failures: one method, `Error() string`. `nil` means success.",
  },
  ["string"] = { summary = "An immutable sequence of bytes, usually UTF-8." },
  ["byte"] = { summary = "An alias for `uint8`." },
  ["rune"] = { summary = "An alias for `int32`: one Unicode code point." },
  ["_"] = {
    summary = "The blank identifier: discards a value or an import you only want the side effects of.",
  },
}

---@type table<string, Docmap.Glossary.Entry>
M.stdlib = {
  ["fmt.Println"] = { summary = "Prints its operands separated by spaces, with a newline." },
  ["fmt.Printf"] = {
    summary = "Prints according to a format string (`%v`, `%+v`, `%s`, `%d`, `%w`).",
  },
  ["fmt.Sprintf"] = { summary = "Like `Printf`, but returns the string." },
  ["fmt.Errorf"] = {
    summary = "Builds an error from a format string.",
    note = "`%w` wraps another error so `errors.Is` and `errors.As` can see through it.",
  },
  ["errors.New"] = { summary = "Creates a plain error from a message." },
  ["errors.Is"] = {
    summary = "Reports whether an error, or any error it wraps, equals the target.",
  },
  ["errors.As"] = { summary = "Finds the first error in the chain of a given type and assigns it." },
  ["context.Background"] = {
    summary = "The empty root context, for `main`, tests and top-level work.",
  },
  ["context.WithCancel"] = {
    summary = "Derives a context and a function that cancels it.",
    note = "Always call the cancel function.",
  },
  ["context.WithTimeout"] = { summary = "Derives a context that cancels itself after a duration." },
  ["os.Exit"] = { summary = "Ends the program immediately; deferred calls do not run." },
  ["os.Args"] = { summary = "The command line; element 0 is the program name." },
  ["os.ReadFile"] = { summary = "Reads a whole file into memory." },
  ["io.EOF"] = { summary = "The error a reader returns when there is no more input." },
  ["strings.Split"] = { summary = "Splits a string at every separator." },
  ["strings.Join"] = { summary = "Joins a slice of strings with a separator." },
  ["strings.Builder"] = {
    summary = "Builds a string with few allocations; write to it, then call `String()`.",
  },
  ["sync.WaitGroup"] = {
    summary = "Waits for a set of goroutines: `Add`, `Done` inside them, `Wait` in the caller.",
  },
  ["sync.Mutex"] = {
    summary = "A mutual-exclusion lock; `Lock` and `Unlock` guard shared data.",
    note = "Copying a mutex after first use is a bug.",
  },
  ["time.Now"] = { summary = "The current time." },
  ["time.Sleep"] = { summary = "Pauses the current goroutine for a duration." },
  ["time.Duration"] = {
    summary = "A length of time in nanoseconds; write it as `5 * time.Second`.",
  },
  ["json.Marshal"] = { summary = "Encodes a value as JSON; exported fields only." },
  ["json.Unmarshal"] = { summary = "Decodes JSON into a value that must be passed by pointer." },
  ["http.ListenAndServe"] = {
    summary = "Starts an HTTP server on an address; it returns only on an error.",
  },
  ["log.Fatal"] = { summary = "Logs the message and exits with status 1." },
  ["sort.Slice"] = { summary = "Sorts a slice with a `less(i, j)` function." },
  ["filepath.Join"] = { summary = "Joins path elements with the platform's separator." },
}

return M
