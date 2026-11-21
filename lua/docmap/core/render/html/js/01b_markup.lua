---@module 'docmap.core.render.html.js.01b_markup'
--- A slice of the page's script: the one place that turns the page's own markup strings into DOM nodes.
---
--- Not a script of its own: the slices are joined in order inside one function (see `html/js/init.lua`), so a
--- slice may use what an earlier one declared and may stop between two statements.

return [[
  // =====================================================================
  // Markup to nodes, without a string ever reaching a parser of the browser.
  //
  // The page builds most of its panels as strings of its own fixed fragments (`'<div class="x">' + esc(name) +
  // '</div>'`). Assigning such a string to `innerHTML` is a Trusted Types sink: under
  // `Content-Security-Policy: require-trusted-types-for 'script'` the browser refuses it, and so it refuses
  // `DOMParser`, `Range.createContextualFragment` and `template.innerHTML`, which are sinks too. A policy that
  // waves strings through would only move the sink; this is the other way: a small reader for exactly the
  // markup the page writes, which builds the nodes with `createElement`, `setAttribute` and `createTextNode`.
  //
  // What that means for a text from a project file (a module name, a path, a comment, a finding):
  //   * it reaches the markup only through `esc` (or the helpers built on it), so every `<` in it is `&lt;`;
  //   * this reader turns `&lt;` into a character of a text node, never into a tag: no text of a project is
  //     ever read as markup, whatever the callers do with it;
  //   * it builds no `script`, `style`, `iframe`, `object`, `embed`, `link`, `meta` or `base` element, no
  //     `on...` attribute, no `srcdoc`, and no link whose target is a `javascript:` or `vbscript:` URL.
  //
  // What it reads: elements (HTML and, below an `<svg>`, SVG), quoted and bare attributes, character
  // references (`&amp;`, `&#43;`, `&#x2B;` and the few names the page uses), comments, and the end tags the
  // HTML parser implies for `p`, `li`, `td`/`th`, `tr`, the table sections and `option`, so a fragment such
  // as `<table><tr>…` reads as the browser read it (a `tbody` is inserted).
  // =====================================================================
  var MK_VOID = { area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1, link: 1, meta: 1, source: 1, track: 1, wbr: 1 };
  var MK_UNSAFE = { script: 1, style: 1, iframe: 1, frame: 1, frameset: 1, object: 1, embed: 1, link: 1, meta: 1, base: 1, applet: 1, noscript: 1 };
  var MK_ENT = {
    amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", times: "×", mdash: "—",
    ndash: "–", middot: "·", rarr: "→", larr: "←", hellip: "…", laquo: "«", raquo: "»"
  };
  var MK_P_CLOSERS = {
    address: 1, article: 1, aside: 1, blockquote: 1, details: 1, div: 1, dl: 1, fieldset: 1, footer: 1, form: 1,
    h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, header: 1, hr: 1, main: 1, nav: 1, ol: 1, p: 1, pre: 1,
    section: 1, table: 1, ul: 1
  };
  var MK_SCOPE_STOP = { table: 1, td: 1, th: 1, button: 1, caption: 1, template: 1, svg: 1, foreignObject: 1 };
  var MK_URL_ATTR = { href: 1, src: 1, "xlink:href": 1, action: 1, formaction: 1, data: 1, poster: 1 };
  var SVG_NS = "http://www.w3.org/2000/svg";

  function mkDecode(s){
    if(s.indexOf("&") < 0) return s;
    return s.replace(/&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([a-zA-Z][a-zA-Z0-9]*));/g, function(whole, dec, hex, name){
      if(name !== undefined) return Object.prototype.hasOwnProperty.call(MK_ENT, name) ? MK_ENT[name] : whole;
      var cp = dec !== undefined ? parseInt(dec, 10) : parseInt(hex, 16);
      if(!(cp > 0 && cp <= 0x10ffff) || (cp >= 0xd800 && cp <= 0xdfff)) return "�";
      return String.fromCodePoint(cp);
    });
  }

  // `<name attr="v" attr='v' attr=v attr>` starting at `from` (just past `<`): the tag, or null when it is
  // not a tag (a bare `<` in a text).
  var MK_TAG = /^(\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:\s+[^\s"'>\/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'>]+))?|\s*\/(?!>))*)\s*(\/?)>/;
  var MK_ATTR = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;

  function mkSafeAttr(name, value){
    var n = name.toLowerCase();
    if(n.slice(0, 2) === "on" || n === "srcdoc") return false;
    if(MK_URL_ATTR[n]){
      var probe = value.replace(/[\u0000- \u007f-\u009f]/g, "").toLowerCase();
      if(/^(javascript|vbscript|data:text\/html)/.test(probe)) return false;
    }
    return /^[a-zA-Z_:][-a-zA-Z0-9_:.]*$/.test(name);
  }

  // The nodes of `html` as a DocumentFragment. `host` is the element they are meant for: its namespace says
  // whether the markup starts out as SVG (the page sets text into `<g>` and `<text>` of its diagrams).
  function markupNodes(html, host){
    var frag = document.createDocumentFragment();
    var stack = [{ node: frag, name: "#root", svg: !!(host && host.namespaceURI === SVG_NS && host.localName !== "foreignObject") }];
    var s = String(html == null ? "" : html);
    var pos = 0;

    function top(){ return stack[stack.length - 1]; }
    function text(str){
      if(str === "") return;
      top().node.appendChild(document.createTextNode(mkDecode(str)));
    }
    // Close elements down to (and including) the nearest open `names`, but never across a scope stop.
    function closeIn(names){
      for(var i = stack.length - 1; i > 0; i--){
        var nm = stack[i].name;
        if(names[nm]){ stack.length = i; return true; }
        if(MK_SCOPE_STOP[nm]) return false;
      }
      return false;
    }
    function open(name, attrs, selfClose){
      var lower = name.toLowerCase();
      var parent = top();
      var svg = parent.svg;
      if(!svg && lower === "svg") svg = true;
      if(!svg){
        if(MK_P_CLOSERS[lower]) closeIn({ p: 1 });
        else if(lower === "li") closeIn({ li: 1 });
        else if(lower === "td" || lower === "th") closeIn({ td: 1, th: 1 });
        else if(lower === "tr") closeIn({ tr: 1 });
        else if(lower === "tbody" || lower === "thead" || lower === "tfoot") closeIn({ tbody: 1, thead: 1, tfoot: 1 });
        else if(lower === "option") closeIn({ option: 1 });
        if(lower === "tr" && top().name === "table"){
          var body = document.createElement("tbody");
          top().node.appendChild(body);
          stack.push({ node: body, name: "tbody", svg: false });
        }
      }
      if(MK_UNSAFE[lower]){
        // dropped with everything inside it
        var end = s.toLowerCase().indexOf("</" + lower, pos);
        if(!selfClose && !MK_VOID[lower]) pos = end < 0 ? s.length : (s.indexOf(">", end) < 0 ? s.length : s.indexOf(">", end) + 1);
        return;
      }
      var el = svg ? document.createElementNS(SVG_NS, name) : document.createElement(lower);
      MK_ATTR.lastIndex = 0;
      var m;
      while((m = MK_ATTR.exec(attrs))){
        var v = mkDecode(m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : "");
        if(!mkSafeAttr(m[1], v)) continue;
        try { el.setAttribute(m[1], v); } catch(e) { /* a name the DOM refuses is not an attribute */ }
      }
      parent.node.appendChild(el);
      if(selfClose || (!svg && MK_VOID[lower])) return;
      // `foreignObject` holds HTML again
      stack.push({ node: el, name: svg ? name : lower, svg: svg && name !== "foreignObject" });
    }
    function close(name){
      var lower = name.toLowerCase();
      for(var i = stack.length - 1; i > 0; i--){
        if(stack[i].name.toLowerCase() === lower){ stack.length = i; return; }
        if(MK_SCOPE_STOP[stack[i].name] && stack[i].name !== name) return;
      }
    }

    while(pos < s.length){
      var lt = s.indexOf("<", pos);
      if(lt < 0){ text(s.slice(pos)); break; }
      if(lt > pos) text(s.slice(pos, lt));
      pos = lt;
      if(s.startsWith("<!--", pos)){
        var ce = s.indexOf("-->", pos + 4);
        pos = ce < 0 ? s.length : ce + 3;
        continue;
      }
      var tag = MK_TAG.exec(s.slice(pos + 1));
      if(!tag){ text("<"); pos += 1; continue; }
      pos += 1 + tag[0].length;
      if(tag[1]) close(tag[2]);
      else open(tag[2], tag[3], tag[4] === "/");
    }
    return frag;
  }

  // `el.innerHTML = html`, as nodes.
  function setMarkup(el, html){
    el.replaceChildren(markupNodes(html, el));
  }
  // `el.insertAdjacentHTML("beforeend", html)`, as nodes.
  function appendMarkup(el, html){
    el.append(markupNodes(html, el));
  }

]]
