# SPIKE v2 — Claude Code Native Desktop App: In-App Browser Pane GitHub Session (Follow-up)

## Investigation question

This is a follow-up to `SPIKE.md` (2026-07-17), which established that the Browser pane uses a "clean browser profile" isolated from the engineer's personal browser (documented) but could not confirm a specific mechanism for the daily-login pattern, and left the storage/partitioning mechanism as an open question.

New local evidence gathered in the main session on 2026-08-05 (treated here as given, not re-derived — see "Local evidence" below) shows the Browser pane's cookie storage is split across per-project `Partitions/launch-preview-<hex>` directories, where `<hex>` is the first 12 hex characters of the MD5 hash of the session's project directory path, and that cookies DO persist on disk for at least 19 days within one such partition. This directly contradicts the prior spike's untested "ephemeral/in-memory session" hypothesis (`SPIKE.md` Finding 8) for the partition that was checked.

Refined questions for this follow-up:

1. Does Anthropic document the Browser pane's storage partitioning at all — per project, per session, or per workspace? Is there anything beyond the "clean browser profile" sentence and the "Persist sessions" dropdown item the prior spike already found?
2. Is there any user-settable configuration (a `settings.json` key, an app GUI toggle, an environment variable, or a managed setting) that changes this scoping, shares one browser profile across projects, or persists an external-site login? Does the documentation say anything about an app update resetting such a setting?
3. Do GitHub issues on `anthropics/claude-code`, searched with different terms than the prior spike used, report the Browser pane requiring repeated login, per-project browser profiles, cookie jars not shared between projects, or a settings reset on update?
4. Does the Claude Code changelog show any change to the Browser pane, its storage, partitions, or session handling between 2026-07-17 and 2026-08-05 that would explain a regression in that window?
5. What is the current documented state of the Claude in Chrome extension (the alternative that reuses the engineer's real logged-in Chrome session) — prerequisites, plan requirements, and any change since 2026-07-17?

## Local evidence (established in the main session before this spike — restated for traceability, not re-derived)

- The app stores per-partition cookie jars under `~/Library/Application Support/Claude/Partitions/`. Directories present on this machine: `cowork-file-preview`, `launch-preview-static`, `launch-preview-6666cd76f969`, `launch-preview-8f8bac277cb8`, `launch-preview-b24d16acb542`, `launch-preview-cabfb3a90b75`.
- The `launch-preview-<hex>` suffix is the first 12 hex characters of the MD5 of the session's project DIRECTORY PATH (verified by direct `md5 -s` computation): `md5 -s "/"` → `6666cd76f969...` → partition `launch-preview-6666cd76f969`; `md5 -s ".../dot-claude"` → `b24d16acb542...` → `launch-preview-b24d16acb542`; `md5 -s ".../integrator"` → `cabfb3a90b75...` → `launch-preview-cabfb3a90b75`; `md5 -s ".../app"` → `8f8bac277cb8...` → `launch-preview-8f8bac277cb8`.
- `sqlite3` (read-only) against the `Cookies` database in partition `launch-preview-6666cd76f969` (project directory `/`) shows `github.com` and `.github.com` cookies with max creation date 2026-07-17 — 19 days old at the time of this spike and still present.
- Partition `launch-preview-cabfb3a90b75` (project directory `.../integrator`) holds only 2 `.github.com` cookies, both created today (2026-08-05) — the anonymous, not-logged-in set.
- `~/Library/Application Support/Claude/config.json` contains no key matching `browser`/`persist`/`cookie`/`session`/`preview`.

## Sources consulted

- https://code.claude.com/docs/en/desktop — refetched 2026-08-05, two independent passes (a full-page paginated read and a targeted-quote pass); text unchanged from the prior spike's 2026-07-17 fetch in every section that overlaps. See Findings 1-3.
- https://code.claude.com/docs/en/settings — refetched 2026-08-05, targeted at Browser-related keys; confirms the same two managed-only keys as the prior spike, no new key. See Finding 2.
- https://code.claude.com/docs/en/chrome — refetched 2026-08-05, full page; found one NEW passage not present in the prior spike's 2026-07-17 excerpt, about Chrome integration requiring `/login` (subscription) auth. See Finding 6.
- https://code.claude.com/docs/en/changelog — fetched 2026-08-05, two passes covering every version from 2.1.198 (2026-07-01) through 2.1.222 (2026-08-04). See Finding 5.
- `gh search issues --repo anthropics/claude-code` — 28 additional queries beyond the prior spike's 11, all with different terms. See Finding 4.
- See auxiliary: `claude-app-browser-session-persistence_v2_doc_1.txt` — full excerpt of the desktop docs' Browser-pane-relevant sections plus the negative-result confirmation (no partition/hash/scoping language found anywhere on the page)
- See auxiliary: `claude-app-browser-session-persistence_v2_doc_2.txt` — full excerpt of the Chrome docs, including the new `/login`-requirement passage and the version-number cross-reference to the changelog
- See auxiliary: `claude-app-browser-session-persistence_v2_doc_3.txt` — every changelog bullet matching Browser/cookie/session/partition/worktree/storage keywords across 2.1.198-2.1.222, with the negative result stated
- See auxiliary: `claude-app-browser-session-persistence_v2_log_1.txt` — the full list of 28 GitHub issue search queries run today with their result counts, continuing from the prior spike's 11

## Findings

### Finding 1: The Browser pane's "clean browser profile" is the only documented storage-isolation statement; no partition/hash/per-directory storage mechanism is documented anywhere on the desktop docs page

**Evidence:**

> "The Browser pane uses a clean browser profile, separate from your personal browser, with none of your saved logins or history. Use it for building and testing your app and for sites that don't need your identity. When you want Claude to act as you in your logged-in sessions, use the Claude in Chrome extension instead, which shares your browser's login state."

**Source:** https://code.claude.com/docs/en/desktop, "Choose between the Browser and the Chrome extension" subsection (auxiliary `claude-app-browser-session-persistence_v2_doc_1.txt`, lines 136-138)

**Significance:** Directly answers Research Question 1's first half: nothing beyond this sentence and the "Persist sessions" item (Finding 2) describes the Browser pane's storage. A full-text check of the fetched page (both fetch passes) confirms the words "partition", "hash", "MD5" do not appear anywhere on the page, and no sentence connects "worktree" (which the page uses extensively for CODE isolation — see Finding 3) to the Browser pane's cookie storage. The local partition-directory evidence (per-project-directory MD5-named folders) is therefore an OBSERVED IMPLEMENTATION DETAIL on this machine, not a documented behavior — see "What remains uncertain".

`URL fetched / Verbatim quote checked / Quote substring confirmed at the "Choose between the Browser and the Chrome extension" subsection, both 2026-08-05 fetch passes, byte-identical to the prior spike's 2026-07-17 quote`

### Finding 2: The desktop docs establish that "Project folder" is chosen once per session at session-start, and that a session's code isolation happens via git worktrees stored under `.claude/worktrees/` — a documented mechanism the page never connects to the Browser pane's storage

**Evidence:**

> "In the Code tab, each conversation is a **session**: it has its own chat history, project folder, and code changes, independent of any other session."

> "Before you send your first message, configure four things in the prompt area: ... **Project folder**: select the folder or repository Claude works in. ..."

> "For Git repositories, each session gets its own isolated copy of your project using Git worktrees, so changes in one session don't affect other sessions until you commit them. ... Worktrees are stored in `<project-root>/.claude/worktrees/` by default."

**Source:** https://code.claude.com/docs/en/desktop, "Start a session" and "Work in parallel with sessions" subsections (auxiliary `claude-app-browser-session-persistence_v2_doc_1.txt`, lines 29, 45-48, 321-329)

**Significance:** This establishes vocabulary needed to interpret the local evidence: the "project folder" is a value the engineer selects once when starting a session (e.g. `~/Projects/4Shark/integrator`), and Claude Desktop's own CODE isolation (via git worktrees under that folder) is a separate, well-documented mechanism from whatever produces the Browser pane's `Partitions/launch-preview-<hex>` directories. The local evidence (see "Local evidence" above) computed the MD5 hash directly against the SELECTED PROJECT FOLDER path (e.g. `.../integrator`), not against a worktree subpath (e.g. `.../integrator/.claude/worktrees/some-branch`) — so the partition naming tracks the project-folder SELECTION, not the per-session worktree Claude Desktop creates underneath it. This is an inference from the local MD5 verification, not a documented fact — the docs never state what the partition key is derived from.

`URL fetched / Verbatim quote checked / Quote substring confirmed at lines 29, 47-48, and 323/327 of the fetched desktop docs page (auxiliary doc_1.txt)`

### Finding 3: The "Persist sessions" toggle remains textually scoped to the local dev-server preview feature — unchanged from the prior spike, re-confirmed by an independent fetch

**Evidence:**

> "Persist cookies and local storage across server restarts by selecting **Persist sessions** in the dropdown, so you don't have to re-login during development"

Followed immediately by the start of a new subsection with no cross-reference:

> "### Browse external sites
> The Browser pane is a tabbed browser, so you can open documentation, issue trackers, or any other site next to your running app..."

**Source:** https://code.claude.com/docs/en/desktop, "Preview your app" / "Browse external sites" subsections (auxiliary `claude-app-browser-session-persistence_v2_doc_1.txt`, lines 111-121)

**Significance:** Re-confirms the prior spike's Finding 2 with an independent fetch on 2026-08-05: this text is byte-identical to the 2026-07-17 quote. The prior spike's uncertainty ("whether 'Persist sessions' also happens to affect external-site tabs is not stated either way") remains unresolved by the documentation — it is still an inference from document structure, not a confirmed fact.

`URL fetched / Verbatim quote checked / Quote substring confirmed at lines 111-121 of the fetched desktop docs page (auxiliary doc_1.txt)`

### Finding 4: No new settings.json key, GUI toggle location, or managed setting for Browser-pane cookie/session persistence or cross-project profile sharing was found

**Evidence:**

> `browserExternalPageTools` — "(Managed settings only) set to `\"disabled\"` to prevent Claude from using tools to read or act on external pages in the Browser pane. Users can still navigate to external sites themselves, and local dev server previews are unaffected."

> `disableBrowserExternalNavigation` — "(Managed settings only) set to `true` to turn off external browsing in the Browser pane entirely. Neither users nor Claude can navigate to external sites, and localhost dev server previews are unaffected. The value must be the JSON boolean `true`; the string `\"true\"` is ignored."

> "To clear saved session data, or to turn the Browser off entirely, use the toggles in Settings → Claude Code."

**Source:** the `browserExternalPageTools` and `disableBrowserExternalNavigation` rows, including the "(Managed settings only)" prefix, are from https://code.claude.com/docs/en/settings, refetched 2026-08-05. The "To clear saved session data" sentence is from https://code.claude.com/docs/en/desktop, line 119 (auxiliary `claude-app-browser-session-persistence_v2_doc_1.txt`), refetched 2026-08-05.

**Significance:** Directly answers Research Question 2: no third managed-settings key, no user-level (non-managed) settings.json key, and no environment variable for Browser-pane cookie/session persistence or cross-project profile sharing was found in either doc page — this matches the prior spike's Finding 3 exactly, re-confirmed. The GUI toggle ("Settings → Claude Code" → clear session data / turn off Browser) is still documented only by that one sentence, with no stated on-disk storage location — consistent with the local `config.json` grep finding no matching key (see "Local evidence"). **Not found anywhere in either doc page**: any statement about an app update resetting a Browser-pane-related setting or toggle. The engineer's report of having changed a setting that later "reverted" cannot be confirmed or explained from the fetched documentation.

`URL fetched / Verbatim quote checked / Quote substring confirmed: the two managed-settings rows in the settings reference of code.claude.com/docs/en/settings; the clear-session-data sentence at line 119 of code.claude.com/docs/en/desktop (auxiliary doc_1.txt); both pages refetched 2026-08-05`

### Finding 5: No changelog entry between 2026-07-01 and 2026-08-04 (the full range covering and surrounding the investigation window) documents a change to the Browser pane's cookie storage, session/login persistence, or partitioning

**Evidence:** Every changelog bullet containing "Browser", "cookie", "session", "partition", "worktree", or "storage" across versions 2.1.198 (2026-07-01) through 2.1.222 (2026-08-04) is reproduced in auxiliary `claude-app-browser-session-persistence_v2_doc_3.txt`. None of them describes a change to the Browser pane's external-site cookie/session handling. The closest-adjacent entries are all about a DIFFERENT, documented mechanism — git worktrees for CODE isolation, e.g.:

> "Fixed worktree-isolated subagents redirecting git into the shared checkout via `git -C`, `--git-dir`, or `GIT_DIR`/`GIT_WORK_TREE`" (2.1.216, 2026-07-20)

> "Fixed worktree-isolated sessions and their subagents being able to run destructive git commands against the main checkout; isolation now applies to file edits and Bash in every session type" (2.1.222, 2026-08-04)

**Source:** https://code.claude.com/docs/en/changelog, fetched 2026-08-05 (auxiliary `claude-app-browser-session-persistence_v2_doc_3.txt`)

**Significance:** Directly answers Research Question 4: no documented change to the Browser pane's storage/session/partition handling exists in the window that would explain a regression the engineer is experiencing now versus before. Every "worktree" changelog entry in this range is about the separate, well-documented CODE-isolation mechanism (Finding 2), never the Browser pane's cookie partitions. This is a negative result, not proof nothing changed — an undocumented internal change is possible and would not appear in a public changelog.

`URL fetched / Verbatim quote checked / Quote substring confirmed against the version-by-version changelog dump, 2026-08-05 fetch (auxiliary doc_3.txt)`

### Finding 6: A documented behavior change landed inside the investigation window, but on the Claude in Chrome EXTENSION path (not the Browser pane) — Chrome integration now requires subscription (`/login`) authentication and is deliberately kept off for API-key/long-lived-token sessions

**Evidence:**

> "Chrome integration also requires signing in with `/login`. If you authenticate with an API key or a long-lived token from `claude setup-token`, Claude Code keeps Chrome integration off, even when you pass `--chrome`, because the browser extension can't authenticate with those credentials. Before v2.1.216, these sessions could enable Chrome integration, but every attempt to connect to the browser extension failed with a 403 error."

**Source:** https://code.claude.com/docs/en/chrome, fetched 2026-08-05 (auxiliary `claude-app-browser-session-persistence_v2_doc_2.txt`); cross-referenced against the changelog (auxiliary doc_3.txt): version 2.1.216 shipped 2026-07-20, three days after the prior spike's 2026-07-17 fetch, so this is a change that landed inside the investigation window

**Significance:** This is new information not present in the prior spike (which fetched the same page on 2026-07-17 and did not capture this passage — either because it postdates that fetch or because the prior spike's excerpt was not this precise passage). It answers Research Question 5's "any change since 2026-07-17" clause with a confirmed, dated example, but the change is about the CHROME EXTENSION alternative (Option B in the prior spike), not the in-app Browser pane the engineer reports the problem with. Practically: whether Claude in Chrome is available to the engineer as a fallback now depends on how his Claude Code authenticates (`/login` subscription vs. API key/long-lived token) — a fact not established in either spike. The rest of the Chrome-extension documentation (prerequisites list, login-state-sharing statement, third-party-provider restriction) is unchanged from the prior spike's 2026-07-17 fetch.

`URL fetched / Verbatim quote checked / Quote substring confirmed in the "Prerequisites" section of code.claude.com/docs/en/chrome, 2026-08-05 fetch (auxiliary doc_2.txt)`

### Finding 7: An expanded GitHub issue search (28 new queries, 39 total across both spikes) still finds no report matching the engineer's specific pattern

**Evidence:** See auxiliary `claude-app-browser-session-persistence_v2_log_1.txt` for the full list of 28 queries and their result counts. Two queries surfaced tangentially related issues, neither on point:

> Issue #75908, open: "preview_start pins a stale per-project working directory to a deleted git worktree; ignores config `cwd`" — about the LOCAL DEV-SERVER preview process's working directory, not external-site cookies.

> Issue #78767, open: "Preview: switching projects leaks previous project's window and orphans its dev-server process, blocking new project's ports" — same category, the dev-server preview process, not the Browser pane's cookie storage for external sites like github.com.

**Source:** `gh search issues --repo anthropics/claude-code`, run 2026-08-05, 28 queries (auxiliary log_1.txt)

**Significance:** Extends the prior spike's Finding 5 (11 queries, zero relevant hits) with 28 additional, differently-worded queries and the same result: no GitHub issue describes the Browser pane requiring repeated external-site login, per-project browser-profile scoping as a bug/feature request, cookie jars failing to persist between project folders, or an app update resetting a Browser-related setting. Combined with the prior spike, 39 distinct search strings have now been tried with no match. This is stronger negative evidence than the prior spike alone, though `gh search issues` full-text coverage is not independently verified to be exhaustive.

`URL fetched / Verbatim quote checked / Quote substring confirmed against gh CLI JSON output, 2026-08-05 (auxiliary log_1.txt)`

### Finding 8: The shipped desktop-app binary carries an undocumented three-state preference, `launchPreviewStorage`, that governs Browser-pane cookie retention — and the app's own UI hint scopes its "shared" state to a single project, not across projects

**Evidence:** the renderer bundle declares the three accepted values and reads the preference with `"none"` as the default:

> `var ga=["none","shared","session"];function ba(e){return ga.some(t=>t===e)}`

> `previewStorage:e?.launchPreviewStorage??"none",setPreviewStorage:(0,Ne.useCallback)(e=>{f?.setPreference?.("launchPreviewStorage",e)},[])`

The same bundle declares the Browser panel's settings-menu labels, each with a hint describing what that state does:

> `trigger:"Panel settings"` … `persistSessions:"Persist sessions",persistNone:"Don't keep",persistNoneHint:"Cleared when the app quits",persistShared:"Shared",persistSharedHint:"Same data for every session in this project",persistSession:"Separate",persistSessionHint:"Each session keeps its own"`

The main-process bundle derives the partition directory name by hashing a path:

> `function Nt(e){return b.default.createHash(`md5`).update(e).digest(`hex`).slice(0,12)}`

**Source:** `/Applications/Claude.app/Contents/Resources/ion-dist/assets/v1/c7c40fbbb-CjPpWvNx.js` (the `ga` array and the `setPreviewStorage` hook); `/Applications/Claude.app/Contents/Resources/ion-dist/assets/v1/c360a9e1c-DNZFFKN3.js` at byte offset 1550272 (the label/hint table); `/Applications/Claude.app/Contents/Resources/app.asar` (the MD5 partition-name function). App bundle timestamped 2026-08-04, read 2026-08-05.

**Significance:** this is the configuration Research Question 2 asked for, and it exists only in the binary — Finding 4 stands unchanged, because no Anthropic documentation page names `launchPreviewStorage` or its three states. Three consequences follow from the hint strings, which are the app's own descriptions and therefore the strongest available statement of intent. First, the default `"none"` is described as *"Cleared when the app quits"*, so a machine left on that default loses every jar it opened during that run — but see Finding 9 for the value actually in force on this machine. Second, `"shared"` is described as *"Same data for every session in this project"* — it unifies cookie storage across SESSIONS within one project, and does NOT unify across projects; the per-project partition boundary holds in all three states, so no setting produces a single cookie jar spanning projects. Third, `"session"` (*"Each session keeps its own"*) is strictly narrower than the per-project default. The `slice(0,12)` of an MD5 digest matches the locally-verified partition names exactly (see "Local evidence"), confirming the observed naming scheme against the code that produces it. The control is reached through the Browser panel's own "Panel settings" menu, not `settings.json` and not the "Settings → Claude Code" panel named in Finding 4.

`File read / Verbatim strings checked / Substrings confirmed at the cited bundle paths, the label table located by byte offset via `grep -o -b`, app bundle mtime 2026-08-04`

### Finding 9: On this machine the preference is already `"shared"`, stored in `claude_desktop_config.json`, and the app tracks a persisted jar for each of the four project folders whose partitions exist on disk

**Evidence:** the preference and its companion arrays, read from `~/Library/Application Support/Claude/claude_desktop_config.json` (byte offset 156):

> `"launchPreviewStorage": "shared",`

> `"launchPreviewPersistedWorkspaces": [ "6666cd76f969", "b24d16acb542", "8f8bac277cb8", "cabfb3a90b75" ],`

> `"launchPreviewSessionScopedSessions": [],`

Partition directory birth times (`stat -f "%SB"`): `launch-preview-6666cd76f969` (project folder `/`) born 2026-07-17; `launch-preview-cabfb3a90b75` (project folder `.../integrator`) born 2026-08-05.

**Source:** `~/Library/Application Support/Claude/claude_desktop_config.json` and `stat` on `~/Library/Application Support/Claude/Partitions/`, read 2026-08-05

**Significance:** the preference lives in `claude_desktop_config.json`, NOT in the sibling `config.json` in the same directory — `config.json` contains no `launchPreview*` key at all, so a grep aimed at it reports the setting as unset and yields the wrong conclusion that the default is in force. The four tracked workspace hashes are exactly the four `launch-preview-<hex>` partitions on disk, confirming that `"shared"` mode registers one persisted jar per project folder. Combined with the birth times, this rules out clearing as the cause of a repeated-login pattern on this machine: the `/` partition has existed since 2026-07-17 and still holds that day's GitHub login (see "Local evidence"), so a jar survives app restarts under `"shared"`, while the `integrator` partition came into existence on 2026-08-05 — the first time the Browser pane was used in a session anchored at that project folder. What remains, therefore, is the per-project boundary itself (Finding 8): every project folder browsed for the first time presents an empty jar and demands one login, and no value of `launchPreviewStorage` removes that boundary, `"shared"` being already the most permissive of the three.

`File read / Verbatim strings checked / Substrings confirmed in claude_desktop_config.json at byte offset 156 and in the stat output, both read 2026-08-05`

## Trade-offs surfaced

This section carries forward, unchanged in substance, the trade-off table from `SPIKE.md` (§ Trade-offs surfaced) — this follow-up did not find new information that changes any row. See `SPIKE.md` for the full table (`gh` CLI, Claude in Chrome, manual Chrome, in-app Browser pane status quo). The one addition from this spike: the Claude in Chrome row's "Requires a qualifying direct Anthropic plan" cost now has a documented precondition attached — Finding 6 — that it also requires `/login` (subscription) authentication specifically, not merely a qualifying plan; API-key or long-lived-token authentication keeps Chrome integration off regardless of plan.

## What remains uncertain

- **Whether the per-project-directory partition naming and the `launchPreviewStorage` states are a stable contract or an implementation detail subject to change without notice.** The mechanism itself is confirmed in the shipped binary (Finding 8), but no Anthropic documentation page names `launchPreviewStorage`, its three states, or the MD5-of-project-path partition scheme (Findings 1 and 4), and no changelog entry in the 2026-07-01 to 2026-08-04 range mentions any of them (Finding 5). A reader relying on this behavior is relying on an undocumented internal, which can change in a release with no public note.
- **Whether the `"Cleared when the app quits"` hint for the `none` state (Finding 8) describes clearing every partition on disk or only the partitions instantiated during that app run.** Untested: this machine runs `"shared"` (Finding 9), so none of the local evidence bears on how `none` behaves, and the clearing routine's reach was not traced through the binary.
- **Whether a repeated-login experience under `"shared"` is fully accounted for by first-time visits to new project folders, or whether some jar also loses its login while remaining registered.** Finding 9 rules out app-restart clearing for a jar that already holds a login, and the `integrator` partition's 2026-08-05 birth date shows at least one such login was a genuine first visit. The test that settles it: browse GitHub from a session anchored at an already-registered project folder, quit the app, and reopen a session anchored at that same folder — a login that survives confirms first-visit cost is the whole explanation; a login that does not survive means a second mechanism is at work and this spike has not found it.
- **Whether the engineer's day-to-day workflow selects a DIFFERENT "project folder" for different tasks/PR reviews** (e.g. reviewing an `integrator` PR from a session anchored at `~/Projects/4Shark/integrator` on one day, and a `dot-claude` PR from a session anchored at `~/Projects/4Shark/dot-claude` — or the workspace root `/` — the next), which would produce a genuinely different, never-before-used partition each time even though the Browser pane's underlying storage is not actually ephemeral. This is a plausible explanation consistent with all the local evidence gathered (the root `/` partition has 19-day-old persisted cookies; the `integrator` partition has only today's anonymous cookies) and the documented fact that "Project folder" is selected once per session — but it was not confirmed against the engineer's actual usage pattern in this spike, and no document states this is how the partition key is derived. Distinguish this from the earlier open question about whether cookies expire ON THEIR OWN within one partition — these are two different candidate explanations and this spike's evidence favors "different partition each time" over "expiry within the same partition", but does not rule out a combination of both.
- **Whether the "Settings → Claude Code" toggle to "clear saved session data" (Finding 4) could be triggered inadvertently** — its on-disk storage/state is not identified in either spike, so whether an accidental click, an app-update-triggered default, or some other action clears it cannot be confirmed or ruled out from documentation alone.
- **Whether the engineer's Claude Code authenticates via `/login` (subscription) or an API key/long-lived token** — this determines, per Finding 6, whether Claude in Chrome (Option B in the prior spike's Suggested Options) is even available to try as of v2.1.216 (2026-07-20). Not established in either spike.
- **Search coverage remains non-exhaustive** — 39 distinct GitHub issue search strings across two spikes found nothing, but `gh search issues`' full-text ranking and coverage were not independently verified to surface every matching issue (Finding 7).

## Suggested options for main and the engineer

- **Option A (carried forward from `SPIKE.md`):** Use `gh` CLI for the bulk of PR-review workflow — already authenticated, zero setup, immune to any Browser-pane session question (`SPIKE.md` Finding 6).
- **Option B (carried forward, with the Finding 6 precondition attached):** Install/enable Claude in Chrome for workflows needing the rendered GitHub web UI with a persistent, real login — reuses the actual Chrome session (`SPIKE.md` Finding 7) — but first confirm the engineer's Claude Code authenticates via `/login` (subscription), since API-key/long-lived-token auth keeps Chrome integration off as of v2.1.216 (this spike's Finding 6).
- **Option C (carried forward, sharpened by this spike's local-evidence inference):** Keep using the in-app Browser pane, and — if the engineer's daily workflow currently switches which "project folder" a session is anchored to for different tasks — deliberately anchor GitHub-review sessions to the SAME project folder each time (e.g. always the workspace root `/`, which already holds a persisted, 19-day-old login per the local evidence), to test whether that removes the daily-login pattern. This is an untested hypothesis, not a confirmed fix — see "What remains uncertain".
- **Option D (carried forward):** Disable the in-app Browser pane entirely via the "Settings → Claude Code" GUI toggle (`SPIKE.md` Finding 4), relying on Option A and/or B instead.
- **Option E (carried forward):** Continue the manual-Chrome fallback with no further tooling change.

- **Option F (new, from Findings 8 and 9):** Anchor GitHub-browsing sessions at a folder that CONTAINS every repository rather than at an individual repository, so all work shares one cookie jar. The partition key is the MD5 of the project folder the session is anchored at (Finding 8) — not of the folders the session touches while running — so a session anchored at `~/Projects/4Shark` maps to a single partition (`launch-preview-213582934a00`) covering every repo underneath it, and one GitHub login there serves all of them. Two pieces of evidence support this working: the `/` partition has held a GitHub login since 2026-07-17 (Finding 9), which is the same shape of high-level anchor; and `launch-preview-213582934a00` does not exist on disk, confirming no session has yet been anchored at the 4Shark parent folder. **The trade-off is real and must be weighed**: `~/Projects/4Shark` is not itself a git repository, so a session anchored there does not get the app's documented per-session git-worktree isolation, which operates on the project folder as a repo (Finding 2). This suits a workflow that spans several repositories per task; it does not suit a workflow that wants the app's automatic worktree isolation for a single repo.

(No recommendation — these are the surfaced options and the testable hypotheses this spike's local evidence supports; the engineer decides.)
