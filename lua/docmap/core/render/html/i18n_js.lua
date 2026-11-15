---@module 'docmap.core.render.html.i18n_js'
--- The JavaScript runtime of the interface catalog: `docmapI18n(data)`, the page's `t(key, params)`.
---
--- The twin of `core/i18n/init.lua`, function for function (`normalize`, `resolve`, `pluralCategory`,
--- `interpolate`, `t`), and held to it by `TESTS/fixtures/i18n/cases.json`: `i18n_runtime_spec.lua` runs every
--- golden case through both and compares the answers. A change of semantics is a change of that file first.
--- `number`, `date`, `dateTime` and `compare` have no twin: they format with `Intl` in the active locale, and the
--- Lua side keeps ungrouped ASCII digits (`docs/i18n.md`). `i18n_runtime_spec.lua` checks them in `node`.
---
--- **Pure on purpose.** One function, no `document`, no `location`, no `navigator`: it takes the embedded
--- catalogs (`core.i18n.for_page()`) and returns the runtime, so the spec can evaluate it in `node` and the page
--- decides for itself where a locale comes from (`docs/i18n.md`, "Which locale").
---
--- Emitted in a `<script>` of its own in front of the page's script, hence one global name.

return [[
function docmapI18n(data){
  var source = data.source, catalogs = data.catalogs || {};
  var active = source, debug = false;
  var own = Object.prototype.hasOwnProperty;

  function shipped(code){ return typeof code === "string" && own.call(catalogs, code); }

  // A BCP 47 tag ("de-AT"), a POSIX locale ("de_DE.UTF-8") or a bare code. The exact region wins when it is
  // shipped, the base language otherwise; a tag no catalog answers is null.
  function normalize(tag){
    if(typeof tag !== "string") return null;
    var bare = tag.replace(/[.@].*$/, "").replace(/_/g, "-");
    var m = /^([A-Za-z]{2,3})(.*)$/.exec(bare);
    if(!m || (m[2] !== "" && m[2].charAt(0) !== "-")) return null;
    var lang = m[1].toLowerCase();
    var r = /^-([A-Za-z]{2})$/.exec(m[2]) || /^-([A-Za-z]{2})-/.exec(m[2]);
    if(r){
      var exact = lang + "-" + r[1].toUpperCase();
      if(shipped(exact)) return exact;
    }
    return shipped(lang) ? lang : null;
  }

  // The first candidate that names a shipped locale, else the source locale.
  function resolve(candidates){
    for(var i = 0; i < candidates.length; i++){
      var code = normalize(candidates[i]);
      if(code) return code;
    }
    return source;
  }

  // The same subset as the Lua runtime: `one` for the number 1 in the languages listed, `other` for the rest.
  // `Intl.PluralRules` would know more, and that is the reason it is not asked: the two runtimes have to agree.
  var ONE_OTHER = { en: true, de: true, nl: true, sv: true, it: true, es: true };
  function pluralCategory(locale, n){
    var lang = (/^[A-Za-z]+/.exec(String(locale)) || [""])[0];
    return (ONE_OTHER[lang] === true && n === 1) ? "one" : "other";
  }

  // A placeholder with no parameter is left standing: `{who}` on screen says the template and its caller drifted.
  function interpolate(template, params){
    if(!params) return template;
    return template.replace(/\{([A-Za-z0-9_]+)\}/g, function(whole, name){
      var value = own.call(params, name) ? params[name] : undefined;
      return (value === undefined || value === null) ? whole : String(value);
    });
  }

  function template(code, key, params){
    var messages = shipped(code) ? catalogs[code] : null;
    var entry = (messages && own.call(messages, key)) ? messages[key] : undefined;
    if(typeof entry === "string") return entry;
    if(entry && typeof entry === "object"){
      var category = pluralCategory(code, params ? params.count : undefined);
      var form = own.call(entry, category) ? entry[category] : undefined;
      if(typeof form !== "string") form = entry.other;
      return typeof form === "string" ? form : null;
    }
    return null;
  }

  function has(key){
    return shipped(source) && own.call(catalogs[source], key);
  }

  // The active locale, then the source, then a marker: never blank, never the bare key.
  function t(key, params, locale){
    var code = locale ? (normalize(locale) || source) : active;
    var found = template(code, key, params);
    if(found !== null) return interpolate(found, params);
    var fallback = code !== source ? template(source, key, params) : null;
    if(fallback !== null) return (debug ? "‹en› " : "") + interpolate(fallback, params);
    return "‹missing:" + key + "›";
  }

  function configure(opts){
    opts = opts || {};
    if(opts.locale !== undefined && opts.locale !== null) active = normalize(opts.locale) || source;
    if(opts.debug !== undefined && opts.debug !== null) debug = !!opts.debug;
    return active;
  }

  // ── Formatting in the active locale (page only) ───────────────────────────
  // The Lua side has no ICU and writes ungrouped ASCII digits (docs/i18n.md, "Placeholders"); the page has
  // `Intl` and formats in the locale the reader chose, not the browser's. One formatter per locale and kind,
  // built on first use. Without `Intl` (an old engine) the plain string stands, never an exception.
  var formatters = {};
  function formatter(kind, make){
    var id = kind + "|" + active;
    if(!own.call(formatters, id)){
      try { formatters[id] = (typeof Intl === "object") ? make(active) : null; }
      catch(e){ formatters[id] = null; }
    }
    return formatters[id];
  }

  // A count or a size: grouped the way the locale groups ("12,345", "12.345").
  function number(n){
    if(typeof n !== "number" || !isFinite(n)) return String(n);
    var f = formatter("number", function(l){ return new Intl.NumberFormat(l); });
    return f ? f.format(n) : String(n);
  }

  // A calendar day as git writes it with `--date=short` ("2026-11-15"). Read and written in UTC: the day is
  // the author's, and a reader west of Greenwich must not see the day before. Anything else is shown as given.
  function date(day){
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day || ""));
    if(!m) return day === undefined || day === null ? "" : String(day);
    var f = formatter("date", function(l){
      return new Intl.DateTimeFormat(l, { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
    });
    return f ? f.format(new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]))) : String(day);
  }

  // A moment in seconds since the epoch (a telemetry capture, a saved snapshot), in the reader's time zone.
  function dateTime(seconds){
    if(typeof seconds !== "number" || !isFinite(seconds)) return String(seconds);
    var when = new Date(seconds * 1000);
    var f = formatter("datetime", function(l){
      return new Intl.DateTimeFormat(l, {
        year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"
      });
    });
    return f ? f.format(when) : when.toISOString();
  }

  // Name order of the locale: letters first, accents and case only to break a tie (`Äpfel` beside `apfel`, not
  // behind `zebra`). A total order, so a sort does not depend on the order it was handed.
  function compare(a, b){
    var base = formatter("collator", function(l){ return new Intl.Collator(l, { sensitivity: "base" }); });
    var full = formatter("collator-full", function(l){ return new Intl.Collator(l); });
    a = String(a); b = String(b);
    if(base && full) return base.compare(a, b) || full.compare(a, b) || (a < b ? -1 : (a > b ? 1 : 0));
    a = a.toLowerCase(); b = b.toLowerCase();
    return a < b ? -1 : (a > b ? 1 : 0);
  }

  return {
    source: source,
    locales: data.locales || [],
    normalize: normalize,
    resolve: resolve,
    pluralCategory: pluralCategory,
    interpolate: interpolate,
    has: has,
    t: t,
    configure: configure,
    number: number,
    date: date,
    dateTime: dateTime,
    compare: compare,
    locale: function(){ return active; }
  };
}
]]
