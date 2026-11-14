-- TESTS/rules_corpus_spec.lua — `standalone/rules_corpus.lua`, the two pure functions of the optional real-corpus
-- case of `scripts/ci.lua`'s `standalone` gate (`rules/catalog` and `rules/run` over `$RULES_VAULT`, Neovim against
-- the standalone build).
--
-- That case runs only on a machine with a PUC Lua, its rocks and a vault, so the part that decides red or green is
-- pinned here, where every run of the suite reaches it: a deliberate divergence between the two answers is found and
-- named by the rule it sits in, identical answers are not, and "every rule" is written as families.

return function(H)
  local eq = H.eq
  local corpus = require("standalone.rules_corpus")

  local function answer()
    return {
      available = true,
      counts = { pass = 1, fail = 1 },
      results = {
        { id = "DEP-01", status = "pass", findings = {} },
        {
          id = "DEP-02",
          status = "fail",
          findings = { { file = "lua/a.lua", line = 4, text = "require in a loop" } },
        },
      },
    }
  end

  -- identical answers: nothing to report (two separately built tables, so identity is not what is compared)
  eq(
    corpus.first_difference(answer(), answer()),
    nil,
    "rules_corpus: identical answers do not differ"
  )

  -- a deliberate divergence in a leaf: found, and named by the rule, not only by its position
  do
    local other = answer()
    other.results[2].status = "pass"
    eq(
      corpus.first_difference(answer(), other),
      'answer.results[2 DEP-02].status: "fail" ~= "pass"',
      "rules_corpus: a differing status is found and names the rule"
    )
  end

  -- a finding one host has and the other lacks
  do
    local other = answer()
    other.results[2].findings = {}
    eq(
      corpus.first_difference(answer(), other),
      "answer.results[2 DEP-02].findings[1]: a table ~= nil",
      "rules_corpus: a missing finding is found"
    )
  end

  -- a key only the second answer has (the walk covers the keys of both sides)
  do
    local other = answer()
    other.warnings = { "x" }
    eq(
      corpus.first_difference(answer(), other),
      "answer.warnings: nil ~= a table",
      "rules_corpus: a key only the other host answers with is found"
    )
  end

  -- a rule one host lists and the other does not
  do
    local other = answer()
    other.results[3] = { id = "DEP-03", status = "manual", findings = {} }
    eq(
      corpus.first_difference(answer(), other),
      "answer.results[3 DEP-03]: nil ~= a table",
      "rules_corpus: a rule only one host lists is found"
    )
  end

  -- a number against its text is a difference (the two hosts encode through different JSON libraries)
  eq(
    corpus.first_difference({ line = 4 }, { line = "4" }),
    'answer.line: 4 ~= "4"',
    "rules_corpus: a number is not its text"
  )

  -- the selection: every family once, sorted, whatever order the catalog lists the rules in
  eq(
    corpus.selection({
      rules = {
        { id = "SEC-02", family = "SEC" },
        { id = "DEP-01", family = "DEP" },
        { id = "SEC-01", family = "SEC" },
        { id = "X", family = "" },
        { id = "Y" },
      },
    }),
    "DEP,SEC",
    "rules_corpus: the selection is the sorted families"
  )
  eq(corpus.selection({ rules = {} }), nil, "rules_corpus: an empty catalog has no selection")
  eq(corpus.selection({ available = false }), nil, "rules_corpus: an answer without rules has none")
end
