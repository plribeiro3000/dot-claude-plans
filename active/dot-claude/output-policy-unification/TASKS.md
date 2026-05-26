# TASKS — Output Policy Unification (revised)

> Reference: PLAN.md (revised, 8 phases) and SPIKE.md (revision 2).

## 0) Pre-conditions

- [x] PLAN.md approved (revised scope — single PR)
- [x] Base branch: `develop` • Working branch: `feature/output-policy-unification` (created in Task 1)
- [x] CROSS-REFERENCES.txt populated (Task 2)

---

## 1) Step by step

### Task 1 — Create feature branch — **DONE**

Branch `feature/output-policy-unification` exists, branched from `develop`. Upstream tracking deferred until first push (Task 11).

### Task 2 — Cross-reference audit — **DONE**

`CROSS-REFERENCES.txt` generated at the feature directory. 33 matches classified as TASK4 / TASK5 / STAY (legacy phase numbering — now corresponds to current Task 4 = CLAUDE.md migration and Task 7 = personas/docs).

### Task 3 — Draft Output Policy v2 (5 layers)

- **Objective:** Draft the new `Output Policy` section as a self-contained block ready to drop into `CLAUDE.md`. Old draft `/tmp/output_policy_draft_20260514_103000.md` is superseded; this is v2.
- **Actions:**
  - [ ] Create `/tmp/output_policy_draft_v2_YYYYMMDD_HHMMSS.md`
  - [ ] Write Layer 1 — Format by destination (6 rows: email, Slack, terminal, IDE, PR/issue/doc, chat) — copy structure from current CLAUDE.md lines 318–325, no semantic change
  - [ ] Write Layer 2 — Channel chat vs file (2 rows) — copy from current CLAUDE.md lines 329–332, no semantic change
  - [ ] Write Layer 3 — File destination `/tmp/` vs `~/Downloads/` — new rule:
    - Default: `/tmp/`
    - `~/Downloads/`: only for distribution formats (`.xlsx`, `.csv`, `.pdf`, `.pptx`, `.docx`) OR when engineer explicitly says "downloads"
    - Agent does not guess — default `/tmp/`, override only on explicit format or instruction
  - [ ] Write Layer 4 — File format markdown vs HTML (3-row table):
    - LLM consumer (KNOWLEDGE.md, DOMAIN.md, PROCESS.md, PLAN.md, TASKS.md, SPIKE.md, ANALYSIS.md, CONTEXT-MAP.md, ADRs) → Markdown
    - Engineer visual review (code review, comparisons, findings, timelines, decision matrices) → HTML from `~/.claude/templates/html/<pattern>.html`
    - External tool output → raw text as emitted
  - [ ] Write Layer 5 — Workflow rules (absorb from DCP + Research-First + Bash Single-Line + Command Safety):
    - Pacing gate `>3 items` for decision
    - Default after research with 3+ reads: write document/HTML first, chat = summary
    - Every item for decision needs code excerpt (10–15 lines fenced) + flow narrative + verdict/question
    - Citation requirement
    - Complex command → script in `/tmp/`, single-line invocation in chat
    - Tool output → file, never piped
  - [ ] Write HTML pattern catalog (8 templates: 5 mapped + 3 optional):
    - For each: name, when, agent that owns it, template path
  - [ ] Write Mermaid note (default for diagrams in markdown — example block)
  - [ ] Write file naming pattern (unchanged from current `{location}/{command}_{environment}_{parameters}_{timestamp}.{ext}`)
  - [ ] Write "Where this applies" — main session + agents + skills (absorbed from DCP "Where this applies")
  - [ ] Cross-link to `docs/OUTPUT-EDGE-CASES.md` at the end
- **Completion criteria:**
  - All 5 layers present
  - Pattern catalog has 8 entries
  - `/tmp/` vs `~/Downloads/` decision rule explicit and unambiguous
  - Mermaid default mentioned
- **[HOLD POINT]** Engineer reviews `/tmp/output_policy_draft_v2_*.md`. Approve or revise before Task 4.

### Task 4 — Apply migration in CLAUDE.md

- **Objective:** One coherent commit that lands Output Policy and removes absorbed content from other sections.
- **Actions:**
  - [ ] Replace lines 312–351 (current `Output Formatting and Delivery`) with approved v2 draft
  - [ ] Delete lines 250–270 (entire `Delegation Context Principle` section, including header)
  - [ ] Edit `Bash Single-Line Policy` (lines 12–18):
    - Remove the "When a command is genuinely too complex for one line ... write a script to `/tmp/`" bullet
    - Add at end: cross-link "See § Output Policy for delivery format and `/tmp/` vs `~/Downloads/` destination"
  - [ ] Edit `Command Safety Policy` (lines 388–395):
    - Remove "Output must be preserved: never pipe..." bullet (content now in Output Policy Layer 5)
    - Add cross-link
  - [ ] Edit `Research-First Policy` (lines 272–285):
    - Remove "Citation requirement" bullets (3 bullets) — content now in Output Policy Layer 5
    - Add cross-link
  - [ ] Verify `Communication Style` line 248 ("Bring full context when reporting issues") stays as-is — it complements Output Policy without duplicating
  - [ ] Edit Repository Structure tree (line 486 area):
    - Rename `OUTPUT-FORMATTING.md` → `OUTPUT-EDGE-CASES.md` with updated comment
    - Add `templates/html/` subdirectory under `~/.claude/`
  - [ ] Update internal cross-references per `CROSS-REFERENCES.txt` (specifically line 394: "Output Formatting and Delivery section above" → "§ Output Policy above")
  - [ ] Verify no orphan reference to `Delegation Context Principle` or `Output Formatting and Delivery` remains in CLAUDE.md: `grep -n -E "Delegation Context Principle|Output Formatting and Delivery" ~/Projects/4Shark/dot-claude/CLAUDE.md` returns empty
- **Affected files:** `~/Projects/4Shark/dot-claude/CLAUDE.md`
- **Completion criteria:**
  - No `Delegation Context Principle` section header in file
  - No `Output Formatting and Delivery` section header (replaced by `Output Policy`)
  - All absorbed bullets reachable from Output Policy
  - All cross-links resolve

### Task 5 — Update `settings.json` for `~/Downloads/`

- **Objective:** Allow Claude Code to write to `~/Downloads/` for distribution-format files.
- **Actions:**
  - [ ] Edit `~/Projects/4Shark/dot-claude/settings.json`
  - [ ] Add `"~/Downloads"` to `permissions.additionalDirectories`, alphabetically between `~/.claude` and `/tmp`
  - [ ] Verify with `jq . ~/Projects/4Shark/dot-claude/settings.json > /dev/null`
- **Affected files:** `~/Projects/4Shark/dot-claude/settings.json`
- **Completion criteria:**
  - `~/Downloads` present in the array
  - JSON valid
  - Alphabetical order preserved

### Task 6 — Create `templates/html/` (9 files)

- **Objective:** Build the 9 HTML templates referenced by Output Policy.
- **Actions:**
  - [ ] Create directory `~/Projects/4Shark/dot-claude/templates/html/`
  - [ ] Build `base.html`:
    - System font stack
    - CSS custom properties (`--bg`, `--surface`, `--text`, `--text-muted`, `--border`, `--accent`, `--success`, `--warning`, `--danger`, `--radius`, `--shadow`)
    - Dark mode via `@media (prefers-color-scheme: dark)` overrides
    - `@media (prefers-reduced-motion: reduce)` respect
    - `@media print` styles (expand all `<details>`, remove dark backgrounds)
    - Mermaid via single `<script type="module">` CDN import (jsdelivr)
    - Placeholder regions: `<title>`, `<meta description>`, `<header>`, `<main>`, `<footer>`
    - Comment header citing inspiration: `ghoulvspol/html-effectiveness-skill` (concepts) + `voidful/claude-html-report-skill` MIT (structure reference)
  - [ ] Build `code-review-board.html` extending `base.html`:
    - File-grouped sections
    - Severity badges (CRITICAL / HIGH / MEDIUM / LOW with color)
    - Before/after diff blocks with monospace
    - Inline rationale per issue
  - [ ] Build `comparison-board.html`:
    - Parallel cards (CSS Grid `auto-fill`)
    - Pros/cons with `+`/`-` badges
    - "Recommended" card highlighted with accent border
    - `<details>` for deep dives per card
  - [ ] Build `decision-matrix.html`:
    - Options as columns, criteria as rows
    - Color-intensity cells representing scores
    - Total row with recommendation
  - [ ] Build `interactive-report.html`:
    - Header stats (counts by category)
    - Filter buttons (data-attribute filter)
    - Card list with summary + `<details>` for excerpt + narrative + verdict
    - Search input filtering cards by text content
  - [ ] Build `annotated-timeline.html`:
    - Vertical timeline with colored nodes
    - Date/timestamp per node
    - Color-coded status (complete/in-progress/pending/error)
    - `<details>` per node for full description
  - [ ] Build `knowledge-explorer.html` (optional):
    - Collapsible sections
    - Anchor links per section
    - Sidebar TOC (sticky)
  - [ ] Build `kanban-board.html` (optional):
    - Columns (TODO / IN PROGRESS / DONE)
    - Cards with title + description + tags
    - No drag (static; engineer edits HTML directly to move)
  - [ ] Build `slide-deck.html` (optional):
    - One `<section>` per slide
    - Arrow-key navigation (~20 lines JS)
    - Progress indicator
  - [ ] Each template: open in browser standalone (`open templates/html/<name>.html`), verify no console errors, dark mode renders, print preview clean
- **Affected files:** new files in `~/Projects/4Shark/dot-claude/templates/html/`
- **Completion criteria:**
  - 9 template files exist
  - Each opens in browser standalone
  - Each has source-inspiration comment header
  - Mermaid renders in templates that use it

### Task 7 — Update personas

- **Objective:** Migrate all DCP references to `§ Output Policy` and bind each agent/skill to its default HTML template.
- **Actions:**
  - [ ] Apply edits per `CROSS-REFERENCES.txt` mapping table (Section C and D — agents/ and commands/)
  - [ ] For each persona, add or update the output specification to reference the default HTML template path. Persona-by-persona:
    - [ ] `agents/code-reviewer.md` — output is `code-review-board.html` in `/tmp/`
    - [ ] `agents/security-reviewer.md` — output is `code-review-board.html` in `/tmp/`
    - [ ] `agents/planner.md` — pattern comparison uses `comparison-board.html` in `/tmp/`
    - [ ] `agents/spike.md` — options analysis uses `decision-matrix.html` in `/tmp/`; SPIKE.md stays markdown for LLM consumption
    - [ ] `agents/task-creator.md` — DCP ref updated; no HTML default (TASKS.md is markdown)
    - [ ] `commands/triage-pr.md` — triage report uses `code-review-board.html` in `/tmp/`
    - [ ] `commands/meeting-context.md` — findings use `interactive-report.html` in `/tmp/`
    - [ ] `commands/cleanup-memories.md` — DCP/Output Formatting ref updated; report stays markdown
    - [ ] `commands/create-integrator.md` — Output Formatting ref updated
    - [ ] `skills/integration-debug/SKILL.md` — verification output uses `annotated-timeline.html` in `/tmp/`
  - [ ] Update docs that reference the old name:
    - [ ] `docs/TERRAFORM-CONVENTIONS.md` line 97 — "Output Formatting and Delivery section" → "§ Output Policy"
    - [ ] `docs/COMMAND-SAFETY.md` line 71 — same
- **Affected files:** persona/skill files listed above + 2 docs
- **Completion criteria:**
  - `grep -r "Delegation Context Principle" ~/Projects/4Shark/dot-claude/` returns matches only in `plans/` and `CHANGELOG.md`
  - Each agent in the table references the correct HTML template path
  - Each agent retains pacing-gate behavior (now sourced from Output Policy, not DCP)

### Task 8 — Rename `OUTPUT-FORMATTING.md` and update pointers

- **Objective:** Rename the Tier 2 doc and prune content moved to CLAUDE.md.
- **Actions:**
  - [ ] `git -C ~/Projects/4Shark/dot-claude mv docs/OUTPUT-FORMATTING.md docs/OUTPUT-EDGE-CASES.md`
  - [ ] Edit `docs/OUTPUT-EDGE-CASES.md`:
    - [ ] Title `# Output Edge Cases`
    - [ ] Opening: "Per-destination edge cases that complement § Output Policy in `~/.claude/CLAUDE.md`. Read when producing output for a destination not covered by the main policy, or when the engineer reports pasted content rendered wrong."
    - [ ] Keep: Slack mrkdwn subset, Outlook quirks, Gmail smart-compose, IDE auto-format, terminal escaping
    - [ ] Add: HTML report destinations section (link previews, Notion/Confluence embedding, attaching to email)
  - [ ] Edit `scripts/read-context.sh`:
    - [ ] Replace the `pointer "OUTPUT-FORMATTING.md" ...` line with `pointer "OUTPUT-EDGE-CASES.md" "Per-destination edge cases for Output Policy (Slack, Outlook, IDE, terminal, Gmail, HTML destinations)" "producing output for an unusual destination, or when pasted content rendered wrong"`
  - [ ] Verify: `bash ~/Projects/4Shark/dot-claude/scripts/read-context.sh > /tmp/test_context_output.txt 2>&1` exits 0
- **Affected files:** `docs/OUTPUT-FORMATTING.md` (renamed), `docs/OUTPUT-EDGE-CASES.md` (edited), `scripts/read-context.sh`
- **Completion criteria:**
  - `git ls-files docs/OUTPUT-FORMATTING.md` returns empty
  - `grep -r "OUTPUT-FORMATTING.md" ~/Projects/4Shark/dot-claude/` returns no matches
  - `read-context.sh` exits 0 with no warnings

### Task 9 — Hook implementation

- **Objective:** Add `inject-research-output-context.sh` and register in `settings.json`. Counter files in `/tmp/` are per-session (different `CLAUDE_SESSION_ID`) and small; the OS handles `/tmp/` cleanup. No additional cleanup script needed.
- **Actions:**
  - [ ] Create `~/Projects/4Shark/dot-claude/scripts/inject-research-output-context.sh`:
    - [ ] Flags: `--count` (default), `--reset`
    - [ ] Read `CLAUDE_SESSION_ID` env (fallback `$$`)
    - [ ] Counter file: `/tmp/claude-research-counter-${SESSION_ID}`
    - [ ] `--count`: increment counter; if `>= 3`, emit `hookSpecificOutput.additionalContext` with reminder body
    - [ ] `--reset`: `rm -f` counter file
    - [ ] Reminder body references `§ Output Policy` and recommends `templates/html/interactive-report.html` for findings
    - [ ] Always exit 0
  - [ ] `chmod +x scripts/inject-research-output-context.sh`
  - [ ] Run `shellcheck scripts/inject-research-output-context.sh` (if available); resolve warnings
  - [ ] Edit `~/Projects/4Shark/dot-claude/settings.json`:
    - [ ] Add `PostToolUse` matcher `Read|Grep|Glob|WebFetch` → `$HOME/.claude/scripts/inject-research-output-context.sh --count`
    - [ ] Add `PostToolUse` matcher `Edit|Write|MultiEdit` → `$HOME/.claude/scripts/inject-research-output-context.sh --reset`
    - [ ] Add `PreToolUse` matcher `AskUserQuestion|TaskCreate` → `$HOME/.claude/scripts/inject-research-output-context.sh --reset`
    - [ ] Verify `jq . settings.json > /dev/null`
- **Affected files:** new `scripts/inject-research-output-context.sh`, `settings.json`
- **Completion criteria:**
  - Hook script executable, `shellcheck` clean (if available)
  - `jq . settings.json` exits 0

### Task 10 — Manual test (engineer-run)

- **Objective:** Validate the hook fires correctly at threshold 3 and resets on Edit/Write.
- **Actions** (engineer runs in a fresh Claude Code session, in any working directory):
  - [ ] Pre-clean: `rm -f /tmp/claude-research-counter-*`
  - [ ] Read 3 different files (e.g., `cat ~/.zshrc`, `cat ~/.gitconfig`, `ls ~/Downloads/`) using `Read`/`Glob`/`Grep`
  - [ ] Expected: after the 3rd, the agent's next response shows the research-output reminder citing `§ Output Policy`
  - [ ] `Write` any file (or `Edit`) → next response: counter reset (no reminder on next read pair)
  - [ ] Read 3 more times → reminder reappears
  - [ ] `Read` 2× + `AskUserQuestion` → counter reset, no reminder
- **Completion criteria:**
  - Reminder appears after exactly 3 consecutive research reads
  - Reminder does NOT appear after `Edit`/`Write`/`AskUserQuestion`/`TaskCreate`
  - Counter file at `/tmp/claude-research-counter-${SESSION_ID}` is created and reset as expected
- **If test fails:** return to Task 9, debug script, repeat.

### Task 11 — CHANGELOG + PR

- **Objective:** Document changes and open PR.
- **Actions:**
  - [ ] Edit `~/Projects/4Shark/dot-claude/CHANGELOG.md`:
    - [ ] Find or create `## [Unreleased]` section
    - [ ] Under `### Added`:
      - `HTML output templates for visual review`
      - `Active reminder after research reads`
    - [ ] Under `### Changed`:
      - `Output rules consolidated under Output Policy section`
      - `Distribution-format files now default to ~/Downloads/`
  - [ ] Decide commit strategy with engineer:
    - Option A: squash all changes to single commit `refactor(output): consolidate output rules under Output Policy`
    - Option B: keep one commit per phase
    - Default: Option A (squash)
  - [ ] First push (explicit refspec): `git -C ~/Projects/4Shark/dot-claude push origin feature/output-policy-unification:refs/heads/feature/output-policy-unification`
  - [ ] Set upstream: `git -C ~/Projects/4Shark/dot-claude branch --set-upstream-to=origin/feature/output-policy-unification feature/output-policy-unification`
  - [ ] Open PR with `gh pr create --title "refactor(output): consolidate output rules under Output Policy" --body "..."`
  - [ ] PR body content:
    - One-paragraph summary
    - Reference: `~/.claude/plans/active/spike/output-policy-unification/SPIKE.md`
    - Sources cited (Thariq post, Simon Willison, html-effectiveness-skill, claude-html-report-skill)
    - Manual test reminder for reviewer
- **Affected files:** `CHANGELOG.md`, PR on GitHub
- **Completion criteria:**
  - `CHANGELOG.md` entries concise, no technical detail
  - Single commit on the branch (or per-phase commits per engineer decision)
  - PR opened against `develop`
  - PR description shows clean diff
- **Observations:** Do NOT merge — engineer or reviewer must run Task 10 manual test before approval. PR stays open pending test.

---

## 2) Hold points

- **Task 3 → Task 4**: engineer reviews `/tmp/output_policy_draft_v2_*.md` before it lands in CLAUDE.md
- **Task 9 → Task 11**: engineer runs Task 10 manual test before PR approval

## 3) Items already decided (no engineer confirmation needed)

- Threshold for hook reminder: 3 consecutive research reads
- Counter storage: `/tmp/claude-research-counter-${SESSION_ID}`
- Hook event: `PostToolUse` (revisit `PostToolBatch` only if double-counting appears)
- HTML primitive: templates, not skill
- Self-contained HTML with only Mermaid as CDN dep
- 5 mapped patterns + 3 optional = 8 HTML templates total
- `/tmp/` default; `~/Downloads/` for `.xlsx`, `.csv`, `.pdf`, `.pptx`, `.docx` or explicit request
- Mermaid default for any diagram in markdown
- Single PR strategy
- `OUTPUT-FORMATTING.md` → `OUTPUT-EDGE-CASES.md`
- "Delegation Context Principle" term removed entirely
