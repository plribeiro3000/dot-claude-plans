# SPIKE — Memory Cleanup Skill

**Status:** Closed — generated PLAN.md + skill (`commands/cleanup-memories.md`) and shipped via 4shark/dot-claude#119, merged 2026-04-29.

## The question

How should we keep Claude Code's auto-memory **enabled** (so engineers benefit from per-session context accumulation) while also having a **process to clean up** those memories into the canonical knowledge locations (CLAUDE.md, docs/, runbooks, plans) before they go stale or get lost on machine reset?

## Why this exists

We just spent a long thread (April 2026) cleaning up ~40 memory files manually — 1 by 1, deciding for each: drop, migrate to CLAUDE.md global, migrate to a Tier 2 doc, migrate to a project CLAUDE.md, turn into a runbook, turn into an ADR, or move to an active plan. That work was valuable but slow, and it was already late — some memories were 6+ weeks old, several pointed to plans that had been renamed, blockers that had been resolved months ago, etc.

The lesson: **memory grows silently**. Without a regular cleanup pass, by the time anyone looks, half the content is stale and the rest is hard to validate. Disabling auto-memory entirely was considered and rejected — it would force the change on every engineer (Emerson) without consent, and would lose the actual benefit of the feature, which is real.

The right answer is to **process the inbox**: keep auto-memory writing to `~/.claude/projects/*/memory/`, but have a tool that reads it, categorizes, opens PRs, and clears the inbox.

## Desired shape

### Skill `/cleanup-memories`

A user-invoked skill that:

1. **Scans** `~/.claude/projects/*/memory/` — every project's memory folder, not just one
2. **Filters by scope** — only acts on projects in a configured whitelist (default: `4Shark/*`). Memories from personal projects (`OSS/<personal>`, `personal-thing`, etc.) are left untouched
3. **Maps each memory to a target repo** by the encoded directory name (e.g., `-Users-<user>-Projects-4Shark-integrator/memory/*.md` → `integrator` repo)
4. **Categorizes each memory** using the rules we validated in the April 2026 cleanup:
   - Already covered in CLAUDE.md / docs / runbooks → **drop**
   - Universal Claude behavioral rule → **CLAUDE.md global** (`~/Projects/4Shark/.claude/CLAUDE.md`)
   - Language/framework convention → **Tier 2 doc** (`~/Projects/4Shark/.claude/docs/<NAME>.md`)
   - Project-specific rule → `<repo>/CLAUDE.md`
   - Operational procedure → `<repo>/docs/runbooks/<area>/<NAME>.md`
   - Architectural decision → `<repo>/docs/adr/ADR-NNN-<topic>.md`
   - Active work / unresolved blocker → `~/.claude/plans/active/<topic>/`
   - Obsolete TODO / resolved blocker / state cache → **drop**
5. **Presents a categorized proposal to the engineer** — does NOT apply silently
6. **Applies after approval**, opening one PR per affected repo
7. **Deletes cleaned up memories** from `~/.claude/projects/<project>/memory/` after the PR is open

### Routine (later, optional)

Once the manual skill is validated, a `/schedule`-based routine could:

- Run every weekday morning (e.g., 08:00 local)
- Check if there are ≥N pending memories or if the oldest is ≥X days old
- Send a desktop notification: "memory inbox has N entries from M projects — run /cleanup-memories"
- Does **not** open PRs on its own — the engineer still drives

Full automation (PRs without engineer approval) is rejected for the same reason that auto-merge of Renovate PRs is gated by the 7-day age check: the cost of a bad PR is non-local.

## Key open questions

The questions below are what makes this a spike instead of a plan. Each one needs an answer before the skill is built.

### 1. Where does the categorization logic live?

Two options:

- **In the skill prompt** — the rules we validated are encoded as instructions to the agent. Pros: easy to update, transparent to the engineer, consistent with how other skills work. Cons: the skill becomes a long prompt; a bug in the prompt is harder to diff than a bug in code.
- **In a separate `~/.claude/docs/MEMORY-CLEANUP.md` Tier 2 doc** that the skill loads — separation of concerns. Pros: rules are reviewable independently, can be linked from elsewhere, can be evolved without touching the skill. Cons: indirection.

**Hypothesis to validate**: option B (separate doc) is better — the rules are team conventions, not skill mechanics, and they will evolve.

### 2. How to detect "already covered" without false positives?

A memory says "use `git push` with explicit refspec." The CLAUDE.md global already has a Git Push Safety section with the exact same content. The skill needs to recognize this and drop the memory.

Options:

- **Content embedding similarity** — compute a vector of the memory and of each CLAUDE.md / doc section; flag memories where the closest match is above a threshold. Probably overkill.
- **Keyword overlap + agent judgment** — let the agent read both and decide. Lighter, matches how we did it manually.
- **Manual whitelist of "already covered" patterns** — too brittle.

**Hypothesis**: option B (agent judgment with a clear "show me what looks already covered" output stage) is enough — the agent presents pairs `(memory, candidate-cover)` and the engineer confirms drop or asks for migration.

### 3. Whitelist mechanism for project scope

Where does the engineer say "clean up from 4Shark and meeting-hive but not from my personal blog"?

- `~/.claude/settings.json` — natural home, but settings.json is shared (working copy in git)
- `~/.claude/settings.local.json` — git-ignored, per-machine. **Better** because Paulo's whitelist may differ from Emerson's
- A skill argument — the engineer specifies on each invocation

**Hypothesis**: `settings.local.json` with a `cleanupScope: ["4Shark/*", "OSS/meeting-hive"]` field. Skill reads it on start; if missing, asks the engineer once and offers to write it.

### 4. PR shape — one big PR per cleanup, or one per repo?

A single cleanup pass might touch the `.claude` repo (rules in CLAUDE.md), the `terraform` repo (runbooks), the `integrator` repo (project rules), and `~/.claude/plans/active/` (no PR, local).

- **One PR per repo** — clean diff per repo, normal review flow, but the engineer loses the holistic view of the cleanup
- **One "cleanup report" doc + one PR per repo** — the report summarizes what went where; each PR is reviewed normally; the report itself is part of the local plans

**Hypothesis**: option B (report + per-repo PRs). The report lives in `~/.claude/plans/active/memory-cleanups/<date>/REPORT.md` and is the engineer's record of what was decided.

### 5. What about the 4Shark `.claude` working copy?

When a memory becomes a CLAUDE.md global rule, the PR is in `~/Projects/4Shark/.claude/`. The engineer (or the skill) needs to:

- Have the working copy on a clean `develop` (or stash whatever they're working on)
- Create a branch with a sensible name
- Apply the edit
- Push with the explicit refspec rule we just documented
- Open a PR
- Restore the previous state if the engineer was working on something

**Open**: should the skill operate on `~/Projects/4Shark/.claude/` directly, or on a worktree of it? Worktrees avoid disturbing in-flight work but add complexity.

### 6. What goes wrong silently?

- **Memory written between scan and apply** — auto-memory may add a new file mid-cleanup. Solution: snapshot the memory directory at scan time, only clean up the snapshot, leave anything new for the next run
- **Plan rename** — if a memory points to `plans/active/integrator/foo/` but `foo/` was renamed to `bar/`, the migration target is wrong. Solution: validate every path the memory mentions before migrating
- **Engineer approves a category, then rejects mid-application** — partial state. Solution: dry-run mode; only apply after engineer reviews the full plan

## What is explicitly NOT in scope

- **Automatic PR merge** — the team's review process applies as normal; the skill opens, does not merge
- **Cross-engineer cleanup** — Paulo's skill on Paulo's machine cleans up Paulo's memories; Emerson runs his own. Memories never travel between machines via this skill
- **Replacing auto-memory** — the skill is a downstream processor, not a replacement for the underlying feature

## Validation plan

When this spike turns into a plan + implementation:

1. Build the skill against Paulo's current state (which will accumulate new memories after this thread)
2. Run it after ~2 weeks of accumulated memories — check that the categorization is right and the PRs are usable
3. Share with Emerson; have him run it on his machine; gather feedback
4. If validated, document the rules in `MEMORY-CLEANUP.md` (Tier 2) and freeze the skill v1
5. Consider a routine (`/schedule`) only after manual usage is stable

## Related context

- The April 2026 cleanup thread (visible in this conversation history) is the manual baseline of "what good looks like"
- `~/.claude/CLAUDE.md` Output Formatting and Delivery section — relevant because cleanup reports may be either in-chat or `/tmp/`
- `~/.claude/docs/MEMORY-CLEANUP.md` — does not exist yet; will be created when the spike turns into a plan

## Decision gates

- **Before building**: answer questions 1–6 above
- **Before adding routine** (`/schedule`): manual skill validated by both Paulo and Emerson over ≥1 month
- **Before considering full automation**: explicitly rejected for now; revisit only if manual + routine both prove insufficient

---

## Evolution — design grew during execution (April 2026)

The original framing (above) treated the skill as a one-shot processor with a `REPORT.md` artifact. During execution this evolved into something larger: the skill produces planning artifacts that ride the team's existing `active/` → `completed/` lifecycle, exactly like any other feature. Capturing the shift here so the spike reflects what was actually built.

### What changed

1. **Per-run artifacts follow the team's plan-execute pattern.** Each invocation produces a `SPIKE.md` (snapshot + proposed destinations) and, after the engineer's decisions, a `PLAN.md` (execution plan). Replaces the original `REPORT.md` design.
2. **Folder layout under `~/.claude/plans/active/`.**
   - `active/memories/<YYYY-MM-DD>/` — one folder per run, regardless of how many projects the memories span. A run is "today's cleanup", not "today's cleanup of project X".
   - Earlier draft had a per-project segment when all memories in a run shared one source project; rejected because it added a branching rule for no real gain — runs typically span multiple projects.
3. **One PR per memory**, not one PR per repo. Branch name: `feature/cleanup-memory-<slug-of-memory-filename>`. Granular review and rollback; merging multiple memories is the rare case.
4. **Active → Completed lifecycle.** When all PRs are open and migrations done for a run, the skill moves the run folder from `active/` to `completed/` (matching the team's feature lifecycle).
5. **Same-day re-run handling.** If a run for the current date already exists (in `active/` or `completed/`), the skill appends new memories to the existing artifacts instead of creating a parallel folder. If the folder is in `completed/`, it is moved back to `active/` first; carries pending entries from the previous round through, marked clearly in the output as "previously planned but not yet executed".
6. **Zero-config root check.** Skill stops at start if `~/Projects/4Shark/` is not present on the machine — does not prompt for an alternate path, does not write any settings file. Rationale: the working-copies root is already a team convention (CLAUDE.md § Configuration Changes Policy); engineers must not have to install/configure the skill.

### What did NOT change

- The categorization catalog (drop / CLAUDE.md global / Tier 2 doc / per-repo CLAUDE.md / runbook / ADR / active plan)
- The "delete memory only after action succeeds" invariant
- The categorization logic stays in the skill prompt — no separate Tier 2 rules doc in v1
- The decision to defer routine/scheduling until manual usage is validated
- Cross-engineer cleanup remains out of scope (each engineer runs the skill on their own machine)

### Why this evolution makes sense

The original `REPORT.md` was a parallel artifact type — yet another markdown file pattern for engineers to learn. Reusing the existing SPIKE → PLAN → execute lifecycle means:

- Same artifacts the team already reads daily
- Same `active/` ↔ `completed/` movement engineers already understand
- Re-runs naturally fit (same folder gets revisited, pending entries persist)
- The cleanup process itself becomes documentable through the same workflow it's processing
