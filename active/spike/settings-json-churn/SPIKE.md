# SPIKE — `~/.claude/settings.json` Churn

## Investigation question

The Claude Code desktop app repeatedly rewrites the tracked `~/.claude/settings.json` (reorders keys, strips blank lines, re-adds personal/UI preferences such as `inputNeededNotifEnabled`, `theme`, `agentPushNotifEnabled`), causing `git pull` on `~/.claude` to abort with `error: Your local changes to the following files would be overwritten by merge`, and forcing a `git checkout -- settings.json` before the pull can proceed. Is this a known/acknowledged problem? Does Claude Code's settings model support sharing team config (hooks, `permissions.allow`/`deny`/`ask`, skill overrides) from a file the app itself never rewrites? Specifically: should `~/.claude/settings.json` move to `.gitignore`, and if so, how does the 3-engineer team still share its config? Candidate solutions (status quo, moving app-managed keys out, gitignore + a different tracked file, a `.gitattributes` merge driver, managed/enterprise read-only settings) are evaluated against two hard requirements: (R1) the team still shares hooks/permissions via git, (R2) the daily churn/pull-abort stops.

## Sources consulted

- https://code.claude.com/docs/en/settings — official settings hierarchy, precedence, auto-write behavior, managed-settings delivery mechanisms. See auxiliary `settings-json-churn_doc_1_settings-hierarchy.md`.
- https://github.com/anthropics/claude-code/issues/62486 — "settings.json partial rewrite strips statusLine, enabledPlugins, hooks mid-session" (closed, not planned, stale). See auxiliary `settings-json-churn_doc_2_issue-62486.md`.
- https://github.com/anthropics/claude-code/issues/55507 — settings.local.json auto-rewriter drops `defaultMode` and other non-`allow` keys (closed, not planned, stale). See auxiliary `settings-json-churn_doc_3_issue-55507.md`.
- https://github.com/anthropics/claude-code/issues/4800 — open, unshipped feature request for an `extends`/import mechanism. See auxiliary `settings-json-churn_doc_4_community-and-feature-requests.md`.
- https://github.com/hardwood-hq/hardwood/issues/590 — third-party project's own committed/gitignored settings split (not Claude Code itself; the opposite-direction problem). See same auxiliary file.
- https://git-scm.com/docs/gitattributes, https://github.com/jonatanpedersen/git-json-merge, https://nesbitt.io/2026/03/30/git-diff-drivers.html — general git merge-driver mechanics for JSON normalization. See same auxiliary file.
- `/Users/plribeiro3000/.claude/settings.json:1-762` — the 4Shark tracked config (hooks, `permissions`, `skillOverrides`, `statusLine`) — read directly, no `theme`/notification keys present at time of research (working tree clean, no diff).
- `/Users/plribeiro3000/.claude/settings.local.json:1-195` — the 4Shark personal/git-ignored file, currently holding `theme`, `agentPushNotifEnabled`, `inputNeededNotifEnabled`, plus personal `permissions.allow` entries and an `env.AWS_MFA_SERIAL`.
- `/Users/plribeiro3000/.claude/.gitignore:70-71` — confirms `settings.local.json` is already the designated personal/git-ignored file.
- `/Users/plribeiro3000/.claude/scripts/check-claude-version.sh` — read for context; does not itself touch `settings.json` (it only checks tags/CHANGELOG), so it is not part of the churn mechanism, only the auto-update-notice feature referenced in the problem statement.
- `git -C /Users/plribeiro3000/.claude status --short -- settings.json settings.local.json` and `git -C /Users/plribeiro3000/.claude diff -- settings.json` — both empty at time of research: the working tree is currently clean, so the specific reformat diff described in the ground truth was not independently reproduced during this spike (see "What remains uncertain").

## Findings

### Finding 1: The churn is a documented class of bug in Claude Code itself, but the exact shape (UI-pref re-injection into a tracked file, plus key reordering) is not independently confirmed as a single filed issue

**Evidence:** Issue #62486 states:

> Claude Code periodically rewrites `~/.claude/settings.json` during a session (not only at startup), stripping fields it didn't explicitly modify — specifically `statusLine`, `enabledPlugins`, `hooks`, and other user-configured fields.

and root-causes it as:

> The settings write path appears to serialize only the schema fields relevant to the current operation, rather than round-tripping the full settings object.

Issue #55507 independently corroborates the same class of defect on `settings.local.json`:

> the rewriter dropped a previously-set `permissions.defaultMode: "bypassPermissions"` field. Adding it back manually fixed it temporarily but it was at risk of being stripped again on the next auto-write.

**Source:** https://github.com/anthropics/claude-code/issues/62486, https://github.com/anthropics/claude-code/issues/55507 (full text in auxiliaries `settings-json-churn_doc_2` and `_doc_3`).

**Significance:** Both issues describe a **partial/selective write path** — the app writes only the fields relevant to the operation it is performing, not a full round-trip of the file. This is mechanically consistent with the 4Shark-observed symptom (personal UI toggles and key reordering appearing in the tracked file) but neither issue is a verbatim match for "the app re-adds `theme`/notification keys into a file also used for team hooks" — that specific combination (team file = user-scope file) is a 4Shark-specific usage the reported issues don't describe, because neither reporter is git-tracking `~/.claude/settings.json` itself (see Finding 2).

### Finding 2: Both issues are closed "not planned" and stale — no Anthropic acknowledgment, no documented off-switch

**Evidence:** Issue #62486 — status "Closed as not planned", labels include `stale`; per the fetch, "No maintainer comments or acknowledgment from Anthropic staff are visible... No documented setting, flag, or environment variable is mentioned to disable auto-rewrite behavior." Issue #55507 — same closure state ("Closed as not planned"), same `stale` label, no maintainer response documented.

**Source:** https://github.com/anthropics/claude-code/issues/62486, https://github.com/anthropics/claude-code/issues/55507.

**Significance:** There is no known flag, environment variable, or setting to stop the app from selectively rewriting `~/.claude/settings.json`, and Anthropic has not engaged with either report. Any fix has to live entirely on the 4Shark side (workflow/process), not by disabling upstream behavior.

### Finding 3: The official settings model treats `~/.claude/settings.json` as inherently personal, and only recognizes four/five fixed scopes — no arbitrary shared file is supported

**Evidence:** Official precedence order:

> 1. Managed (highest): can't be overridden by anything
> 2. Command line arguments: temporary session overrides
> 3. Local: overrides project and user settings
> 4. Project: overrides user settings
> 5. User (lowest): applies when nothing else specifies the setting

And per the extracted table, `~/.claude/settings.json` is documented as "User home | User | N/A | Yes (via `/config`, UI) | Personal preferences across all projects" — the tool's own model does not anticipate this file being git-tracked for team sharing at all; that is a 4Shark-specific overlay on top of a file the tool considers purely personal, and one the app freely writes to for `/config`/UI actions ("Toggle preferences in the Settings UI (theme, editor mode, notifications, etc.)").

**Source:** https://code.claude.com/docs/en/settings (full extraction in `settings-json-churn_doc_1_settings-hierarchy.md`).

**Significance:** The root cause of the conflict is a mismatch of intent: 4Shark uses the **user-scope** file (`~/.claude/settings.json`) to hold **team-shared** config, but Claude Code's own model treats the user scope as inherently personal and freely writable by the app. The **project scope** (`.claude/settings.json` inside a repo working tree) is the one the tool itself documents as "Team-shared settings for all collaborators" — but that scope does not apply here because there is no enclosing project repo above `~/.claude/`; `~/.claude/` itself is both the config root Claude Code reads and the git repo 4Shark uses to share it.

### Finding 4: No shipped "extends"/import mechanism exists — the closest matching feature request is open and unimplemented

**Evidence:** Feature request #4800 ("Add extends field to settings.json for shared configuration inheritance") is **Open**, with "No assignees... No projects assigned... No milestone... Development section shows: No branches or pull requests" — i.e., proposed, not built, not scheduled.

**Source:** https://github.com/anthropics/claude-code/issues/4800 (full extraction in `settings-json-churn_doc_4_community-and-feature-requests.md`).

**Significance:** Any solution that requires Claude Code to natively load shared config from a differently-named tracked file (option (a) or (b) in the original question) is **not achievable today** — there is no supported way to tell Claude Code "also read `team-settings.json`" beyond the four/five fixed-name scopes in Finding 3.

### Finding 5: A read-only "managed settings" layer exists and the app never writes to it — but its distribution model is per-machine file placement or MDM, not git tracking

**Evidence:**

> `managed-settings.json` and `managed-mcp.json` deployed to system directories... File-based managed settings also support a drop-in directory at `managed-settings.d/`

Delivered via one of: an Anthropic admin console (server-managed, requires a Claude Enterprise/Team account with an admin console), OS-level MDM (macOS plist via Jamf/Kandji, Windows registry via Group Policy/Intune), or a file dropped into a fixed **system directory** (`/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/` on Linux/WSL, `C:\Program Files\ClaudeCode\` on Windows) — and per the extracted table, this file is "No (admin-deployed)" for auto-write, i.e., **Claude Code itself never writes to managed-settings.json.** Locked-down keys like `allowManagedHooksOnly` confirm hooks are a supported managed-settings key, not just permissions.

**Source:** https://code.claude.com/docs/en/settings (full extraction in `settings-json-churn_doc_1_settings-hierarchy.md`).

**Significance:** This is the one file in Claude Code's model that (a) the app never rewrites and (b) can carry hooks + permissions. It satisfies "a file the app won't touch" structurally. The cost is that it lives at a **fixed system path outside any git working tree** — sharing it across 3 engineers means either (i) each engineer's machine needs a manual/scripted step to place or symlink a git-tracked source file into that system path (an install-time action, not a `git pull`-only workflow), or (ii) a paid Claude Enterprise/Team admin console, which is a materially different operational commitment than "the config lives in a repo we `git pull`."

### Finding 6: A `.gitattributes` merge driver does not address the specific failure mode observed (dirty-tree pull abort), only committed 3-way merges

**Evidence:** General git tooling (not Claude-Code-specific) shows JSON merge drivers operate on git's three-way merge of **committed** revisions (ancestor/ours/theirs) — e.g. `git-json-merge`, a driver bound via `.gitattributes`, "uses xdiff to automatically resolve merge conflicts in json files." Separately, multiple independent git-error explainer sources describe the `error: Your local changes to the following files would be overwritten by merge` failure as Git refusing to even start a merge because the **working tree has uncommitted modifications** to a path the incoming merge also touches — this check runs before any merge/diff driver is invoked.

**Source:** https://git-scm.com/docs/gitattributes, https://github.com/jonatanpedersen/git-json-merge; corroborating explainers: https://www.git-tower.com/learn/git/faq/git-force-pull, https://labex.io/tutorials/git-how-to-address-error-your-local-changes-would-be-overwritten-by-merge-in-git-417548 (full reasoning in `settings-json-churn_doc_4_community-and-feature-requests.md`).

**Significance:** Because the app's rewrite is never committed (it just dirties the working tree), the observed failure is the **dirty-tree pre-merge check**, not an actual merge conflict. A `.gitattributes` merge driver therefore does **not**, by itself, stop the pull-abort — it would only help if the app's rewrite were first committed on its own (turning the case into an actual two-sided merge), which is not the current workflow (PR #360's `check-claude-version.sh` instead discards the local rewrite via `git checkout -- settings.json` before pulling).

### Finding 7: The minimal observed churn, per the engineer's ground truth, is confined to personal/UI-preference keys plus reordering — not hooks/permissions content

**Evidence:** The engineer's ground-truth description (not independently reproduced in this session — working tree was clean at research time, see "What remains uncertain") names exactly three re-injected keys — `inputNeededNotifEnabled`, `theme`, `agentPushNotifEnabled` — plus key reordering and blank-line stripping. These three keys are presently found, cleanly, in the git-ignored `settings.local.json:192-195`:

```json
  "agentPushNotifEnabled": true,
  "theme": "dark",
  "inputNeededNotifEnabled": true
```

**Source:** `/Users/plribeiro3000/.claude/settings.local.json:192-195` (direct read); engineer's problem statement for the churned-keys list (not independently re-observed this session).

**Significance:** If the churn is genuinely confined to these three personal keys (as both the engineer's account and the general shape of issues #62486/#55507 suggest — "fields it didn't explicitly modify"), the tracked `settings.json` never structurally needs to carry them at all: they already have a legitimate home in `settings.local.json`. Whether removing them from the tracked file actually stops the app from re-adding them to the TRACKED file specifically (as opposed to continuing to maintain them in the local file only) was **not found** in any consulted source — no issue or doc confirms the app respects "this key already exists in a lower-precedence file, don't also write it to the tracked one." This is the open question central to Options A/B below.

## Trade-offs surfaced

| Option | R1 (team still shares hooks/permissions via git) | R2 (daily churn/pull-abort stops) | What breaks / cost |
|---|---|---|---|
| **A. Status quo** — keep tracked `settings.json`, `check-claude-version.sh`-style flow discards the app's reformat before pulling | Yes — unchanged | Partially — the abort is worked around (`git checkout -- settings.json`) each time, not prevented | Cheapest, zero migration. Residual hole (per Finding 6/7): a genuine hand-edit to the tracked file sitting uncommitted is indistinguishable from an app reformat and gets silently discarded by the same recovery step unless the engineer notices before running it |
| **B. Remove the three UI-pref keys from the tracked file; leave them to `settings.local.json`** | Yes — unchanged | **Unconfirmed** — depends on whether the app stops re-adding them to the tracked file once absent, or keeps writing them there regardless of `settings.local.json` already holding them (Finding 7; no source confirms either way) | Low cost, reversible, additive to Option A. If the app still re-writes them into the tracked file regardless, no improvement beyond removing lines that keep reappearing |
| **C. `.gitignore` `settings.json`; share team config via a different tracked file Claude Code loads on its own** | **No** in the shipped product — no supported way to make Claude Code read shared hooks/permissions from an arbitrary tracked filename (Finding 3, Finding 4) | Yes, trivially (the churned file would no longer be tracked at all) | Breaks team sharing outright unless paired with a manual sync step (e.g., a script that copies/diffs a tracked "source" file into `~/.claude/settings.json` on each engineer's machine before/after `git pull`) — which reintroduces process overhead and a new class of drift (the copy going stale) |
| **D. `.gitattributes` merge driver / JSON normalization** | Yes — unchanged | **No** — per Finding 6, the observed abort is a dirty-working-tree pre-merge check, not a committed-revision merge conflict; a merge driver does not run in that case | Effort spent on a mechanism that does not address the actual observed failure mode, unless the workflow first commits the app's local rewrite (not current practice) |
| **E. Managed/enterprise read-only settings for hooks/permissions, leaving the user `settings.json` for the app to churn harmlessly** | Yes, but via a **different distribution channel** than the current `git pull`-only flow (system-path file placement per machine, or an Enterprise/Team admin console) | Yes — per Finding 5, the app never writes to `managed-settings.json` | Highest R2 confidence of all options, but heaviest operational lift: needs a per-machine deployment/symlink step (git-tracked source → OS-specific system path) engineered and maintained by 4Shark, or a paid admin console subscription. Nothing in the consulted docs or issues describes teams doing this purely to solve settings churn (not found) |

## What remains uncertain

- Whether the tracked `~/.claude/settings.json` churn described in the problem statement is caused by the SAME mechanism as issues #62486/#55507 (a partial/selective write path) or a distinct one specific to the desktop app's Settings UI writing theme/notification toggles — the consulted issues describe CLI/session-level rewrites, not explicitly the desktop app's preference panel. **Not found**: an issue reporting the exact combination "desktop app Settings UI writes theme/notification prefs into a file also used for git-tracked team hooks."
- Whether removing the three UI-pref keys from the tracked file (Option B) actually stops the app from re-adding them there, or whether the app writes user-scope preferences to `~/.claude/settings.json` unconditionally regardless of what `settings.local.json` already holds. No source in this research confirms either behavior.
- Whether `hooks` and `permissions.allow`/`ask`/`deny` (4Shark's actual shared content) can be placed in `managed-settings.json` in practice for a 3-engineer team without an Enterprise/Team admin console — the docs confirm `allowManagedHooksOnly` exists (implying hooks are a supported managed-settings key) but do not walk through a concrete non-MDM, non-admin-console, git-tracked-source-file workflow for a small team. This would need to be prototyped/tested, not just read about.
- Whether a symlink from `~/.claude/settings.json` to a differently-named git-tracked file would survive the app's write behavior (the app likely does an atomic replace — write-new-file-then-rename — which would replace the symlink itself with a plain file, breaking the link) or whether it in fact writes in place (preserving the symlink). **Not found** in any consulted source; this is an untested hypothesis, not a finding.
- The current working tree was clean at research time (`git -C ~/.claude diff -- settings.json` returned no output), so the specific reformat diff described in the ground truth was not independently reproduced or captured during this spike — the finding rests on the engineer's account plus the closest-matching upstream issues, not a freshly observed diff.

## Suggested options for main and the engineer

- **Option A**: keep the status quo (tracked file + discard-before-pull), accepting the residual risk that a genuine hand-edit sitting uncommitted looks identical to an app reformat.
- **Option B**: remove the three UI-pref keys from the tracked `settings.json` (they already live correctly in `settings.local.json`) as a low-cost experiment, then observe over several sessions whether the tracked file stays clean — this directly tests the open question in Finding 7/"What remains uncertain" without committing to a bigger structural change.
- **Option C**: do NOT `.gitignore` `settings.json` as a standalone move — per Finding 3/4, Claude Code has no supported way to load team-shared hooks/permissions from a different tracked file, so gitignoring the shared file with no replacement channel breaks team sharing outright (R1 fails).
- **Option D**: deprioritize the `.gitattributes` merge-driver route — per Finding 6, it does not address the actual observed failure (dirty-tree pull abort), only actual merge conflicts between committed revisions.
- **Option E**: investigate `managed-settings.json` as a longer-term structural fix, since it is the one place in Claude Code's model the app is documented to never write to and that can hold hooks — but budget time to prototype the per-machine distribution step (git-tracked source file → OS-specific system path, e.g. via a setup script comparable to `setup-worktree.sh`) before committing, since no consulted source describes this pattern in production for a small team.

No recommendation is made among these — the evidence shows each option's trade-off; the choice is the engineer's.
