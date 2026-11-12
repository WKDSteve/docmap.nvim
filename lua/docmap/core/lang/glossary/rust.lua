---@module 'docmap.core.lang.glossary.rust'
--- Rust's keyword glossary for the in-snippet hover. Data, not code; see `glossary/lua.lua` for the rules every
--- glossary follows.
---
--- Keywords and the prelude names a reader actually meets (`Option`, `Result`, `Vec`, `Box`...). There is no
--- `stdlib` table: Rust paths are written with `::` (`std::fs::read`), and the page's tokenizer matches dotted runs,
--- so a `std::...` key could never match anything it produces. The `?` operator, lifetimes (`'a`) and `&mut` are
--- symbols the word tokenizer cannot see, so their words (`mut`, `ref`, `dyn`, `unsafe`) carry the explanation.

local M = {}

---@type Docmap.Glossary.Reference
M.reference = {
  label = "The Rust Reference",
  url = "https://doc.rust-lang.org/reference/",
}

---@type Docmap.Glossary.Syntax
M.syntax = {
  line_comment = "//",
  block_comment = { "/*", "*/" },
  strings = { { '"', '"' } },
  escape = "\\",
}

---@type table<string, Docmap.Glossary.Entry>
M.keywords = {
  -- Items
  ["fn"] = { summary = "Defines a function." },
  ["struct"] = {
    summary = "Defines a record type with named fields, a tuple struct or a unit struct.",
  },
  ["enum"] = {
    summary = "Defines a type that is exactly one of several variants, each of which can carry data.",
  },
  ["trait"] = {
    summary = "Defines a set of methods a type can promise to provide; the closest thing to an interface.",
  },
  ["impl"] = {
    summary = "Gives a type its methods (`impl Type`) or implements a trait for it (`impl Trait for Type`).",
    note = 'In an argument or return position, `impl Trait` means "some type that implements it", chosen at compile time.',
  },
  ["type"] = { summary = "Declares a type alias, or an associated type inside a trait." },
  ["mod"] = {
    summary = "Declares a module: a namespace, and with `mod name;` a file or folder of its own.",
  },
  ["use"] = { summary = "Brings a path into scope so it can be named without its prefix." },
  ["pub"] = {
    summary = "Makes an item visible outside its module; `pub(crate)` limits that to this crate.",
    note = "Everything is private to its module by default.",
  },
  ["const"] = {
    summary = "A compile-time constant, inlined at every use; also `const fn` for a function usable in constants.",
  },
  ["static"] = {
    summary = "A single value with a fixed address for the whole program.",
    note = "A `static mut` can only be touched inside `unsafe`.",
  },
  ["crate"] = { summary = "The root of the current crate in a path (`crate::module::item`)." },
  ["super"] = { summary = "The parent module in a path." },
  ["self"] = {
    summary = "The current module in a path, or the receiver of a method (`&self`, `&mut self`, `self`).",
  },
  ["Self"] = { summary = "The type being implemented, inside an `impl` or a trait." },
  ["where"] = {
    summary = "Puts the bounds on generic parameters after the signature, where they stay readable.",
  },
  ["extern"] = {
    summary = 'Links to code in another language (`extern "C"`) or declares an external crate.',
  },
  ["macro_rules"] = {
    summary = "Defines a declarative macro by pattern matching on its input tokens.",
  },

  -- Bindings and ownership
  ["let"] = {
    summary = "Binds a name to a value. Bindings are immutable unless declared `mut`.",
    note = "A later `let` with the same name shadows the first; it is a new variable, not an assignment.",
  },
  ["mut"] = { summary = "Makes a binding or a reference mutable: `let mut x`, `&mut T`." },
  ["ref"] = { summary = "In a pattern, binds by reference instead of moving the value out." },
  ["move"] = {
    summary = "Makes a closure take ownership of the variables it uses instead of borrowing them.",
    note = "Needed when the closure must outlive the function, e.g. for a thread.",
  },
  ["unsafe"] = {
    summary = "Opens a block, function or trait where the compiler trusts you with raw pointers, FFI and other things it cannot check.",
    note = "It does not turn the checks off for everything else; it only allows five specific operations.",
  },
  ["dyn"] = {
    summary = "Marks a trait object: a value called through a vtable at run time (`Box<dyn Trait>`).",
  },
  ["as"] = {
    summary = "A primitive cast (`x as u8`, which truncates silently), or a rename in a `use`.",
  },

  -- Control flow
  ["if"] = { summary = "A conditional that is also an expression: both branches give a value." },
  ["else"] = { summary = "The branch taken when the condition was false." },
  ["match"] = {
    summary = "Compares a value against patterns and runs the first that fits.",
    note = "Must be exhaustive; the compiler rejects a match that leaves a case out.",
  },
  ["for"] = {
    summary = "Loops over an iterator (`for x in items`); in `impl Trait for Type` it names the implementing type.",
  },
  ["while"] = { summary = "Loops while the condition holds." },
  ["loop"] = {
    summary = "An endless loop; `break value` leaves it and gives the value of the `loop` expression.",
  },
  ["break"] = { summary = "Leaves the innermost loop, or a labelled one (`break 'outer`)." },
  ["continue"] = { summary = "Skips to the next pass of the loop." },
  ["return"] = {
    summary = "Returns early from a function. The last expression, without a semicolon, is the normal return.",
  },
  ["in"] = { summary = "Separates the pattern from the iterator in a `for` loop." },
  ["async"] = {
    summary = "Makes a function or block return a future that does nothing until it is polled.",
  },
  ["await"] = {
    summary = "Suspends an async function until the future is ready, then continues with its value.",
  },

  -- Values and prelude types
  ["true"] = { summary = "The boolean true." },
  ["false"] = { summary = "The boolean false." },
  ["Some"] = { summary = "The variant of `Option` that holds a value." },
  ["None"] = {
    summary = "The variant of `Option` that holds nothing. Rust has no null; this is its place.",
  },
  ["Option"] = {
    summary = "Either `Some(value)` or `None`: the way a value that may be absent is typed.",
  },
  ["Ok"] = { summary = "The success variant of `Result`." },
  ["Err"] = { summary = "The failure variant of `Result`." },
  ["Result"] = {
    summary = "Either `Ok(value)` or `Err(error)`: the way a fallible operation reports its outcome.",
    note = "`?` after an expression returns the `Err` early and unwraps the `Ok`.",
  },
  ["Vec"] = { summary = "A growable array on the heap." },
  ["String"] = { summary = "An owned, growable UTF-8 string; `&str` is the borrowed view of one." },
  ["Box"] = {
    summary = "A value on the heap with a single owner; the usual way to hold a trait object or a recursive type.",
  },
  ["Rc"] = { summary = "A reference-counted pointer for shared ownership within one thread." },
  ["Arc"] = {
    summary = "An atomically reference-counted pointer: shared ownership across threads.",
  },
  ["unwrap"] = {
    summary = "Takes the value out of an `Option` or `Result` and panics if there is none.",
    note = "Fine in tests and when the case is impossible; use `?` or `match` where it is not.",
  },
  ["expect"] = { summary = "Like `unwrap`, but panics with your message." },
  ["clone"] = {
    summary = "Makes an independent copy of a value, which can be expensive; a move or a borrow is free.",
  },
  ["derive"] = {
    summary = "An attribute that generates trait implementations (`#[derive(Debug, Clone)]`).",
  },
  ["panic"] = {
    summary = "Aborts the current thread with a message; the macro behind `unwrap` and failed asserts.",
  },
}

return M
