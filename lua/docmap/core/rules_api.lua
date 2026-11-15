---@module 'docmap.core.rules_api'
--- The `rules/*` routes of `core/api.lua`: `rules.nvim`'s engine answering for one project, as plain tables.
---
--- Step P2 of the Rules tab of `docmap-desktop` (`RULES_AGENT_CONCEPT.md`, D4-B): the desktop app has no Neovim, so
--- the engine it bundles answers these through `--api=rules/catalog` and `--api=rules/run`, and `editor/serve.lua`
--- answers the same routes from inside the editor. One definition of the answers, two transports.
---
--- **What is read, and from where.** The rulesets and gates come from `rules.settings.resolve({ project = root })`:
--- the project's own `.rules.json` first, then the vault (`$RULES_VAULT`), exactly as `rules.nvim` resolves them for
--- `:Rules check` -- a second reader here would be a second, drifting definition of that file. Waivers come from the
--- project's `.rules-waivers.json` (`rules.engine.waivers`), a file that exists and cannot be used is an answer with
--- a reason, never "no waivers".
---
--- **Trust is the host's, per rule.** A `lua_predicate` is code from a ruleset, and the app takes any folder as a
--- project. So a predicate runs only when its rule file lies (by real path) under a folder the host named in
--- `opts.rules_trust` (`--trust=<folder>` on the command line; the desktop trust store decides what to pass). That is
--- stricter than `rules.settings` on purpose: there a vault named by `$RULES_VAULT` is trusted because the user set the
--- variable, but a child process of an app inherits an environment nobody looked at for this run. Everything else
--- a ruleset says (grep, file_exists, json_key_absent) runs regardless: those read files, they do not execute them.
--- An untrusted predicate reports `error` with `NOT_TRUSTED`, visibly, never silently absent (D5).
---
--- **The agent half** (`rules/plan`, `rules/validate`) wires `rules.nvim`'s pure agent functions
--- (`rules.engine.agent.plan`, `.request`, `.validate`), the ones `:Rules agent` uses, so the prompt, the deny list and
--- the evidence check live in one place for both hosts. Neither sends anything; the input of both is bounded.
---
--- **Absence is an answer** (the rule `core/api.lua` states): `rules.nvim` not part of this engine, a `.rules.json`
--- that cannot be used, no ruleset configured, a selection that names nothing -- each is
--- `{ available = false, reason = ... }`.

local M = {}

---What a predicate the host did not trust reports, as the finding's text.
M.NOT_TRUSTED = "predicate not trusted: the host has not trusted this ruleset (--trust=<folder>)"

---What a route answers when `rules.nvim` cannot be loaded at all.
M.NO_ENGINE = "rules.nvim is not part of this engine"

---The statuses `rules.engine.runner` reports, in the order counts are listed.
M.STATUSES = { "pass", "fail", "error", "manual", "waived" }

---A selection longer than this is refused (a host can list a whole catalog by family or gate instead of by id).
M.MAX_SELECTION_BYTES = 64 * 1024
---A selection naming more items than this is refused.
M.MAX_SELECTION_ITEMS = 4096
---An answer bigger than this is not read: `rules/validate` refuses it with a reason.
M.MAX_ANSWER_BYTES = 1024 * 1024
---`rules/plan` refuses a plan whose requests (system and prompt) add up to more characters than this, rather than
---printing it: select fewer rules. The planner's own `max_context_bytes` bounds a single rule; this bounds the sum.
M.MAX_PLAN_CHARS = 16 * 1024 * 1024

---What `rules/plan` and `rules/validate` answer when `rules.nvim` is there but has no agent functions.
M.NO_AGENT = "the rules.nvim of this engine has no agent functions (rules.engine.agent.*)"

---`rules.nvim`'s modules, or nil when it is not reachable from this host.
---@return table|nil engine `{ settings, loader, runner, waivers }`
function M.engine()
  local probe = require("docmap.core.soft_require").probe
  local settings = probe("rules.settings")
  local loader = probe("rules.engine.loader")
  local runner = probe("rules.engine.runner")
  local waivers = probe("rules.engine.waivers")
  if not (settings and loader and runner and waivers) then
    return nil
  end
  return { settings = settings, loader = loader, runner = runner, waivers = waivers }
end

---`rules.nvim`'s agent functions (the planner, the request writer, the check of an answer), or nil when this host
---has none: an older `rules.nvim`, or a bundle that did not stage them.
---@return table|nil agent `{ plan, request, validate }`
function M.agent_engine()
  local probe = require("docmap.core.soft_require").probe
  local plan = probe("rules.engine.agent.plan")
  local request = probe("rules.engine.agent.request")
  local validate = probe("rules.engine.agent.validate")
  if not (plan and request and validate) then
    return nil
  end
  return { plan = plan, request = request, validate = validate }
end

---`/`-separated, no trailing slash, `.` and `..` segments folded: a ruleset a `.rules.json` names as `../ruleset`
---reaches the loader as `<project>/../ruleset`, and a path the app shows (and opens) should not read like that.
---Lexical only, no link is resolved; a leading `..` that has nothing to fold stays.
---@param path string
---@return string
local function slashed(path)
  local s = tostring(path):gsub("\\", "/")
  local head, rest = s:match("^(//[^/]+/[^/]+)(.*)$")
  if not head then
    head, rest = s:match("^(%a:/)(.*)$")
  end
  if not head then
    head, rest = s:match("^(/)(.*)$")
  end
  if not head then
    head, rest = "", s
  end
  local parts = {}
  for seg in rest:gmatch("[^/]+") do
    if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
      parts[#parts] = nil
    elseif seg ~= "." and not (seg == ".." and head ~= "") then
      parts[#parts + 1] = seg
    end
  end
  local out = head .. table.concat(parts, "/")
  if head:match("^//") and #parts > 0 then
    out = head .. "/" .. table.concat(parts, "/")
  end
  if out == "" then
    return "."
  end
  return out
end

---Whether a file or folder lies under a folder the host trusts. Built on `rules.settings.trust_check`, so it compares
---real paths the way `rules.nvim` does (a link out of a trusted folder is not trusted).
---@param engine table
---@param trust string[]|nil
---@return fun(path: string): boolean
local function host_trust(engine, trust)
  local entries = {}
  for _, path in ipairs(trust or {}) do
    if type(path) == "string" and path ~= "" then
      entries[#entries + 1] = { path = path, trusted = true }
    end
  end
  if #entries == 0 then
    return function()
      return false
    end
  end
  return engine.settings.trust_check({ entries = entries })
end

---The settings and the rules of the project, or the reason there are none to show.
---@param engine table
---@param opts table
---@return table|nil loaded `{ res, rules, errors, root }`
---@return string|nil reason
local function load(engine, opts)
  -- absolute: the findings are made relative to it, and the checks build their paths from it
  local root = slashed(vim.fn.fnamemodify(opts.root or ".", ":p"))
  local settings = engine.settings
  local res = settings.resolve({ project = root })
  local problem = settings.error_text(res, true)
  if problem then
    return nil, problem
  end
  if #res.rulesets == 0 then
    return nil,
      "no ruleset is configured: name one in the project's .rules.json (rulesets), or set a vault"
  end
  local rules, errors = engine.loader.load(res.rulesets)
  if #rules == 0 and #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  return { res = res, rules = rules, errors = errors, root = root }, nil
end

---@param engine table
---@param res table `Rules.Settings`
---@return string[]
local function warnings_of(engine, res)
  local out = {}
  for _, note in ipairs(res.warnings or {}) do
    out[#out + 1] = engine.settings.format(note, true)
  end
  return out
end

---A finding's file relative to the project, `/`-separated; the project itself is `.`.
---@param root string
---@param file any
---@return string
local function relative(root, file)
  local p = slashed(file or "")
  if p == root then
    return "."
  end
  local prefix = root .. "/"
  if p:sub(1, #prefix) == prefix then
    return p:sub(#prefix + 1)
  end
  return p
end

---The gates of the settings as a list sorted by name, `{ { name, families } }`: a map would encode as `[]` when
---empty and as an object otherwise (`core/json` cannot tell an empty map from an empty list), and a typed consumer
---(the desktop app) would fail on the first project without gates.
---@param gates table<string, string[]>|nil
---@return { name: string, families: string[] }[]
local function gate_list(gates)
  local out = {}
  for name, families in pairs(gates or {}) do
    if type(families) == "table" then
      out[#out + 1] = { name = name, families = families }
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

---Run a route's body, turning an error raised inside `rules.nvim` (a module missing from the bundle, a bug in the
---engine) into an answer with its reason: the app shows it, where a traceback on stderr would only fail the call.
---@param body fun(...): table
---@return fun(...): table
local function guarded(body)
  return function(...)
    local ok, result = pcall(body, ...)
    if ok then
      return result
    end
    return { available = false, reason = "the rules engine failed: " .. tostring(result) }
  end
end

---`/api/rules/catalog` -- every rule of the configured rulesets, sorted by id, with what the Rules tab lists and
---groups by: file, section, family, whether there is a mechanical check and of which type, and the agent hint.
---`gates` is a list sorted by name, `{ { name, families } }`.
---@param opts table A resolved `Docmap.Opts`; `opts.rules_trust` the folders whose predicates may run.
---@return table
local function catalog(opts)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  local trusted = host_trust(engine, opts.rules_trust)

  local rules, counts = {}, { rules = 0, automated = 0, manual = 0, predicates = 0 }
  for _, rule in ipairs(loaded.rules) do
    local check = type(rule.check) == "table" and rule.check.type or nil
    local agent
    if type(rule.agent) == "table" then
      agent = {
        question = rule.agent.question,
        include = rule.agent.include,
        max_files = rule.agent.max_files,
      }
    end
    rules[#rules + 1] = {
      id = rule.id,
      severity = rule.severity,
      family = engine.runner.family_of(rule.id),
      title = rule.title,
      section = rule.section,
      text = rule.text or "",
      source_file = slashed(rule.source_file),
      source_line = rule.source_line,
      has_check = check ~= nil,
      check = check,
      agent = agent,
    }
    counts.rules = counts.rules + 1
    if check then
      counts.automated = counts.automated + 1
    else
      counts.manual = counts.manual + 1
    end
    if check == "lua_predicate" then
      counts.predicates = counts.predicates + 1
    end
  end
  table.sort(rules, function(a, b)
    return a.id < b.id
  end)

  local rulesets = {}
  for _, entry in ipairs(loaded.res.entries or {}) do
    rulesets[#rulesets + 1] = {
      name = entry.name,
      path = slashed(entry.path),
      origin = entry.origin,
      trusted = trusted(entry.path),
    }
  end

  return {
    available = true,
    rulesets = rulesets,
    gates = gate_list(loaded.res.gates),
    rules = rules,
    counts = counts,
    errors = loaded.errors,
    warnings = warnings_of(engine, loaded.res),
  }
end

---Read a selection: comma-separated rule ids (`DEP-01`), family prefixes (`DEP`) and gates (`gate:release`).
---@param param string|nil
---@return { ids: string[], families: string[], gates: string[] }
function M.parse_selection(param)
  local out = { ids = {}, families = {}, gates = {} }
  for item in tostring(param or ""):gmatch("[^,]+") do
    local trimmed = item:match("^%s*(.-)%s*$")
    local gate = trimmed:match("^gate:(.+)$")
    if gate then
      out.gates[#out.gates + 1] = gate
    elseif trimmed:match("^%a+%-") then
      out.ids[#out.ids + 1] = trimmed
    elseif trimmed ~= "" then
      out.families[#out.families + 1] = trimmed
    end
  end
  return out
end

---A selection that is too large to be one question: a host may pass a whole catalog's ids, but not without bound.
---@param param string|nil
---@return { ids: string[], families: string[], gates: string[] }|nil selection
---@return string|nil reason
local function bounded_selection(param)
  if type(param) == "string" and #param > M.MAX_SELECTION_BYTES then
    return nil,
      ("the selection is too long (%d bytes, limit %d): select families or gates instead of single ids"):format(
        #param,
        M.MAX_SELECTION_BYTES
      )
  end
  local selection = M.parse_selection(param)
  local items = #selection.ids + #selection.families + #selection.gates
  if items == 0 then
    return nil, "nothing selected: name rule ids, families or gate:<name>, comma-separated"
  end
  if items > M.MAX_SELECTION_ITEMS then
    return nil,
      ("the selection names %d items (limit %d): select families or gates instead of single ids"):format(
        items,
        M.MAX_SELECTION_ITEMS
      )
  end
  return selection, nil
end

---The rules a selection names, in the loader's order, their families (sorted), and the items that matched nothing.
---@param engine table
---@param loaded table `load`'s result
---@param selection { ids: string[], families: string[], gates: string[] }
---@return table[] selected
---@return string[] families
---@return string[] unknown
local function resolve_selection(engine, loaded, selection)
  local present_family, present_id = {}, {}
  for _, rule in ipairs(loaded.rules) do
    present_family[engine.runner.family_of(rule.id)] = true
    present_id[rule.id] = true
  end
  local unknown = {}
  local want_family, want_id = {}, {}
  for _, id in ipairs(selection.ids) do
    if present_id[id] then
      want_id[id] = true
    else
      unknown[#unknown + 1] = id
    end
  end
  local function add_family(family, label)
    if present_family[family] then
      want_family[family] = true
    else
      unknown[#unknown + 1] = label or family
    end
  end
  for _, family in ipairs(selection.families) do
    add_family(family)
  end
  for _, name in ipairs(selection.gates) do
    local families = loaded.res.gates[name]
    if type(families) ~= "table" then
      unknown[#unknown + 1] = "gate:" .. name
    else
      for _, family in ipairs(families) do
        add_family(family, ("gate:%s/%s"):format(name, family))
      end
    end
  end

  local selected, families, seen_family = {}, {}, {}
  for _, rule in ipairs(loaded.rules) do
    local family = engine.runner.family_of(rule.id)
    if want_family[family] or want_id[rule.id] then
      selected[#selected + 1] = rule
      if not seen_family[family] then
        seen_family[family] = true
        families[#families + 1] = family
      end
    end
  end
  table.sort(families)
  return selected, families, unknown
end

---`/api/rules/run`, `param` the selection (`M.parse_selection`) -- the mechanical run of the selected rules over the
---project: one result per rule, `pass | fail | error | manual | waived`, with its findings.
---
---Never "every rule": a selection that names nothing is an answer with a reason, as `rules.engine.runner` refuses a
---whole-catalog sweep by design. A caller that wants everything names every family, which it can read off the
---catalog.
---@param opts table A resolved `Docmap.Opts`; `opts.rules_trust` the folders whose predicates may run,
---`opts.rules_today` the date waivers are judged against (`YYYY-MM-DD`, default today: for tests).
---@param param string|nil
---@return table
local function run(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local selection, refused = bounded_selection(param)
  if not selection then
    return { available = false, reason = refused }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  local waiver_entries, waiver_err = engine.waivers.load_entries(loaded.root)
  if waiver_err then
    return { available = false, reason = waiver_err }
  end

  local selected, families, unknown = resolve_selection(engine, loaded, selection)
  if #selected == 0 then
    return {
      available = false,
      unknown = unknown,
      reason = "the selection matches no rule of the configured rulesets",
    }
  end

  local trusted = host_trust(engine, opts.rules_trust)
  local run_opts = {
    today = opts.rules_today,
    lua_predicates = function(rule)
      if trusted(rule.source_file) then
        return true
      end
      return false, M.NOT_TRUSTED
    end,
  }

  local results = {}
  local counts = {}
  for _, status in ipairs(M.STATUSES) do
    counts[status] = 0
  end
  for _, family in ipairs(families) do
    for _, res in
      ipairs(engine.runner.check_family(selected, family, loaded.root, waiver_entries, run_opts))
    do
      local findings = {}
      for _, f in ipairs(res.findings or {}) do
        findings[#findings + 1] = {
          file = relative(loaded.root, f.file),
          line = f.line,
          text = f.text,
        }
      end
      local entry = {
        id = res.rule.id,
        family = family,
        severity = res.rule.severity,
        title = res.rule.title,
        status = res.status,
        findings = findings,
      }
      if res.status == "waived" then
        entry.waiver = {
          reason = res.waiver_reason,
          expires = res.waiver_expires,
          paths = res.waiver_paths,
        }
      end
      if res.partial_waiver then
        entry.partial_waiver = res.partial_waiver
      end
      if res.expired_waiver then
        entry.expired_waiver = res.expired_waiver
      end
      results[#results + 1] = entry
      counts[res.status] = (counts[res.status] or 0) + 1
    end
  end
  table.sort(results, function(a, b)
    return a.id < b.id
  end)

  return {
    available = true,
    families = families,
    unknown = unknown,
    results = results,
    counts = counts,
    errors = loaded.errors,
    warnings = warnings_of(engine, loaded.res),
  }
end

---`rules.nvim`'s agent config of the project, as the planner reads it (`batch_size`, `max_context_bytes`, `deny`,
---`scopes`, defaults filled in by `rules.settings`).
---@param loaded table
---@return table
local function agent_config(loaded)
  return loaded.res.agent or {}
end

---`/api/rules/plan`, `param` the selection (`M.parse_selection`) -- what an agent run over the selected rules would
---send, and what it would not, without sending anything.
---
---The planner and the request writer are `rules.nvim`'s own (`rules.engine.agent.plan`, `.request`), the same pure
---functions `:Rules agent` uses in the editor: scope (`agent.include` of the rule, else of its family), the deny list
---(built in plus `agent.deny`, links never sent), the size limit and the batching are decided there, so they hold in
---both hosts. Rules with a check are not planned (a check answers them, `rules/run`) and come back in `with_check`;
---nothing of them runs here, so no predicate runs and there is nothing to trust -- the trust of `rules/run` is the
---only one there is (a lead derived from a predicate would have to pass it the same way).
---@param opts table A resolved `Docmap.Opts`.
---@param param string|nil
---@return table
local function plan(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local agent = M.agent_engine()
  if not agent then
    return { available = false, reason = M.NO_AGENT }
  end
  local selection, refused = bounded_selection(param)
  if not selection then
    return { available = false, reason = refused }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  local selected, _, unknown = resolve_selection(engine, loaded, selection)
  if #selected == 0 then
    return {
      available = false,
      unknown = unknown,
      reason = "the selection matches no rule of the configured rulesets",
    }
  end

  local manual, with_check = {}, {}
  for _, rule in ipairs(selected) do
    if rule.check == nil then
      manual[#manual + 1] = rule
    else
      with_check[#with_check + 1] = {
        id = rule.id,
        check = type(rule.check) == "table" and rule.check.type or nil,
      }
    end
  end
  table.sort(with_check, function(a, b)
    return a.id < b.id
  end)

  local cfg = agent_config(loaded)
  local planned = agent.plan.plan(manual, loaded.root, { agent = cfg })

  local skipped = {}
  for _, entry in ipairs(planned.skipped) do
    skipped[#skipped + 1] = { id = entry.rule.id, status = entry.status, reason = entry.reason }
  end
  local batches = {}
  local totals = { requests = 0, files = 0, bytes = 0, chars = 0, tokens = 0 }
  for _, batch in ipairs(planned.batches) do
    local req, build_err = agent.request.build(batch, loaded.root)
    if not req then
      -- not sent, and not lost: each of its rules says why
      for _, entry in ipairs(batch.rules) do
        skipped[#skipped + 1] = { id = entry.rule.id, status = "unclear", reason = build_err }
      end
    else
      local rules = {}
      for _, entry in ipairs(batch.rules) do
        rules[#rules + 1] = {
          id = entry.rule.id,
          severity = entry.rule.severity,
          title = entry.rule.title,
          source = entry.source,
          truncated = entry.truncated,
        }
      end
      batches[#batches + 1] = {
        id = batch.id,
        system = req.system,
        prompt = req.prompt,
        files = req.sent,
        unreadable = req.unreadable,
        bytes = batch.bytes,
        chars = req.chars,
        tokens = req.tokens,
        rules = rules,
      }
      totals.requests = totals.requests + 1
      totals.files = totals.files + #req.sent
      totals.bytes = totals.bytes + batch.bytes
      totals.chars = totals.chars + req.chars
      totals.tokens = totals.tokens + req.tokens
      if totals.chars > M.MAX_PLAN_CHARS then
        return {
          available = false,
          reason = ("the plan is too large (more than %d characters of requests): select fewer rules"):format(
            M.MAX_PLAN_CHARS
          ),
        }
      end
    end
  end
  table.sort(skipped, function(a, b)
    return a.id < b.id
  end)

  return {
    available = true,
    batches = batches,
    skipped = skipped,
    denied = planned.denied,
    with_check = with_check,
    unknown = unknown,
    totals = totals,
    limits = {
      batch_size = cfg.batch_size or agent.plan.DEFAULT_BATCH_SIZE,
      max_context_bytes = cfg.max_context_bytes or agent.plan.DEFAULT_MAX_CONTEXT_BYTES,
    },
    -- where a request may go is the host's to enforce; it reads the project's allow-list from here
    agent = { backends = cfg.backends or {}, models = cfg.models or {} },
    errors = loaded.errors,
    warnings = warnings_of(engine, loaded.res),
  }
end

---The answer a host hands `rules/validate`: `opts.rules_answer` (the text, an in-process host) or
---`opts.rules_answer_file` (a path, `--answer=<file>` on the command line), bounded by `M.MAX_ANSWER_BYTES`.
---@param opts table
---@return string|nil text
---@return string|nil reason
local function answer_of(opts)
  local text = opts.rules_answer
  if text == nil and opts.rules_answer_file then
    local path = tostring(opts.rules_answer_file)
    local fh = io.open(path, "rb")
    if not fh then
      return nil, "the answer file cannot be read: " .. path
    end
    -- one byte past the limit is enough to know it is too big; nothing more is read
    text = fh:read(M.MAX_ANSWER_BYTES + 1) or ""
    fh:close()
  end
  if type(text) ~= "string" then
    return nil, "no answer given: pass the model's answer as a file (--answer=<file>)"
  end
  if #text > M.MAX_ANSWER_BYTES then
    return nil, ("the answer is too large (more than %d bytes)"):format(M.MAX_ANSWER_BYTES)
  end
  return text, nil
end

---A dropped finding as plain fields: the model wrote it, so it is whatever JSON came back (a `null` is a userdata
---in the editor and a table under the shim); only the parts a host shows are kept, and only with their own type.
---@param dropped { finding: any, reason: string }[]
---@return table[]
local function plain_dropped(dropped)
  local out = {}
  for _, d in ipairs(dropped or {}) do
    local f = type(d.finding) == "table" and d.finding or {}
    out[#out + 1] = {
      reason = d.reason,
      file = type(f.file) == "string" and f.file or nil,
      line = type(f.line) == "number" and f.line or nil,
      quote = type(f.quote) == "string" and f.quote or nil,
    }
  end
  return out
end

---`/api/rules/validate`, `param` one rule id -- the model's answer about that rule (`opts.rules_answer[_file]`)
---checked against the tree as it is now, by `rules.engine.agent.validate`.
---
---The files the answer may claim to have looked at are the ones the request of this rule carries: planned and
---written again here (the planner is deterministic, and a rule's files do not depend on the rules it shares a batch
---with), never taken from the caller. A rule that is not sent has no request, so any answer is `unclear`.
---The result is a proposal, never a verdict: `proposed = true`, `verified = false`.
---@param opts table A resolved `Docmap.Opts`.
---@param param string|nil
---@return table
local function validate(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local agent = M.agent_engine()
  if not agent then
    return { available = false, reason = M.NO_AGENT }
  end
  local id = tostring(param or ""):match("^%s*(.-)%s*$")
  if id == "" or id:find("[,%s]") then
    return { available = false, reason = "name exactly one rule id (--select=<ID>)" }
  end
  local text, refused = answer_of(opts)
  if not text then
    return { available = false, reason = refused }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  local rule
  for _, candidate in ipairs(loaded.rules) do
    if candidate.id == id then
      rule = candidate
    end
  end
  if not rule then
    return {
      available = false,
      unknown = { id },
      reason = "no rule of the configured rulesets has this id",
    }
  end
  if rule.check ~= nil then
    return {
      available = false,
      reason = ("%s has a check: rules/run answers it, an agent answers only the rules without one"):format(
        id
      ),
    }
  end

  local planned = agent.plan.plan({ rule }, loaded.root, { agent = agent_config(loaded) })
  local result, sent
  if planned.skipped[1] then
    sent = {}
    result =
      agent.validate.unclear(id, "this rule is not sent (" .. planned.skipped[1].reason .. ")")
  else
    local req, build_err = agent.request.build(planned.batches[1], loaded.root)
    if not req then
      sent = {}
      result = agent.validate.unclear(id, build_err)
    else
      sent = req.sent
      result = agent.validate.validate(rule, text, loaded.root, { sent = sent })
    end
  end

  return {
    available = true,
    rule = { id = rule.id, severity = rule.severity, title = rule.title },
    sent = sent,
    proposal = {
      rule_id = result.rule_id,
      status = result.status,
      proposed = true,
      verified = false,
      findings = result.findings,
      checked = result.checked,
      unchecked = result.unchecked or {},
      dropped = plain_dropped(result.dropped),
      reason = result.reason,
      raw = result.raw,
    },
    errors = loaded.errors,
    warnings = warnings_of(engine, loaded.res),
  }
end

-- ── one file a person attaches to a conversation ─────────────────────────────────

---The longest path `rules/attach` takes, in bytes.
M.MAX_ATTACH_PATH = 1024

---The path `rules/attach` was given, made relative and "/"-separated, or the reason it is not one file of the project.
---@param param string|nil
---@return string|nil path
---@return string|nil reason
local function attach_path(param)
  local raw = tostring(param or ""):gsub("\\", "/"):match("^%s*(.-)%s*$")
  if raw == "" then
    return nil, "name one file relative to the project (--select=<path>)"
  end
  if #raw > M.MAX_ATTACH_PATH then
    return nil, ("the path is too long (more than %d bytes)"):format(M.MAX_ATTACH_PATH)
  end
  if raw:find("%c") then
    return nil, "the path has a control character"
  end
  if raw:sub(1, 1) == "/" or raw:find("^%a:") then
    return nil, "the path must be relative to the project"
  end
  -- `*` is the only pattern character of `rules.engine.glob`; a path with one would name several files
  if raw:find("*", 1, true) then
    return nil, "a path with * is a pattern: name one file"
  end
  local parts = {}
  for part in raw:gmatch("[^/]+") do
    if part == ".." then
      return nil, "the path must stay inside the project"
    end
    if part ~= "." then
      parts[#parts + 1] = part
    end
  end
  if #parts == 0 then
    return nil, "name one file relative to the project (--select=<path>)"
  end
  return table.concat(parts, "/"), nil
end

---`rules/attach`, `param` one path relative to the project -- whether that file may go into a request, and if so its
---text the way a request carries it (`=== path ===` and numbered lines).
---
---For a host's conversation about a rule, which cannot open files by itself: a person attaches one. The decision is
---the planner's, not a second copy of it: the file is planned as the only scope of a stand-in rule, so the deny list
---(built in plus `agent.deny`), the links that are never sent, the folders the walk never enters, the size limit
---and the reading of the file are exactly those of `rules/plan`. Nothing is sent and nothing is written.
---@param opts table A resolved `Docmap.Opts`.
---@param param string|nil
---@return table
local function attach(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local agent = M.agent_engine()
  if not agent then
    return { available = false, reason = M.NO_AGENT }
  end
  local path, refused = attach_path(param)
  if not path then
    return { available = false, reason = refused }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  -- the stand-in rule has nothing of its own but the scope: its id and text never leave this function
  local stand_in = {
    id = "ATTACH-0",
    severity = "info",
    title = "",
    text = "",
    agent = { include = { path } },
  }
  local planned = agent.plan.plan({ stand_in }, loaded.root, { agent = agent_config(loaded) })
  local function not_sent(why, denied)
    return { available = true, file = path, sent = false, denied = denied, reason = why }
  end
  for _, denied in ipairs(planned.denied) do
    if denied == path then
      return not_sent("the deny list keeps this file out of every request (or it is a link)", true)
    end
  end
  local skipped = planned.skipped[1]
  if skipped then
    if tostring(skipped.reason):find("^scope matches no file") then
      return not_sent("no such file in the tree a request may read from", false)
    end
    return not_sent(skipped.reason, false)
  end
  local batch = planned.batches[1]
  local req, build_err = agent.request.build(batch, loaded.root)
  if not req then
    return not_sent(build_err, false)
  end
  -- the stand-in rule's block comes first; everything after the `Files:` line is the file
  local block = req.prompt:match("\nFiles:\n\n(.*)$") or ""
  return {
    available = true,
    file = path,
    sent = true,
    denied = false,
    text = block,
    bytes = batch.bytes,
    chars = #block,
    tokens = agent.request.estimate_tokens(#block),
    errors = loaded.errors,
  }
end

-- ── the two routes that write ────────────────────────────────────────────────────

---What `rules/accept` and `rules/waive` answer when `rules.nvim` is there but cannot write (an older one, or a
---bundle that did not stage its writers).
M.NO_WRITER =
  "the rules.nvim of this engine cannot write verdicts or waivers (rules.engine.verdicts.accept, rules.ops)"

---The longest `by` a host may pass (`rules.engine.verdicts` keeps the same limit in characters; this one is bytes,
---checked first so an absurd value is never decoded or written).
M.MAX_BY_BYTES = 400

---The command-line flags of the two writing routes, by name, and the option each one fills. One table for both
---hosts (`standalone/docmap.lua`, `standalone/rules_api.lua`), so they read the same flags the same way.
M.WRITE_FLAGS = {
  proposal = "rules_proposal_file",
  by = "rules_by",
  note = "rules_note",
  reason = "rules_reason",
  expires = "rules_expires",
  paths = "rules_paths",
}

---The option one argument fills, when it is a flag of `M.WRITE_FLAGS` (`--by=Stefan` -> `"rules_by", "Stefan"`).
---@param a string
---@return string|nil key
---@return string|nil value
function M.write_flag(a)
  local name, value = a:match("^%-%-(%a+)=(.*)$")
  local key = name and M.WRITE_FLAGS[name]
  if key then
    return key, value
  end
  return nil, nil
end

---`rules.nvim`'s two writers, or nil: `rules.engine.verdicts.accept` (the only function that writes
---`.rules-verdicts.json`) and `rules.ops.run` (the `rules-ops/1` door, whose `waive` is the code of `:Rules waive`).
---@return table|nil writer `{ verdicts, ops }`
function M.write_engine()
  local probe = require("docmap.core.soft_require").probe
  local verdicts = probe("rules.engine.verdicts")
  local ops = probe("rules.ops")
  if
    not (verdicts and type(verdicts.accept) == "function" and ops and type(ops.run) == "function")
  then
    return nil
  end
  return { verdicts = verdicts, ops = ops }
end

---One rule id and nothing else, the way `rules/validate` takes it.
---@param param string|nil
---@return string|nil id
---@return string|nil reason
local function one_id(param)
  local id = tostring(param or ""):match("^%s*(.-)%s*$")
  if id == "" or id:find("[,%s]") then
    return nil, "name exactly one rule id (--select=<ID>)"
  end
  return id, nil
end

---The loaded rule with this id, or the answer that says there is none.
---@param loaded table
---@param id string
---@return table|nil rule
---@return table|nil answer
local function rule_of(loaded, id)
  for _, candidate in ipairs(loaded.rules) do
    if candidate.id == id then
      return candidate, nil
    end
  end
  return nil,
    {
      available = false,
      unknown = { id },
      reason = "no rule of the configured rulesets has this id",
    }
end

---The proposal a host hands `rules/accept`: `opts.rules_proposal` (a table or its JSON text, an in-process host) or
---`opts.rules_proposal_file` (a path, `--proposal=<file>`), bounded like an answer. It is the `proposal` object of a
---`rules/validate` answer, as it came back.
---@param opts table
---@return table|nil proposal
---@return string|nil reason
local function proposal_of(opts)
  local given = opts.rules_proposal
  if type(given) == "table" then
    return given, nil
  end
  local text = given
  if text == nil and opts.rules_proposal_file then
    local path = tostring(opts.rules_proposal_file)
    local fh = io.open(path, "rb")
    if not fh then
      return nil, "the proposal file cannot be read: " .. path
    end
    text = fh:read(M.MAX_ANSWER_BYTES + 1) or ""
    fh:close()
  end
  if type(text) ~= "string" then
    return nil,
      "no proposal given: pass the proposal of rules/validate as a file (--proposal=<file>)"
  end
  if #text > M.MAX_ANSWER_BYTES then
    return nil, ("the proposal is too large (more than %d bytes)"):format(M.MAX_ANSWER_BYTES)
  end
  local ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= "table" or (next(decoded) ~= nil and vim.islist(decoded)) then
    return nil, "the proposal is not a JSON object (the proposal of a rules/validate answer)"
  end
  return decoded, nil
end

---A one-line text a host passes on (`by`, `note`, `reason`), or the reason it cannot be one.
---@param value any
---@param what string
---@param required boolean
---@return string|nil text
---@return string|nil reason
local function given_text(value, what, required)
  if value == nil or value == "" then
    if required then
      return nil, ("%s is required (--%s=...)"):format(what, what)
    end
    return nil, nil
  end
  if type(value) ~= "string" then
    return nil, what .. " must be a text"
  end
  if #value > M.MAX_ANSWER_BYTES then
    return nil, what .. " is too long"
  end
  return value, nil
end

---`rules/accept`, `param` one rule id -- accept the agent's proposal about that rule as a verdict: written to the
---project's `.rules-verdicts.json` by `rules.engine.verdicts.accept`, the only function that writes that file.
---
---Its guarantees are `rules.nvim`'s and are not repeated here: one proposal at a time, no `verified` and no
---`unclear` proposal, the evidence held against the tree, a verdicts file that exists and cannot be used (or is a
---link) is never overwritten, a change of the file between read and write stops it. What this route adds is what a
---host must not decide: the files the request carried (`sent`) are planned again here and replace whatever the
---proposal says, the rule must be the one named and one an agent answers (no check), and the person (`by`) comes from
---the host, never from the proposal. The date is today's: a host does not date a verdict.
---@param opts table A resolved `Docmap.Opts`; `rules_proposal[_file]`, `rules_by`, `rules_note`.
---@param param string|nil
---@return table
local function accept(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local agent = M.agent_engine()
  if not agent then
    return { available = false, reason = M.NO_AGENT }
  end
  local writer = M.write_engine()
  if not writer then
    return { available = false, reason = M.NO_WRITER }
  end
  local id, bad_id = one_id(param)
  if not id then
    return { available = false, reason = bad_id }
  end
  local by, bad_by = given_text(opts.rules_by, "by", true)
  if not by then
    return { available = false, reason = bad_by }
  end
  if #by > M.MAX_BY_BYTES then
    return { available = false, reason = "by is too long" }
  end
  local note, bad_note = given_text(opts.rules_note, "note", false)
  if bad_note then
    return { available = false, reason = bad_note }
  end
  local proposal, refused = proposal_of(opts)
  if not proposal then
    return { available = false, reason = refused }
  end
  if proposal.rule_id ~= id then
    return {
      available = false,
      reason = ("the proposal is about %s, not %s"):format(tostring(proposal.rule_id), id),
    }
  end
  local loaded, reason = load(engine, opts)
  if not loaded then
    return { available = false, reason = reason }
  end
  local rule, none = rule_of(loaded, id)
  if not rule then
    return none --[[@as table]]
  end
  if rule.check ~= nil then
    return {
      available = false,
      reason = ("%s has a check: rules/run answers it, a verdict is for a rule without one"):format(
        id
      ),
    }
  end

  -- What the request of this rule carried, planned again: the evidence is held against this list, not the host's.
  local planned = agent.plan.plan({ rule }, loaded.root, { agent = agent_config(loaded) })
  if planned.skipped[1] then
    return {
      available = false,
      reason = ("%s is not sent (%s): no answer about it can be accepted"):format(
        id,
        planned.skipped[1].reason
      ),
    }
  end
  local req, build_err = agent.request.build(planned.batches[1], loaded.root)
  if not req then
    return { available = false, reason = ("%s is not sent (%s)"):format(id, tostring(build_err)) }
  end
  local candidate = vim.deepcopy(proposal)
  candidate.sent = req.sent

  local ok, err = writer.verdicts.accept(loaded.root, candidate, { by = by, note = note })
  if not ok then
    return { available = false, reason = err }
  end
  local entries, load_err = writer.verdicts.load(loaded.root)
  local entry = entries[id]
  if load_err or not entry then
    return {
      available = false,
      reason = load_err or "the verdict was written but cannot be read back",
    }
  end
  return {
    available = true,
    written = true,
    file = writer.verdicts.FILE,
    id = id,
    verdict = entry,
    warnings = warnings_of(engine, loaded.res),
  }
end

---The paths a host passes to `rules/waive`: a list (an in-process host) or a comma-separated text (`--paths=`).
---@param value any
---@return string[]|nil paths
local function paths_of(value)
  if type(value) == "table" then
    return value
  end
  if type(value) ~= "string" or value == "" then
    return nil
  end
  local out = {}
  for item in value:gmatch("[^,]+") do
    local trimmed = item:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      out[#out + 1] = trimmed
    end
  end
  return #out > 0 and out or nil
end

---`rules/waive`, `param` one rule id -- add a waiver of that rule to the project's `.rules-waivers.json` through the
---`waive` operation of `rules.nvim`'s write door (`rules.ops`, the code `:Rules waive` runs): the rule must be loaded,
---the reason one line that says something, the expiry a date, the paths relative globs; a waiver that is there
---already is refused (renew or remove it in the editor), the same one again is `unchanged`; the file is written under
---its lock, canonically, and never through a link. Nothing here re-decides any of that.
---@param opts table A resolved `Docmap.Opts`; `rules_reason`, `rules_expires`, `rules_paths`.
---@param param string|nil
---@return table
local function waive(opts, param)
  local engine = M.engine()
  if not engine then
    return { available = false, reason = M.NO_ENGINE }
  end
  local writer = M.write_engine()
  if not writer then
    return { available = false, reason = M.NO_WRITER }
  end
  local id, bad_id = one_id(param)
  if not id then
    return { available = false, reason = bad_id }
  end
  local reason_text, bad_reason = given_text(opts.rules_reason, "reason", true)
  if not reason_text then
    return { available = false, reason = bad_reason }
  end
  local expires, bad_expires = given_text(opts.rules_expires, "expires", false)
  if bad_expires then
    return { available = false, reason = bad_expires }
  end
  -- The project and its settings, as for every other route: a `.rules.json` that cannot be used is told here, in
  -- the words the other routes use, before the door is asked.
  local loaded, why = load(engine, opts)
  if not loaded then
    return { available = false, reason = why }
  end
  local doc, err = writer.ops.run({
    ops = {
      {
        op = "waive",
        id = id,
        reason = reason_text,
        expires = expires,
        paths = paths_of(opts.rules_paths),
      },
    },
  }, { project = loaded.root })
  if not doc then
    return { available = false, reason = err and err.message or "the waiver was not written" }
  end
  local entry = (doc.results or {})[1] or {}
  if entry.ok ~= true then
    local e = entry.error or {}
    return { available = false, reason = e.message or "the waiver was not written", code = e.code }
  end
  local entries = engine.waivers.load_entries(loaded.root) or {}
  local waiver = entries[id] or {}
  local out = {
    available = true,
    written = entry.outcome ~= "unchanged",
    outcome = entry.outcome,
    file = engine.waivers.FILE,
    id = id,
    waiver = { reason = waiver.reason, expires = waiver.expires, paths = waiver.paths },
    warnings = warnings_of(engine, loaded.res),
  }
  for _, text in ipairs(entry.warnings or {}) do
    out.warnings[#out.warnings + 1] = text
  end
  return out
end

-- Exported guarded: whatever `rules.nvim` raises comes back as `{ available = false, reason }`.

---`/api/rules/catalog` (see `catalog` above).
---@type fun(opts: table): table
M.catalog = guarded(catalog)

---`/api/rules/run` (see `run` above).
---@type fun(opts: table, param: string|nil): table
M.run = guarded(run)

---`/api/rules/plan` (see `plan` above).
---@type fun(opts: table, param: string|nil): table
M.plan = guarded(plan)

---`/api/rules/validate` (see `validate` above).
---@type fun(opts: table, param: string|nil): table
M.validate = guarded(validate)

---`rules/attach` (see `attach` above).
---@type fun(opts: table, param: string|nil): table
M.attach = guarded(attach)

---`rules/accept` (see `accept` above).
---@type fun(opts: table, param: string|nil): table
M.accept = guarded(accept)

---`rules/waive` (see `waive` above).
---@type fun(opts: table, param: string|nil): table
M.waive = guarded(waive)

return M
