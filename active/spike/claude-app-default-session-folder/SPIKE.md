# SPIKE — Claude Code Desktop App: Default Project Folder for New Sessions

## Investigation question

In the Claude Code native desktop app on macOS, can the engineer guarantee that every new session — specifically one opened with Cmd+N — starts anchored at a fixed project folder of their choosing (`~/Projects/4Shark`), rather than defaulting to the last-used folder, to no folder, or to anything else?

Five sub-questions structure the research:

1. Does the desktop app expose any setting/preference/config — in-app Settings UI, `settings.json`, managed settings, `claude_desktop_config.json`, or an environment variable — that sets a default/fixed project folder for new sessions?
2. What does the app actually do when a new session is created with no explicit folder choice?
3. Is there a launch-time mechanism (CLI invocation, URL scheme, `.app` argument, `open -a`, macOS Shortcut, documented automation hook) that could pin the folder?
4. Do `anthropics/claude-code` GitHub issues discuss this?
5. Does the documented relationship between a session's project folder and the Browser pane's storage scope exist (re-confirming the prior spike)?

## Sources consulted

- https://code.claude.com/docs/en/desktop — fetched 2026-08-05, full page (965 lines), read start to end. See auxiliary `claude-app-default-session-folder_doc_1.txt` for the extracted "Start a session", "Work in parallel with sessions", keyboard-shortcuts, Browser-pane-isolation, and "Failed to load session" passages. Answers Sub-questions 1, 2, 5.
- https://code.claude.com/docs/en/settings — fetched 2026-08-05, two passes (a full-page summarization query and a raw-markdown targeted fetch of the settings-files intro plus the alphabetically-early portion of the settings table). See auxiliary `claude-app-default-session-folder_doc_2.txt`. Answers Sub-question 1.
- https://code.claude.com/docs/en/deep-links — fetched 2026-08-05, full page. See auxiliary `claude-app-default-session-folder_doc_3.txt`. Answers Sub-question 3.
- `gh search issues --repo anthropics/claude-code` + `gh issue view` on the six matching issues (#44933, #46052, #46053, #46176, #47050, #57607) — run 2026-08-05. See auxiliary `claude-app-default-session-folder_log_1.txt`. Answers Sub-question 4.
- Read-only inspection of `/Applications/Claude.app/` (Info.plist, `app.asar`, `ion-dist/assets/v1/*.js`) via `plutil -p` and `grep -o -b -a` + `tail -c +N | head -c M`, 2026-08-05, app version 1.25927.0. See auxiliary `claude-app-default-session-folder_excerpt_1.txt`. Answers Sub-questions 1, 2, 3.
- `~/Library/Application Support/Claude/claude_desktop_config.json` on this machine — read directly in the main session, 2026-08-05 (see Finding 2). Answers Sub-question 1 for this one machine.
- `~/Projects/4Shark/dot-claude-plans/active/spike/claude-app-browser-session-persistence/SPIKE-v2.md` (2026-08-05) — read as background per the task briefing, not re-derived. Its Findings 1–3 and 8–9 are the basis for Sub-question 5 and for the "why this matters" context; this spike re-confirmed Finding 1 with an independent fresh fetch rather than citing it as already-settled.

## Findings

### Finding 1: The documented session-start flow requires picking a "Project folder" for every session; the docs describe no default, remembered, or pinned value

**Evidence:**

> "Before you send your first message, configure four things in the prompt area: **Environment** ... **Project folder**: select the folder or repository Claude works in. ... **Model** ... **Permission mode** ..."

**Source:** https://code.claude.com/docs/en/desktop, "Start a session" section (auxiliary `claude-app-default-session-folder_doc_1.txt`).

**Significance:** This is the entire documented account of how a session's folder is chosen. The word "select" is the only verb used, and no sentence anywhere in the "Start a session" section, the "Work in parallel with sessions" section, or the keyboard-shortcuts table describes a default value, a remembered value, or any way to pre-set the field before a session exists. The Cmd+N binding itself ("Click **+ New session** in the sidebar, or press **Cmd+N** on macOS ... to work on multiple tasks in parallel") is documented with no folder-default behavior attached to it.

`URL fetched / Verbatim quote checked / Quote substring confirmed at the "Start a session" section, full-page fetch 2026-08-05 (auxiliary doc_1.txt)`

### Finding 2: No `settings.json` key, managed-settings key, or `claude_desktop_config.json` preference sets a default project folder — a negative result corroborated by three independent checks

**Evidence, check A (settings.json full-page search):**

> "Based on my search of the provided documentation, I found no setting that controls what folder a new session in the desktop app opens with ... there is no key related to: Default project folder / Default working directory / Default repository / Recent folder / last folder / startDirectory (outside SSH configs) / Initial session folder for the desktop app"

**Evidence, check B (settings.json table, literal rows, alphabetical range `advisorModel`–`fastMode`):** 52 consecutive table rows read verbatim; none has a Key column containing folder/directory/dir/cwd/workspace/recent/last, or a `default*Project`/`default*Working`/`default*Folder` name. Full row list preserved in the auxiliary.

**Evidence, check C (this machine's own config file):**

> `"launchPreviewStorage": "shared", "launchPreviewPersistedWorkspaces": [...], "chromeExtensionEnabled": true, "coworkScheduledTasksEnabled": true, ...` — no `defaultProjectFolder`, `defaultWorkspaceFolder`, `cowork.defaultWorkspaceFolder`, or `chillingSlothLocation` key present anywhere in `~/Library/Application Support/Claude/claude_desktop_config.json` on this machine.

**Source:** https://code.claude.com/docs/en/settings, both fetch passes (auxiliary `claude-app-default-session-folder_doc_2.txt`); `~/Library/Application Support/Claude/claude_desktop_config.json`, read directly 2026-08-05.

**Significance:** Directly answers Sub-question 1's first half. Two independent community bug reports corroborate this from their own machines — see Finding 9. **Caveat**: check B's raw fetch covers only the alphabetically-early portion of the settings table (the harness truncated the raw-markdown fetch at ~25k tokens); check A is a separate, full-page summarization pass not subject to the same truncation and is what covers the rest of the alphabet, so the negative result rests on check A for full coverage and check B for literal-row confirmation of the covered range.

`URL fetched / Verbatim quote checked / Quote substring confirmed against the settings.json fetch passes (auxiliary doc_2.txt) and against the config file read directly on this machine, both 2026-08-05`

### Finding 3: "Worktree location" is a real, documented Desktop setting, but it configures where a session's git-worktree COPY is stored — not which folder a session opens with

**Evidence:**

> "Worktrees are stored in `<project-root>/.claude/worktrees/` by default. You can change this to a custom directory in Settings → Claude Code under 'Worktree location'."

**Source:** https://code.claude.com/docs/en/desktop, "Work in parallel with sessions" section (auxiliary `claude-app-default-session-folder_doc_1.txt`).

**Significance:** This is the one Desktop-app setting whose name could be mistaken for the answer. It presumes a project folder has already been selected and only redirects where that folder's worktree copy is written — it does not affect the folder-selection step itself and cannot substitute for a default-folder feature.

`URL fetched / Verbatim quote checked / Quote substring confirmed at the "Work in parallel with sessions" section (auxiliary doc_1.txt)`

### Finding 4: A documented, launch-time, folder-pinning URL scheme exists (`claude-cli://open?cwd=...`) — but it opens the standalone CLI in a terminal window, not a Code-tab session inside the desktop app

**Evidence:**

> "A deep link is a `claude-cli://` URL that opens Claude Code in a new terminal window. The URL can carry a working directory and a prompt to pre-fill."
>
> "`cwd` — Absolute path to use as the working directory. Network and UNC paths are rejected, and so are paths that contain invisible or bidirectional control characters."
>
> "A new terminal window opens with Claude Code running in the directory the link specified, and the link's prompt text already in the input box."

**Source:** https://code.claude.com/docs/en/deep-links, full page (auxiliary `claude-app-default-session-folder_doc_3.txt`).

**Significance:** This is a real, working, documented mechanism that would reliably open at a fixed folder every time — `open "claude-cli://open?cwd=/Users/plribeiro3000/Projects/4Shark"` on macOS. It directly answers Sub-question 3 in the affirmative for a launch-time mechanism *existing*, but it launches the **standalone CLI in a terminal**, a structurally different surface from the desktop app's Code tab the engineer's question is about (Cmd+N, the session sidebar, the Browser pane). The doc's own architecture confirms the split: the handler app is a separate helper (`~/Applications/Claude Code URL Handler.app` on macOS), distinct from `Claude.app`, and the doc explicitly cross-references that the VS Code extension registers ITS OWN separate scheme (`vscode://anthropic.claude-code/open`) for opening a VS Code tab instead of a terminal — establishing that each surface (terminal CLI, VS Code, Desktop app) is documented separately and this page covers only the terminal-CLI one.

`URL fetched / Verbatim quote checked / Quote substring confirmed in the "How it works" and "Build a link" sections, full-page fetch 2026-08-05 (auxiliary doc_3.txt)`

### Finding 5: Opening or dragging a folder onto the installed desktop app routes it to Cowork, not to a new Code-tab session — a second, code-verified launch-time mechanism with a different destination than Finding 4's

**Evidence:**

Info.plist registers the app as a folder handler:

> `"CFBundleTypeName" => "Folder"` `"CFBundleTypeRole" => "Editor"` `"LSItemContentTypes" => ["public.folder"]`

The shipped `app.asar`'s Electron `open-file` handler for a dropped/opened directory:

> `async function Zi(e){if(o.o.info(\`Handling folder drop: ${e}\`), ...){ ... } let t=f.j.getDispatcher(u.d.webContents); if(!t){o.o.warn(\`LocalAgentModeSessions dispatcher not available\`);return} t.dispatchOnCoworkFromMain({selectedDirectories:[e]}), u.f&&!u.f.isDestroyed()&&(u.f.show(),u.f.focus())}`

**Source:** `/Applications/Claude.app/Contents/Info.plist` (via `plutil -p`); `/Applications/Claude.app/Contents/Resources/app.asar`, byte offset 10127369 (auxiliary `claude-app-default-session-folder_excerpt_1.txt`, section 2). App version 1.25927.0, read 2026-08-05.

**Significance:** `open -a Claude ~/Projects/4Shark`, dragging that folder onto the Dock icon, or Finder's "Open With → Claude" all trigger this code path — a genuine, OS-registered, launch-time mechanism (answers Sub-question 3 with a second candidate). But the destination is literally named `dispatchOnCoworkFromMain` against a dispatcher looked up by the name `LocalAgentModeSessions` — **Cowork**, the Dispatch/persistent-conversation tab, not the Code tab. There is no branch in this function that opens a new Code-tab session anchored at the folder directly. Per the desktop docs' Cowork section (https://code.claude.com/docs/en/desktop, full-page fetch 2026-08-05; this passage sits outside the sections extracted into `claude-app-default-session-folder_doc_1.txt`), a Cowork task can become a Code session only "you ask for one directly ... or Dispatch decides the task is development work and spawns one on its own" — an indirect, judgment-mediated hop, not a guaranteed direct anchor.

`File read / Verbatim strings checked / Substrings confirmed at the cited byte offset (auxiliary excerpt_1.txt, section 2), app bundle read 2026-08-05`

### Finding 6: The desktop app's OWN `claude://` scheme (distinct from `claude-cli://`) supports a `resume` path for reopening an existing session by transcript — not for pinning a new session's folder

**Evidence:**

> `` description:`Error toast when a claude://resume deep link fails because the desktop app's own sign-in has expired or account info is unavailable.` ``
>
> `` description:`Error toast when a claude://resume deep link references a CLI session whose transcript is not on disk.` ``

**Source:** `/Applications/Claude.app/Contents/Resources/app.asar`, byte offset 10060577 (auxiliary `claude-app-default-session-folder_excerpt_1.txt`, section 3).

**Significance:** Confirms the `claude://` scheme registered by `Claude.app` itself (Info.plist, Finding 5) is a separate grammar from `claude-cli://` (Finding 4), and that its documented-in-code use is resuming a specific, already-existing session by its CLI transcript — a handoff/continuity feature, not a default-folder-for-new-sessions feature. No `folder=`, `cwd=`, or `path=` parameter was found associated with this scheme in the strings searched.

`File read / Verbatim strings checked / Substrings confirmed at the cited byte offset (auxiliary excerpt_1.txt, section 3), app bundle read 2026-08-05`

### Finding 7: The composer's own folder-picker UI is fed by a "frecent" (frequency + recency) list of the engineer's previously used folders, and its own unselected state is a placeholder, not a default

**Evidence:**

> `noFolders:{defaultMessage:"No recent folders. Browse to choose one.",id:"uZDrCkKZ4T"}`
>
> `U=(0,z.memo)(function({value:e,frecentTargets:s,onSelect:a,onBrowse:t,disabled:o}){ ... value:e??null, ... triggerLabel:e?y(e,void 0):r.formatMessage(G.selectFolder), ...`

**Source:** `/Applications/Claude.app/Contents/Resources/ion-dist/assets/v1/c0243d234-CX00KggP.js`, offset 0–2600 (auxiliary `claude-app-default-session-folder_excerpt_1.txt`, section 4).

**Significance:** Directly relevant to Sub-question 2 — what actually happens with no explicit choice. The picker component's list source is a prop literally named `frecentTargets`, the community-established term (from Firefox/Mozilla Places) for a frequency+recency-ranked list — i.e. the app remembers and surfaces the engineer's PAST folders as convenient re-selections, not as a persistent single default. Absent an incoming `value`, the component's own fallback is the literal string "Select folder" (`value:e??null`). **Limit of this evidence**: this spike traced multiple `LocalSessions.start` call sites in the bundle (a scheduled-task "Run now" flow, a Cowork task-suggestion "Fix in this session" flow, a background-task-suggestion chip flow) but did not locate or byte-verify the specific initializer for the plain sidebar "+ New session"/Cmd+N composer's own folder state — so this finding establishes what the SHARED picker component does when GIVEN no value, not a directly-confirmed trace of what value the Cmd+N composer supplies it by default.

`File read / Verbatim strings checked / Substrings confirmed at byte offset 0 of the cited file (auxiliary excerpt_1.txt, section 4), app bundle read 2026-08-05`

### Finding 8: A genuine per-Space folder-remembering mechanism (`ccdFolderPath`) exists in the shipped app — but it is scoped to a claude.ai "Space" composer with multiple attached folders, a different session-creation surface than the plain Cmd+N flow

**Evidence:**

> `h=(...)=>{const s=i.trim(); s&&!c&&(1!==e.folders.length?e.ccdFolderPath?x(e.ccdFolderPath,s):(p.current=s,m(!0)):x(e.folders[0].path,s))}`
>
> `f=(...)=>{m(!1), t&&S?.updateSpace?.(e.id,{ccdFolderPath:s}), await x(s,p.current)}`
>
> placeholder text: `Zt(1===e.folders.length?e.folders[0].path:e.ccdFolderPath??t.formatMessage({defaultMessage:"Choose on start",id:"UtWNsA/DcV"}),void 0)`

**Source:** `/Applications/Claude.app/Contents/Resources/ion-dist/assets/v1/c17beaa76-CssaINS2.js`, byte offset 98700 (auxiliary `claude-app-default-session-folder_excerpt_1.txt`, section 5).

**Significance:** Answers Sub-question 1 with a real, code-verified mechanism the docs never name — but it is not the mechanism the sub-question asks about. `e` here is a claude.ai "Space" (Project) object; `ccdFolderPath` is a value persisted ON THAT SPACE via `updateSpace(id, {ccdFolderPath})`. Behavior: a Space with exactly one attached folder always uses it, silently, with no picker. A Space with multiple attached folders checks `ccdFolderPath`: unset the first time (shows "Choose on start" and opens a picker), then reused silently on every subsequent session start from THAT SAME SPACE'S composer once set. This is scoped per-Space, not per-app and not per-workspace-root; this spike found no code path connecting it to the plain sidebar "+ New session" button or the Cmd+N shortcut described in Finding 1. It demonstrates the underlying product HAS built a remember-my-folder pattern somewhere, just not (as far as this spike traced) in the surface asked about.

`File read / Verbatim strings checked / Substrings confirmed at byte offset 98700 of the cited file (auxiliary excerpt_1.txt, section 5), app bundle read 2026-08-05`

### Finding 9: Six `anthropics/claude-code` GitHub issues directly request or report this exact gap; none carries an Anthropic maintainer response, and closures are bot-driven inactivity closures, not confirmed fixes

**Evidence:**

> "[FEATURE] Desktop app: Remember/pin default project folder" ... "Every time I start a new session in the Claude Code desktop app, I have to click 'Select folder' and navigate to my project directory. There's no way to set a default folder." (#46053, and its near-duplicate #46052)

> "Config files — Checked claude_desktop_config.json and every other config location I could find. There's no defaultWorkspaceFolder key or anything similar. ... Bottom line: There is no workaround." (#44933, comment by cameron-bales-telus-health)

> "Previously (as of April 9, 2026), opening a new conversation in the desktop app would default to the last-used project folder. After an update, it now defaults back to the home directory (~)." (#46176)

**Source:** `gh search issues --repo anthropics/claude-code "default project folder"` + `gh issue view` on all six hits, 2026-08-05 (auxiliary `claude-app-default-session-folder_log_1.txt`).

**Significance:** Directly answers Sub-question 4. Six distinct issues (#44933 open, #46052/#46053/#46176/#47050/#57607 closed) describe this exact gap across macOS, Windows, and both the Code tab and Cowork surfaces. **Every closure in this set is either `NOT_PLANNED` — the `github-actions` bot auto-closing for inactivity, the same pattern 4Shark's own CLAUDE.md documents elsewhere as NOT evidence the underlying behavior was addressed — or `DUPLICATE`: #46052 as a duplicate of #46053, which is in this set, and #47050 as a duplicate of #46680, which is outside it and was not separately fetched.** No comment from an Anthropic-affiliated account appears in any of the six threads. #46176 and a comment in #47050 each separately allege a REGRESSION (the app used to default to the last-used folder and an update removed that), but neither claim carries maintainer confirmation and this spike found no corroborating changelog entry (not separately checked in this pass — see "What remains uncertain").

`URL fetched / Verbatim quote checked / Quote substring confirmed against gh CLI JSON output for all six issues, 2026-08-05 (auxiliary log_1.txt)`

### Finding 10: The documentation still describes no connection between a session's project folder and the Browser pane's storage scope — re-confirmed with a fresh, independent fetch

**Evidence:**

> "The Browser pane uses a clean browser profile, separate from your personal browser, with none of your saved logins or history."

**Source:** https://code.claude.com/docs/en/desktop, "Choose between the Browser and the Chrome extension" subsection (auxiliary `claude-app-default-session-folder_doc_1.txt`).

**Significance:** This spike's own full-page fetch (965 lines, read start to end) found no occurrence of "partition", "hash", "MD5", or any sentence linking "Project folder" to the Browser pane's cookie/storage scoping — the same negative result the prior spike (`claude-app-browser-session-persistence/SPIKE-v2.md`, Findings 1 and 4) established on 2026-08-05 with an earlier fetch. This finding does not re-derive that spike's binary-level evidence (the `launchPreviewStorage` preference and the MD5-of-project-path partition-naming scheme) — it only confirms the documentation-level negative result still holds on a second, independent fetch of the same page.

`URL fetched / Verbatim quote checked / Quote substring confirmed at the "Choose between the Browser and the Chrome extension" subsection, full-page fetch 2026-08-05 (auxiliary doc_1.txt)`

### Finding 10: The `chillingSlothLocation.customPath` preference relocates git worktrees, not a session's project folder — it cannot pin where a new session is anchored

**Evidence:** the preference is read in exactly two places, both inside the worktree-path logic:

> `getWorktreeParentDir(e){let t=o.n(`chillingSlothLocation`);if(typeof t===`object`&&`customPath`in t){let n=E.basename(e),r=E.join(t.customPath,n);return E.resolve(r)===E.resolve(e)?E.join(t.customPath,`${n}-worktrees`):r}return E.join(e,`.claude`,`worktrees`)}`

> `isManagedWorktreePath(e,t){ … let a=o.n(`chillingSlothLocation`);if(typeof a===`object`&&`customPath`in a){let n=E.resolve(a.customPath); … let o=[E.join(n,i),E.join(n,`${i}-worktrees`)]; … }return!1}`

The sibling keys sharing the `chillingSloth` prefix are capability flags for a sandbox/VM feature — `chillingSlothFeat`, `chillingSlothSshShell`, `chillingSlothEnterprise`, `chillingSlothLocal`, `chillingSlothPool` — none of which reads a project folder.

**Source:** `/Applications/Claude.app/Contents/Resources/app.asar` at byte offset 15415015 (both readers of the key) and 6564367 (the capability-flag list), located with `grep -o -b -a` and read with `tail -c +N | head -c M`, 2026-08-05

**Significance:** the key's whole effect is to substitute a caller-chosen parent directory for the default `<repo>/.claude/worktrees` when the app creates or recognizes a worktree. It never participates in choosing the folder a session is anchored at, so it cannot make a new session open at a fixed path and it does not influence the Browser pane's partition, which keys on the anchored project folder. Setting it would move worktrees outside the repository — the opposite of 4Shark's own worktree placement rule, which puts them at `<repo>/.claude/worktrees` deliberately so a project `.envrc` and Terramate relative paths resolve through the parent directory chain.

`File read / Verbatim strings checked / Substrings confirmed at byte offsets 15415015 and 6564367 of app.asar, app bundle mtime 2026-08-04`

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Manually pick `~/Projects/4Shark` every Cmd+N | No setup; works today | Repetitive; nothing prevents picking the wrong folder on a distracted day | Finding 1 |
| Rely on the "frecent" folder list to resurface `~/Projects/4Shark` at/near the top | No setup beyond using it repeatedly; self-reinforcing | Not a guarantee — it is a ranked list the engineer still has to open and click, not an auto-fill; competes with every OTHER folder used recently | Finding 7 |
| `open "claude-cli://open?cwd=~/Projects/4Shark"` (shell alias / macOS Shortcut) | Documented, real, launch-time folder pin; scriptable | Opens the standalone CLI in a terminal window, not a Code-tab session in the desktop app — does not touch the Browser pane or the sidebar workflow the question is about | Finding 4 |
| `open -a Claude ~/Projects/4Shark` (shell alias / macOS Shortcut / Dock drag) | Documented (Info.plist) OS-level registration; real, launch-time | Routes to Cowork (`dispatchOnCoworkFromMain`), not directly to a new Code-tab session; becoming a Code session depends on Dispatch's own judgment or an explicit follow-up ask | Finding 5 |
| Start every session from within a claude.ai Space that has `~/Projects/4Shark` as its one attached folder | A real, code-verified mechanism (`ccdFolderPath` / single-folder auto-use) that DOES anchor reliably once set up | A different composer/surface than the plain sidebar; requires setting up and using a Space instead of the ordinary "+ New session" flow; not verified against the Cmd+N/sidebar flow | Finding 8 |
| File a new GitHub issue / react on an existing open one (#44933) | Contributes to the signal Anthropic might act on | No effect on current behavior; six existing issues on this exact gap have produced no maintainer response | Finding 9 |

## What remains uncertain

- **Whether the plain sidebar "+ New session" (Cmd+N) composer's folder state is ever pre-filled from the "frecent" list's top entry, or always starts unselected.** Finding 7 establishes the shared picker component's own fallback (an unselected placeholder when given no value) and that a DIFFERENT composer (the scheduled-Routine dialog) feeds it `value:e.cwd` from its own local state — but this spike did not locate and byte-verify the specific `cwd`/folder-state initializer for the Cmd+N sidebar composer itself. The GitHub issue evidence is split on this exact point: #46176's reporter claims the app "would default to the last-used project folder" before an alleged regression, while #44933's commenter states unambiguously "Each new session starts with no folder selected" (for Cowork specifically). Neither claim is independently confirmed against the code in this spike.
- **Whether the alleged regression in #46176 and #47050 (folder-default behavior existing, then removed by an update) is real, and if so when.** Not checked against the Claude Code changelog in this pass — the prior spike's Finding 5 checked the changelog for Browser-pane/cookie/partition/worktree/storage keywords in the 2026-07-01–2026-08-04 window specifically, not for folder-default/session-start keywords, so it does not settle this question either.
- **Whether the alleged folder-default behavior the #46176 and #47050 reporters describe ever shipped.** The `chillingSlothLocation.customPath` key those reports point at governs worktree placement rather than session-folder selection (Finding 10), so it cannot be the mechanism they remember; what they are describing, if anything, is some other behavior this spike did not locate.
- **Whether a macOS Shortcut/Automator action, distinct from the two launch-time mechanisms found (Findings 4 and 5), could combine `open -a Claude <folder>` with a scripted follow-up (e.g. simulating Cmd+N after the app is frontmost) to land directly on a new Code-tab session.** Not tested — the spike briefing forbids launching the app to test dynamically, and no such combined/scripted mechanism is documented by Anthropic.
- **Whether starting every session from within a claude.ai Space (Finding 8) is a practical fit for the engineer's actual workflow** — it requires adopting the Spaces feature and setting `~/Projects/4Shark` as that Space's one attached folder, which is a workflow change, not a setting toggle, and this spike did not investigate what else changes about session behavior when started from a Space versus the plain sidebar.

## Suggested options for main and the engineer

- **Option A**: Accept that no setting/mechanism guarantees a fixed default folder for the plain Cmd+N flow (Findings 1, 2, 3, 9), and manually re-select `~/Projects/4Shark` each time, relying on the "frecent" list (Finding 7) to make the re-selection fast once it is habitual.
- **Option B**: Build a shell alias or macOS Shortcut around `open "claude-cli://open?cwd=~/Projects/4Shark"` (Finding 4) for workflows that are fine with the standalone CLI in a terminal, accepting this does not touch the desktop app's Code tab/Browser-pane surface the original investigation (SPIKE-v2) was about.
- **Option C**: Adopt a claude.ai Space with `~/Projects/4Shark` as its single attached folder and start Code sessions from that Space's own composer (Finding 8), accepting the workflow change and the residual uncertainty about how that composer otherwise differs from the plain sidebar.
- **Option D**: React on or comment on the open GitHub issue #44933 (or file a new, Code-tab-scoped issue distinct from Cowork's) to add signal toward Anthropic building this, accepting no near-term effect on current behavior (Finding 9).

(No recommendation — these are the surfaced options and their sourced trade-offs; the engineer decides.)
