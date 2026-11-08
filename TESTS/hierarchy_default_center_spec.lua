-- TESTS/hierarchy_default_center_spec.lua — a graph view opens on something
--
-- The Hierarchy's graph views (Deps, Calls, Module Calls) opened on the root
-- whenever the URL named no center. The root is a folder: it requires
-- nothing, declares no functions and calls nothing, so on a map with a
-- thousand edges (an nvim config: 832 calls, 183 requires) Deps and Module
-- Calls drew one lonely box and Calls said "<root> declares no functions" -
-- and the reader concluded the views were broken. Now:
--
--   * with no center in the URL, a graph view whose start has no edge of its
--     kind starts on the node with the most of them, and says so;
--   * a center somebody chose is kept, and if it has no edge the view says
--     why instead of drawing boxes with nothing between them.
--
-- **Same limit as `hierarchy_gestures_spec.lua`.** The behaviour runs in the
-- browser; it was verified by driving the real page of an nvim config (Deps,
-- Calls and Module Calls each start on a busy module with a note under the
-- graph; `center=<root>` in the URL shows the explanation). What a spec can
-- hold is the structure that keeps it true.

return function(H)
  local ok = H.ok

  local src = H.html_source()

  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "default center: " .. msg)
  end

  -- The caller says whether the center was chosen; only then may the view
  -- move it. Without the flag a click on the root would be overridden too.
  has(
    'drawHierarchy(s.center || IR.root, s.view || "modules", false, !s.center)',
    "applyState passes whether the URL named a center"
  )
  has(
    "function drawHierarchy(centerId, view, forceCenter, implicitCenter){",
    "drawHierarchy takes it"
  )
  has(
    "if(implicitCenter && isGraphView(view) && graphDegree(view, hcenter) === 0){",
    "only an implicit center without edges is moved"
  )

  -- One degree per view, from the indexes built once at load.
  has("function graphDegree(view, id){", "a degree per graph view")
  has(
    'if(view === "deps") return (depOut[id] || []).length + (depIn[id] || []).length;',
    "deps counts requires both ways"
  )
  has(
    "(moduleCallOut[id] || []).length + (moduleCallIn[id] || []).length",
    "module calls counts pairs both ways"
  )
  has(
    "(callOut[k] || []).length + (callIn[k] || []).length",
    "calls counts call sites of every function"
  )
  has("function busiestFor(view){", "the busiest node is one function")

  -- Boxes without one edge between them are empty, and say why.
  has(
    "if(built.count === 0 || (isGraphView(view) && built.edges && built.edges.length === 0)){",
    "an edgeless graph view takes the empty branch"
  )

  -- The move is announced, and the note is cleared like the others.
  has('auto.className = "htrunc hauto";', "an auto-centered view says so")
  has(
    'hgraphWrap.parentNode.querySelectorAll(".htrunc").forEach(function(el){ el.remove(); });',
    "every note under the graph is cleared on redraw, not just the first"
  )
end
