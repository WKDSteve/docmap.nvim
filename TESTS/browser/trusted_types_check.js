// TESTS/browser/trusted_types_check.js -- opens generated map pages under `require-trusted-types-for 'script'`
// and walks every tab, view, menu and popup of them. Any violation (securitypolicyviolation event, console error,
// uncaught page error) is a failure.
//
// usage: node trusted_types_check.js <page.html>...
// exit 0: clean, 1: a violation or a page error, 77: node / playwright / chromium missing (a reported skip).
"use strict";
const fs = require("fs");
const path = require("path");

function load() {
  const dirs = [process.env.TESTING_PLAYWRIGHT_DIR, process.cwd(), ""].filter((d) => d !== undefined);
  for (const mod of ["playwright-core", "playwright"]) {
    for (const d of dirs) {
      try {
        return require(d ? require.resolve(mod, { paths: [d] }) : mod);
      } catch (_) {}
    }
  }
  return null;
}

const CSP = "require-trusted-types-for 'script'";
const ORIGIN = "http://docmap.test";

// Buttons and links that open something; each is clicked once, in this order, and the page must stay clean.
const CLICK_GROUPS = [
  ".tab-btn",
  ".hview-btn",
  ".hdir-btn",
  ".hdepth-btn",
  ".hext-btn",
  ".hgest-btn",
  ".cmpview-btn",
  ".anview-btn",
  "#subtabs button",
  "#subtabs a",
  ".stat-link",
  "#hshapebtn",
  "#expand",
  "#collapse",
  "#hup",
  "#hroot",
  "#hlr",
  "#markbar",
  "#cmpclear",
  "[data-explain]",
  ".hist-row",
  "#hist-list > *",
  "#hist-list li",
  "#hist-list .hrow",
  "#tree .row",
  "#tree .head",
  "#findings .row",
  "a.nfn",
  ".bd[data-kw]",
  "#hgraph .node",
  "#hgraph g[data-id]",
  ".tm > *",
];

async function sweep(page, file, url) {
  const failures = [];
  const seen = (what) => failures.push(`${path.basename(file)}: ${what}`);
  page.on("dialog", (d) => d.dismiss().catch(() => {}));
  page.on("pageerror", (e) => seen("page error: " + e.message));
  page.on("console", (m) => {
    if (m.type() === "error" || /TrustedHTML|Trusted Type/i.test(m.text())) seen("console: " + m.text());
  });
  await page.addInitScript(() => {
    window.__violations = [];
    document.addEventListener("securitypolicyviolation", (e) =>
      window.__violations.push(e.violatedDirective + " " + (e.sample || "")),
    );
  });
  await page.goto(url || ORIGIN + "/" + path.basename(file));
  await page.waitForTimeout(300);

  // Clicks run inside the page (no actionability waits): each visible match of a selector is clicked once, the
  // elements are looked up again after every click because a click redraws its panel.
  const clickAll = (sel, limit) =>
    page.evaluate(
      async ({ sel, limit }) => {
        const wait = (ms) => new Promise((r) => setTimeout(r, ms));
        const n = Math.min(document.querySelectorAll(sel).length, limit);
        for (let i = 0; i < n; i++) {
          const el = document.querySelectorAll(sel)[i];
          if (!el || el.offsetParent === null) continue;
          el.click();
          el.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
          await wait(20);
          document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        }
      },
      { sel, limit },
    );
  for (const sel of CLICK_GROUPS) {
    await clickAll(sel, 30);
    // go back to the first tab so the next group finds its controls
    if (sel === ".tab-btn") await clickAll('.tab-btn[data-tab="hierarchy"]', 1);
  }
  // the tabs once more, each followed by its own sub-controls
  const tabs = await page.locator(".tab-btn").evaluateAll((els) => els.map((e) => e.dataset.tab));
  for (const tab of tabs) {
    await clickAll(`.tab-btn[data-tab="${tab}"]`, 1);
    for (const sel of [".anview-btn", ".cmpview-btn", ".hview-btn", "#subtabs button"]) await clickAll(sel, 30);
  }
  // search, and the keys the page listens for, all inside the page (an input that is hidden must not make the
  // sweep wait for it)
  await page.evaluate(async () => {
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    const q = document.getElementById("q");
    if (q) {
      for (const text of ["a", "app", "zzzz-no-match", "<b>x</b>", ""]) {
        q.value = text;
        q.dispatchEvent(new Event("input", { bubbles: true }));
        await wait(150);
      }
    }
    for (const key of ["?", "/", "Escape", "0"]) {
      document.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
      await wait(30);
    }
    // the context menu and the hover popups of the graph and the lists
    for (const sel of ["#hgraph .node", "#tree .row", "a.nfn"]) {
      const el = document.querySelector(sel);
      if (!el) continue;
      for (const type of ["contextmenu", "mouseover", "mouseenter", "focusin"]) {
        el.dispatchEvent(new MouseEvent(type, { bubbles: true }));
      }
      await wait(60);
    }
  });
  const v = await page.evaluate(() => window.__violations || []);
  for (const x of v) seen("securitypolicyviolation: " + x);
  return failures;
}

async function main() {
  const files = process.argv.slice(2);
  const pw = load();
  if (!pw) {
    console.log("playwright is not installed");
    process.exit(77);
  }
  let browser;
  try {
    browser = await pw.chromium.launch();
  } catch (e) {
    console.log("chromium cannot be launched: " + e.message.split("\n")[0]);
    process.exit(77);
  }
  const failures = [];
  for (const file of files) {
    const html = fs.readFileSync(file);
    const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    await ctx.route(ORIGIN + "/**", (route) =>
      route.fulfill({
        status: 200,
        headers: { "content-type": "text/html; charset=utf-8", "content-security-policy": CSP },
        body: html,
      }),
    );
    // nothing leaves the fixture: a link the sweep clicks must not take the page away
    await ctx.route((u) => !u.href.startsWith(ORIGIN), (route) => route.abort());
    const page = await ctx.newPage();
    failures.push(...(await sweep(page, file)));
    await ctx.close();
  }
  await browser.close();
  const unique = [...new Set(failures)];
  console.log(JSON.stringify({ failures: unique.length, details: unique.slice(0, 40) }));
  process.exit(unique.length === 0 ? 0 : 1);
}

module.exports = { sweep, ORIGIN };
if (require.main === module) main();
