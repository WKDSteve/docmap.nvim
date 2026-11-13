---@module 'docmap.core.render.html.js.02_explorer_and_state'
--- A slice of the page's script: Compiler Explorer, state and history.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Compiler Explorer (opts.godbolt, experimental, session 2026-08-10) —
  // a genuine `luac -l -l -p` bytecode disassembly for Lua, not a
  // workaround: verified against Compiler Explorer's own `/api/languages`
  // (lua is a real language id there) and its compiler source (the "lua"
  // compiler class runs exactly that), after an earlier version of this
  // roadmap item wrongly assumed Lua had no meaningful compiled output to
  // show. `godbolt.org/clientstate/<base64 JSON>` is Compiler Explorer's
  // own documented, fully client-side link format — no API call needed to
  // build one, so opening it is the only network access this feature ever
  // causes, the same posture every other external link on this page
  // (`srcUrl`, `tag_links`) already has.
  //
  // No new IR field: built lazily, on click, from `fn.snippet` — already
  // serialized for the existing hover-preview feature, already bounded the
  // same way `core/snippet.lua` bounds it. A very long function's snippet
  // may be truncated (`snippet_omitted` says by how much); the bytecode
  // Compiler Explorer shows for it is correspondingly a compile of that
  // same truncated fragment — the same honesty the in-page preview already
  // has, not a new limitation this feature introduces. A module's own link
  // concatenates its functions' snippets in declaration order — an
  // approximation of the file, not the file itself (comments/requires/
  // symbols outside a function are not part of any `fn.snippet`), which is
  // why this is marked experimental rather than a byte-perfect "whole
  // project" view — Compiler Explorer's own Lua compiler (`luac`) takes
  // exactly one file per compile in any case; there is no project mode for
  // it the way CMake/C++ has.
  // Which Compiler Explorer. `godbolt.org` unless the reader has said
  // otherwise, and **the committed page never carries anything else** —
  // a generated artifact that hard-wired one machine's `localhost:10240`
  // would be a link that works for its author and 404s for everyone the
  // repository is shared with. So the override lives in `localStorage`,
  // which is a fact about the machine the page is being *read* on rather
  // than about the tree it describes.
  //
  // Unscoped, for the reason `docmap:classic-clicks` is: someone running a
  // local Compiler Explorer runs one, not one per repository.
  var CE_LS_KEY = "docmap:compiler-explorer";
  var CE_DEFAULT = "https://godbolt.org";

  function ceBase(){
    try {
      var v = (localStorage.getItem(CE_LS_KEY) || "").trim().replace(/\/+$/, "");
      // Only ever an origin this page could have reached anyway. A stored
      // `javascript:` would otherwise become a click target built by the
      // page itself, which is the one thing a base URL must not be able to
      // turn into.
      if(/^https?:\/\//.test(v)) return v;
    } catch(e){ void 0; }
    return CE_DEFAULT;
  }

  function ceIsLocal(){ return ceBase() !== CE_DEFAULT; }

  // One or more sources in one `clientstate`. Compare Explorer's own format
  // is an array of sessions, so two functions side by side is the format
  // being used as documented rather than a trick — and it is the question
  // the Duplicates panel raises and cannot answer: these two have the same
  // shape, do they compile to the same thing?
  //
  // Measured on this repository's 17 duplicate groups: a pair comes to 3 104
  // characters at the longest, comfortably inside the limit below, while two
  // of the 17 whole groups exceed it. Pairs are the case this is built for
  // and also the common one — 144 of the corpus's 232 groups have exactly
  // two members.
  function godboltUrl(sources){
    if(typeof sources === "string") sources = [sources];
    var state = { sessions: sources.map(function(src, i){
      return { id: i + 1, language: "lua", source: src,
        compilers: [{ id: "lua547", options: "" }] };
    }) };
    // btoa is Latin1-only; encodeURIComponent/unescape is the standard
    // UTF-8-safe detour around that (Lua source can carry UTF-8 in
    // comments/strings). The result then needs the url-safe substitution
    // Compiler Explorer's own clientstate format documents.
    var b64 = btoa(unescape(encodeURIComponent(JSON.stringify(state))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    return ceBase() + "/clientstate/" + b64;
  }

  // Emits nothing at all unless `opts.godbolt` was set at generation time
  // — same "render nothing when not applicable" shape `docTrigger` above
  // already has, just gated by a build-time flag instead of runtime data.
  // The URL itself is *not* built here: constructing and base64-encoding a
  // clientstate JSON for every function/module on a large tree, on every
  // page load, for a link most readers will never click, would be
  // needless work — `kind`/`key` are carried on the element instead, and
  // the real URL is built once, lazily, in the click handler below.
  // Functions only. `kind` is kept on the element because the click handler
  // reads it, not because there is a second kind left to pass.
  //
  // The notice is a real box on hover and on focus, not a `title`. What it
  // has to say is that clicking sends this function's source to a third
  // party — a `title` tooltip is the wrong weight for that, it appears after
  // a delay, never appears for keyboard users, and cannot be read by anyone
  // who is deciding whether to click.
  function godboltTrigger(kind, key){
    if(!IR.meta.godbolt) return "";
    // The warning is rewritten, not merely relabelled, when the reader has
    // pointed this at their own instance. "Leaves your machine" is the whole
    // point of the notice and it is simply untrue of `localhost` — a warning
    // that cries wolf is one people learn to click past.
    var tip = ceIsLocal()
      ? '<b>Experimental — your own Compiler Explorer.</b> Opens ' + esc(ceBase()) +
        ' in a new tab with this function’s source and shows you real ' +
        '<code>luac</code> bytecode. Nothing leaves your machine, because that ' +
        'address is on it. Cleared in the Compare tab.'
      : '<b>Experimental — leaves your machine.</b> ' +
        'Opens Compiler Explorer in a new tab and hands it this function’s source, so ' +
        'godbolt.org compiles it and shows you real <code>luac</code> bytecode. The code ' +
        'travels inside the link itself: nothing is uploaded ahead of time and nothing is ' +
        'stored there. It is still someone else’s server, and this map has no other ' +
        'outbound request anywhere. The Compare tab is where you point this at a ' +
        'Compiler Explorer you run yourself instead.';
    return '<span class="godi-wrap"><a href="#" class="godi" data-godbolt="' + kind +
      '" data-godbolt-key="' + esc(key) + '">⚙ Compiler Explorer ↗</a>' +
      '<span class="godi-tip" role="note">' + tip + '</span></span>';
  }

  // Where a mention lives, and the line it sits on. Rendered into the same
  // card the annotation popup uses rather than a second floating thing with
  // its own lifecycle — one set of rules for one page.
  function docRefsHTML(key){
    var refs = DOCREFS[key] || [];
    var h = ['<div class="fn-sig">Mentioned in the docs<span class="fn-badges">' +
      '<span class="bd">' + refs.length + '</span></span></div>'];
    refs.forEach(function(r){
      h.push('<div class="docref">' +
        '<div class="docref-where">' + esc(r.doc) + ':' + r.line +
        (r.confidence === "heuristic"
          ? '<span class="bd" title="matched on a bare, tree-unique name">heuristic</span>'
          : '') +
        '</div>' +
        '<div class="docref-ctx">' + esc(r.context) + '</div></div>');
    });
    if(refs.more){
      h.push('<div class="fn-desc">… and ' + refs.more +
        ' more, not carried into the artifact.</div>');
    }
    return h.join("");
  }

  // Everything a function's annotations say, as HTML: signature line with
  // badges, deprecation, summary, params, returns, overloads, see-also,
  // example.
  //
  // Shared on purpose between the Tree tab's detail pane (which has always
  // rendered this) and the annotation popup (which is the whole reason this
  // was extracted). Two copies of "how a function's annotations look" is
  // exactly the drift this plugin exists to detect, and shipping one inside
  // it would be hard to defend — the same argument the `?` key-hint overlay
  // already makes for rendering from the same KEYS table it binds from.
  //
  // What deliberately stays with the caller: the `<div class="fn">` wrapper
  // and the Calls-view links, both of which only make sense in the detail
  // pane, where `callOut`/`callIn` counts and a stable per-function anchor
  // exist.
  // The owning scope, read from `fn.owner`/`fn.owner_kind` rather than from
  // the front of `fn.name`. That distinction is the whole of engine item M7:
  // a Python `Class.helper` written at module scope and a `helper` written
  // inside `class Class` have the identical qualified name, and only the
  // field separates them. Grouped here rather than baked into the artifact —
  // this is exactly the data the page already has, and a second copy in
  // `module_map.json` is one more thing that can disagree with itself.
  //
  // Returns `[freeFunctions, scopes]`, source order preserved in both.
  function groupByOwner(fns){
    var free = [], scopes = [], byName = {};
    (fns || []).forEach(function(fn){
      if(!fn.owner || !fn.owner_kind){ free.push(fn); return; }
      var sc = byName[fn.owner];
      if(!sc){ sc = { name: fn.owner, kind: fn.owner_kind, functions: [] };
        byName[fn.owner] = sc; scopes.push(sc); }
      sc.functions.push(fn);
    });
    return { free: free, scopes: scopes };
  }

  // A type as written in an annotation, with the class names in it as
  // triggers of the lookup layer (kind `type`). A name the map declares is
  // one; so is, in a map that carries no class details at all, a name spelled
  // like a LuaCATS class (`Docmap.Node`), where the card says that the
  // details are not known and why. Everything else stays plain text.
  //
  // `lang` is the language of the function the type belongs to, when the
  // caller knows it. The "not known" card names what would supply the
  // details, and that is LuaLS: for a `System.String` of a C# file the same
  // sentence would be advice that cannot work, so only Lua (or a caller that
  // does not know) gets the trigger.
  function typeHTML(text, lang){
    var out = "", last = 0, m;
    var re = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/g;
    var guess = !hasTypeDetail() && (!lang || lang === "lua");
    text = text || "";
    while((m = re.exec(text)) !== null){
      var name = m[0];
      var known = own(classByName, name);
      if(!known && (!guess || !/^[A-Z][A-Za-z0-9_]*\.[A-Za-z_]/.test(name))) continue;
      out += esc(text.slice(last, m.index)) + '<span class="kw" data-kw="' + esc(name) +
        '" data-kwkind="type" tabindex="0">' + esc(name) + '</span>';
      last = m.index + name.length;
    }
    return out + esc(text.slice(last));
  }

  // `key` (the function's `fnKey`) is optional: with it the `deprecated` and
  // `internal` badges can say who still calls the function.
  function fnAnnotationHTML(fn, key){
    var h = [];
    var lang = (key && own(fnByKey, key)) ? fnByKey[key].node.language : null;
    var badges = [];
    // The badges *are* the tags, so they are the third trigger surface of
    // the lookup layer (`ReferenceTab.md` § One layer, four trigger
    // surfaces). A reader who does not know what `nodiscard` promises is
    // looking straight at the word; sending them to a tab to find out is the
    // proximity failure that document warns about.
    //
    // `data-kw` rather than a second popup: the dwell timer, the grace
    // period on the way out, the keyboard path and the flip-when-it-would-
    // overflow positioning all already exist behind that attribute. A
    // tag-specific implementation would be a fourth copy of them.
    function tagBadge(name, label, cls){
      return '<span class="bd' + (cls ? " " + cls : "") + '" data-kw="' + name +
        '" data-kwkind="tag"' + (key ? ' data-kwctx="' + esc(key) + '"' : '') +
        ' tabindex="0">' + esc(label) + '</span>';
    }
    if(fn.deprecated !== undefined) badges.push(tagBadge("deprecated", "deprecated", "dep"));
    if(fn.async) badges.push(tagBadge("async", "async"));
    if(fn.nodiscard) badges.push(tagBadge("nodiscard", "nodiscard"));
    if(fn.internal) badges.push(tagBadge("internal", "internal", "sk-binding"));
    if(fn.since) badges.push(tagBadge("since", "since " + fn.since));
    // Visible from the list, not only once the function is opened — the
    // whole point of parsing @overload structurally instead of leaving
    // it as opaque text is to answer "does this have call variants" at a
    // glance, the same way "deprecated"/"async" already do.
    if(fn.overload && fn.overload.length){
      badges.push('<span class="bd">+'+fn.overload.length+' signature'
        +(fn.overload.length===1?'':'s')+'</span>');
    }
    // R2 — auto-derived, coarse and safe in the "tested" direction (see
    // coverage.lua). No badge for the false case: this is a "not found
    // by name in a spec" signal, not "definitely untested", and a
    // warning-shaped badge on the majority of functions would be noise,
    // not information.
    if(fn.tested) badges.push('<span class="bd tested">tested</span>');
    h.push('<div class="fn-sig">'+esc(fn.signature)
      +(badges.length?'<span class="fn-badges">'+badges.join("")+'</span>':'')+'</div>');
    if(fn.deprecated){ h.push('<div class="fn-dep">⚠ Deprecated: '+esc(fn.deprecated)+'</div>'); }
    if(fn.summary){ h.push('<div class="fn-desc">'+prose(fn.summary)+'</div>'); }
    if(fn.params && fn.params.length){
      h.push('<ul class="fn-plist">');
      fn.params.forEach(function(p){
        h.push('<li><code>'+esc(p.name)+(p.optional?'?':'')+'</code> '+typeHTML(p.type, lang)
          +(p.desc?' — '+esc(p.desc):'')+'</li>');
      });
      h.push('</ul>');
    }
    if(fn.returns && fn.returns.length){
      h.push('<ul class="fn-plist">');
      fn.returns.forEach(function(r){
        h.push('<li>→ <code>'+typeHTML(r.type, lang)+'</code>'+(r.name?' '+esc(r.name):'')
          +(r.desc?' — '+esc(r.desc):'')+'</li>');
      });
      h.push('</ul>');
    }
    if(fn.overload && fn.overload.length){
      h.push('<div class="fn-overloads"><div class="fn-ov-label">Also callable as</div>');
      fn.overload.forEach(function(ov){
        if(ov.params.length === 0 && ov.returns.length === 0 && !ov.raw.match(/^fun\s*\(\s*\)/)){
          // Did not parse as fun(...) — shown verbatim rather than as an
          // empty, misleading "fn.name()".
          h.push('<div class="fn-ov-raw">'+esc(ov.raw)+'</div>');
          return;
        }
        // An anonymous LuaCATS param (`fun(string)`, no `name:`) got the
        // placeholder name "_" from parse_overload — shown as its type
        // instead of a bare underscore, which would read as an actual
        // parameter called "_" rather than as "unnamed".
        var paramNames = ov.params.map(function(p){
          return (p.name === "_" ? p.type : p.name) + (p.optional?'?':'');
        });
        h.push('<div class="fn-ov-sig">'+esc(fn.name)+'('+paramNames.join(', ')+')</div>');
        if(ov.params.length){
          h.push('<ul class="fn-plist">');
          ov.params.forEach(function(p){
            h.push('<li><code>'+esc(p.name)+(p.optional?'?':'')+'</code> '+esc(p.type)+'</li>');
          });
          h.push('</ul>');
        }
        if(ov.returns.length){
          h.push('<ul class="fn-plist">');
          ov.returns.forEach(function(r){
            h.push('<li>→ <code>'+esc(r.type)+'</code></li>');
          });
          h.push('</ul>');
        }
      });
      h.push('</div>');
    }
    if(fn.see && fn.see.length){
      var seeLinks = fn.see.map(function(target){
        var targetId = seeIndex[target];
        return targetId
          ? '<a href="#" data-see-target="'+esc(targetId)+'">'+esc(target)+'</a>'
          : '<span title="unresolved">'+esc(target)+'</span>';
      });
      h.push('<div class="fn-desc fn-see">See also: '+seeLinks.join(", ")+'</div>');
    }
    if(fn.example){ h.push('<div class="fn-ex">'+exampleHTML(fn.example)+'</div>'); }
    return h.join("");
  }

  // The keyword lookup inside a rendered snippet.
  //
  // The page has shown source since `core/snippet.lua` existed; it just
  // never said anything about it. `IR.glossaries` carries one entry per
  // file extension (see `lang_registry.glossaries()`), and a backend that
  // ships none decorates nothing at all — which is the honest degradation.
  // Falling back to another language's keywords would explain `goto` in a
  // file where it means something else.
  //
  // The glossary is chosen by the *snippet's own* extension, not by the
  // page's or the reader's: a polyglot tree has Lua snippets and TS
  // snippets on the same screen, and each has to answer for itself.
  function glossaryForPath(path){
    if(!path || !IR.glossaries) return null;
    var m = /\.([A-Za-z0-9]+)$/.exec(path);
    if(!m) return null;
    return IR.glossaries[m[1].toLowerCase()] || null;
  }

  // The first two kinds of the lookup layer: a language keyword and a
  // standard-library name, both out of the glossary of the snippet's own
  // language. `null` when the glossary has no such entry: that is a bug in
  // whatever decorated the word, not something to show a card for.
  function glossaryAnswer(tableName){
    return function(key, ctx){
      var gl = glossaryForPath(ctx.path);
      var table = gl && gl[tableName];
      if(!own(table, key)) return null;
      var entry = table[key];
      return {
        word: key, summary: entry.summary, note: entry.note || null,
        // Where the name comes from, when it is not the language itself:
        // the reason `vim.*` entries can sit in a Lua glossary without
        // pretending to be Lua.
        origin: entry.origin || null,
        // Only for entries that *are* the language, and one base URL per
        // language rather than one per keyword. A `vim.*` name is not in the
        // Lua manual; a link there would look right and answer nothing.
        link: (!entry.origin && gl.reference && gl.reference.url)
          ? { href: gl.reference.url + (entry.anchor || ""), label: gl.reference.label }
          : null
      };
    };
  }
  lookupRegister("kw", glossaryAnswer("keywords"));
  lookupRegister("std", glossaryAnswer("stdlib"));

  // The tag catalogue as a lookup table, built once. Keyed by name without
  // the `@`, which is how the badges and the parser both spell it.
  var tagByName = null;
  function tagEntry(name){
    if(tagByName === null){
      tagByName = {};
      (IR.tags || []).forEach(function(t){ tagByName[t.name] = t; });
    }
    return own(tagByName, name) ? tagByName[name] : null;
  }

  // The third kind. Unlike keywords and stdlib names it has no per-language
  // glossary: an annotation means the same thing wherever it is written,
  // which is why the catalogue is one table and the glossaries are one per
  // language.
  //
  // On a `deprecated` or an `internal` badge of a function the card also
  // says what the tag means *here*: who still calls the function. That is
  // the question either tag raises, and the call edges already answer it.
  lookupRegister("tag", function(key, ctx){
    var tag = tagEntry(key);
    if(!tag) return null;
    var card = {
      word: "@" + tag.name, summary: tag.summary,
      origin: tag.origin === "luals" ? "LuaCATS annotation" : "this project's own convention",
      // Only where the origin publishes one. A LuaLS link for `@todo` would
      // load, look authoritative and not contain the answer.
      link: tag.url ? { href: tag.url, label: "LuaLS reference" } : null
    };
    var e = ctx.fnKey && own(fnByKey, ctx.fnKey) ? fnByKey[ctx.fnKey] : null;
    if(e && (key === "deprecated" || key === "internal")){
      if(!hasCallEdges(e.node)){
        card.lines = [{ label: "Callers", text: "not known (the map has no call edges for " +
          (e.node.language || "this language") + ")" }];
      } else {
        var callers = callPeers(ctx.fnKey, true);
        // An internal function is meant to be called from its own module;
        // the callers worth naming are the ones outside it.
        if(key === "internal"){
          callers = callers.filter(function(k){ return fnByKey[k] && fnByKey[k].node.id !== e.node.id; });
        }
        if(callers.length){
          card.rows = {
            title: key === "deprecated" ? "Still called by" : "Called from outside its module by",
            items: callers.map(function(k){
              var c = fnByKey[k];
              return c ? { code: c.fn.name, text: c.node.module || c.node.path } : { code: k };
            })
          };
        } else {
          card.lines = [{ label: "Callers", text: key === "deprecated"
            ? "nothing in this tree calls it any more"
            : "nothing outside its own module calls it" }];
        }
      }
    }
    return card;
  });

  // Which spans of a snippet are *not* code.
  //
  // A keyword decorated inside a string or a comment is a false positive:
  // the definition shown would be right and the context wrong, which is
  // worse than leaving it plain. So this skips those spans, driven by the
  // per-language delimiters in `glossary.syntax` rather than by a lexer per
  // language living here.
  //
  // Every known limit (Lua long brackets above level zero, JS template
  // interpolation, a regex literal containing comment-looking bytes) costs
  // a *missing* decoration rather than a wrong one. That is the direction
  // to fail in, and it is why this is allowed to be approximate at all.
  //
  // `ctx` is optional and names the function the snippet belongs to
  // (`{ fnKey }`). With it the tokenizer also marks what the IR knows about
  // this function's own text: the calls that resolve in the tree, its own
  // name, the external modules of its file and the paths it requires. Those
  // need no glossary, so a language without one gets them too; what it loses
  // is the skipping of strings and comments, and the call match is by line
  // and name, which a comment rarely satisfies by accident.
  function snipBodyHTML(src, path, ctx){
    var gl = glossaryForPath(path);
    var self = (ctx && ctx.fnKey && own(fnByKey, ctx.fnKey)) ? fnByKey[ctx.fnKey] : null;
    if((!gl || !gl.keywords) && !self) return esc(src);
    if(!gl) gl = {};
    var sx = gl.syntax || {};
    var strs = sx.strings || [];
    var out = "", plain = "", i = 0, n = src.length;

    // ---- what the IR knows about this function ----
    function bare(name){ return String(name).replace(/^.*[.:]/, ""); }
    var callees = {}, externals = {}, modules = {}, ownBare = null, ownDone = false;
    if(self){
      ownBare = bare(self.fn.name);
      (callOut[ctx.fnKey] || []).forEach(function(e){
        var b = bare(e.to_fn);
        if(!own(callees, b)) callees[b] = [];
        callees[b].push({ key: fnKey(e.to, e.to_fn), line: e.line });
      });
      (self.node.requires_external || []).forEach(function(m){
        modules[m] = true;
        if(!underOwnPrefix(m)) externals[m] = true;
      });
      (self.node.calls_external || []).forEach(function(c){
        if(!underOwnPrefix(c.module)) externals[c.module] = true;
      });
      (depOut[self.node.id] || []).forEach(function(d){ if(d.to_module) modules[d.to_module] = true; });
    }
    // The source line a position of the snippet is on (the snippet starts at
    // the function's own first line). Positions only ever grow.
    var lnPos = 0, lnNo = 0;
    function lineAt(pos){
      while(lnPos < pos){ if(src.charAt(lnPos) === "\n") lnNo++; lnPos++; }
      return lnNo;
    }
    function span(key, kind, label){
      return '<span class="kw" data-kw="' + esc(key) + '" data-kwkind="' + kind +
        '" tabindex="0">' + esc(label) + '</span>';
    }
    // Which callee a call written `name(` on this line is. The edge's own
    // line decides. An edge says where its call is, so the same name on a
    // line no edge names is some other `name`: a method of an object, a local
    // of that name, a call the scan could not resolve. Marking it would put a
    // real function's card on text that is not a call to it.
    //
    // Only a map whose edges of that name carry no line at all (an artifact
    // older than the field) falls back to the name, and then only when every
    // such edge leads to the same function.
    function calleeAt(name, pos){
      if(!own(callees, name)) return null;
      var list = callees[name], line = self.fn.line + lineAt(pos), k, lined = false;
      for(k = 0; k < list.length; k++){
        if(list[k].line === line) return list[k].key;
        if(typeof list[k].line === "number") lined = true;
      }
      if(lined) return null;
      for(k = 1; k < list.length; k++){ if(list[k].key !== list[0].key) return null; }
      return list[0].key;
    }

    function flush(){ if(plain){ out += esc(plain); plain = ""; } }
    function at(tok){ return tok && src.substr(i, tok.length) === tok; }

    while(i < n){
      if(at(sx.line_comment)){
        var eol = src.indexOf("\n", i);
        if(eol < 0) eol = n;
        plain += src.slice(i, eol); i = eol; continue;
      }
      var bc = sx.block_comment;
      if(bc && at(bc[0])){
        var close = src.indexOf(bc[1], i + bc[0].length);
        var stop = close < 0 ? n : close + bc[1].length;
        plain += src.slice(i, stop); i = stop; continue;
      }
      var str = null;
      for(var s = 0; s < strs.length; s++){
        if(at(strs[s][0])){ str = strs[s]; break; }
      }
      if(str){
        var j = i + str[0].length;
        while(j < n){
          if(sx.escape && src.charAt(j) === sx.escape){ j += 2; continue; }
          if(src.substr(j, str[1].length) === str[1]){ j += str[1].length; break; }
          j++;
        }
        if(j > n) j = n;
        // A string that is a `require`/`import` path: the fifth thing a
        // snippet can be asked about. Either the word before it says so, or
        // the map knows the name as a module this file requires.
        var body = src.slice(i + str[0].length, j - str[1].length);
        if(self && j - str[1].length >= i + str[0].length &&
           src.substr(j - str[1].length, str[1].length) === str[1] &&
           /^[A-Za-z0-9_@.\/:-]+$/.test(body) &&
           (own(modules, body) ||
            /(?:^|[^A-Za-z0-9_])(?:require|import|from)\s*\(?\s*$/.test(src.slice(Math.max(0, i - 24), i)))){
          plain += str[0];
          flush();
          out += span(body, "req", body);
          plain += str[1];
          i = j; continue;
        }
        plain += src.slice(i, j); i = j; continue;
      }
      var ch = src.charAt(i);
      if(/[A-Za-z_]/.test(ch)){
        // The whole dotted run, not just the first identifier: a stdlib entry
        // is `table.concat`, and stopping at `table` would look up a word
        // that means nothing on its own. Consumed once, then matched
        // longest-first below.
        var k = i;
        while(k < n && /[A-Za-z0-9_]/.test(src.charAt(k))) k++;
        while(k + 1 < n && src.charAt(k) === "." && /[A-Za-z_]/.test(src.charAt(k + 1))){
          k++;
          while(k < n && /[A-Za-z0-9_]/.test(src.charAt(k))) k++;
        }
        var run = src.slice(i, k);

        // `hasOwnProperty` rather than a truthiness test: a glossary is a
        // plain object from JSON, so a word like "constructor" would
        // otherwise find Object.prototype's own member and decorate an entry
        // that does not exist.
        function has(table, key){
          return table && Object.prototype.hasOwnProperty.call(table, key);
        }

        // Longest prefix wins: `vim.treesitter.query.parse` beats
        // `vim.treesitter`, which beats nothing. A shorter match on a longer
        // run would explain the namespace while the reader pointed at the
        // function.
        var parts = run.split(".");
        var matched = null, kind = null, label = null;

        // `s:gsub(...)` is `string.gsub`, and in real Lua it is the common
        // spelling by two orders of magnitude. The receiver's type is
        // unknowable here, so this is deliberately narrow: a *declared*
        // namespace, a single word, and only names that namespace actually
        // has. An object of one's own with a `:format` method gets the
        // string card, which is the price -- and the same direction of error
        // the rest of this tokenizer accepts: an entry that exists, on text
        // that may not be it, never an invented one.
        //
        // `::label::` is not a method call, hence the second look back.
        if(sx.method_namespace && parts.length === 1 && i > 0 &&
           src.charAt(i - 1) === ":" && src.charAt(i - 2) !== ":"){
          var viaColon = sx.method_namespace + "." + run;
          if(own(gl.stdlib, viaColon)){
            matched = viaColon; kind = "std"; label = run;
          }
        }

        for(var take = parts.length; take >= 1 && !matched; take--){
          var candidate = parts.slice(0, take).join(".");
          if(has(gl.stdlib, candidate)){ matched = candidate; kind = "std"; }
          // A keyword is a bare word by definition, so only the whole run
          // can be one -- `end` in `foo.end` is not Lua at all.
          else if(take === parts.length && take === 1 && has(gl.keywords, candidate)){
            matched = candidate; kind = "kw";
          }
        }

        if(matched){
          flush();
          // The decorated text is not always the key: a colon call shows
          // `gsub` and answers about `string.gsub`.
          if(label === null) label = matched;
          // The undecorated tail (`.parse` when only `vim.treesitter`
          // matched) is emitted plain rather than swallowed into the span:
          // the card would otherwise claim to describe text it does not.
          out += '<span class="kw" data-kw="' + esc(matched) + '" data-kwkind="' + kind +
            '" tabindex="0">' + esc(label) + '</span>';
          plain += run.slice(label.length);
        } else if(self){
          // Nothing of the language itself: ask the IR. The function's own
          // name where it is declared, then a call that resolves in the
          // tree, then an external module of this file.
          var lastSeg = parts[parts.length - 1], after = k, hit = null;
          while(after < n && /[ \t]/.test(src.charAt(after))) after++;
          if(!ownDone && lineAt(i) <= 2 && (run === self.fn.name || lastSeg === ownBare)){
            ownDone = true;
            hit = span(ctx.fnKey, "fn", run);
          } else if(src.charAt(after) === "(" && calleeAt(lastSeg, i)){
            hit = span(calleeAt(lastSeg, i), "call", run);
          }
          if(hit){
            flush(); out += hit;
          } else {
            var extName = null;
            for(var cut = parts.length; cut >= 1 && !extName; cut--){
              var prefix = parts.slice(0, cut).join(".");
              if(own(externals, prefix)) extName = prefix;
            }
            if(extName){
              flush();
              out += span(extName, "ext", extName);
              plain += run.slice(extName.length);
            } else {
              plain += run;
            }
          }
        } else {
          plain += run;
        }
        i = k; continue;
      }
      plain += ch; i++;
    }
    flush();
    return out;
  }

  // The bounded source snippet, popup-only — deliberately **not** folded
  // into `fnAnnotationHTML` above, unlike everything else that function
  // renders. That function is shared with the Tree tab's detail pane, which
  // already lists every function of a node in full; a node with a few dozen
  // functions each carrying up to 40 lines of source would turn that pane
  // into mostly code, for a question ("what does this look like") the
  // pane's own click-through to source already answers one step away. The
  // popup is a different reading task — one function, inspected without
  // navigating — where the tradeoff runs the other way. See
  // `docs/ecosystem.md` §3.5 for the "bounded snippet, embeddable tier"
  // this implements.
  function snippetHTML(fn, node){
    if(!fn.snippet) return "";
    var omitted = fn.snippet_omitted
      ? ' <span class="bd" title="truncated — not carried into the artifact">+' +
        fn.snippet_omitted + ' more line' + (fn.snippet_omitted === 1 ? '' : 's') + '</span>'
      : '';
    // The path rides on the container rather than on every keyword span:
    // one attribute per snippet instead of one per word, and the lookup
    // walks up to it, which is what `.closest` is for.
    var path = node ? (node.source || node.path || "") : "";
    return '<div class="fn-snip-label">Source' + omitted + '</div>' +
      '<div class="fn-snip" data-path="' + esc(path) + '"' +
      (node ? ' data-fnkey="' + esc(fnKey(node.id, fn.name)) + '"' : '') + '>' +
      snipBodyHTML(fn.snippet, path, node ? { fnKey: fnKey(node.id, fn.name) } : null) + '</div>';
  }

  // Artifact lives in out_dir; repo-relative paths need to climb back out.
  function rel(p){ return (IR.meta.out_depth ? "../".repeat(IR.meta.out_depth) : "") + p; }

  // =====================================================================
  // State + history
  //
  // One object describes everything the page can be showing:
  //   { tab: "tree"|"hierarchy", id: <selected tree node>,
  //     center: <hierarchy centered node>,
  //     view: "modules"|"types"|"deps"|"calls",
  //     dir: "out"|"in"|"both",   — deps/calls only: follow edges forwards
  //                                 (what this needs), backwards (what needs
  //                                 this), or both around the center
  //     depth: 1|2|3|0,           — 0 means unbounded, still capped by MAX_HNODES
  //     fn: "<node id>#<name>" }  — calls view centered on one function
  //
  // Direction is an axis rather than two more views on purpose: "callers of X"
  // and "callees of X" are the same diagram walked the other way, and making
  // them separate views would have doubled the view list to four buttons
  // saying almost the same thing.
  //
  // navigate(patch) is the single entry point every discrete click handler
  // calls; it merges the patch into current state, updates the DOM, and
  // pushes a real history entry so the browser Back/Forward buttons step
  // through actual states instead of only reacting to a directly-edited
  // hash. Every axis above goes through it — a control that set `dir` or
  // `depth` behind its back would produce a diagram the Back button cannot
  // return from. Live preview while typing in the Hierarchy search box is the
  // one deliberate exception — see the "input" listener below for why going
  // through history.replaceState there was a real bug, not just an
  // unnecessary one.
  // =====================================================================
  var DEFAULT_STATE = {
    tab: "hierarchy", id: null, center: null, view: "modules",
    dir: "out", depth: 2, fn: null, ext: false, iview: "functions", atool: "test",
    sha: null,
    // Modules view only: how many top layers of the real tree are peeled
    // off, so every node that used to sit at that depth renders as its own
    // parallel root instead — a "forest" view, not a re-center on any one
    // of them (that's what `center` already does). Mutually exclusive with
    // `center` in practice — see `navigate()`'s own note on why setting one
    // clears the other.
    hideroot: 0,
    // The tint of the Modules view: null (off, the default), "doc", "test",
    // "fix" or "debt" (see the Tint section of the maps slice).
    tint: null,
    // The shape diff of the Hierarchy tab: null (off), or the two maps being
    // compared as `<older sha>` (against this map) or `<older>..<newer>`.
    cmp: null,
    // Analysis sort. `null` means "this panel's own default order", which is
    // deliberately not spelled as an explicit column: each panel's default is
    // an editorial choice (worst coverage first, highest fan-in first) that a
    // named column would flatten into "sorted by pct, descending" and lose the
    // tiebreaks with it.
    asort: null, adir: null,
    // Which capture the Telemetry panel's single-view table reads: `null`
    // means the live aggregate ("Latest"), otherwise a snapshot name.
    // `tsnapb` is set only in compare mode — `null` means "not comparing",
    // the string `"latest"` means "compare against the live aggregate
    // explicitly", anything else is a second snapshot name.
    tsnap: null, tsnapb: null,
    // Which persisted runtime-analysis.loaded snapshot the Loaded panel
    // reads. `null` means "none selected yet" —
    // unlike Telemetry there is no live aggregate to fall back to here
    // (see drawAnalysisLoaded's own header for why), so a picker with
    // nothing chosen shows a prompt rather than data.
    lsnap: null,
    // Per-tab text filter. One field, but the *contract* is per tab — see
    // `filterFor`.
    q: null,
    // Compare layout. "matrix" is the default because it is the layout that
    // earns the feature: two annotation cards side by side is something two
    // browser windows already do, whereas "which of these four differ, and
    // where" has no other answer on this page.
    cview: "matrix",
    // Marked objects, as `"<node id>"` or `"<node id>#<fn>"` — the same key
    // scheme `fnKey` and `quicks.evidence` use. In the hash so a comparison
    // set is shareable, which is the same promise every other view on this
    // page makes; also mirrored into localStorage, because a mark collected
    // while reading should survive the regenerate that follows.
    marks: [],
    // Dimmed Hierarchy boxes — same key scheme `hboxes` uses (node id, class
    // name, or `fnKey`), unlike `marks` not unified with it since the two
    // answer different questions. Hierarchy-scoped in the hash (see
    // `serializeState`'s hierarchy branch), unlike `marks`, which is
    // deliberately global — a dimmed box only exists inside the Hierarchy
    // tab, so carrying it into a Tree-tab link would be noise no other
    // hierarchy axis (`dir`/`depth`/`ext`) is allowed to add either.
    hidden: []
  };
  // Both are arrays, so a shared reference would let one state's edits reach
  // every other state object built from the same default — including the
  // one `parseState` starts from on every popstate.
  function freshState(){
    var s = Object.assign({}, DEFAULT_STATE);
    s.marks = [];
    s.hidden = [];
    return s;
  }

  var state = freshState();
  // Tracks only the hash of the last *pushed* entry — deliberately never
  // touched by a replace. Search-as-you-type replaces the current entry on
  // every keystroke; without this separation, typing to a match and then
  // pressing Enter to commit it would compute the same resulting hash the
  // last replace already wrote, and a single "skip if hash unchanged" guard
  // would then suppress the deliberate push entirely — Enter would silently
  // do nothing. Keeping the two trackers apart means a push always executes
  // unless the *previous push* (not the previous replace) had that hash.
  var lastPushedHash = null;

  // Only axes that matter for the current view are serialized: a Tree-tab URL
  // carrying dir/depth/view would be three pieces of noise in every link
  // anyone shares, and a Modules-view URL carrying `dir` would suggest a
  // control that view does not have.
  function isGraphView(v){ return v === "deps" || v === "calls" || v === "modulecalls"; }

  function serializeState(s){
    var parts = ["tab=" + encodeURIComponent(s.tab)];
    if(s.tab === "tree"){
      if(s.id) parts.push("id=" + encodeURIComponent(s.id));
    } else if(s.tab === "notes"){
      // Nothing else to carry: a flat aggregate over the whole map, with no
      // center, view or direction to remember. Falling through to the
      // hierarchy branch would put a `view=modules` in every shared link that
      // means nothing there.
      void 0;
    } else if(s.tab === "index"){
      // One axis, not the hierarchy branch's whole set: R3's Functions/
      // Modules toggle, omitted when it is the default so the common case
      // stays a bare `#tab=index` link.
      if(s.iview === "modules") parts.push("iview=modules");
    } else if(s.tab === "analysis"){
      // Same rule, Analysis's own axes: which tool panel is open, and how it
      // is sorted. Both omitted at their defaults so the common case stays a
      // bare `#tab=analysis` link.
      if(s.atool !== "test") parts.push("atool=" + encodeURIComponent(s.atool));
      if(s.asort){
        parts.push("asort=" + encodeURIComponent(s.asort));
        parts.push("adir=" + encodeURIComponent(s.adir === "asc" ? "asc" : "desc"));
      }
      // Telemetry's own two axes — which capture, and what it is compared
      // against — only meaningful on that one panel, same as asort/adir are
      // scoped to whichever panel is actually sortable.
      if(s.tsnap) parts.push("tsnap=" + encodeURIComponent(s.tsnap));
      if(s.tsnapb) parts.push("tsnapb=" + encodeURIComponent(s.tsnapb));
      if(s.lsnap) parts.push("lsnap=" + encodeURIComponent(s.lsnap));
      if(s.q) parts.push("q=" + encodeURIComponent(s.q));
    } else if(s.tab === "history"){
      // The opened commit, so a link to one is shareable. Validated on the
      // way back in — the server validates it again before it reaches git,
      // but a hash is user input and the fetch URL is built from it here.
      if(s.sha) parts.push("sha=" + encodeURIComponent(s.sha));
    } else if(s.tab === "quicks"){
      // Nothing to carry: one flat verdict list over the whole map, same as
      // Notes.
      void 0;
    } else if(s.tab === "features"){
      // One axis: which theme file is showing. Left out when it is the
      // first one, so the common case stays a bare `#tab=features` link.
      if(s.ftheme && s.ftheme === featureTheme(s) && s.ftheme !== featureTheme(null)){
        parts.push("ftheme=" + encodeURIComponent(s.ftheme));
      }
    } else if(s.tab === "compare"){
      if(s.cview !== "matrix") parts.push("cview=" + encodeURIComponent(s.cview));
    } else if(s.tab && s.tab.indexOf("feature-") === 0){
      // A promoted feature's own tab: same reasoning as Features itself —
      // one flat page over one feature, no axis of its own to carry. Caught
      // here rather than falling into the hierarchy branch below, which
      // would otherwise stamp a meaningless `view=modules` onto every link
      // to one of these tabs.
      void 0;
    } else {
      if(s.center) parts.push("center=" + encodeURIComponent(s.center));
      parts.push("view=" + encodeURIComponent(s.view || "modules"));
      // Orientation, and only when it is not the default — the common case
      // stays the link this page has always produced. It belongs to every
      // graph view, unlike `dir`/`depth`, because every one of them is
      // laid out in layers.
      if(s.hdir === "lr") parts.push("hdir=lr");
      // Modules only, same "only where it applies" rule as `ext` below —
      // Deps/Calls/Module Calls/Types/Inheritance have no notion of a
      // directory root to peel layers off of.
      if((s.view || "modules") === "modules" && s.hideroot) {
        parts.push("hideroot=" + encodeURIComponent(String(s.hideroot)));
      }
      // The tint is an encoding of the Modules view; off is the default and
      // stays out of the link.
      if((s.view || "modules") === "modules" && s.tint) parts.push("tint=" + encodeURIComponent(s.tint));
      if(isGraphView(s.view)){
        parts.push("dir=" + encodeURIComponent(s.dir || "out"));
        parts.push("depth=" + encodeURIComponent(String(s.depth === 0 ? 0 : (s.depth || 2))));
      }
      // Only when on, and only where it applies: an "ext=0" in every Deps
      // link would be noise in the common case.
      if((s.view === "deps" || s.view === "modulecalls") && s.ext) parts.push("ext=1");
      if(s.view === "calls" && s.fn) parts.push("fn=" + encodeURIComponent(s.fn));
      // The Tree view's filter and the Treemap's measure, each only in its
      // own view and only when set.
      if(s.view === "tree" && s.tq) parts.push("tq=" + encodeURIComponent(s.tq));
      if(s.view === "treemap" && s.tm === "functions") parts.push("tm=functions");
      // Hierarchy-scoped, unlike `marks` below: a dimmed box only exists in
      // this tab, so a Tree-tab link carrying `hidden=` would name a control
      // that link's own view does not have — the same rule `dir`/`depth`/
      // `ext`/`fn` above already follow.
      if(s.hidden && s.hidden.length) parts.push("hidden=" + encodeURIComponent(s.hidden.join(",")));
      // The comparison belongs to this tab's diagram and to every view of it.
      if(s.cmp) parts.push("cmp=" + encodeURIComponent(s.cmp));
    }
    // Outside the per-tab branches, unlike every other axis: marks are
    // collected while reading any tab and belong to the reader, not to a view.
    // Only when non-empty, so the common case is not a link with a trailing
    // `&marks=` in it.
    if(s.marks && s.marks.length) parts.push("marks=" + encodeURIComponent(s.marks.join(",")));
    return "#" + parts.join("&");
  }

  function parseState(hash){
    var s = freshState();
    var raw = (hash || "").replace(/^#/, "");
    if(!raw) return s;
    // A bare node id with no "=" is the pre-existing #<id> scheme (also what
    // a hand-typed or externally shared link looks like) — treat it as
    // "select this node in the Tree tab".
    if(raw.indexOf("=") === -1){
      s.id = decodeURIComponent(raw);
      return s;
    }
    raw.split("&").forEach(function(kv){
      var i = kv.indexOf("=");
      if(i < 0) return;
      var k = kv.slice(0, i), v = decodeURIComponent(kv.slice(i + 1));
      if(k === "tab") s.tab = v;
      else if(k === "id") s.id = v;
      else if(k === "center") s.center = v;
      else if(k === "view") s.view = v;
      else if(k === "dir") s.dir = (v === "in" || v === "both") ? v : "out";
      // Anything unparseable falls back to the default rather than to NaN,
      // which would make every BFS below terminate immediately and draw an
      // empty diagram for a URL that merely had a typo in it.
      else if(k === "depth"){ var d = parseInt(v, 10); s.depth = isNaN(d) ? 2 : d; }
      // Clamped against the real tree at layout time (layoutModulesRooted),
      // not here — maxRootDepth() reads IR, which parseState has no need to
      // depend on. A negative or unparseable value falls back to 0 (the
      // ordinary single-root case) rather than to NaN, same reasoning as
      // `depth` above.
      else if(k === "hideroot"){ var hr = parseInt(v, 10); s.hideroot = (isNaN(hr) || hr < 0) ? 0 : hr; }
      else if(k === "fn") s.fn = v;
      // An unknown tint is no tint: a link with a typo opens the plain view.
      else if(k === "tint") s.tint = (v === "doc" || v === "test" || v === "fix" || v === "debt") ? v : null;
      else if(k === "ext") s.ext = (v === "1" || v === "true");
      // Anything that is not one or two commit hashes is no comparison.
      else if(k === "cmp") s.cmp = shapeSpec(v);
      else if(k === "iview") s.iview = (v === "modules") ? "modules" : "functions";
      // Checked where it is used (`featureTheme`): a theme that no longer
      // exists opens the first one.
      else if(k === "ftheme") s.ftheme = v;
      else if(k === "atool") s.atool = (v === "doc" || v === "deps" || v === "complexity" ||
        v === "duplicates" || v === "plugins" || v === "lazy" || v === "tools" || v === "hooks" ||
        v === "decorators" || v === "rust" ||
        v === "checklist" || v === "api" || v === "annotations" ||
        v === "docs" || v === "endpoints" || v === "telemetry" || v === "loaded" ||
        v === "startup" ||
        v === "bindings") ? v : "test";
      // Snapshot names are whatever runtime-analysis.telemetry's own
      // sanitizer allowed through when saved — not re-validated here, the
      // same posture `sha`/`q` already take: a value that does not
      // actually name a saved snapshot just gets "snapshot not found" back
      // from `/api/telemetry`, not silently dropped before it can ask.
      // Orientation. Anything but "lr" is top-down, so an old link and a
      // typo land in the same place — the one this page has always had.
      else if(k === "hdir") s.hdir = (v === "lr") ? "lr" : null;
      else if(k === "tsnap") s.tsnap = v || null;
      else if(k === "tsnapb") s.tsnapb = v || null;
      // Same posture as tsnap/tsnapb: a snapshot name runtime-analysis.
      // loaded's own sanitizer allowed through when saved, not
      // re-validated here — an invalid one just gets "snapshot not found"
      // back from /api/loaded.
      else if(k === "lsnap") s.lsnap = v || null;
      // Not whitelisted against a column list here, because the valid columns
      // differ per panel and this parser does not know which panel `atool`
      // will resolve to. `anSort` looks the key up in the panel's own column
      // spec and falls back to the default order when it does not match — so
      // an unknown value degrades to "the normal view", not to a broken one.
      else if(k === "asort") s.asort = v || null;
      else if(k === "adir") s.adir = (v === "asc") ? "asc" : "desc";
      else if(k === "q") s.q = v || null;
      else if(k === "tq") s.tq = v || null;
      else if(k === "tm") s.tm = (v === "functions") ? "functions" : null;
      // Validated here, not just at the server: this value is interpolated
      // into a fetch URL, and the same whitelist the server applies before it
      // reaches git is the right shape to demand of a hash too. Anything else
      // is dropped rather than sanitized.
      else if(k === "sha") s.sha = /^[0-9a-f]{7,40}$/.test(v) ? v : null;
      else if(k === "cview") s.cview = (v === "columns" || v === "stacked") ? v : "matrix";
      // Filtered against what this map actually contains, not taken on trust.
      // A shared link outlives the tree it was made from: rename a module and
      // yesterday's comparison URL names keys that no longer resolve. Dropping
      // them here means the surviving ones still open, instead of the page
      // rendering a row of "unknown" cards — the same tolerance `fnByKey`
      // already extends to a stale `data-sig`.
      else if(k === "marks"){
        s.marks = v.split(",").filter(function(key){ return key && markExists(key); });
      }
      else if(k === "hidden"){
        s.hidden = v.split(",").filter(function(key){ return key && hiddenKeyExists(key); });
      }
    });
    return s;
  }

  // Applies `s` to the DOM. `push` controls history: true adds a Back-stack
  // entry (every discrete navigate() call), false replaces the current entry
  // in place (restoring state after a popstate, and the very first load —
  // neither should itself create a Back-stack entry). Never mutates `state`
  // directly outside this function, so `state` always reflects exactly what
  // is on screen.
  function applyState(s, push){
    // A promoted feature's tab id is content-derived and can disappear
    // across a regenerate (renamed, un-promoted, its theme file deleted) —
    // unlike the other nine, permanent tabs. A bookmarked or shared link to
    // one that no longer resolves falls back to the Features catalog rather
    // than leaving every `.view` panel inactive and the page blank.
    if(s.tab && s.tab.indexOf("feature-") === 0 &&
       !collectPromotedFeatures().some(function(p){ return p.slug === s.tab; })){
      s.tab = "features";
    }
    state = s;

    var group = topTab(s.tab);
    document.querySelectorAll(".tab-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.tab === group);
    });
    renderSubTabs(s);
    document.getElementById("view-tree").classList.toggle("active", s.tab === "tree");
    document.getElementById("view-hierarchy").classList.toggle("active", s.tab === "hierarchy");
    document.getElementById("view-notes").classList.toggle("active", s.tab === "notes");
    document.getElementById("view-index").classList.toggle("active", s.tab === "index");
    document.getElementById("view-analysis").classList.toggle("active", s.tab === "analysis");
    document.getElementById("view-history").classList.toggle("active", s.tab === "history");
    document.getElementById("view-findings").classList.toggle("active", s.tab === "findings");
    document.getElementById("view-quicks").classList.toggle("active", s.tab === "quicks");
    document.getElementById("view-compare").classList.toggle("active", s.tab === "compare");
    document.getElementById("view-features").classList.toggle("active", s.tab === "features");
    document.querySelectorAll('[id^="view-feature-"]').forEach(function(v){
      v.classList.toggle("active", v.id === "view-" + s.tab);
    });

    if(s.tab === "tree" && s.id && byId[s.id]) selectRow(s.id);
    if(s.tab === "hierarchy") drawHierarchy(s.center || IR.root, s.view || "modules", false, !s.center);
    if(s.tab === "notes") drawNotes();
    if(s.tab === "index") drawIndex();
    if(s.tab === "analysis") drawAnalysis();
    if(s.tab === "history") drawHistory(s.sha || null);
    if(s.tab === "quicks") drawQuicks();
    if(s.tab === "compare") drawCompare();
    if(s.tab === "features") drawFeatures();
    if(s.tab && s.tab.indexOf("feature-") === 0) drawFeatureTab(s.tab);
    // After the draw, not before: a redraw rebuilds the rows that carry the
    // mark triggers, so painting them first would paint elements about to be
    // replaced.
    syncMarks();
    syncHidden();
    syncLangFilter();
    syncShape(s);
    syncGraphControls(s);
    syncSearchBox(s);

    var hash = serializeState(s);
    if(push){
      if(hash !== lastPushedHash){
        history.pushState(s, "", hash);
        lastPushedHash = hash;
      }
    } else {
      history.replaceState(s, "", hash);
    }

    postContext(s);
  }

  // A host embedding this page in an iframe (docmap-desktop is the first —
  // `src-tauri/src/server.rs` serves it over a real origin specifically so
  // this has somewhere to go) has no other way to know which panel is on
  // screen: `history.pushState` above only updates *this* page's own
  // session history, invisible outside it, and a `<button>` inside this
  // panel could not act on the embedding app regardless (a browser page
  // cannot reach into a Tauri window's own process — the same category
  // error `docs/ecosystem.md` already names for the reverse direction).
  // `postMessage` is the one channel that crosses the iframe boundary in
  // either direction.
  //
  // Coarse on purpose — `tab`/`atool`/`view` only, not the full state
  // object: a host reacting to "which panel" does not need `center`,
  // `depth`, or any of the dozen other keys the URL hash already carries,
  // and sending them would make this page's own internal state shape part
  // of a cross-origin contract other code depends on.
  //
  // `"*"` as the target origin, not this page's own: the parent's origin
  // (`tauri://…`, `file://`, whatever embeds this) is not something a page
  // that does not know it is embedded can predict, and every value sent is
  // already public — it is exactly what the URL bar of this page itself
  // would show.
  var lastPostedContext = null;
  function postContext(s){
    if(window.parent === window) return;
    var ctx = { source: "docmap", tab: s.tab || null, atool: s.atool || null, view: s.view || null };
    var key = ctx.tab + "|" + ctx.atool + "|" + ctx.view;
    if(key === lastPostedContext) return;
    lastPostedContext = key;
    try { window.parent.postMessage(ctx, "*"); } catch(e){ /* no listening host, or postMessage unavailable — silent, same as no host at all */ }
  }

  ///Apply `patch` over the current state.
  ///
  ///`opts.push === false` replaces the current history entry instead of adding
  ///one — for changes that happen per keystroke, where one Back-stack entry
  ///per character would make the Back button useless.
  function navigate(patch, opts){
    // Centering on a specific node and hiding root levels are two different
    // answers to "what does the Modules view show" — picking one has to
    // clear the other, or double-clicking a box while a forest view is up
    // would appear to do nothing (still covered by every other root's own
    // subtree), and dragging the slider after centering somewhere would
    // leave a stale `center` sitting in the URL that the forest layout
    // never even reads. Centralized here rather than at each of the dozen
    // call sites that set one or the other, so none of them has to
    // remember to.
    if(patch.center !== undefined && patch.hideroot === undefined){
      patch = Object.assign({}, patch, { hideroot: 0 });
    } else if(patch.hideroot !== undefined && patch.center === undefined){
      patch = Object.assign({}, patch, { center: null });
    }
    applyState(Object.assign({}, state, patch), !(opts && opts.push === false));
  }

  window.addEventListener("popstate", function(ev){
    applyState(ev.state || parseState(location.hash), false);
    // Back or Forward moved to another entry, so "the last push" is no
    // longer the entry on top: the guard in `applyState` has to compare with
    // the entry landed on. Left as it was, going A -> B, Back, and to B
    // again drew B and pushed nothing, and the address bar kept saying A.
    lastPushedHash = serializeState(state);
  });

]]
