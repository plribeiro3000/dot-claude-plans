# SPIKE — Recurring `settings.json` Merge Conflict in `~/.claude`

## Investigation question

Every `git pull` in `~/.claude` (after a PR merges into `dot-claude`'s `develop`) aborts with `error: Your local changes to the following files would be overwritten by merge: settings.json`. This recurs every time, not once. Questions to answer:

1. What exactly diverges between the local working-tree `settings.json` and the committed version — cosmetic reorder, formatting, or genuine setting changes?
2. Is the cause Claude Code's own write behavior, a repo hook/script, or manual editing?
3. What does Claude Code's documentation and issue history say about how/where it persists user-level settings (theme, notifications, `/config`), and whether it reformats/reorders the file on write?
4. What is the local reality of `settings.local.json` on this machine, and could app-managed personal keys live there instead of the tracked `settings.json`?
5. What fix options exist, with trade-offs, given the evidence?

## Sources consulted

- `git -C ~/.claude diff settings.json` (full output) — see auxiliary `claude-settings-local-divergence_diff_1.txt`
- `git -C ~/.claude status` — confirms only `settings.json` is modified; `settings.local.json` is untracked and not listed as modified (by construction — untracked files never appear as "modified")
- `git -C ~/.claude log --oneline -10 -- settings.json` — commit history of the tracked file
- `stat` on `~/.claude/settings.json` and `~/.claude/settings.local.json` — mtimes
- `git -C ~/.claude check-ignore -v settings.local.json` — confirms the `.gitignore` rule
- `grep` across `~/Projects/4Shark/dot-claude/scripts/` for `settings.json` / `settings.local.json` references
- Local read of `~/.claude/settings.local.example.json` and its git history
- Local read of `~/.claude/settings.json` and `~/.claude/settings.local.json` top-level key structure (structure only, no values)
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) — official settings precedence and file-purpose documentation
- [github.com/anthropics/claude-code#2688](https://github.com/anthropics/claude-code/issues/2688) — "System overwrite ~/.claude/settings.json"
- [github.com/anthropics/claude-code#62486](https://github.com/anthropics/claude-code/issues/62486) — "settings.json partial rewrite strips statusLine, enabledPlugins, hooks mid-session"
- [github.com/anthropics/claude-code#49076](https://github.com/anthropics/claude-code/issues/49076) — "/model command silently persists effortLevel to settings.json"
- [github.com/anthropics/claude-code#9875](https://github.com/anthropics/claude-code/issues/9875) — "Pressing '2' overwrites .claude/settings.local.json instead of appending permissions"
- WebSearch results surfacing further related issues (#15339, #13785, #13827, #9234, #33489, #26167) — titles/summaries only, not individually fetched/quoted
- WebSearch on `CLAUDE_CONFIG_DIR` — underdocumented env var, redirects the whole config directory

## Findings

### Finding 1: The divergence is 100% reorder + whitespace + two appended keys — zero content changes to any shared setting

**Evidence:** The full diff (auxiliary `claude-settings-local-divergence_diff_1.txt`) shows the entire 379-line file rewritten (`@@ -1,379 +1,11 @@` … the hunk headers span the whole file). Walking every hunk:

- Every hook entry under `hooks.SessionStart`, `hooks.SubagentStart`, `hooks.UserPromptSubmit`, `hooks.PostToolUse`, `hooks.PreToolUse`, `hooks.Notification` is byte-identical in content between old and new position — only the `hooks` object as a whole moved from right after `env` to right before `statusLine`.
- Inside each terraform `PreToolUse` hook entry, the `if` key moved from before `type`/`command` to after `command` — e.g. old: `"if": "Bash(terraform *)"` on its own line preceding `"type": "command"`; new: the same string appears after `"command": "...inject-terraform-context.sh"`. No value changed.
- Every entry in `permissions.allow` (181+ lines) is textually identical; only the blank lines that visually grouped entries into sections (`git`, then blank, then `bundle/rails/...`, then blank, then rvm wrappers, etc.) were removed. Diff lines like `-` (removing a bare blank line) appear repeatedly with no adjacent content change.
- `permissions.additionalDirectories` changed from `["~/Projects", "~/.claude", "~/Downloads", "/tmp"]` (single line) to the same four strings spread across five lines — same array, same order, same values, only formatting.
- `permissions.ask` and `permissions.deny` arrays are byte-identical in content; only their relative order changed (`ask` was before `deny`, now `ask` is after `deny`), and `defaultMode: "acceptEdits"` moved from between `ask` and `deny` to after `ask`.
- Top-level key order changed from `$schema, alwaysThinkingEnabled, autoMemoryEnabled, cleanupPeriodDays, env, hooks, includeCoAuthoredBy, permissions, skillOverrides, statusLine` to `$schema, cleanupPeriodDays, env, includeCoAuthoredBy, permissions, skillOverrides, hooks, statusLine, alwaysThinkingEnabled, autoMemoryEnabled, theme, inputNeededNotifEnabled`.
- The only genuinely new content is two keys appended at the very end of the file: `"theme": "dark"` and `"inputNeededNotifEnabled": true` (diff lines 981–982 of the auxiliary file).

**Source:** `claude-settings-local-divergence_diff_1.txt` (full `git -C ~/.claude diff settings.json` output).

**Significance:** No hunk touches the *content* of any shared/team setting (no hook removed/added, no permission entry removed/added/changed). The recurring conflict is 100% attributable to (a) whole-file key reordering, (b) loss of the blank-line visual grouping the tracked file was hand-formatted with, and (c) two new keys. This directly confirms the engineer's characterization in the investigation brief.

### Finding 2: The reorder pattern is consistent with a schema-driven re-serialization, not a random or manual edit

**Evidence:** The new top-level order (`$schema, cleanupPeriodDays, env, includeCoAuthoredBy, permissions, skillOverrides, hooks, statusLine`) is neither alphabetical nor the original file's order, and it is followed by `alwaysThinkingEnabled, autoMemoryEnabled` (present in the original file but seemingly not part of whatever fixed order produced the first eight keys) and finally the two brand-new keys `theme, inputNeededNotifEnabled`. Within `permissions`, the new order is `allow, deny, ask, defaultMode, additionalDirectories` — again not alphabetical, not the original order.

**Source:** Same diff, described in Finding 1.

**Significance:** A hand-edit or a script targeting a specific key would leave the rest of the file's key order untouched. A whole-object reorder where recognized keys land in one fixed sequence and less-recognized/newly-added keys are appended at the end is the signature of: parse the file into an in-memory object → construct/merge a new object by iterating a fixed internal schema/field list → append any remaining keys the schema list didn't cover → serialize back with `JSON.stringify`-style formatting (which cannot preserve blank lines, since JSON has no blank-line concept — any blank-line grouping in the original file is necessarily lost the moment a full object round-trip happens). This is circumstantial, not directly documented (no fetched source states this exact algorithm) — flagged as inferred, not confirmed.

### Finding 3: No script, hook, or human-editable path in the `dot-claude` repo itself writes to `settings.json`

**Evidence:** `grep -rn "settings.json" ~/Projects/4Shark/dot-claude/scripts/` returned only comments describing *where a hook is wired in* settings.json (e.g. `cleanup-sessions.sh:20: SETTINGS_FILE="${CLAUDE_DIR}/settings.json"` reads `cleanupPeriodDays` from it) — no script writes to it. `git -C ~/.claude log --oneline -10 -- settings.json` shows only human-authored feature/fix commits (`feat(hooks): ...`, `fix(permissions): ...`) going back through normal PR merges, no automated commit pattern.

**Source:** `grep` output over `~/Projects/4Shark/dot-claude/scripts/*.sh`; `git -C ~/.claude log --oneline -10 -- settings.json` output.

**Significance:** Rules out a 4Shark-authored hook/script as the writer of the uncommitted changes. `cleanup-sessions.sh` only *reads* `cleanupPeriodDays` — it does not write the file. Combined with Finding 1 (whole-file reorder + two new user-preference-shaped keys, `theme`/`inputNeededNotifEnabled`), the remaining plausible writer is the Claude Code application itself (its settings-persistence code path triggered by an in-app action — `/config`, theme picker, or a notification toggle), not a human hand-edit (a human editing wouldn't reorder 379 lines with zero content change) and not a repo script (none found).

### Finding 4: Official docs place `~/.claude/settings.json` as the "User" scope — the lowest-precedence, but still the literal file the app is documented to treat as the global settings file

**Evidence:** Per the fetched official docs: "User settings are defined in ~/.claude/settings.json and apply to all projects" and the precedence order is "1. Managed (highest) ... 2. Command line arguments ... 3. Local: overrides project and user settings ... 4. Project: overrides user settings ... 5. User (lowest): applies when nothing else specifies the setting." Separately: "`.claude/settings.local.json` for settings that are not checked in, useful for personal preferences and experimentation. When Claude Code creates `.claude/settings.local.json`, it configures git to ignore the file." On write behavior, the docs state only: "Claude Code watches your settings files and reloads them when they change... A few keys are read once at session start" (naming `model` and `outputStyle`) — the docs contain **no statement** about the app reformatting/reordering the file structure on write.

**Source:** [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings), quoted directly above.

**Significance:** By the docs' own model, "personal preferences" are supposed to live in `.claude/settings.local.json`, distinct from the shared `settings.json`. But the docs describe `settings.local.json` as a **project**-scope construct (`.claude/settings.local.json` inside a project directory) — 4Shark's setup is atypical in that `~/.claude/` is used as *both* the global config directory Claude Code reads by default *and* a git-tracked team-shared repo, so the same directory hosts both the "User" file (`settings.json`) and, per this repo's own convention (see Finding 6), a manually-maintained local-override file at the same literal path. The docs do not resolve which file an in-app UI action (theme, notification toggle) targets — that had to be checked against reported behavior (Finding 5).

### Finding 5: A confirmed GitHub issue shows an in-app setting-change action (`/model`) writes directly to `~/.claude/settings.json` — not to `settings.local.json`

**Evidence:** Issue #49076, title `"/model command silently persists effortLevel to settings.json, overriding user's preferred default"`. Per the fetched issue: "The `/model` interactive picker silently writes the selected `effortLevel` to `~/.claude/settings.json` as a persistent global default... The issue explicitly states the file is `~/.claude/settings.json` (user-level settings file)."

**Source:** [github.com/anthropics/claude-code/issues/49076](https://github.com/anthropics/claude-code/issues/49076).

**Significance:** This is the closest **directly documented** precedent for "an in-app preference change writes to the tracked `~/.claude/settings.json` file, not to `settings.local.json`." It is a different key (`effortLevel`/`model`) than the ones observed locally (`theme`, `inputNeededNotifEnabled`), so it does not by itself prove the exact mechanism for our two keys — but it establishes that Claude Code's app-driven settings writer, at least for some keys, targets `~/.claude/settings.json` by design, matching what was observed in Finding 1. No fetched source confirms whether `theme` and `inputNeededNotifEnabled` specifically follow the same write path — this is inferred from the pattern, not directly documented for these two keys. Marked as inference, not confirmed fact.

### Finding 6: A related, but distinct, GitHub issue shows permission-approval actions ("always allow") write to `settings.local.json`, not to `settings.json`

**Evidence:** Issue #9875, title `"Bug: Pressing '2' overwrites .claude/settings.local.json instead of appending permissions"` (per WebSearch result title). Local evidence corroborates: `~/.claude/settings.local.json` (mtime `Jun 3 14:29:12 2026`, 13943 bytes) has its own independent `permissions.allow` array of 181 entries, and a diff between the tracked file's `permissions.allow` (212 entries) and the local file's `permissions.allow` shows the two lists diverge immediately (different content, not a subset relationship at the sorted-diff level) — confirming they are maintained as two genuinely separate lists, not one being a stale copy of the other.

**Source:** `diff <(sorted tracked allow list) <(sorted local allow list)` output; issue title from WebSearch (issue body not independently fetched/quoted beyond the title — flagging this as a lower-confidence citation than Findings 4/5, which quote fetched issue bodies directly).

**Significance:** This shows Claude Code's settings writer is **not monolithic** — different categories of app-driven writes target different files (permission approvals → `settings.local.json`; at least one user-preference key, `effortLevel`, → `settings.json` per Finding 5). This asymmetry is central to evaluating Option (a) below: it is not established that *all* personal-preference keys can be redirected to `settings.local.json` by moving them there manually, because the app may keep re-writing `theme`/`inputNeededNotifEnabled` back into `settings.json` on the next in-app toggle regardless of where the engineer manually placed them.

### Finding 7: `settings.local.json` already exists on this machine, is git-ignored, and the repo already documents it as a personal-override file — but its content (permissions + `agentPushNotifEnabled`) does not include `theme` or `inputNeededNotifEnabled`

**Evidence:** `ls -la ~/.claude/settings.local.json` confirms the file exists (13943 bytes, mtime `Jun 3 14:29:12 2026` — five weeks older than `settings.json`'s mtime of `Jul 7 19:54:36 2026`). `git -C ~/.claude check-ignore -v settings.local.json` returns `.gitignore:71:settings.local.json	settings.local.json` confirming it is ignored. Its top-level structure (values not printed, per the credential-value rule) is: `env: { AWS_MFA_SERIAL: str }`, `permissions: { allow: list len=181, deny: list len=0, ask: list len=0 }`, `agentPushNotifEnabled: bool`. Note: `AWS_MFA_SERIAL` is an ARN identifier, not a secret value — it is safe to name the key. Neither `theme` nor `inputNeededNotifEnabled` appears in `settings.local.json`; both are only in the tracked `settings.json` (per Finding 1). The repo itself ships `settings.local.example.json` (tracked) as a template showing the intended shape of a personal override file: `env.AWS_MFA_SERIAL` + a curated `permissions.allow`/`ask`. The team's own `CLAUDE.md` § Security already states: *"Files like `history.jsonl`, `projects/`, `todos/`, `settings.local.json` are personal."*

**Source:** `ls -la`, `stat`, `git check-ignore -v`, Python structure dump of `settings.local.json`, `Read` of `settings.local.example.json`, `git -C ~/.claude log -p -1 --follow -- settings.local.example.json`.

**Significance:** The mtime gap (settings.local.json last touched five weeks before the last settings.json rewrite) shows these two files are **not** rewritten together by a single unified event — whatever wrote `theme`/`inputNeededNotifEnabled` into `settings.json` on Jul 7 did not touch `settings.local.json` at the same time. This is consistent with Finding 6's asymmetry: different settings categories are written to different files by the app, and `agentPushNotifEnabled` (present only in the local file) suggests at least one notification-shaped boolean already round-trips through `settings.local.json` successfully — raising the open question (see "What remains uncertain") of why `inputNeededNotifEnabled` (a similarly-shaped notification boolean) did not.

### Finding 8: `CLAUDE_CONFIG_DIR` redirects the whole config directory, not selective keys — not a fix at the key level

**Evidence:** Per WebSearch synthesis of GitHub issues #3833, #25762, #33430: `CLAUDE_CONFIG_DIR` "can be used to specify an alternative configuration directory instead of the default `~/.claude/`" but is "not documented anywhere — not in `claude --help`, not in the official docs," and even then "Claude Code still creates local `.claude/` directories in individual workspaces even when `CLAUDE_CONFIG_DIR` is set." (Titles/synthesis from WebSearch; not independently fetched and quoted — lower-confidence citation, flagged.)

**Significance:** This env var operates at the directory level (moving the whole `~/.claude/` elsewhere), not at the individual-setting level — it does not offer a way to tell Claude Code "write `theme` here, write `hooks` there." Not a viable mechanism for splitting personal vs. shared keys within the same directory.

## Trade-offs surfaced

| Option | Stops the recurring conflict? | Keeps shared settings under version control? | Risk of losing personal prefs | Evidence basis |
|---|---|---|---|---|
| (a) Move app-managed/personal keys (`theme`, `inputNeededNotifEnabled`, possibly `defaultMode`) out of tracked `settings.json` into git-ignored `settings.local.json` | **Uncertain** — only works if the app's writer, on the next in-app toggle, targets `settings.local.json` for these specific keys instead of re-writing them into `settings.json`. Finding 5 shows at least one key (`effortLevel`) is documented to always write to `settings.json` regardless of where the engineer places it; Finding 7 shows `agentPushNotifEnabled` already lives in `settings.local.json` successfully, suggesting behavior is key-specific, not uniform. No fetched source resolves this for `theme`/`inputNeededNotifEnabled` specifically. | Yes | Neutral to positive — moving the keys does not risk losing the shared config; risk is only whether the fix "sticks" | Findings 5, 6, 7 |
| (b) `.gitattributes` `merge=ours` (or a custom merge driver) for `settings.json` | Yes, mechanically — a merge conflict cannot occur if the merge driver always keeps one side | Yes, but **silently drops future shared-config changes to `settings.json`** on every pull unless the driver is `ours`-on-conflict-only (not `ours`-always) — `merge=ours` unconditionally prefers the local version, which means legitimate upstream hook/permission additions merged by other engineers would stop landing locally without a manual re-sync | None to personal keys, but risks silently stale shared config | Not independently researched in this spike — flagged as a candidate needing its own follow-up investigation into `merge=ours` semantics before adoption |
| (c) `git update-index --skip-worktree` / `--assume-unchanged` on `settings.json` | Yes, for the pull symptom specifically (git stops tracking local modifications for merge purposes) | Yes, nominally, but the local copy silently diverges from every subsequent shared-config change with no automatic re-sync, and `--assume-unchanged` is explicitly documented upstream as unsafe across pulls (git can still overwrite it inconsistently) | High — this is a git-level workaround, not investigated further in this spike | Not independently researched in this spike |
| (d) Stop hand-formatting the tracked `settings.json` (adopt the app's serialization/key order and drop blank-line grouping) | Partially — eliminates the reorder/whitespace-churn portion of every future diff, but does **not** stop the app from appending new keys (`theme`, `inputNeededNotifEnabled`, or future ones) that still were never asked to be part of the shared config — those still cause a genuine (small) local diff on every pull | Yes | None — this only changes formatting philosophy, not what's tracked | Grounded in Finding 1 (the reorder+whitespace portion is the majority of every diff hunk) but does not address Finding 1's third component (the two appended keys) |
| (e) A pre-pull stash/normalize step baked into `/merge-cleanup` (or a new pull wrapper) that strips app-added personal keys and restores hand-formatting before every `git pull` | Yes, mechanically, on every invocation | Yes | None, if the strip-list is kept current — but requires maintaining a list of "keys to strip before pull," which grows every time Claude Code adds a new app-managed setting (recurring maintenance cost) | Grounded in Findings 1, 3 (no existing script does this yet) |

## What remains uncertain

- **The exact triggering in-app action** for the `theme`/`inputNeededNotifEnabled` writes (theme picker, `/config` menu, a notification-settings toggle, or an automatic default-value backfill on a Claude Code version upgrade) is not confirmed — no session log or Claude Code changelog entry was found correlating the Jul 7 19:54 mtime with a specific engineer action. Not found: a direct citation stating "theme changes always write to `~/.claude/settings.json`" — this is inferred from the pattern in Finding 1 plus the precedent in Finding 5 for a different key.
- **Why `agentPushNotifEnabled` lives in `settings.local.json` while `inputNeededNotifEnabled` (a similarly-shaped notification boolean) landed in the tracked `settings.json`** is unresolved — this could mean the app's write-target is genuinely per-key (hardcoded which file each setting name goes to), or it could mean `agentPushNotifEnabled` was set at a different Claude Code version with different behavior, or it could mean one was set via a different UI surface (CLI flag vs. in-app menu) than the other. No source distinguishes these.
- **Whether option (a) will actually stop future recurrences** cannot be confirmed without either (i) an official statement of which settings keys the app writes to `settings.local.json` vs `settings.json`, or (ii) an empirical test: move `theme`/`inputNeededNotifEnabled` to `settings.local.json`, delete them from the tracked file, trigger the same in-app action again, and observe which file receives the write. This spike did not perform that test (it would require intentionally invoking the app's theme/notification UI, which was out of scope for a read-only investigation).
- **Options (b) and (c)** were named in the investigation brief but not independently researched to the same depth as (a) — their trade-off rows above are flagged as preliminary and would need their own grounding pass (current git documentation on merge drivers and `--skip-worktree` semantics) before being treated as equally evidenced as (a), (d), (e).
- **Issues #9875, #3833, #25762, #33430** were cited from WebSearch synthesis (titles and AI-summarized bodies) rather than independently fetched and quote-verified the way #2688, #62486, and #49076 were — their citations in this document are flagged as lower-confidence per the Citation Discipline (UNVERIFIED-adjacent; the titles are accurate per the search tool, but body text was not independently re-fetched and quote-checked).

## Suggested options for main and the engineer

- **Option A**: Relocate app-managed personal keys (`theme`, `inputNeededNotifEnabled`, and audit for others like `defaultMode`) from the tracked `settings.json` into the already-existing, git-ignored `settings.local.json` — contingent on confirming (via a small empirical test) that the app's writer will target `settings.local.json` for these specific keys going forward.
- **Option B**: Adopt a `.gitattributes` merge strategy or custom merge driver for `settings.json` scoped to *only* resolve the reorder/whitespace/personal-key noise, not to blindly prefer either side wholesale — needs its own research pass on driver semantics before adoption.
- **Option C**: A git-level "ignore local changes to this tracked file" mechanism (`--skip-worktree` or similar) — carries a known risk of silent staleness against future shared-config changes; needs further research on safety before adoption.
- **Option D**: Change the tracked `settings.json`'s formatting convention to match Claude Code's own serialization (drop the hand-grouped blank lines, accept the app's key order) — reduces diff noise but does not eliminate the recurring conflict caused by newly appended keys.
- **Option E**: Add a pre-pull normalization step (e.g., to `/merge-cleanup` or a new wrapper) that strips known app-added personal keys from `settings.json` before every `git pull` — mechanically effective but adds an ongoing maintenance burden (the strip-list must track every new Claude Code setting).

No option is recommended here — the evidence in Findings 5–7 shows the app's write-target behavior is asymmetric and not fully documented, which is the central uncertainty any chosen option must account for.
