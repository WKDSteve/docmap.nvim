---@module 'docmap.core.render.html.js'
--- The script of the generated page: the slices in `html/js/`, joined in order.
---
--- The page runs the whole script as one function (`(function(){ ... })();`), so the slices share its scope. They
--- are joined as they are (each slice ends with its own line end); the result is byte-for-byte the string that
--- used to sit in html.lua.

local SLICES = {
  "docmap.core.render.html.js.01_marks_and_dimming",
  "docmap.core.render.html.js.02_explorer_and_state",
  "docmap.core.render.html.js.03_tree_findings_tabs_hierarchy",
  "docmap.core.render.html.js.04_directed_views_and_notes",
  "docmap.core.render.html.js.05_features_help_index",
  "docmap.core.render.html.js.06_analysis_tools",
  "docmap.core.render.html.js.07_analysis_panels",
  "docmap.core.render.html.js.08_history_tree_treemap",
  "docmap.core.render.html.js.09_zoom_graph_export",
  "docmap.core.render.html.js.10_search_menus_popups",
  "docmap.core.render.html.js.11_quicks_compare_init",
}

local parts = {}
for _, name in ipairs(SLICES) do
  parts[#parts + 1] = require(name)
end

return table.concat(parts)
