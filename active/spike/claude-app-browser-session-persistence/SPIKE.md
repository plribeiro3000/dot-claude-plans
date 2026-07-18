# SPIKE — Claude Code Native Desktop App: In-App Browser Pane Loses GitHub Session Daily

## Investigation question

The engineer uses the Claude Code native desktop app's (macOS) in-app "Browser" pane (`mcp__Claude_Browser__*` tools — navigate, read_page, computer, preview_start) to view GitHub PRs. The GitHub login session does not persist: the engineer has had to re-login to github.com every single day this week (Mon–Fri).

1. Is this a known issue, or is it by design?
2. Is there a setting or config that makes the session persist?
3. What are the alternatives (`gh` CLI, Claude in Chrome, manual Chrome), and what do they cost?
4. Can the in-app Browser pane be disabled/removed?

## Sources consulted

- https://code.claude.com/docs/en/desktop — official Desktop application docs; describes the Browser pane's "clean browser profile" behavior, the "Persist sessions" toggle (scoped to local dev-server preview), and the Settings → Claude Code toggles to clear session data / turn the Browser off
- https://code.claude.com/docs/en/settings — settings.json reference; documents `browserExternalPageTools` and `disableBrowserExternalNavigation`, both marked "(Managed settings only)", plus the settings precedence order
- https://code.claude.com/docs/en/chrome — official "Use Claude Code with Chrome" docs; describes the `claude-in-chrome` extension's login-state-sharing behavior and prerequisites
- `gh search issues --repo anthropics/claude-code` (multiple queries) — searched for reports of the Browser pane losing cookies/sessions; see Finding 5 for what was and was not found
- https://github.com/anthropics/claude-code/issues/77473 — "Built-in browser does not support passkey (WebAuthn) authentication on macOS — blocks GitHub login" (open)
- https://github.com/anthropics/claude-code/issues/64630 — "Claude on MacOS does not use default browser for logging in" (open, different scope — Claude's own SSO login, not the Browser pane)
- Local filesystem evidence on this machine (already gathered before this spike began; restated here only for traceability, not re-derived): `~/Library/Application Support/Claude/Cookies`, `~/Library/Application Support/Claude/Partitions/`, `~/Library/Application Support/Claude/config.json`
- See auxiliary: `claude-app-browser-session-persistence_doc_1.txt` — full excerpt of the Desktop docs' Browser-pane sections (line-numbered) plus the settings.json managed-keys table
- See auxiliary: `claude-app-browser-session-persistence_doc_2.txt` — full excerpt of the Claude-in-Chrome docs (prerequisites, login-state-sharing statement, setup)

## Findings

### Finding 1: The Browser pane is documented to use an isolated "clean browser profile" that does not share logins with the engineer's personal browser

**Evidence:**

> "The Browser pane uses a clean browser profile, separate from your personal browser, with none of your saved logins or history. Use it for building and testing your app and for sites that don't need your identity. When you want Claude to act as you in your logged-in sessions, use the Claude in Chrome extension instead, which shares your browser's login state."

**Source:** https://code.claude.com/docs/en/desktop (fetched 2026-07-17; quote confirmed present in the raw fetched page text, reproduced verbatim in the auxiliary file at the line labeled 136)

**Significance:** This is an explicit, documented design statement: the Browser pane is NOT the engineer's real Chrome profile and never will carry the engineer's actual github.com session, by design. This directly explains why a github.com login made in the Browser pane is scoped only to that pane's own isolated profile, never to the engineer's regular Chrome. It does not, by itself, explain why that isolated profile's own session fails to survive from one day to the next — that is a separate question (Finding 3).

`URL fetched / Verbatim quote checked / Quote substring confirmed at the "Choose between the Browser and the Chrome extension" subsection of code.claude.com/docs/en/desktop`

### Finding 2: A documented "Persist sessions" toggle exists, but it is textually scoped to the local dev-server preview feature, not to general external-site browsing (e.g., github.com)

**Evidence:**

> "Start or stop servers from the server dropdown in the session toolbar"
> "Persist cookies and local storage across server restarts by selecting **Persist sessions** in the dropdown, so you don't have to re-login during development"
> "Edit the server configuration or stop all servers at once"
> "Claude creates the initial server configuration based on your project..."
> "To clear saved session data, or to turn the Browser off entirely, use the toggles in Settings → Claude Code."

Immediately after this block, a new subsection begins:

> "### Browse external sites
> The Browser pane is a tabbed browser, so you can open documentation, issue trackers, or any other site next to your running app... You can sign in to sites in the pane, including popup sign-in flows such as Google OAuth."

**Source:** https://code.claude.com/docs/en/desktop (see auxiliary `claude-app-browser-session-persistence_doc_1.txt`, lines 110–121)

**Significance:** The "Persist sessions" toggle sits in the **server dropdown** — the control for starting/stopping the app's own local dev server preview — and the surrounding sentences ("Persist cookies... across server restarts", "don't have to re-login during development") describe persisting a login to the engineer's own local app under development, not to an arbitrary external site like github.com. The "Browse external sites" behavior is documented as a separate subsection immediately after, with no cross-reference back to "Persist sessions." Whether "Persist sessions" also happens to affect external-site tabs is not stated either way in the fetched text — this is an inference from document structure, not a confirmed fact (see "What remains uncertain").

`URL fetched / Verbatim quote checked / Quote substring confirmed at lines 110-121 of the fetched desktop docs page (auxiliary file doc_1.txt)`

### Finding 3: The two settings.json keys that control Browser-pane external browsing are managed-settings-only — not something an individual engineer can set in their own config

**Evidence:**

> `browserExternalPageTools` — "(Managed settings only) Set to `"disabled"` to prevent Claude from using tools to read or act on external pages in the desktop app's Browser pane. Users can still navigate to external sites themselves, and local dev server previews are unaffected"

> `disableBrowserExternalNavigation` — "(Managed settings only) Set to `true` to turn off external browsing in the desktop app's Browser pane. Neither users nor Claude can navigate to external sites, and localhost dev server previews are unaffected. The value must be the JSON boolean `true`; the string `"true"` is ignored"

> On the "Managed settings only" designation: "Managed settings: For organizations that need centralized control, Claude Code supports multiple delivery mechanisms for managed settings. All use the same JSON format and cannot be overridden by user or project settings."

**Source:** https://code.claude.com/docs/en/settings (fetched 2026-07-17, two passes — the second pass explicitly requested verbatim table-row text; see auxiliary `claude-app-browser-session-persistence_doc_1.txt` for the reproduced table)

**Significance:** Neither key is a cookie/session-persistence control — both are about permitting or forbidding external navigation/tool-use, not about whether a session persists across restarts. Neither is settable by an individual engineer in `~/.claude/settings.json` or a project `.claude/settings.json` — both require organization-level `managed-settings.json` / MDM / server-managed-settings deployment, which sits outside the individual engineer's own configuration. No settings.json key describing cookie/session persistence for the "Browse external sites" mode was found in the fetched settings reference.

`URL fetched / Verbatim quote checked / Quote substring confirmed in the settings-precedence and settings-reference sections of code.claude.com/docs/en/settings`

### Finding 4: A documented, individually-usable path exists to clear session data or disable the Browser pane entirely — but it is an in-app GUI toggle, not a settings.json key

**Evidence:**

> "To clear saved session data, or to turn the Browser off entirely, use the toggles in Settings → Claude Code."

**Source:** https://code.claude.com/docs/en/desktop (auxiliary `claude-app-browser-session-persistence_doc_1.txt`, line 117)

**Significance:** This answers investigation question 4 directly: yes, a supported way exists to turn the Browser pane off, and it does not require organization-level managed settings — it is a per-user toggle inside the desktop app's own Settings → Claude Code panel. The doc names this as the mechanism for BOTH "clear saved session data" and "turn the Browser off entirely" — two distinct actions bundled under one described location. The engineer's own machine's `~/Library/Application Support/Claude/config.json` contains no key matching `/[Bb]rowser/` (confirmed via direct grep during this spike), so this GUI toggle's on-disk storage location was not identified — it either lives in a file not yet inspected, or is not yet exercised on this machine. Not found: the exact config key/file this toggle writes to.

`URL fetched / Verbatim quote checked / Quote substring confirmed at line 117 of the fetched desktop docs page`

### Finding 5: No GitHub issue was found reporting the Browser pane losing cookies/sessions daily or requiring repeated github.com login — this specific report is not documented as a known issue

**Evidence:** Searches run against `anthropics/claude-code` via `gh search issues` for: `"browser session cookie"`, `"browser login"`, `"Browser pane"`, `"in-app browser cookies"`, `"Claude_Browser"`, `"browser pane github login"`, `"ephemeral browser partition"`, `"Browser pane persist"`, `"browser profile storage partition"`, `"re-login every day browser"`, `"cookies not saved browser pane"` returned either zero results or results about unrelated topics (Claude's own OAuth/account login, not the Browser pane's per-site cookie persistence). The one substantively related issue found is a different, narrower bug:

> Issue #77473, open: "The Claude Code built-in browser on macOS does not support passkey (WebAuthn / platform authenticator / Touch ID) authentication. When a site requires a passkey to log in — in my case GitHub — the passkey prompt does not work in the built-in browser, leaving me unable to authenticate." ... "Concrete impact: I could not log into GitHub in the built-in browser to review a pull request. There is no fallback to the platform authenticator, so passkey-only or passkey-preferred logins are a dead end."

**Source:** https://github.com/anthropics/claude-code/issues/77473 (fetched 2026-07-17)

**Significance:** This is a related but DISTINCT bug from the engineer's report. #77473 is about the login flow itself failing (passkey/WebAuthn/Touch ID prompts don't work in the built-in browser), not about a successful password-based login failing to persist across days. If the engineer's GitHub account uses a passkey to sign in, #77473 could independently block or complicate re-login (worth checking, out of scope to confirm here). But the specific pattern reported — successful login that then evaporates daily — has no matching GitHub issue found in this search. This is not proof the behavior is unreported (search coverage is not exhaustive), but no citable issue was found describing it.

`URL fetched / Verbatim quote checked / Quote substring confirmed in the issue body of github.com/anthropics/claude-code/issues/77473`

### Finding 6: `gh` CLI is already authenticated on this machine and covers the PR-review workflow without any browser

**Evidence:**

```
github.com
  ✓ Logged in to github.com account plribeiro3000 (keyring)
  - Active account: true
  - Git operations protocol: ssh
  - Token: gho_************************************
  - Token scopes: 'gist', 'read:org', 'repo'

  ✓ Logged in to github.com account ivonoide (keyring)
  - Active account: false
```

**Source:** `gh auth status`, run directly on this machine during this spike (2026-07-17)

**Significance:** Confirms the state described in the investigation brief — `gh` is authenticated for both accounts, keyring-backed, with `repo` scope (which covers reading PR metadata, diffs, comments, and check statuses via `gh pr view`, `gh pr diff`, `gh pr checks`, `gh api`). This is a direct local observation, not an external citation. For "view PR, diff, comments, checks," `gh` needs no browser session at all and is immune to the Browser pane's session-persistence question entirely, since it authenticates via its own stored OAuth token, not a browser cookie.

### Finding 7: Claude in Chrome is documented to reuse the engineer's actual Chrome login state, unlike the Browser pane's isolated profile — with a specific plan requirement

**Evidence:**

> "Claude opens new tabs for browser tasks and shares your browser's login state, so it can access any site you're already signed into."

Prerequisites, verbatim list:

> "Google Chrome, Microsoft Edge, or another Chromium-based browser such as Brave, Arc, Vivaldi, or Opera"
> "Claude in Chrome extension version 1.0.36 or higher, available in the Chrome Web Store"
> "Claude Code"
> "A direct Anthropic plan (Pro, Max, Team, or Enterprise)"

> "Chrome integration is not available through third-party providers like Amazon Bedrock, Google Cloud's Agent Platform, or Microsoft Foundry. If you access Claude exclusively through a third-party provider, you need a separate claude.ai account to use this feature."

**Source:** https://code.claude.com/docs/en/chrome (fetched 2026-07-17; full excerpt in auxiliary `claude-app-browser-session-persistence_doc_2.txt`)

**Significance:** This directly answers investigation question 3 for this alternative: yes, by explicit design, Claude in Chrome reuses the engineer's real, already-logged-in Chrome session (the opposite of the Browser pane's "clean browser profile" from Finding 1) — so it would not require a daily github.com re-login, because it is not a separate profile at all; it drives the engineer's actual browser. Cost: requires installing a Chrome Web Store extension (native messaging host setup, one-time), and requires "a direct Anthropic plan (Pro, Max, Team, or Enterprise)" — not available when accessed exclusively through a third-party provider (Bedrock/GCP/Azure) without a separate claude.ai account. Enabling it also has a documented context-usage cost: "Enabling Chrome by default in the CLI increases context usage since browser tools are always loaded."

`URL fetched / Verbatim quote checked / Quote substring confirmed in the "Get started in the CLI" and "Prerequisites" sections of code.claude.com/docs/en/chrome`

### Finding 8: The working hypothesis (ephemeral/in-memory session discarded on app exit) is not confirmed by any source found in this spike

**Evidence:** No GitHub issue, changelog entry, or documentation page found in this spike states or confirms a mechanism by which the Browser pane's external-site session storage is ephemeral/in-memory and discarded specifically on app process exit. The only confirmed, citable fact is Finding 1 (a "clean browser profile" separate from the personal browser) — which explains isolation from the personal Chrome profile, but not the specific daily-loss cadence.

**Source:** Absence of finding — searches listed in Finding 5, plus the two docs pages fetched, returned no text addressing the underlying storage mechanism (in-memory session vs. an on-disk partition that is cleared).

**Significance:** Per the citation discipline governing this spike, an unconfirmed hypothesis must be labeled as such, not presented as the cause. I did not find a source confirming or refuting the in-memory/ephemeral-session hypothesis. It remains a plausible but unverified explanation for the observed local filesystem evidence (zero github.com cookies in the on-disk Cookies DB, zero cookies in either named Partition) already gathered before this spike began.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| `gh` CLI | Already authenticated on this machine (both accounts); no browser session dependency at all; covers PR view/diff/comments/checks via `gh pr view` / `gh pr diff` / `gh pr checks` / `gh api`; zero setup | No visual rendering of the GitHub web UI itself (diffs/comments are read as text/JSON, not the rendered page); does not cover workflows that need the actual rendered GitHub web UI (e.g. clicking through a complex review UI, viewing rendered images/diagrams in a PR description) | Finding 6 (local `gh auth status`) |
| Claude in Chrome | Documented to reuse the engineer's actual, already-logged-in Chrome session — "shares your browser's login state" — so it would not hit the daily re-login problem at all; renders the full GitHub web UI | Requires installing/maintaining a Chrome Web Store extension + native messaging host; requires a qualifying direct Anthropic plan (Pro/Max/Team/Enterprise) — not available via third-party-provider-only access without a separate claude.ai account; increases context usage when enabled by default; browser automation, not a passive viewing pane — a different interaction model | Finding 7 |
| Manual Chrome (engineer's stated fallback) | Zero setup; full native GitHub web UI, engineer's own real session, no re-login problem by construction | Requires manually switching out of the Claude Code app/context to a separate browser window; no agent-assisted reading of the page content | Engineer's stated fallback in the investigation brief — not independently researched further per the brief's framing |
| In-app Browser pane (status quo) | Integrated inside the Claude Code desktop app; no extension install; can browse arbitrary sites Claude reads/acts on directly | Documented "clean browser profile" isolated from the engineer's real logins (Finding 1); observed daily re-login to github.com; the specific persistence bug/behavior is not documented in any source found in this spike (Finding 5, Finding 8) | Findings 1, 5, 8 |

## What remains uncertain

- Whether the documented "Persist sessions" toggle (Finding 2) has any effect on "Browse external sites" tabs (e.g., a github.com tab), or is strictly limited to the local dev-server preview feature it is textually grouped with. Not found: an explicit statement either confirming or ruling out cross-application of this toggle to external-site tabs.
- The exact underlying storage mechanism for the Browser pane's external-site cookies/session (in-memory/ephemeral vs. an on-disk partition that gets cleared) — unconfirmed (Finding 8).
- Where the "Settings → Claude Code" GUI toggle described in Finding 4 ("clear saved session data" / "turn the Browser off entirely") persists its own state on disk — not identified in this machine's `config.json` (no key matching `/[Bb]rowser/` found).
- Whether the engineer's GitHub account authentication method (password vs. passkey/WebAuthn) intersects with the separate, confirmed bug in issue #77473 (built-in browser cannot complete passkey-based GitHub login) — not established in this spike, as the brief did not specify the engineer's GitHub 2FA/passkey configuration.
- Whether other GitHub issues describing this exact daily-persistence pattern exist under different search terms than the ones tried in this spike (Finding 5) — search coverage was not exhaustive.

## Suggested options for main and the engineer

- Option A: Use `gh` CLI for the bulk of the PR-review workflow (view, diff, comments, checks) — already authenticated, zero additional setup, and immune to the Browser-pane session question entirely (Finding 6).
- Option B: Install and enable Claude in Chrome (`--chrome` flag or `/chrome` → "Enabled by default") for any workflow that specifically needs the rendered GitHub web UI with the engineer's real, persistent login — documented to reuse the actual Chrome session rather than an isolated profile (Finding 7), at the cost of the extension install and a qualifying Anthropic plan.
- Option C: Keep using the in-app Browser pane and accept the daily re-login as a known trade-off of its documented "clean browser profile" design (Finding 1), optionally testing whether the "Persist sessions" toggle in the server dropdown has any effect on external-site tabs despite its textual scoping to local dev-server preview (Finding 2 — untested in this spike).
- Option D: Disable the in-app Browser pane entirely via the "Settings → Claude Code" GUI toggle (Finding 4), removing it from the workflow altogether and relying on Option A and/or Option B instead.
- Option E: Fall back to the engineer's stated manual-Chrome workflow for any GitHub browsing need, with no further tooling change.

(No recommendation — these are the surfaced options; the engineer decides.)
