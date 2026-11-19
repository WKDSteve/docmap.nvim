-- TESTS/sheets/features.lua -- the functionalities of docmap.nvim that start a process (git, a headless editor,
-- the language server, the system's opener), each with the feature sheet that checks it as a user meets it
-- (testing.nvim docs/SHEETS.md, "Feature sheets and the catalog"; `testing perf` measures them, docs/PERF.md).
-- The browser sheets of the page (coupling-view, layers-view, ...) start nothing in the editor and carry no feature.
return {
  {
    id = "docmap.generate",
    title = ":DocMap writes the module map, with the remote and branch read from git for the page's links",
    surface = { "command:DocMap" },
    docs = "README.md",
  },
  {
    id = "docmap.generate-full",
    title = ":DocMap full adds the lua-language-server pass (@class/@alias detail) to the map",
    surface = { "command:DocMap full", "config:luals" },
    perf = "skip:lua-language-server is not on the CI runners, so its sheet (generate-full) carries no feature"
      .. " and skips without it; testing perf measures it where the server is installed",
  },
  {
    id = "docmap.generate-all",
    title = ":DocMap all generates every configured project's map, each in a headless editor",
    surface = { "command:DocMap all", "config:generate_all.projects" },
  },
  {
    id = "docmap.diff",
    title = ":DocMap diff <ref> compares the tree with the map committed at a revision (completed from git refs)",
    surface = { "command:DocMap diff" },
  },
  {
    id = "docmap.impact",
    title = ":DocMap impact lists the functions a change touches and their callers",
    surface = { "command:DocMap impact" },
  },
  {
    id = "docmap.churn",
    title = ":DocMap churn ranks the modules by commits times complexity",
    surface = { "command:DocMap churn" },
  },
  {
    id = "docmap.checklist",
    title = ":DocMap checklist lists the hand-verified items whose cited file changed since",
    surface = { "command:DocMap checklist" },
    docs = "docs/checklist_format.md",
  },
  {
    id = "docmap.open",
    title = ":DocMap open hands the generated page to the system's opener",
    surface = { "command:DocMap open" },
  },
  {
    id = "docmap.serve",
    title = ":DocMap serve answers the page's history from git over a local server",
    surface = { "command:DocMap serve" },
  },
  {
    id = "docmap.browse-history",
    title = ":DocBrowse history lists the commits of the repository in the map browser",
    surface = { "command:DocBrowse history" },
  },
  {
    id = "docmap.browse-page",
    title = "gO in :DocBrowse opens the generated page at the module under the cursor",
    surface = { "key:gO" },
  },
  {
    id = "docmap.browse-traffic",
    title = ":DocBrowse traffic shows github_stats.nvim's traffic of the repository named by the git remote",
    surface = { "command:DocBrowse traffic" },
  },
  {
    id = "docmap.callhierarchy",
    title = "Incoming and outgoing calls in a mapped Lua file, answered from the map by an in-process client",
    surface = { "config:callhierarchy" },
  },
  {
    id = "docmap.mcp-checklist",
    title = "The MCP tool docmap_checklist tells a coding agent which checklist items are stale",
    surface = { "script:scripts/mcp_server.lua" },
  },
  {
    id = "docmap.cli-breaking",
    title = "The CLI gate --breaking=<ref> fails on a change that breaks a caller of the map at a revision",
    surface = { "script:scripts/gen_map.lua --breaking" },
  },
  {
    id = "docmap.testing-provider",
    title = "The affected-spec provider tells a test runner which specs a change since a revision touches",
    surface = { "api:docmap.testing.affected_specs" },
    docs = "docs/testing-contract.md",
  },
}
