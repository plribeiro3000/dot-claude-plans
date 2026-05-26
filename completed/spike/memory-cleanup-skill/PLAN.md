# PLAN — Memory Cleanup Skill

**Status:** Done — skill shipped in 4shark/dot-claude#119, merged 2026-04-29. Skill file at `~/.claude/commands/cleanup-memories.md`.

**Known follow-ups (not part of this plan):**
- The skill hardcodes `~/Projects/4Shark/.claude/` in 4 places (lines 140, 232, 322, 459). The repo was renamed to `dot-claude` mid-cycle and PR #116 made the working copy path location-agnostic. Skill needs updating to either use a runtime prompt for the `.claude` working copy path or to align with the new `dot-claude` name. Open as a separate task when revisited.

## Current Situation

- **Auto-memory is enabled and writing to** `~/.claude/projects/<encoded-cwd>/memory/` — every session accumulates `user_*.md`, `feedback_*.md`, `project_*.md`, `reference_*.md` files plus the `MEMORY.md` index.
- **No process exists to clean up**. In April 2026 we did this manually for ~40 files. Several were 6+ weeks stale: pointing to renamed plans, blockers already resolved, conventions already documented in CLAUDE.md.
- **The canonical knowledge locations already exist** — `~/.claude/CLAUDE.md` (global rules), `~/.claude/docs/*.md` (Tier 1/2), `<repo>/CLAUDE.md`, `<repo>/docs/runbooks/`, `<repo>/docs/adr/`, `~/.claude/plans/active/`. The problem is moving knowledge from inbox to canonical home before it goes stale.
- **Memory directories are per-cwd**, encoded as `-Users-<user>-Projects-<group>-<repo>` (e.g., `-Users-plribeiro3000-Projects-4Shark-integrator/memory/`). The encoding is the bridge from a memory file to its target repo.
- **Impacted components**: `~/.claude/` repo (skill definition, supporting Tier 2 doc), every 4Shark repo that may receive a CLAUDE.md / runbook / ADR addition, `~/.claude/plans/active/` for migrated active-work memories, `~/.claude/settings.local.json` for the per-machine scope whitelist.

## Objective / Target State

- **A user-invoked skill** `/cleanup-memories` that the engineer runs on demand (no schedule, no automation).
- **Zero-config:** the skill stops with a clear message if `~/Projects/4Shark/` is not on disk. Engineers do not edit any settings file.
- When invoked, the skill:
  1. Verifies the working-copies root `~/Projects/4Shark/` exists; if not, stops with a clear setup message
  2. Snapshots every memory file whose decoded directory is under `~/Projects/4Shark/`
  3. Determines the run's folder — always `active/memories/<YYYY-MM-DD>/` (one folder per run, no project-name segment)
  4. **If a folder for today's run already exists** (in `active/` or `completed/`), reuses it: brings it back to `active/` if needed, and merges new entries with any pending old entries
  5. Writes a `SPIKE.md` describing every memory found with the proposed destination and "why"
  6. Presents the proposal table to the engineer — distinguishing fresh entries from "previously planned but not yet executed" carry-overs
  7. Lets the engineer accept, change, or skip each row
  8. Promotes the SPIKE into a `PLAN.md` with the engineer's final decisions
  9. Applies decisions: **one PR per memory** (branch `feature/cleanup-memory-<slug>`), or local migration to `~/.claude/plans/active/<topic>/` for active-work entries, or simple deletion for drops
  10. Deletes each memory from the inbox **only after** its target action succeeded
  11. Moves the run folder from `active/` to `completed/` when every memory has been finalized (PR open, plan migrated, or dropped)
- **Acceptance criteria**:
  - First-time run on a machine with N accumulated memories produces N decisions, ≤N PRs, and an empty inbox for everything finalized
  - Memories the engineer skips remain untouched
  - No memory is deleted unless its target action succeeded
  - Memories outside `~/Projects/4Shark/` are never read or modified
  - Re-running the skill immediately after produces an empty proposal (idempotent)
  - Same-day re-run reuses the existing folder rather than creating a parallel one; pending entries from the earlier round are surfaced and re-tried; finished entries are not redone

## Problem / New Feature

- **Objective description**: build a manual skill that processes the auto-memory inbox the same way we processed it manually in April 2026, encoded as a repeatable interactive flow. The skill is the cleanup process turned into a tool.
- The skill replaces no existing flow — auto-memory keeps writing as today.

## Challenges, Difficulties and Risks

### Technical

- **Per-cwd memory encoding** — mapping `-Users-plribeiro3000-Projects-4Shark-integrator` back to the `integrator` repo on disk requires a deterministic decoder; if a project moved or was renamed, the decoder must report "no target repo found" rather than guess.
- **`.claude` working copy state** — many decisions land in `~/Projects/4Shark/.claude/` (CLAUDE.md global, Tier 2 docs). The engineer may have in-flight work there. The skill must not clobber it.
- **Snapshot vs live writes** — auto-memory may write a new file mid-cleanup. The skill must clean up the snapshot only and ignore anything that appeared after.
- **Path validation** — a memory may reference a plan path that has been renamed; migrating the memory to the wrong target is worse than leaving it.

### Product/UX

- **Decision fatigue** — N memories means N decisions. The proposal must be scannable in one view and let the engineer batch-accept obvious ones.
- **Trust gradient** — first-time engineers won't trust the categorization. Output must show *why* the skill recommends each action (the rule that applied).

### Security/privacy

- **Personal memories from non-4Shark projects** — must never be opened, summarized, or sent in PR descriptions. The root check + per-directory decode in Phase 1 gates this before any file is read.
- **PR content** — the skill is committing to public 4Shark repos; the body of any memory becomes a public diff. Engineer reviews before push.

### Re-run safety

- **Same-day collision** — the engineer may run cleanup multiple times in a day (morning sweep, end-of-day sweep). The skill must detect today's existing folder (in `active/` or `completed/`) and merge into it without losing any prior decision or pending entry.
- **Pending entries from earlier runs** — a memory may have been planned in the morning but had its PR fail to open. The afternoon re-run must surface that entry (not silently re-propose) and continue from where it stopped.
- **Folder lifecycle correctness** — folders move from `active/` to `completed/` only when every entry inside has been finalized (PR open, plan migrated, or dropped). Re-runs reverse this when needed.

### Performance

- Not a concern at expected scale (≤200 memory files per machine).

## Resolved Open Questions (from SPIKE)

| SPIKE question | Decision |
|---|---|
| 1. Categorization logic location | **No separate rules doc**. The agent uses the destinations that already exist in the canonical layout (`CLAUDE.md` global, Tier 1/2 docs, per-repo `CLAUDE.md`, runbooks, ADRs, plans) and proposes a destination for each memory in real time. The engineer validates each proposal, so a maintained rules catalog is unnecessary in v1. Revisit if the agent's first-pass categorization proves inconsistent. |
| 2. "Already covered" detection | **Agent judgment**. The proposal pairs each memory with the candidate covering section; engineer confirms drop. |
| 3. Project scope | **Zero-config**. The skill checks `~/Projects/4Shark/` exists and processes only memories whose decoded directory falls under that root. If the root is missing, the skill stops with a setup message — no settings file, no prompt for an alternate path. Memories outside the root are skipped silently. |
| 4. Run artifacts and PR shape | **One folder per run** at `active/memories/<YYYY-MM-DD>/` (always — no project-name segment; a run is "today's cleanup", not "today's cleanup of project X"). The folder holds a `SPIKE.md` (proposal) that becomes a `PLAN.md` (decisions). **One PR per memory** — branch `feature/cleanup-memory-<slug>`. When all memories in the run are finalized, the folder moves to `completed/`. |
| 5. `.claude` working copy handling | **Operate on `~/Projects/4Shark/.claude/` directly**, with explicit precondition: branch is `develop` and tree is clean. If not, skill stops and asks the engineer to stash or commit before retrying. No worktree complexity in v1. |
| 6. Failure modes | **Snapshot at start** (only clean up captured set); **validate every path** a memory references before migrating; **dry-run by default** — engineer reviews the full proposal table before any file is touched. |
| 7. Same-day re-run | **Reuse the existing folder** for today's date. If found in `completed/`, move back to `active/`. Append fresh entries to the existing `SPIKE.md`/`PLAN.md`; surface old entries that were planned but not yet executed (PR open failed, etc.) and re-attempt them. Re-runs never create a parallel folder for the same date. |

## Interaction Model (engineer-driven)

This is the flow the user described — it replaces any automation:

1. Engineer runs `/cleanup-memories`.
2. Skill verifies `~/Projects/4Shark/` exists; stops with a setup message if not.
3. Skill snapshots in-scope memories. Determines today's run folder location:
   - All memories belong to one project → `active/memories/<project-name>/<YYYY-MM-DD>/`
   - Otherwise → `active/memories/<YYYY-MM-DD>/`
4. Skill checks if today's folder already exists (in `active/` or `completed/`). If found in `completed/`, moves back to `active/`. If found, merges the new snapshot with existing entries — old "planned but not finalized" entries carry over and are clearly marked.
5. Skill writes/updates `SPIKE.md` with the full snapshot: source memory path, summary, recommended destination, rule that fired, "why".
6. Engineer reviews and gives per-row decisions: `accept`, `change to <destination>`, or `skip`. Bulk shortcuts allowed (`accept all drops`, `accept all category X`).
7. Skill confirms the decision set and waits for explicit "go".
8. On "go", skill writes `PLAN.md` (final decisions) and starts applying:
   - Each memory destined for a file → its own branch `feature/cleanup-memory-<slug>`, its own commit, its own PR
   - Each memory destined for an active plan → migrated to `~/.claude/plans/active/<topic>/` (local, no PR)
   - Each memory destined for `drop` → just deleted from inbox
9. Skill deletes each memory **only after its action succeeded**. Failed actions leave the memory in place; entries stay in `PLAN.md` for the next run to retry.
10. When every entry in `PLAN.md` is finalized (PR open / migrated / dropped), the run folder moves from `active/` to `completed/`.

The deletion step is intrinsic to the implementation: the skill removes a memory only because its content has already landed in its canonical home (or was confirmed already covered, or was rejected as obsolete).

## Destination Reference (informational — already exist in the layout)

These are the destinations the agent proposes from. They are not new — they are the canonical knowledge locations the team already uses. Listed here to make the design explicit; the skill prompt names them as available targets, not as a maintained catalog.

| Source memory shape | Destination |
|---|---|
| Already covered in `~/.claude/CLAUDE.md` / `~/.claude/docs/*.md` / `<repo>/CLAUDE.md` / runbook | drop |
| Universal Claude behavioral rule (any project) | `~/.claude/CLAUDE.md` (PR to `4Shark/.claude`) |
| Language/framework convention (Ruby, Rails, RSpec, etc.) | `~/.claude/docs/<NAME>.md` Tier 2 (PR to `4Shark/.claude`) |
| Project-specific rule | `<repo>/CLAUDE.md` (PR to that repo) |
| Operational procedure | `<repo>/docs/runbooks/<area>/<NAME>.md` (PR to that repo) |
| Architectural decision | `<repo>/docs/adr/ADR-NNN-<topic>.md` (PR to that repo) |
| Active work / unresolved blocker | `~/.claude/plans/active/<topic>/` (no PR — local) |
| Obsolete TODO / resolved blocker / state cache | drop |

## Proposed Steps (high level, don't execute yet)

1. **Build the skill** at `~/.claude/commands/cleanup-memories.md` (single markdown file, frontmatter + prose, no helper script in v1). Skill responsibilities, in order:
   - Verify `~/Projects/4Shark/` exists; if not, stop with a setup message
   - Snapshot memory files whose decoded directory is under the 4Shark root; skip silently anything outside
   - Compute today's run folder path: `active/memories/<YYYY-MM-DD>/` (always)
   - Check `active/` and `completed/` for an existing folder for today; if found in `completed/`, move it back to `active/`; merge new snapshot with existing entries (old pending entries persist with a "previously planned" marker)
   - Write/update `SPIKE.md` in the run folder with every entry (source path, summary, proposed destination, why)
   - Render the proposal in chat (≤10 rows) or `/tmp/` (>10 rows) per Output Formatting policy
   - Collect per-row decisions (with bulk shortcuts) and explicit "go" confirmation
   - Promote `SPIKE.md` to `PLAN.md` (or write a sibling `PLAN.md` capturing the final decisions)
   - Apply each decision: **one branch + one PR per memory** (`feature/cleanup-memory-<slug>`), or active-plan migration (local), or drop (delete only)
   - Delete each memory only after its action succeeds
   - When every entry in `PLAN.md` is finalized, move the run folder from `active/` to `completed/`
2. **Validate against Paulo's machine state** — run the skill on the current memory inbox, walk through proposal → decisions → apply end-to-end with real data, fix prompt/UX as needed.
3. **Document the skill in `~/.claude/CLAUDE.md` Available Commands section** so future sessions know it exists.
4. **Defer the routine/schedule and a maintained rules catalog** — explicitly out of scope until the manual flow is validated by both Paulo and Emerson over ≥1 month (matches SPIKE decision gate). Revisit a Tier 2 rules doc only if the agent's first-pass categorization proves inconsistent in practice.

## Internal References

- SPIKE: `~/.claude/plans/active/spike/memory-cleanup-skill/SPIKE.md`
- Existing skill examples: `~/.claude/skills/` (review during step 2 to match conventions)
- Settings: `~/.claude/settings.json` (shared) and `~/.claude/settings.local.json` (per-machine, git-ignored)
- Memory inbox: `~/.claude/projects/<encoded-cwd>/memory/`
- Output formatting policy: `~/.claude/CLAUDE.md` § "Output Formatting and Delivery" and `~/.claude/docs/OUTPUT-FORMATTING.md`
- Git push safety: `~/.claude/CLAUDE.md` § "Git Push Safety" — relevant for the skill's own pushes from `~/Projects/4Shark/.claude/` and from any other working copy

---

**Question:** Approve this plan?
Answer with: `APPROVED` to proceed to task breakdown, or describe changes you'd like first.
