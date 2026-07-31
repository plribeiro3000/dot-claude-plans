# SPIKE — HTML output stealing window focus across parallel sessions

## Investigation question

The Output Policy routes visual/comparative content to a self-contained HTML file in `/tmp/` and instructs the agent to open it with `open <path>`. On macOS that activates Chrome and raises it to the foreground. With ~10 concurrent Claude Code sessions this fires constantly: windows pop in front of whatever the engineer is doing (including screen-shares and meetings), keystrokes land in the wrong window, and Chrome accumulates unlabelled tabs whose originating session is no longer identifiable.

Can HTML output be delivered per-session, inside the Claude Code desktop app's own Browser pane, so that no external window is raised and no tab accumulates in Chrome — and does that pane support what the 4Shark HTML templates actually need (inline JS interactivity, CDN-loaded Mermaid/Chart.js)?

## Sources consulted

- `/tmp/open_help.txt:19` — `open(1)` usage output captured on this machine; documents the `-g` flag
- Live probes in this session (Browser pane tools: `tabs_context`, `get_page_text`, `navigate`, `javascript_tool`, `read_page`) — see Findings 2–6
- [anthropics/claude-code#51587](https://github.com/anthropics/claude-code/issues/51587) — auto-open of the preview panel on Write/Edit; no opt-out
- [anthropics/claude-code#65443](https://github.com/anthropics/claude-code/issues/65443) — preview pane serves a stale snapshot after the file changes
- [anthropics/claude-code#27792](https://github.com/anthropics/claude-code/issues/27792) — `preview_start` does not accept `file://` paths
- [anthropics/claude-code#71604](https://github.com/anthropics/claude-code/issues/71604) — `file://` preview broke external CSS; fixed
- `~/.claude/CLAUDE.md:888-890,923,1350`, `~/.claude/docs/OUTPUT-EDGE-CASES.md:129`, `~/.claude/templates/html/base.html:16`, `~/.claude/scripts/inject-output-policy-reminder.sh:50` — the policy sites that mandate `open`

## Findings

### Finding 1: `open` raises the application by default; `-g` suppresses that, and is available on this machine

**Evidence:** from the captured usage output:

```
      -j, --hide            Launches the app hidden.
      -g, --background      Does not bring the application to the foreground.
```

**Source:** `/tmp/open_help.txt:18-19` (output of `open --help` on this machine, macOS Darwin 25.5.0)

**Significance:** the focus-steal half of the problem has a one-flag mitigation that requires no change to where files are written. It does **not** address tab accumulation in Chrome — a backgrounded `open` still creates the tab.

**Verification:** Command executed in this session; output written to `/tmp/open_help.txt` and read back; quote confirmed at lines 18-19.

### Finding 2: Writing an HTML file already loads it into the session's own Browser pane, with no `open` call

**Evidence:** immediately after `Write` created `/tmp/probe_tmp_20260730.html`, the harness emitted a PostToolUse system-reminder: `/tmp/probe_tmp_20260730.html is now visible in the Browser pane.` Querying the pane confirmed it:

```json
{
  "tabs": [
    { "tabId": "seed",  "origin": "file:///private/tmp/claude-501/-/.../scratchpad/probe.html", "isActive": false },
    { "tabId": "tab-1", "origin": "file:///private/tmp/probe_tmp_20260730.html",                "isActive": true  }
  ]
}
```

**Source:** `mcp__Claude_Browser__tabs_context` result, this session

**Significance:** the desired behavior is not something to build — it is already the default for any HTML file the agent writes, in both the scratchpad and `/tmp/`. Each session has its own pane, so the delivery is per-session by construction. The `open` call is therefore not the delivery mechanism; it is a redundant second delivery that additionally raises Chrome.

**Verification:** `Write` executed twice (scratchpad path and `/tmp/` path); `tabs_context` called after; both origins present as `file://` tabs.

### Finding 3: The pane renders the file's real content, not a placeholder

**Evidence:**

```
Title: Probe — internal browser
URL: (non-http)
Source element: <body>
---
PROBE_OK_INTERNAL_BROWSER

If this text is readable through the browser pane tools, a local file:// URL loads in the internal browser.
```

**Source:** `mcp__Claude_Browser__get_page_text` result, this session

**Significance:** confirms the pane parses and renders the local file rather than merely registering its path.

**Verification:** tool called against the active pane tab; returned the exact body text written to disk.

### Finding 4: The pane is a live document — inline JS runs, CDN fetches succeed, click handlers fire

**Evidence:** a probe page whose inline `<script>` overwrote two paragraphs and fetched Chart.js from jsDelivr rendered as:

```
JS probe
INLINE_JS_RAN
CDN_FETCH_OK_200
click me
```

and driving the button programmatically returned the handler's result:

```
document.getElementById('btn').click(); document.getElementById('inline').textContent;
→ "CLICK_HANDLER_RAN"
```

**Source:** `mcp__Claude_Browser__get_page_text` and `mcp__Claude_Browser__javascript_tool` results, this session

**Significance:** this is the load-bearing compatibility question. The 4Shark HTML pattern catalog depends on inline JS (search/filter in `interactive-report.html`), on CDN-loaded Mermaid, and on CDN-loaded Chart.js — `base.html` auto-loads both when the corresponding element is present. All three work in the pane. No template needs changing.

**Verification:** probe written to `/tmp/probe_js_20260730.html`; page text read after render; `javascript_tool` executed against the same tab.

### Finding 5: Files the agent does *not* write with `Write` can be loaded explicitly with `navigate`

**Evidence:** a file created via a Bash redirect (no `Write`, so no auto-preview) loaded on demand:

```
opened file:///tmp/probe_bash_20260730.html in the preview pane (files outside the project folder render as static snapshots)
```

**Source:** `mcp__Claude_Browser__navigate` result, this session

**Significance:** covers the residual case — HTML produced by a script or an external tool rather than by the `Write` tool. The "static snapshots" wording refers to the absence of dev-server/live-reload semantics, not to a dead document: Finding 4 was measured on this same pane.

**Verification:** file created via `printf > /tmp/probe_bash_20260730.html`; `navigate` called with the `file://` URL; quoted string is the tool's verbatim return.

### Finding 6: The pane's accessibility tree is unavailable while the pane is not being rendered

**Evidence:** `read_page` against a tab that `get_page_text` had just read successfully returned `(empty page)` with `Viewport: 0x0`.

**Source:** `mcp__Claude_Browser__read_page` result, this session

**Significance:** affects only the agent's ability to enumerate interactive elements programmatically; it does not affect what the engineer sees when they look at the pane, and `get_page_text` plus `javascript_tool` both work regardless. Not a blocker for human-facing report delivery.

**Verification:** called immediately after a successful `get_page_text` on the same `tabId`.

### Finding 7: The auto-open of the preview panel cannot be disabled

**Evidence:** verbatim from the issue body:

> When editing HTML files via Write/Edit tools inside Claude Desktop,
> the Launch preview panel auto-opens and a PostToolUse system-reminder
> instructs the assistant to mention it. Closing the panel manually does
> not persist — it re-opens on the next edit.

State: `OPEN`, created 2026-04-21, priority filed as "Low - Nice to have".

**Source:** [anthropics/claude-code#51587](https://github.com/anthropics/claude-code/issues/51587), fetched via `gh issue view`

**Significance:** cuts both ways. For this spike the behavior is wanted, so the absence of an opt-out is harmless — and it means the behavior is stable and will not silently need re-enabling. For an engineer who did *not* want it there is no setting; that is a separate complaint from the one this spike addresses.

**Verification:** `gh issue view 51587 -R anthropics/claude-code --json ... > /tmp/issue_51587.json`; file read; quote confirmed in the `body` field; `state` field reads `OPEN`.

### Finding 8: The pane caches a rendered file — a re-written path can show stale content, and the documented workaround is the naming convention 4Shark already uses

**Evidence:** verbatim from the issue body:

> Workaround: open the file directly in an external browser, or write to a new filename each time (a never-before-launched path always renders fresh).

State: `CLOSED`, `stateReason: NOT_PLANNED`.

**Source:** [anthropics/claude-code#65443](https://github.com/anthropics/claude-code/issues/65443), fetched via `gh issue view`

**Significance:** the only real defect in this delivery path, and Anthropic has declined to fix it. It is neutralized by the Output Policy's existing file-naming convention, which appends `{timestamp}` (`YYYYMMDD_HHMMSS`) and states *"Multiple executions of the same operation create separate files (do not overwrite)"* — every report already lands on a never-before-launched path. The risk is confined to a report deliberately re-written to the same filename, which the convention already forbids.

**Verification:** `gh issue view 65443 -R anthropics/claude-code --json ... > /tmp/issue_65443.json`; file read; quote confirmed in the `body` field; `state`/`stateReason` fields read `CLOSED`/`NOT_PLANNED`.

### Finding 9: `preview_start` is not the right tool for a local file; `navigate` is

**Evidence:** verbatim from the issue body: *"The `preview_start` tool currently only works with dev servers (localhost URLs)."* State: `CLOSED`, `stateReason: NOT_PLANNED`.

**Source:** [anthropics/claude-code#27792](https://github.com/anthropics/claude-code/issues/27792), fetched via `gh issue view`

**Significance:** rules out the tool an implementer would reach for first, and confirms the request for it was declined. Finding 5 shows `navigate` covers the same need, so nothing is lost.

**Verification:** `gh issue view 27792 -R anthropics/claude-code --json ... > /tmp/issue_27792.json`; file read; quote confirmed in the `body` field.

### Finding 10: The `file://` rendering bug that broke external stylesheets is fixed, and would not have affected 4Shark templates anyway

**Evidence:** issue title *"[BUG] Claude Desktop Preview For Static HTML Pages Opens file:// Instead of Live Server — CSS Styles Not Loading"*, state `CLOSED`, `stateReason: COMPLETED`. The reported reproduction requires `<link rel="stylesheet" href="./styles.css">` — an external stylesheet.

**Source:** [anthropics/claude-code#71604](https://github.com/anthropics/claude-code/issues/71604), fetched via `gh issue view`

**Significance:** removes the one known rendering-fidelity objection. It is doubly moot here: every template in `~/.claude/templates/html/` is self-contained with inline CSS, so a relative-asset failure could not occur.

**Verification:** `gh issue view 71604 -R anthropics/claude-code --json ... > /tmp/issue_71604.json`; file read; `state`/`stateReason` fields read `CLOSED`/`COMPLETED`.

### Finding 11: The `open` mandate is written into eight places across the config

**Evidence:**

| Location | Text |
|---|---|
| `~/.claude/CLAUDE.md:888` | `**File** as HTML through a template (see Layer 4), opened with \`open\` for the engineer to consume` |
| `~/.claude/CLAUDE.md:889` | ``a terminal has no copy button, so code beyond ~10 lines goes to a `/tmp/` file opened with `open` `` |
| `~/.claude/CLAUDE.md:890` | ``Code the engineer will **run** (`open` the file to execute) … **File** in `/tmp/`, opened with `open` `` |
| `~/.claude/CLAUDE.md:923` | ``human-facing HTML is a self-contained local file in `/tmp/`, opened with `open`, never a published Artifact`` |
| `~/.claude/CLAUDE.md:1350` | ``# HTML report templates — self-contained, opened with `open` (see § Output Policy)`` |
| `~/.claude/docs/OUTPUT-EDGE-CASES.md:129` | ``The local `/tmp/` HTML opened with `open` already delivers everything an Artifact would`` |
| `~/.claude/templates/html/base.html:16` | ``3. Open with `open <path>` — engineer reads in browser`` |
| `~/.claude/scripts/inject-output-policy-reminder.sh:50` | ``render HTML from ~/.claude/templates/html/<pattern>.html to /tmp/, open with `open`.`` |

**Source:** `grep` over `~/.claude`, this session

**Significance:** sizes the change. The hook at `inject-output-policy-reminder.sh:50` matters most — it re-injects the instruction at the start of *every* engineer turn, so leaving it untouched would keep reproducing the behavior regardless of what the prose says. `CLAUDE.md:890` is a different case and must **not** be changed: it governs a file the engineer opens to *execute*, where `open` is the correct verb.

**Verification:** `grep -rn` executed against `~/.claude`; each path and line number is from the grep output.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A — Browser pane (write the file, drop the `open`)** | No external window raised; per-session isolation; zero Chrome tabs; templates work unchanged (inline JS + CDN); already the default behavior | Only exists in the desktop app, not a terminal session; stale-render risk on a re-used filename; pane accumulates tabs (contained, per-session) | Findings 2, 3, 4, 5, 8, 6 |
| **B — `open -g` (keep Chrome, background it)** | One-flag change; works on any entrypoint including terminal | Does not stop tab accumulation — the six unlabelled tabs problem persists; still routes every session's output into one shared Chrome | Finding 1 |
| **C — Status quo (`open`)** | Zero work | Raises Chrome on every report, across every session; tabs accumulate unattributed | Engineer's report; Finding 11 |
| **D — `SendUserFile` with `display: "render"`** | In-app side panel, explicit delivery with a caption | Untested in this spike; a second in-app surface alongside the pane, with no established rule for which to use | Not measured — see open questions |

## What remains uncertain

- **Does rendering into the pane raise the Claude Code window when that session is not frontmost?** Not measurable from inside the session — it needs focus instrumentation (`lsappinfo front` sampled before/after by an external observer). The mechanism argues no: the pane is a sub-view of an existing window, and macOS focus-stealing comes from LaunchServices activating an application, which `open` does and a webview render does not. Cheap validation: keep one session in the background, have it write a report, and see whether the window comes forward.
- **`SendUserFile` with `display: "render"` was not exercised.** It is the other in-app surface and may be a better fit for a deliberate hand-off, but adopting it would need a rule separating it from the pane.
- **Terminal-entrypoint sessions have no Browser pane.** This machine reports `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, so it is unaffected, but any rule written must carry a terminal fallback — `open -g` is the natural one.
- **Tab accumulation inside the pane** is bounded per session and far less harmful than Chrome tabs, but no cleanup discipline exists. `tabs_close` is available if one is wanted.

## Options for the engineer

- **Option A — Change the policy to "write the file, do not call `open`", with `open -g` as the terminal fallback.** Touches the seven sites in Finding 11 (excluding `CLAUDE.md:890`), most importantly the per-turn hook. Relief is immediate for desktop sessions and needs no new tooling.
- **Option B — Add a mechanical guard.** A `PreToolUse(Bash)` hook in the shape of the existing `redirect-terraform.sh` / `redirect-home-path.sh`: when the command is `open <path>.html`, block it on `claude-desktop` (the file is already in the pane) and rewrite it to `open -g` on a terminal entrypoint. Follows established repo precedent and does not depend on the prose being re-read.
- **Option C — A and B together.** The prose change alone repeats the pattern that the existing config notes elsewhere: a documented rule that keeps being violated is what motivated the redirect hooks in the first place.
- **Option D — Do nothing to the config, and rely on the behavior already being the default.** Costs nothing, but leaves the written policy actively instructing the opposite.

---

> **Authoring:** written by the main session as time-boxed research to reduce uncertainty. Every claim cites its source (`file:line` + quote for local evidence, tool-result text for live probes, URL + verbatim quote for upstream issues). The four upstream issues were fetched with `gh issue view` rather than read from a search summary, and their `state`/`stateReason` fields are quoted from the fetched JSON.
