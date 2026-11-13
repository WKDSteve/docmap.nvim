-- TESTS/hierarchy_wide_levels_spec.lua — Tree and Treemap in the Hierarchy
--
-- The box views lay every level out as one row; an nvim config (310
-- namespaces) gives rows wider than the window and a Modules view at the
-- 90-box cap. Two views read the same `children` tree without layers:
--
--   * Tree: a folding list from the center, a filter that keeps every match
--     and the path to it (`tq=` in the URL), the keyboard (arrows, Home/End,
--     Enter re-roots like a click on a box);
--   * Treemap: nested areas from the center, sized by lines or functions
--     (`tm=functions`), a click zooms in, a leaf opens in the Tree tab.
--
-- **Same limit as `hierarchy_gestures_spec.lua`.** The behaviour runs in the
-- browser; it was verified by driving the real page of an nvim config:
-- filtering "heartbeat" leaves nvim > startup > heartbeat.lua with the input
-- still focused, a reload of that link restores the filter, the arrows walk
-- and fold, Enter re-roots, the Treemap draws 4 groups and 38 tiles, the
-- metric toggle and a click on a group land in the URL, a right-click on a
-- tile opens the node menu, and Modules afterwards draws its 90 boxes again.
-- What a spec can hold is the structure that keeps those true.

return function(H)
  local ok, eq = H.ok, H.eq

  local src = H.html_source()

  local function has(needle, msg)
    ok(src:find(needle, 1, true) ~= nil, "wide levels: " .. msg)
  end

  -- The page loads at all: the views are part of the one script, which lives
  -- in a Lua long string. The module requiring cleanly is the proof that no
  -- two closing brackets in a row slipped into it.
  ok(pcall(require, "docmap.core.render.html"), "wide levels: html.lua still parses")

  -- Two buttons, two known views, one container outside the zooming wrap.
  has('data-view="tree" data-explain="view.tree">Tree</button>', "a Tree button")
  has('data-view="treemap" data-explain="view.treemap">Treemap</button>', "a Treemap button")
  has("tree: 1, treemap: 1,", "both are known views (an unknown one falls back to Modules)")
  has(
    '<div id="halt" hidden><div id="halt-bar" class="hctl"></div><div id="halt-body"></div></div>',
    "their own container"
  )
  has('"view.tree":', "Tree explains itself")
  has('"view.treemap":', "Treemap explains itself")

  -- drawHierarchy hands them off before any layered layout runs, and gives
  -- the diagram back when another view is chosen.
  has("if(isAltView(view)){ drawAltView(view); return; }", "drawHierarchy hands the two views off")
  has('hgraphWrap.style.display = "";', "...and shows the diagram again for the others")

  -- The URL carries what it takes to show the same thing, and nothing else.
  has(
    'if(s.view === "tree" && s.tq) parts.push("tq=" + encodeURIComponent(s.tq));',
    "the filter is in the link"
  )
  has(
    'if(s.view === "treemap" && s.tm === "functions") parts.push("tm=functions");',
    "the measure is in the link"
  )
  has('else if(k === "tq") s.tq = v || null;', "...and read back")
  has(
    'else if(k === "tm") s.tm = (v === "functions") ? "functions" : null;',
    "...an unknown measure is lines"
  )

  -- Typing filters without a history entry per key and without stealing the
  -- input's focus; serializeState already starts with the `#`.
  has(
    'history.replaceState(state, "", serializeState(state));\n      drawTree(hcenter);',
    "the filter replaces the entry"
  )
  eq(src:find('"#" + serializeState', 1, true), nil, "wide levels: no doubled # in a URL")

  -- Rows and tiles are nodes to the context menu.
  has(
    'role="treeitem" tabindex="-1" data-id="',
    "a tree row is a focusable treeitem with its node id"
  )
  has("'\" data-id=\"' + esc(id) + '\" title=\"'", "a treemap box carries its node id")

  -- The layout and the keyboard.
  has("function squarify(items, x, y, w, h){", "a squarified treemap")
  has('if(ev.key === "ArrowDown") go(all[i + 1]);', "arrows walk the rows")
  has('} else if(ev.key === "Enter"){', "Enter re-roots")

  -- Controls that belong to the drawn diagram step aside.
  has('["hlr", "hgest", "hzoomreset", "hzoomlabel", "hexport"]', "diagram-only controls are hidden")
  -- ...and so are their keys: + - 0 would zoom the diagram that is not shown.
  has(
    'if(state.tab !== "hierarchy") return;\n    // Tree and Treemap hide the zoom controls; the keys would otherwise\n    // change the zoom of the diagram that is not on screen.\n    if(isAltView(state.view)) return;',
    "zoom keys stay out of Tree and Treemap"
  )

  -- "Hidden (n) — show all" reaches rows and tiles, not only diagram boxes.
  local sync = src:match("function syncHidden%(%)(.-)\n  }\n")
  ok(sync ~= nil, "wide levels: syncHidden is found")
  ok(
    (sync or ""):find('".ht-row[data-id], .tm-group[data-id], .tm-tile[data-id]"', 1, true) ~= nil,
    "wide levels: syncHidden re-dims tree rows and treemap areas"
  )
end
