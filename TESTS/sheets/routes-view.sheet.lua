-- TESTS/sheets/routes-view.sheet.lua -- the Routes view of the Hierarchy, in a real window.
-- A browser sheet over the page TESTS/sheets_spec.lua renders from TESTS/fixtures/routes_page: a Next.js tree with
-- an `app` directory (a group, a dynamic segment, both catch-all forms, a slot, an interceptor, a handler) and a
-- `pages` directory. Its routes need the tsx and typescript parsers of the editor that renders the page. The sheet
-- checks what a spec cannot: that the route trees are drawn as trees in the zooming diagram, that a click
-- re-centers on a segment, and that the Endpoints panel leads here.
local BOX = "document.querySelector('#hstage .hnode[data-key=\"route:%s\"]')"
local function box(dir)
  return BOX:format(dir)
end
local function top(dir)
  return "parseFloat(" .. box(dir) .. ".style.top)"
end
local COUNT = "document.querySelectorAll('#hstage .hnode:not(.leaving)').length"

return {
  id = "routes-view",
  title = "Hierarchy: the Routes view (file-based routing as a tree)",
  task = "docmap.nvim/file-based-routing-hierarchy",
  engine = "browser",
  sizes = { { cols = 1900, rows = 800 } },
  steps = {
    { open = "TESTS/sheets/out/routes-page.html" },
    { click = 'button[data-tab="hierarchy"]', note = "the Hierarchy tab" },
    {
      focus = 'button.hview-btn[data-view="routes"]',
      note = "the view is reached with the keyboard",
    },
    { press = "Enter" },
    { wait = COUNT .. " === 21", note = "both route trees are drawn, a box per segment" },
    {
      expect = "/view=routes/.test(location.hash) && document.getElementById('halt').hidden"
        .. " && document.getElementById('hexport').style.display !== 'none'"
        .. " && document.getElementById('hpath').textContent === '2 route trees · 12 routes'",
      note = "the link carries the view; it is the zooming diagram; the path counts trees and routes",
    },
    {
      expect = "(b => /^src\\/appApp Router · 8 routes$/.test(b.textContent) && /Next\\.js App Router/.test(b.title))("
        .. box("src/app")
        .. ") && /Pages Router · 4 routes/.test("
        .. box("src/pages")
        .. ".textContent)",
      note = "a root names its router and counts its routes",
    },
    {
      expect = "(b => b.classList.contains('rt-dynamic') && b.classList.contains('rt-route')"
        .. " && b.querySelector('.hnm').textContent === '[slug]' && b.querySelector('.hline').textContent === '/blog/[slug]'"
        .. " && /loading: src\\/app\\/blog\\/\\[slug\\]\\/loading\\.tsx/.test(b.title))("
        .. box("src/app/blog/[slug]")
        .. ")",
      note = "a dynamic segment is named as written, with its URL; the tooltip lists its files",
    },
    {
      expect = "/group · not in the URL/.test("
        .. box("src/app/(marketing)")
        .. ".textContent) && !"
        .. box("src/app/(marketing)")
        .. ".classList.contains('rt-route') && "
        .. box("src/app/(marketing)/about")
        .. ".querySelector('.hline').textContent === '/about'",
      note = "a route group is no route and leaves the URL below it alone",
    },
    {
      expect = box("src/app/api/health")
        .. ".querySelector('.hline').textContent === '/api/health · handler' && /slot · not in the URL/.test("
        .. box("src/app/dashboard/@stats")
        .. ".textContent) && /intercepts a route/.test("
        .. box("src/app/photos/(.)view")
        .. ".textContent) && "
        .. box("src/app/docs/[[...path]]")
        .. ".querySelector('.hline').textContent === '/docs/[[...path]]' && "
        .. box("src/pages/posts/[id]")
        .. ".querySelector('.hline').textContent === '/posts/[id]'",
      note = "a handler, a slot, an interceptor, an optional catch-all and a file route of the Pages Router",
    },
    {
      expect = top("src/app")
        .. " < "
        .. top("src/app/blog")
        .. " && "
        .. top("src/app/blog")
        .. " < "
        .. top("src/app/blog/[slug]")
        .. " && document.querySelectorAll('#hsvg .hedge').length === 19",
      note = "the nesting of the directories is the nesting of the tree: a segment under the one that holds it",
    },
    { press = "Escape", note = "close the explanation the keyboard focus opened" },
    {
      wait = "!document.getElementById('hsvg').classList.contains('settling')"
        .. " && [...document.querySelectorAll('#hstage .hnode')].every(b => getComputedStyle(b).left === b.style.left"
        .. " && getComputedStyle(b).opacity === '1')",
      note = "the boxes have arrived",
    },
    { shot = "trees-light" },
    { scheme = "dark" },
    {
      wait = "new Promise(done => setTimeout(() => done(true), 450))",
      note = "the colours of the other theme have faded in",
    },
    { shot = "trees-dark" },
    { scheme = "light" },
    { click = '#hstage .hnode[data-key="route:src/app/blog"]', note = "a click pins a segment" },
    {
      click = '#hstage .hnode[data-key="route:src/app/blog"]',
      note = "a second click re-centers on it",
    },
    {
      wait = COUNT
        .. " === 2 && /center=src%2Fapp%2Fblog(&|$)/.test(location.hash)"
        .. " && document.getElementById('hpath').textContent === 'src/app/blog · /blog · routes' && "
        .. box("src/app/blog")
        .. ".classList.contains('center')",
      note = "the segment and what is below it; the center is its directory, so the link carries it",
    },
    { shot = "segment-light" },
    { click = "#hup", note = "Up" },
    {
      wait = COUNT .. " === 15 && /center=src%2Fapp(&|$)/.test(location.hash)",
      note = "one directory up: the whole tree of the app directory",
    },
    {
      expect = "(location.hash = '#tab=analysis&atool=endpoints', true)",
      note = "the Endpoints panel of the Analysis tab",
    },
    {
      wait = "/This tree also has 12 file-based routes/.test(document.getElementById('view-analysis').textContent)"
        .. " && !/unbuilt/.test(document.getElementById('view-analysis').textContent)",
      note = "it says that the tree routes by file, and no longer that this is unbuilt",
    },
    { click = '#view-analysis a[href="#tab=hierarchy&view=routes"]', note = "its link" },
    {
      wait = COUNT
        .. " === 21 && /view=routes/.test(location.hash) && document.getElementById('view-hierarchy').classList.contains('active')",
      note = "leads to the Routes view, all trees",
    },
  },
  judge = {
    "the two route trees read as trees: a root on top, segments below what holds them, no box over another (trees-light)",
    "a route can be told from a segment that is none without colour: the URL below its name, the heavier left edge (trees-light, trees-dark)",
    "the re-centered segment shows itself and its child, with the path above (segment-light)",
  },
}
