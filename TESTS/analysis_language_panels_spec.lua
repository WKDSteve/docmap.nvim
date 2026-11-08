-- TESTS/analysis_language_panels_spec.lua — the Decorators and Rust panels and the Clusters view of the
-- Duplicates panel.
--
-- Same limit as `compiler_explorer_spec.lua`: all of this runs in the browser, so a Lua spec holds the
-- wiring. The page itself was driven once by hand on a tree with Python and Rust (2026-11-06). A panel
-- that is written but not wired reaches nobody and throws nothing, which is what this catches: each
-- `atool` must be a button, pass the URL check, pass the draw check and have its dispatch.

return function(H)
  local ok = H.ok

  local src = H.html_source()

  local function has(needle, what)
    ok(src:find(needle, 1, true) ~= nil, what)
  end

  for atool, fn in pairs({ decorators = "renderAnalysisDecorators", rust = "renderAnalysisRust" }) do
    has(('data-atool="%s" data-explain="atool.%s"'):format(atool, atool), atool .. ": a button")
    has(('"atool.%s":'):format(atool), atool .. ": an explanation")
    has(('v === "%s"'):format(atool), atool .. ": a link to it survives the URL check")
    has(('state.atool === "%s"'):format(atool), atool .. ": drawAnalysis lets it through")
    has(('if(atool === "%s") return %s();'):format(atool, fn), atool .. ": it dispatches")
    has(("function %s()"):format(fn), atool .. ": the panel exists")
  end

  -- An empty state that names the language: no Python is not the same as no decorators.
  has("Only Python files are", "decorators: the empty state names the language")
  has("Rust files are checked", "rust: the empty state names the language")

  -- The clusters: reachable from the panel, and part of what the panel cache is keyed on, or the
  -- button would redraw the cached list.
  has('data-dupview="clusters"', "clusters: a button in the Duplicates panel")
  has('"|" + dupView', "clusters: the cache key holds the view")
  has("renderDuplicateCluster(g)", "clusters: the panel draws them")
  -- `sigTrigger` is what carries the mark, and the mark is what the Compare tab reads.
  has("anrow dupcl-fn", "clusters: a row goes to its module like a row of the list")
  ok(
    src:find("dupcl%-fn.-esc%(m%.signature or m%.name%)") == nil
      and src:find("dupcl%-fn.-sigTrigger%(m%.node, m%.name%)") ~= nil,
    "clusters: a row carries the mark"
  )
end
