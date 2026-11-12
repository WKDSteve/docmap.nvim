---@module 'docmap.core.lang.glossary.python'
--- Python's keyword glossary -- what the page shows when the reader hovers a keyword or a standard-library call in a
--- rendered source snippet. Data, not code; see `glossary/lua.lua` for the rules every glossary follows (one offline
--- sentence per entry, a `note` only for what surprises, no per-entry anchors until someone has opened the link).
---
--- Python 3. The entries were chosen for what is actually written in a code base and not obvious from the shape --
--- the decorator and dunder conventions, `self`/`cls`, `yield`, the context manager -- not transcribed from the
--- keyword list. `*args`/`**kwargs` and `@decorator` are symbols the word tokenizer cannot see, so they live in the
--- words around them (`args`, `kwargs`, `staticmethod`, `property`).

local M = {}

---@type Docmap.Glossary.Reference
M.reference = {
  label = "Python 3 documentation",
  url = "https://docs.python.org/3/",
}

---@type Docmap.Glossary.Syntax
M.syntax = {
  line_comment = "#",
  strings = { { '"""', '"""' }, { "'''", "'''" }, { '"', '"' }, { "'", "'" } },
  escape = "\\",
}

---@type table<string, Docmap.Glossary.Entry>
M.keywords = {
  -- Definitions
  ["def"] = { summary = "Defines a function. The body is the indented block that follows." },
  ["class"] = { summary = "Defines a class. Calling the class creates an instance." },
  ["lambda"] = {
    summary = "An anonymous function whose body is a single expression.",
    note = "No statements, no annotations; anything longer wants a `def`.",
  },
  ["return"] = {
    summary = "Returns a value from a function. A function that falls off the end returns `None`.",
  },
  ["yield"] = {
    summary = "Hands a value out of a generator and suspends it until the caller asks for the next one.",
    note = "A function containing `yield` is a generator: calling it runs nothing until it is iterated.",
  },
  ["async"] = {
    summary = "Marks a function, `for` or `with` as asynchronous: it runs on an event loop.",
  },
  ["await"] = {
    summary = "Suspends the enclosing coroutine until an awaitable finishes, then continues with its result.",
    note = "Only valid inside an `async def`.",
  },
  ["global"] = {
    summary = "Makes a name in this function refer to the module-level variable instead of a new local.",
  },
  ["nonlocal"] = {
    summary = "Makes a name in a nested function refer to the enclosing function's variable.",
  },

  -- Control flow
  ["if"] = { summary = "Starts a conditional. `elif` and `else` follow at the same indentation." },
  ["elif"] = { summary = "A further condition, tested only when the ones above it were false." },
  ["else"] = {
    summary = "The branch taken when every condition above was false.",
    note = "Also valid after `for`, `while` and `try`: there it runs when the loop was not left by `break` (or no exception was raised).",
  },
  ["for"] = { summary = "Loops over the items of an iterable: `for x in items:`." },
  ["while"] = { summary = "Loops while the condition holds, tested before each pass." },
  ["break"] = { summary = "Leaves the innermost enclosing loop." },
  ["continue"] = { summary = "Skips to the next pass of the innermost enclosing loop." },
  ["pass"] = { summary = "Does nothing; fills a block that needs a statement." },
  ["match"] = {
    summary = "Structural pattern matching (3.10+): runs the first `case` whose pattern fits the subject.",
  },
  ["case"] = { summary = "One pattern of a `match` statement, with an optional `if` guard." },

  -- Errors and context
  ["try"] = {
    summary = "Starts a block whose exceptions the `except` clauses below it can handle.",
  },
  ["except"] = {
    summary = "Handles an exception of the named type raised in the `try` block.",
    note = "A bare `except:` also catches `KeyboardInterrupt` and `SystemExit`; `except Exception:` does not.",
  },
  ["finally"] = {
    summary = "Runs whatever happened in the `try` block, including a `return` or an exception.",
  },
  ["raise"] = {
    summary = "Raises an exception. A bare `raise` inside `except` re-raises the one being handled.",
  },
  ["assert"] = {
    summary = "Raises `AssertionError` when the condition is false.",
    note = "Removed entirely when Python runs with `-O`, so never use it for input validation.",
  },
  ["with"] = {
    summary = "Runs a block inside a context manager, which sets up and always tears down (`with open(p) as f:`).",
  },
  ["as"] = { summary = "Binds a name: `import x as y`, `with open(p) as f`, `except E as e`." },
  ["del"] = {
    summary = "Removes a name, an item (`del d[k]`) or a slice. It does not free the object by itself.",
  },

  -- Modules
  ["import"] = { summary = "Loads a module and binds it to a name in this scope." },
  ["from"] = {
    summary = "`from m import x` binds names out of a module; `raise X from Y` chains the cause of an exception.",
  },

  -- Operators and values
  ["in"] = { summary = "Membership test (`x in items`), and the iterable part of a `for` loop." },
  ["is"] = {
    summary = "Identity test: true when both sides are the same object.",
    note = "Use `==` to compare values; `is` is for `None` and sentinels.",
  },
  ["not"] = { summary = "Boolean negation." },
  ["and"] = {
    summary = "Short-circuit AND that returns one of its operands, not necessarily a bool.",
  },
  ["or"] = {
    summary = "Short-circuit OR that returns the first truthy operand, which makes `x or default` an idiom.",
  },
  ["None"] = { summary = "The single null value; what a function returns when it returns nothing." },
  ["True"] = { summary = "The boolean true. It is also the integer `1`." },
  ["False"] = { summary = "The boolean false. It is also the integer `0`." },

  -- Conventions that look like keywords
  ["self"] = {
    summary = "By convention the first parameter of an instance method: the object the method was called on.",
    note = "Not a keyword; Python passes the instance explicitly and the name is only a habit.",
  },
  ["cls"] = {
    summary = "By convention the first parameter of a `@classmethod`: the class itself, so subclasses get their own.",
  },
  ["args"] = {
    summary = "By convention the name of `*args`: the extra positional arguments, collected into a tuple.",
  },
  ["kwargs"] = {
    summary = "By convention the name of `**kwargs`: the extra keyword arguments, collected into a dict.",
  },
  ["staticmethod"] = {
    summary = "Decorator for a method that needs neither the instance nor the class.",
  },
  ["classmethod"] = {
    summary = "Decorator for a method that receives the class (`cls`) instead of an instance.",
  },
  ["property"] = {
    summary = "Decorator that makes a method read like an attribute (`obj.size`, no call).",
  },
  ["__init__"] = {
    summary = "The initialiser: runs on a new instance, after `__new__` has made it.",
    note = "It returns nothing; it cannot replace the object.",
  },
  ["__name__"] = {
    summary = 'The module\'s name; it is `"__main__"` when the file is run as a script, hence `if __name__ == "__main__":`.',
  },
  ["__all__"] = { summary = "The list of names `from module import *` exports." },
  ["__enter__"] = {
    summary = "Called on entering a `with` block; its return value is what `as` binds.",
  },
  ["__exit__"] = {
    summary = "Called when a `with` block ends, with the exception if there was one; returning true swallows it.",
  },
  ["__repr__"] = {
    summary = "The unambiguous text form of an object, what the REPL and `repr()` show.",
  },
  ["__str__"] = {
    summary = "The readable text form of an object, what `print` and `str()` use; falls back to `__repr__`.",
  },
  ["super"] = {
    summary = "Gives access to the next class in the method resolution order, usually the parent.",
  },
}

---@type table<string, Docmap.Glossary.Entry>
M.stdlib = {
  ["os.path.join"] = { summary = "Joins path parts with the platform's separator." },
  ["os.path.exists"] = {
    summary = "True when the path exists (a broken symlink counts as missing).",
  },
  ["os.environ"] = {
    summary = "The process environment as a mapping; indexing a missing name raises `KeyError`.",
  },
  ["os.getcwd"] = { summary = "The current working directory." },
  ["sys.argv"] = { summary = "The command line as a list; element 0 is the script's own name." },
  ["sys.exit"] = { summary = "Exits by raising `SystemExit`, so `finally` blocks still run." },
  ["sys.path"] = { summary = "The list of directories `import` searches, in order." },
  ["json.loads"] = { summary = "Parses a JSON string into Python objects." },
  ["json.dumps"] = { summary = "Serialises Python objects to a JSON string." },
  ["json.load"] = { summary = "Parses JSON from an open file." },
  ["json.dump"] = { summary = "Writes Python objects as JSON to an open file." },
  ["re.match"] = {
    summary = "Matches a pattern at the *start* of the string only.",
    note = "Use `re.search` to find it anywhere.",
  },
  ["re.search"] = { summary = "Finds the first match of a pattern anywhere in the string." },
  ["re.sub"] = { summary = "Replaces every match of a pattern, with a string or a function." },
  ["re.compile"] = { summary = "Compiles a pattern once, for reuse." },
  ["subprocess.run"] = {
    summary = "Runs a command and waits for it, returning a `CompletedProcess`.",
    note = "Pass a list, not a string, and avoid `shell=True` with untrusted input.",
  },
  ["logging.getLogger"] = { summary = "Returns the named logger; `__name__` is the usual name." },
  ["pathlib.Path"] = { summary = "An object-oriented filesystem path; `/` joins parts." },
  ["time.sleep"] = { summary = "Blocks the thread for the given seconds." },
  ["datetime.datetime.now"] = {
    summary = "The current local date and time, without a timezone unless one is passed.",
  },
  ["itertools.chain"] = { summary = "Iterates several iterables as one." },
  ["functools.partial"] = {
    summary = "Fixes some arguments of a function, returning a new callable.",
  },
  ["collections.defaultdict"] = {
    summary = "A dict that creates a missing value from a factory on first access.",
  },
  ["asyncio.run"] = {
    summary = "Runs a coroutine to completion on a fresh event loop; the usual entry point.",
  },
  ["asyncio.gather"] = {
    summary = "Runs awaitables concurrently and collects their results in order.",
  },
}

return M
