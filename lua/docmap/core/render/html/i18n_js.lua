---@module 'docmap.core.render.html.i18n_js'
--- The JavaScript runtime of the interface catalog: `docmapI18n(data)`, the page's `t(key, params)`.
---
--- The twin of `core/i18n/init.lua`, function for function (`normalize`, `resolve`, `pluralCategory`,
--- `interpolate`, `t`), and held to it by `TESTS/fixtures/i18n/cases.json`: `i18n_runtime_spec.lua` runs every
--- golden case through both and compares the answers. A change of semantics is a change of that file first.
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
    locale: function(){ return active; }
  };
}
]]
