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

  const settle = () => page.waitForTimeout(40);
  for (const sel of CLICK_GROUPS) {
    const n = await page.locator(sel).count();
    for (let i = 0; i < Math.min(n, 40); i++) {
      const el = page.locator(sel).nth(i);
      if (!(await el.isVisible().catch(() => false))) continue;
      await el.click({ timeout: 1500, trial: false, force: true }).catch(() => {});
      await settle();
      await page.keyboard.press("Escape").catch(() => {});
    }
    // go back to the first tab so the next group finds its controls
    if (sel === ".tab-btn") await page.locator('.tab-btn[data-tab="hierarchy"]').click().catch(() => {});
  }
  // the tabs once more, each followed by its own sub-controls
  const tabs = await page.locator(".tab-btn").evaluateAll((els) => els.map((e) => e.dataset.tab));
  for (const tab of tabs) {
    await page.locator(`.tab-btn[data-tab="${tab}"]`).click().catch(() => {});
    await settle();
    for (const sel of [".anview-btn", ".cmpview-btn", ".hview-btn", "#subtabs button"]) {
      const n = await page.locator(sel).count();
      for (let i = 0; i < Math.min(n, 30); i++) {
        const el = page.locator(sel).nth(i);
        if (await el.isVisible().catch(() => false)) {
          await el.click({ timeout: 1500, force: true }).catch(() => {});
          await settle();
        }
      }
    }
  }
  // search
  const q = page.locator("#q");
  if (await q.count()) {
    for (const text of ["a", "app", "zzzz-no-match", "<b>x</b>"]) {
      await q.fill(text).catch(() => {});
      await page.waitForTimeout(150);
    }
    await q.fill("").catch(() => {});
  }
  // keyboard on the document: help, search, escape
  for (const k of ["?", "/", "Escape", "0"]) {
    await page.keyboard.press(k).catch(() => {});
    await settle();
  }
  // the context menu and the hover popups of the graph
  for (const sel of ["#hgraph .node", "#tree .row", "a.nfn"]) {
    const el = page.locator(sel).first();
    if (await el.count()) {
      await el.click({ button: "right", timeout: 1500, force: true }).catch(() => {});
      await el.hover({ timeout: 1500, force: true }).catch(() => {});
      await settle();
    }
  }
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
