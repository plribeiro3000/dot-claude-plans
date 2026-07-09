# SPIKE — Auto-Updating the dot-claude Config Repo on SessionStart

## Investigation question

Can `~/.claude` (the dot-claude config repo) be made to auto-update on `SessionStart`
— running `git pull` automatically when a newer tagged version exists on the remote
— instead of only warning the engineer to pull manually, as `check-claude-version.sh`
already does today? If an auto-pull is feasible, does the *current* session pick up
the newly-pulled configuration, or only the *next* session? And should auto-pull be
unconditional, or gated by the bump severity the existing script already classifies
(MAJOR / MINOR / PATCH / SECURITY HOTFIX)?

## Ground truth carried into this spike (not re-derived)

- The "warn" half is already built and shipping: `check-claude-version.sh:1-251`
  (read in full for this spike), wired as a `SessionStart` + `UserPromptSubmit` hook
  in `settings.json:20-86` and `settings.json:119-137`. It resolves owner/repo from
  `origin`, compares `git describe --tags --abbrev=0 HEAD` against
  `gh api repos/<repo>/tags --jq '.[0].name'`, classifies the bump, and tells the
  engineer to run `git -C ~/.claude pull` — it does not run the pull itself.
  (`check-claude-version.sh:166-171,231-244`)
- A bare `git -C ~/.claude pull` frequently aborts because the desktop app rewrites
  `settings.json` on disk (key reordering, blank-line stripping, re-adding personal
  prefs like `inputNeededNotifEnabled`) without staging anything. This was directly
  observed twice in the session that produced this spike's brief, each time resolved
  manually with `git -C ~/.claude checkout settings.json` followed by
  `git -C ~/.claude pull` — see `auto-update-dot-claude_log_1.txt` for the captured
  git state and the full account of that precedent.
- Those app-injected personal prefs (`theme`, `inputNeededNotifEnabled`,
  `agentPushNotifEnabled`) already live in the git-ignored `settings.local.json`, so
  discarding the tracked `settings.json`'s reformatting loses nothing — the
  personalization survives in the file git never tracks.

## Sources consulted

- `check-claude-version.sh` (read in full) — the existing warn-only mechanism, its
  gating logic, and its classification scheme.
- `settings.json:20-86` (SessionStart hooks array), `settings.json:119-137`
  (UserPromptSubmit hooks array) — confirms `check-claude-version.sh` and
  `read-context.sh` sit in the **same** `hooks` array under the same `"matcher": "*"`
  block for `SessionStart`.
- `check-dependencies.sh` (read in full) — sibling hook pattern (persistent block
  notice, no daily marker on failure) that a new auto-pull hook would need to follow
  if it fails.
- This session's own `git -C ~/.claude status/branch/remote/log` output — see
  `auto-update-dot-claude_log_1.txt`.
- `https://git-scm.com/docs/git-pull` — `--ff-only` semantics. See
  `auto-update-dot-claude_doc_2.md`.
- `https://git-scm.com/docs/git-checkout` — `checkout <path>` semantics for
  discarding unstaged changes to one tracked file. See
  `auto-update-dot-claude_doc_2.md`.
- `https://git-scm.com/docs/git-status` — porcelain `XY` status-code format, used to
  detect "only settings.json is dirty" vs. "something else is dirty too". See
  `auto-update-dot-claude_doc_2.md`.
- `https://code.claude.com/docs/en/settings` — settings.json hot-reload scope and its
  two documented exceptions (`model`, `outputStyle`). See
  `auto-update-dot-claude_doc_1.md`.
- `https://code.claude.com/docs/en/debug-your-config` — settings.json reload timing
  ("brief file-stability delay"); subdirectory CLAUDE.md on-demand loading. See
  `auto-update-dot-claude_doc_1.md`.
- `https://code.claude.com/docs/en/memory` — CLAUDE.md load timing, the `/compact`
  re-read guarantee (project-root only), and the "delivered as a user message"
  framing. See `auto-update-dot-claude_doc_1.md`.
- `https://code.claude.com/docs/en/hooks` — "All matching hooks run in parallel"
  (self-checked verbatim). See `auto-update-dot-claude_doc_1.md`.
- `https://code.claude.com/docs/en/skills` — Live change detection for `SKILL.md`
  files (self-checked verbatim). See `auto-update-dot-claude_doc_1.md`.
- `https://code.claude.com/docs/en/sub-agents` — live file-watching for
  `~/.claude/agents/` definitions, and what a freshly-spawned subagent loads at its
  own startup. See `auto-update-dot-claude_doc_1.md`.
- `https://agentpatterns.ai/tools/claude/reload-skills-mid-session/` — third-party,
  non-Anthropic source, kept only as corroboration of the code.claude.com skills
  finding; not used to sustain any claim on its own. See
  `auto-update-dot-claude_doc_1.md`.

## Findings

### Finding 1: A safe auto-pull recipe is buildable — the dirty-tree problem has a narrow, principled resolution

**Evidence:** `check-claude-version.sh:38-42` already gates on branch:

```bash
[[ -d "${CLAUDE_DIR}/.git" ]] || exit 0
branch=$(git -C "${CLAUDE_DIR}" branch --show-current 2>/dev/null) || exit 0
[[ "${branch}" == "master" || "${branch}" == "develop" ]] || exit 0
```

**Significance:** any auto-pull hook reuses this exact gate — same branch
restriction, same "not a git repo → no-op" escape hatch.

**Design (described, not implemented) — the safe auto-pull sequence:**

1. **Gate on branch** — identical to `check-claude-version.sh:38-42`. Off-branch
   sessions (a feature branch checked out inside `~/.claude` for editing the config
   itself) never auto-pull.
2. **`git -C ~/.claude fetch origin`** then compare the fetched remote tag to the
   local tag exactly as `check-claude-version.sh:166-171` already does — no new
   comparison logic, reuse the existing `gh api repos/<repo>/tags` + `git describe`
   pair.
3. **Classify the dirty tree with `git -C ~/.claude status --porcelain=v1`.** Per
   `auto-update-dot-claude_doc_2.md` (git-status docs), each line is a two-character
   `XY` code; an unstaged modification to a tracked file shows as ` M <path>` (space
   in X, `M` in Y — "work tree changed since index"). Three outcomes:
   - **Zero lines** → tree is clean → proceed straight to step 5.
   - **Exactly one line, and it is ` M settings.json` (or `.gitignore`-adjacent
     equivalents the desktop app is known to touch)** → the only dirt is the known
     app-reformatting case → proceed to step 4 (discard that one file) → step 5.
   - **Any other line present** (an untracked new file, a modification to any path
     other than `settings.json`, a staged change, a merge-conflict marker) → this is
     **real local work** the engineer has not committed → do **not** auto-pull.
     Fall back to today's warn-only notice (`check-claude-version.sh:231-250`)
     unchanged.
4. **`git -C ~/.claude checkout settings.json`** — per
   `auto-update-dot-claude_doc_2.md` (git-checkout docs): *"Replace the specified
   files and/or directories with the version from the index... will discard any
   unstaged changes"*. Safe specifically because the app-injected prefs it discards
   (`theme`, `inputNeededNotifEnabled`, `agentPushNotifEnabled`) already persist in
   the git-ignored `settings.local.json` — nothing personal is lost. This step only
   ever runs when step 3 already confirmed `settings.json` is the *sole* dirty path.
5. **`git -C ~/.claude pull --ff-only`** — never a merge commit. Per
   `auto-update-dot-claude_doc_2.md` (git-pull docs): *"resolve the merge as a
   fast-forward when possible. When not possible, refuse to merge and exit with a
   non-zero status"* and *"fails if your local branch has diverged from the remote
   branch. This is the default."* If the pull fails (local history diverged from
   `origin/<branch>` — for example the engineer made and committed a local-only
   change to `~/.claude` directly, off the PR workflow), the auto-pull hook does
   **not** attempt any recovery (no rebase, no merge, no reset) — it falls back to
   the existing warn notice and surfaces the failure verbatim, exactly like
   `check-claude-version.sh`'s other failure branches (`check-claude-version.sh:131-163`)
   already do for `gh` failures.

**Edge cases enumerated:**

| Case | Handling |
|---|---|
| `~/.claude` not a git repo | No-op (existing gate, step 1) |
| Branch is not `master`/`develop` | No-op (existing gate, step 1) |
| `gh` unauthenticated / no repo access / API failure | Existing failure-notice branches fire unchanged (`check-claude-version.sh:131-163`) — auto-pull never attempted without a resolved remote tag |
| Local tag == remote tag | No-op, touch the existing daily marker, nothing to pull |
| Tree fully clean, tags differ | Auto-pull proceeds (steps 2, 3-zero-lines, 5) |
| Only `settings.json` dirty (app reformat) | Auto-pull proceeds (steps 3-one-line, 4, 5) |
| `settings.json` dirty AND another path also dirty | Real work is suspected present → fall back to warn, no auto-pull, no discard |
| Any other tracked file dirty (not `settings.json`) | Fall back to warn — never blind-discard a file the recipe was not specifically designed around |
| Untracked file present (e.g. a scratch file the engineer is editing under `~/.claude`) | `git status --porcelain` reports it as `??`; per the "exactly one line" rule above, this makes the "only settings.json dirty" test fail (there are now two lines) → fall back to warn. This is deliberately conservative: an engineer's own scratch file under `~/.claude` never gets silently overwritten by a pull, even though `git pull` alone would not touch an untracked file — the design does not try to distinguish "harmless untracked scratch" from "untracked file about to conflict with an incoming tracked file of the same name", and treats any untracked presence as reason to defer to the engineer |
| Local commits exist that are not on `origin` (diverged) | `git pull --ff-only` fails non-zero → no merge attempted → fall back to warn, verbatim failure surfaced |
| `git fetch` fails (network) | Treated the same as the existing `gh api` network-failure branch — persistent notice, no marker, retry instruction |

### Finding 2: current-session hot-reload is real but partial — not a clean "yes" or "no"

**Evidence and significance, broken down by what a `git pull` inside `~/.claude`
actually changes:**

1. **`settings.json` (hook wiring) and hook script bodies — reload within the
   current session, no restart.** Per `auto-update-dot-claude_doc_1.md`: *"Claude
   Code watches your settings files and reloads them when they change, so edits to
   most keys apply to the running session without a restart. This includes
   `permissions`, `hooks`... "* and *"Edits to `settings.json` take effect in the
   running session after a brief file-stability delay. You don't need to restart."*
   Separately (not itself a Claude-Code-specific claim, just how process invocation
   works): a hook is a path to a script Claude Code shells out to at each firing —
   so even without the settings.json watcher, the **next firing of any given hook**
   (e.g. `check-claude-version.sh` firing again on the very next `UserPromptSubmit`,
   per `settings.json:119-137`) executes whatever is currently on disk at that
   moment, new content included.

2. **`~/.claude/skills/*/SKILL.md` — reload within the current session, no
   restart**, per `auto-update-dot-claude_doc_1.md`: *"Claude Code watches skill
   directories for file changes. Adding, editing, or removing a skill under
   `~/.claude/skills/`... takes effect within the current session without
   restarting."* Only creating a brand-new top-level skills directory that did not
   exist at session start needs a restart — not our case, since `~/.claude/skills/`
   already exists.

3. **`~/.claude/agents/*.md` (subagent definitions) — reload within the current
   session, no restart, at the next delegation.** Per
   `auto-update-dot-claude_doc_1.md`: *"Claude Code watches `~/.claude/agents/` and
   `.claude/agents/`. When you add or edit a subagent file on disk... Claude Code
   detects the change within a few seconds and the next delegation uses the updated
   definition, with no restart needed."* So a pull that updates `spike.md`,
   `plan-researcher.md`, etc. is picked up by the very next `Task` call in the same
   session.

4. **Tier 3 docs read on demand via the `Read` tool (runbooks, ADRs, most of
   `~/.claude/docs/`) — reflect the pull immediately**, because the `Read` tool
   reads current disk state at call time; there is no caching layer. This is the
   same mechanism the docs describe for subdirectory CLAUDE.md files: *"They load
   when Claude reads a file in that directory with the Read tool, not at launch"*
   (`auto-update-dot-claude_doc_1.md`) — the same on-demand-read behavior extends to
   any file read via the `Read` tool, not only nested CLAUDE.md.

5. **A freshly-spawned subagent's own CLAUDE.md/Tier-1/2-doc injection — built fresh
   at that subagent's own startup, mid-session relative to the parent.** Per
   `auto-update-dot-claude_doc_1.md`, what a subagent loads at its own startup
   includes *"CLAUDE.md and memory: every level of the memory hierarchy the main
   conversation loads, including `~/.claude/CLAUDE.md`..."* — this load happens at
   the moment of that `Task` call, not at the parent session's original start. A
   subagent spawned after the pull sees the new `CLAUDE.md` content.

6. **The MAIN session's own already-injected `~/.claude/CLAUDE.md` text and the
   Tier 1/2 doc content injected once by `read-context.sh` at `SessionStart`
   (`settings.json:76`, main-session mode) — do NOT refresh mid-session under
   normal operation.** Two separate reasons converge here:
   - CLAUDE.md is *"delivered as a user message after the system prompt"*
     (`auto-update-dot-claude_doc_1.md`) at session start — a message already in the
     transcript is not retroactively edited by a later file change.
   - The one documented mid-session refresh path is `/compact`: *"Project-root
     CLAUDE.md survives compaction: after `/compact`, Claude re-reads it from disk
     and re-injects it into the session."* This guarantee is stated specifically for
     **project-root** CLAUDE.md. The user-level `~/.claude/CLAUDE.md` (the "User
     instructions" scope) is not explicitly covered by that sentence either way —
     flagged in "What remains uncertain" below.
   - `read-context.sh`'s Tier 1/2 injection fires once, at `SessionStart`
     (`settings.json:20-86`). Nothing in the fetched docs describes a mid-session
     re-fire of `SessionStart` outside of session resume — an auto-pull that runs
     inside this same hook batch does not retroactively change what an
     *already-completed* `SessionStart` firing put into context.

7. **A same-`SessionStart`-batch ordering shortcut does NOT exist.**
   `check-claude-version.sh` and `read-context.sh` sit in the exact same `hooks`
   array under the same `"matcher": "*"` block (`settings.json:22-85`, entries at
   `:31` and `:76`), and the internal comment at `check-claude-version.sh:78`
   ("Mandatory tools... verified by scripts/check-dependencies.sh, which runs ahead
   of this hook") asserts a run-before ordering. Per `auto-update-dot-claude_doc_1.md`
   (self-checked verbatim): *"All matching hooks run in parallel, and identical
   handlers are deduplicated automatically."* This is stated as the general
   execution model for the `hooks` array inside a matcher block, not scoped to one
   event. If that generality holds for `SessionStart` specifically, an auto-pull
   placed inside (or before) `check-claude-version.sh` in the array has **no
   guaranteed ordering** relative to `read-context.sh` firing in the same batch —
   there is a race, not a sequencing guarantee, contradicting the informal ordering
   the sibling script's own comment assumes. This spike does not resolve whether the
   listed array order is, in practice, also the execution order for `SessionStart`
   hooks specifically (the general statement and the sibling script's assumption
   conflict) — flagged in "What remains uncertain."

**Feasibility verdict for Q2:** current-session pickup is **real for skills, agent
definitions, hook scripts/wiring, and anything read on-demand via the `Read` tool or
freshly spawned via `Task`** — these do not need a session restart. Current-session
pickup is **not available for the specific text already injected into the *main*
session's own context at its original `SessionStart`** (the user-level
`~/.claude/CLAUDE.md` body and the Tier 1/2 doc dump from `read-context.sh`) — that
text stays as it was until `/compact` (confirmed for project-root CLAUDE.md,
unconfirmed for user-level) or a fresh session. The engineer's premise in the
brief — "next session gets it, and that's fine" — holds specifically for that last
category; it is stricter than necessary for skills, agents, and hooks, which the
evidence shows already update live.

### Finding 3: policy question — should auto-pull be unconditional across MAJOR/MINOR/PATCH/SECURITY?

**Evidence:** `check-claude-version.sh:206-229` already computes a `classification`
string distinguishing MAJOR (`rm > lm`, "potentially breaking, review CHANGELOG
before pulling"), MINOR (`rn > ln`, "new features added"), and PATCH (`rp > lp`,
further split into plain PATCH vs. "SECURITY HOTFIX detected in CHANGELOG" via
`remote_changelog_has_security()` at `check-claude-version.sh:176-198`).

**Significance:** this classification already exists and is free to reuse as a gate
for an auto-pull decision — the only question is where to draw the line, and that is
a policy call the engineer owns, not a technical constraint. Two shapes surfaced by
the classification that already exists:

- **Gate on severity** — auto-pull PATCH and SECURITY HOTFIX bumps (low risk,
  narrow diff, security bumps benefit from applying fast — this mirrors 4Shark's own
  stated reasoning for bypassing the dependency-update cooldown on security PRs, per
  `CLAUDE.md` § Automated Dependency Updates: *"Cooldown bypass is intentional: a
  published CVE is already public, waiting helps attackers"*), but leave MINOR and
  MAJOR to the existing warn-only path so the engineer reviews the CHANGELOG before
  a larger or potentially-breaking behavior change lands unattended.
- **Auto-pull everything** — treat all four classes the same, on the reasoning that
  `~/.claude` config changes are lower-stakes than application code (no user-facing
  runtime, no deploy) and the existing PR review process already vetted the change
  before it reached the tagged release.

**Also open:** whether auto-pull is **on by default** or **opt-in** (an env var or a
`~/.claude/settings.local.json` flag the engineer sets once), independent of which
severities it covers.

This spike does not choose between these — it surfaces the trade-off for the
engineer, per the brief's explicit instruction not to decide.

### Finding 4: combined behavior — auto-pull and the existing warn notice are complementary, not a replacement

**Evidence:** `check-claude-version.sh:83-89` already has a `--decline` mode and a
`/tmp` daily marker (`check-claude-version.sh:36,169-170`) that silences the notice
for the day once the local tag matches the remote tag.

**Significance — the resulting combined flow, at the design level (no code):**

1. Auto-pull hook runs at `SessionStart` (and/or `UserPromptSubmit`, mirroring where
   `check-claude-version.sh` already runs — `settings.json:20-86,119-137`).
2. If Finding 1's recipe succeeds (clean tree, or only `settings.json` dirty, and a
   fast-forward is possible, and — if Finding 3's severity gate is adopted — the
   bump qualifies): the pull happens silently or with a brief confirmation ("dot-claude
   updated to vX.Y.Z — restart or spawn a subagent to pick it up in full" per
   Finding 2's nuance), and the existing "CLAUDE CONFIG UPDATE AVAILABLE" notice
   (`check-claude-version.sh:231-250`) never fires for that version, because the
   local tag now equals the remote tag by the time the comparison in
   `check-claude-version.sh:166-171` runs (whether that comparison is the same
   invocation or a subsequent one depends on the ordering question in Finding 2,
   item 7).
3. If Finding 1's recipe cannot proceed (real local changes beyond `settings.json`,
   a diverged history, a `gh`/network failure, or — if adopted — a severity outside
   the auto-pull gate): **today's warn notice fires exactly as it does now**,
   unmodified. Nothing about Finding 1's recipe changes `check-claude-version.sh`'s
   existing failure-notice branches (`check-claude-version.sh:131-163`) or its
   MAJOR/MINOR/PATCH classification text (`check-claude-version.sh:206-229`) — the
   auto-pull sits in front of that logic as an additional attempt, with the
   classification and warn notice remaining the universal fallback.

This is additive: the engineer keeps the exact warn behavior they have today for
every case auto-pull cannot safely handle, and gains silent/low-friction updates for
the cases it can.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Auto-pull unconditionally (all bump sizes) | Simplest rule, no severity branching to maintain, fewer stale-config engineers | A MAJOR bump can change behavior underneath a running session without the engineer reviewing the CHANGELOG first | Finding 3 |
| Auto-pull only PATCH + SECURITY, warn on MINOR/MAJOR | Mirrors 4Shark's existing "security bypasses cooldown" reasoning (`CLAUDE.md` § Automated Dependency Updates); larger changes still get human review before they land | Two code paths to maintain instead of one; engineer must remember the split when reasoning about "did my config already update?" | Finding 3, `CLAUDE.md` § Automated Dependency Updates |
| Auto-pull on by default | Zero-effort staleness reduction across the whole team | An engineer who deliberately wants to pin an older config version for a specific debugging session loses that control unless they know the opt-out exists | Finding 3 |
| Auto-pull opt-in (flag/env var) | No surprise behavior change for engineers who haven't explicitly turned it on | Defeats the purpose for anyone who doesn't remember to opt in — the whole team stays on the manual-pull status quo unless each engineer acts | Finding 3 |
| Discard-then-pull only when `settings.json` is the sole dirty path (Finding 1) | Narrowly scoped to the one reformatting behavior directly observed twice this session; never touches a path the recipe wasn't designed around | Any other simultaneous dirt (even a harmless untracked scratch file) blocks the whole auto-pull, falling back to warn — more conservative than strictly necessary, by design | Finding 1, `auto-update-dot-claude_log_1.txt` |

## What remains uncertain

- Whether the user-level `~/.claude/CLAUDE.md` (as opposed to project-root
  `CLAUDE.md`) is re-read from disk on `/compact` the same way project-root
  `CLAUDE.md` is documented to be. Not found: the fetched `code.claude.com/docs/en/memory`
  page states the guarantee for "project-root CLAUDE.md" specifically and is silent
  on the user-level scope either way.
- Whether `SessionStart` hooks in the same `hooks` array (`settings.json:22-85`) are
  actually executed in array-listed order in practice, despite the general "All
  matching hooks run in parallel" statement in the hooks reference doc. The general
  statement and `check-claude-version.sh:78`'s own comment ("runs ahead of this
  hook") are in tension; this spike did not find a source that resolves the
  conflict specifically for `SessionStart`.
- Whether `SessionStart` (and therefore `read-context.sh`'s Tier 1/2 injection) ever
  re-fires mid-session on its own (e.g. on a resume event) outside of an explicit
  `/compact`. Not found in the fetched docs.
- What the desktop app's `settings.json` rewrite behavior looks like across every
  future app version — the "only settings.json, and only a reformatting-shaped
  diff" assumption in Finding 1 rests on twice-observed behavior in one session
  (`auto-update-dot-claude_log_1.txt`), not a documented, stable contract from the
  app vendor.

## Suggested options for main and the engineer

- **Option A — Build the auto-pull hook per Finding 1's recipe, gated by Finding 3's
  "PATCH + SECURITY only" severity split, on by default.** Warn-only remains the
  fallback for MINOR/MAJOR and for every case the recipe cannot safely resolve.
- **Option B — Build the same recipe, but auto-pull unconditionally across all
  four severities.** Simpler to reason about; trades away the "let the engineer
  review MAJOR/MINOR before it lands" property.
- **Option C — Build the same recipe as opt-in only** (an env var or
  `settings.local.json` flag), defaulting to today's warn-only behavior until an
  engineer explicitly turns it on.
- **Option D — Do not build auto-pull; instead close the specific dirty-tree
  friction with a narrower fix**: teach `check-claude-version.sh`'s own instructions
  to include the `git checkout settings.json` step when `settings.json` is the only
  dirty path, so the engineer's manual pull becomes copy-paste-safe again, without
  handing the pull itself to a hook.

Each option should be read alongside Finding 2's nuance: regardless of which option
is chosen, skills, agent definitions, and hook scripts already refresh mid-session
without extra work — only the main session's own already-injected CLAUDE.md/Tier
1-2-doc text waits for `/compact` or the next session, so the engineer should expect
partial, not zero, current-session effect from any of the above.
