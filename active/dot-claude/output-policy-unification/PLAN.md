# PLAN — Output Policy Unification (revised)

> Reference: `~/.claude/plans/active/spike/output-policy-unification/SPIKE.md` (revision 2)

## Objective

Consolidate every output-related rule into a single canonical "Output Policy" section in `~/.claude/CLAUDE.md`, structured in 5 layers (destination format → chat vs file → `/tmp/` vs `~/Downloads/` → markdown vs HTML by consumer → workflow rules). Adopt HTML as the default file format when a human consumes the output, with 5 templates mapped to existing agents and 3 optional templates available on demand. Remove the "Delegation Context Principle" term. Add an active `PostToolUse` hook that injects a reminder after 3 research reads.

## Scope

### In Scope

- New `Output Policy` section in `CLAUDE.md` with 5 layers (see SPIKE.md for layer definitions)
- Textual migration: extract output content from `Output Formatting and Delivery`, `Delegation Context Principle`, `Bash Single-Line Policy`, `Research-First Policy`, `Command Safety Policy`. Leave back-references
- `~/Downloads/` added to `settings.json` `additionalDirectories`
- Rename `docs/OUTPUT-FORMATTING.md` → `docs/OUTPUT-EDGE-CASES.md`; prune content moved to CLAUDE.md
- Create `~/.claude/templates/html/` with:
  - `base.html` — self-contained template (CSS inline, system fonts, dark mode, Mermaid via CDN as only external dependency)
  - 5 mapped patterns: `code-review-board.html`, `comparison-board.html`, `decision-matrix.html`, `interactive-report.html`, `annotated-timeline.html`
  - 3 optional patterns: `knowledge-explorer.html`, `kanban-board.html`, `slide-deck.html`
- `scripts/inject-research-output-context.sh` — `PostToolUse` hook on `Read|Grep|Glob|WebFetch` with per-session counter, threshold 3, reset on `Edit|Write|MultiEdit|AskUserQuestion|TaskCreate`. Reminder body references `§ Output Policy` and recommends `Interactive Report` template
- Update personas to reference Output Policy and their default HTML pattern:
  - `agents/code-reviewer.md` → `code-review-board.html`
  - `agents/security-reviewer.md` → `code-review-board.html`
  - `agents/planner.md` → `comparison-board.html`
  - `agents/spike.md` → `decision-matrix.html`
  - `agents/task-creator.md` → `interactive-report.html` (when presenting research, otherwise stays markdown for TASKS.md)
  - `commands/triage-pr.md` → `code-review-board.html`
  - `commands/meeting-context.md` → `interactive-report.html`
  - `commands/integration-debug.md` (skill) → `annotated-timeline.html`
- Update `scripts/read-context.sh` pointer to reflect doc rename
- Mermaid as default for diagrams in markdown — note added to Output Policy
- `CHANGELOG.md` entries under `### Changed` and `### Added`
- Single PR against `develop`

### Out of Scope

- HTML report publishing to GitHub Pages (defer — current use case is local-only)
- Additional hooks beyond the research-output reminder (flagged for future)
- `Design Token Sheet` pattern (no design system context in 4Shark)
- Migration of meeting-notes / integration-debug skills to also output `.xlsx` (HTML is enough for now)

## Execution Phases

### Phase 1: Cross-reference audit — **DONE**

Executed in Task 2. Output: `CROSS-REFERENCES.txt` in the feature directory. 33 matches classified by action (TASK4 / TASK5 / STAY).

### Phase 2: Draft the Output Policy section

**Objective**: Author the new Output Policy section (5 layers, replaces current `Output Formatting and Delivery`). Drafted in `/tmp/` for engineer review before applying to `CLAUDE.md`.

**Components**:
- File: `/tmp/output_policy_draft_v2_{timestamp}.md` (the existing `output_policy_draft_20260514_103000.md` is superseded — start fresh with v2)
- Structure:
  - Preamble (engineer should not clean up output)
  - Layer 1: Format by destination (6-row table from current section)
  - Layer 2: Channel chat vs file (2-row table from current section)
  - Layer 3: File destination `/tmp/` vs `~/Downloads/` (new rule: default `/tmp/`, `~/Downloads/` only for distribution formats or explicit request)
  - Layer 4: File format markdown vs HTML (3-row table: LLM consumer → markdown; engineer visual review → HTML from `templates/html/<pattern>.html`; external tool output → raw)
  - Layer 5: Workflow rules (pacing gate, default after research, item-for-decision format, citation, complex command → script, tool output → file never piped)
  - HTML pattern catalog (5 mapped + 3 optional, with the agent that owns each)
  - Mermaid for diagrams in markdown (note + example)
  - File naming pattern (unchanged from current)
  - "Where this applies" (absorbs from DCP — main session, agents, skills)
  - Cross-link to `OUTPUT-EDGE-CASES.md`

**Dependencies**: Phase 1 (audit list informs which phrases other docs reference).

**Success Criteria**:
- [ ] All 5 layers present and unambiguous
- [ ] HTML pattern catalog covers 8 templates (5 mapped + 3 optional), each with: when to use, which agent owns it
- [ ] `/tmp/` vs `~/Downloads/` rule explicit, distribution-format list named
- [ ] Mermaid default mentioned for markdown diagrams
- [ ] Draft reviewed by engineer (hold point) before applying to CLAUDE.md

### Phase 3: Apply migration in CLAUDE.md

**Objective**: Replace `Output Formatting and Delivery` with new `Output Policy`. Remove `Delegation Context Principle` section. Edit other sections to remove absorbed content and add cross-links.

**Components**:
- Work file: `~/Projects/4Shark/dot-claude/CLAUDE.md`
- Replace lines 312–351 (current `Output Formatting and Delivery` section) with the approved v2 draft
- Delete lines 250–270 (entire `Delegation Context Principle` section)
- Edit `Bash Single-Line Policy` (lines 12–18): remove the "/tmp/ script" line, add cross-link "See § Output Policy for delivery format and `/tmp/` vs `~/Downloads/`"
- Edit `Command Safety Policy` (lines 388–395): remove the "Output must be preserved" line, add cross-link
- Edit `Research-First Policy` (lines 272–285): remove citation-requirement bullets, add cross-link. Citation rule now lives in Output Policy Layer 5
- Edit `Communication Style` (line 248): keep the "Bring full context" rule, add cross-link to Output Policy for the format
- Edit `Repository Structure` (line 486): rename `OUTPUT-FORMATTING.md` → `OUTPUT-EDGE-CASES.md` in the tree; add `templates/html/` to the tree
- Update internal references per `CROSS-REFERENCES.txt` (line 394 specifically: "following the Output Formatting and Delivery section above" → "following § Output Policy above")

**Dependencies**: Phase 2 (draft approved).

**Success Criteria**:
- [ ] No `Delegation Context Principle` section header anywhere in CLAUDE.md
- [ ] No `Output Formatting and Delivery` section header (replaced by `Output Policy`)
- [ ] All absorbed content reachable from Output Policy (audit by re-reading each old section's bullets)
- [ ] All cross-references resolve to existing sections
- [ ] Single coherent diff (no half-migrated state)

### Phase 4: Update `settings.json` for `~/Downloads/`

**Objective**: Allow Claude Code to write to `~/Downloads/`.

**Components**:
- Edit `~/Projects/4Shark/dot-claude/settings.json`
- Add `~/Downloads` to `permissions.additionalDirectories` (alphabetical, between `~/.claude` and `/tmp`)
- Verify JSON parses: `jq . settings.json > /dev/null`

**Dependencies**: None (independent edit).

**Success Criteria**:
- [ ] `~/Downloads` present in `additionalDirectories`
- [ ] `jq . settings.json` exits 0
- [ ] Alphabetical order preserved within the array

### Phase 5: Create `~/.claude/templates/html/`

**Objective**: Build 9 HTML templates (1 base + 5 mapped + 3 optional). All self-contained, CSS inline, Mermaid via CDN as only external dependency.

**Components**:
- Directory: `~/Projects/4Shark/dot-claude/templates/html/`
- `base.html` — minimal template with:
  - System font stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`)
  - CSS custom properties (`--bg`, `--surface`, `--text`, `--accent`, `--success`, `--warning`, `--danger`, etc)
  - Dark mode via `@media (prefers-color-scheme: dark)`
  - `prefers-reduced-motion` respect
  - Print styles
  - Mermaid via CDN (conditional loader — only when `<pre class="mermaid">` exists)
  - Chart.js via CDN (conditional loader — only when `<canvas class="chart">` exists; MIT, ~60KB)
  - CSS classes for `.chart-container`, `<figure>`, `<figcaption>` (images embedded inline or referenced from `/tmp/`)
  - Placeholder regions: title, summary, content
- 5 mapped patterns, each `<pattern>.html` extends `base.html` structure:
  - `code-review-board.html` — file-grouped findings, severity badges, before/after diff sections
  - `comparison-board.html` — parallel cards with pros/cons, recommended-highlighted
  - `decision-matrix.html` — options × criteria grid with color-intensity scores
  - `interactive-report.html` — header stats, filter buttons, card details, search input
  - `annotated-timeline.html` — vertical timeline, color-coded status, expandable details
- 3 optional patterns:
  - `knowledge-explorer.html` — collapsible sections, tabbed code, anchor nav
  - `kanban-board.html` — columns with cards (no drag, only static — engineer-managed)
  - `slide-deck.html` — arrow-key nav slides, zero JS dependencies beyond Mermaid
- Each template has a comment header: source inspiration (ghoulvspol concept, voidful structural reference) + how to use

**Dependencies**: Phase 2 (Output Policy defines which template applies when, names must match the Output Policy catalog).

**Success Criteria**:
- [ ] All 9 templates exist
- [ ] Each template opens in a browser standalone (file:// URL) with no console errors
- [ ] Dark mode renders correctly in each (toggle OS appearance and verify)
- [ ] Print stylesheet emits clean output (browser print preview)
- [ ] Mermaid renders in any template that uses it
- [ ] Each template has a comment header identifying source inspiration

### Phase 6: Update personas (expanded — substantial rewrite for output-rich agents)

**Objective**: Two-tier update:
- **Tier A (rewrite)** — agents/skills that produce decision-ready output get their output section substantially rewritten to integrate the HTML pattern as the primary output, with markdown summary in chat carrying only the decision items. Affected: `agents/spike.md`, `agents/code-reviewer.md`, `agents/security-reviewer.md`, `agents/planner.md`, `commands/triage-pr.md`, `commands/meeting-context.md`, `skills/integration-debug/SKILL.md`.
- **Tier B (reference update only)** — agents/skills that produce LLM-consumed docs (markdown stays). Affected: `agents/task-creator.md`, `commands/cleanup-memories.md`, `commands/create-integrator.md`. DCP/Output-Formatting references updated to point to § Output Policy.

**Components**:
- Use `CROSS-REFERENCES.txt` from Phase 1 as the action list
- For each persona below, update DCP → Output Policy AND add the pattern reference:

| File | Old reference | New reference | Default HTML pattern |
|---|---|---|---|
| `agents/code-reviewer.md` | DCP gate | § Output Policy | `code-review-board.html` |
| `agents/security-reviewer.md` | DCP gate | § Output Policy | `code-review-board.html` |
| `agents/planner.md` | DCP gate | § Output Policy | `comparison-board.html` |
| `agents/spike.md` | DCP refs | § Output Policy | `decision-matrix.html` |
| `agents/task-creator.md` | DCP gate | § Output Policy | (no default; markdown TASKS.md stays) |
| `commands/triage-pr.md` | DCP refs | § Output Policy | `code-review-board.html` |
| `commands/meeting-context.md` | DCP refs | § Output Policy | `interactive-report.html` |
| `commands/cleanup-memories.md` | "Output Formatting and Delivery policy" | § Output Policy | (no default) |
| `commands/create-integrator.md` | "Output Formatting and Delivery section" | § Output Policy | (no default) |
| `skills/integration-debug/SKILL.md` | (no DCP ref, but skill produces audit output) | (add reference to § Output Policy) | `annotated-timeline.html` |
- Also update:
  - `docs/TERRAFORM-CONVENTIONS.md` line 97: "Output Formatting and Delivery section" → "§ Output Policy"
  - `docs/COMMAND-SAFETY.md` line 71: same edit
  - `docs/OUTPUT-FORMATTING.md` lines 1, 3: handled in Phase 7 (rename)

**Dependencies**: Phase 5 (templates must exist for personas to reference them).

**Success Criteria**:
- [ ] `grep -r "Delegation Context Principle" ~/Projects/4Shark/dot-claude/` returns no matches outside `plans/` and `CHANGELOG.md`
- [ ] Each persona in the table above references the correct HTML template path
- [ ] Each persona retains its pacing-gate behavior (now sourced from Output Policy)

### Phase 7: Rename `OUTPUT-FORMATTING.md` and update pointers

**Objective**: Rename the Tier 2 doc and prune content moved to CLAUDE.md.

**Components**:
- `git mv docs/OUTPUT-FORMATTING.md docs/OUTPUT-EDGE-CASES.md` (from working copy root)
- Edit `docs/OUTPUT-EDGE-CASES.md`:
  - Title: `# Output Edge Cases`
  - Opening: "Per-destination edge cases that complement § Output Policy in `~/.claude/CLAUDE.md`. Read when producing output for a destination not covered by the main policy, or when the engineer reports pasted content rendered wrong."
  - Keep edge case sections (Slack mrkdwn, Outlook quirks, IDE auto-format, Gmail smart-compose, terminal escaping)
  - Add new section: "HTML report destinations" — when sharing an HTML report (link previews, embedding in Notion/Confluence, attaching to email — the file does not always render cleanly outside the browser)
- Edit `scripts/read-context.sh`:
  - Find the `pointer "OUTPUT-FORMATTING.md" ...` line
  - Update to `pointer "OUTPUT-EDGE-CASES.md" "Per-destination edge cases for Output Policy (Slack, Outlook, IDE, terminal, Gmail, HTML destinations)" "producing output for an unusual destination, or when pasted content rendered wrong"`

**Dependencies**: Phase 3 (CLAUDE.md references the new name).

**Success Criteria**:
- [ ] `git ls-files docs/OUTPUT-FORMATTING.md` returns empty
- [ ] `grep -r "OUTPUT-FORMATTING.md" ~/Projects/4Shark/dot-claude/` returns no matches
- [ ] `bash scripts/read-context.sh > /tmp/test-context.txt 2>&1` exits 0 with no warnings

### Phase 8: Hook + cleanup + CHANGELOG + PR

**Objective**: Implement the `PostToolUse` hook, extend cleanup, document changes, open PR.

**Components**:

**Hook** (`scripts/inject-research-output-context.sh`):
- Flags: `--count` (default), `--reset`
- Reads `CLAUDE_SESSION_ID` env (fallback `$$`)
- Counter file: `/tmp/claude-research-counter-${SESSION_ID}`
- `--count`: increment, check `>= 3`, emit `hookSpecificOutput.additionalContext`
- `--reset`: delete the counter file if it exists
- Reminder body references `§ Output Policy`, suggests `templates/html/interactive-report.html` for findings
- Always exits 0
- `chmod +x`
- `shellcheck` clean

**`settings.json` hook registration**:
- `PostToolUse` matcher `Read|Grep|Glob|WebFetch` → `scripts/inject-research-output-context.sh --count`
- `PostToolUse` matcher `Edit|Write|MultiEdit` → `scripts/inject-research-output-context.sh --reset`
- `PreToolUse` matcher `AskUserQuestion|TaskCreate` → `scripts/inject-research-output-context.sh --reset`

**`CHANGELOG.md`** under `## [Unreleased]`:
- `### Added`
  - `HTML output templates for visual review`
  - `Active reminder after research reads`
- `### Changed`
  - `Output rules consolidated under Output Policy section`
  - `Distribution-format files now default to ~/Downloads/`

**PR**:
- Branch: `feature/output-policy-unification` (already created in Task 1)
- First push: explicit refspec `git push origin feature/output-policy-unification:refs/heads/feature/output-policy-unification`
- Set upstream after first push: `git branch --set-upstream-to=origin/feature/output-policy-unification feature/output-policy-unification`
- Commit strategy: one commit per phase OR squash to single commit on push — engineer decides at end. Default: squash to single commit, message `refactor(output): consolidate output rules under Output Policy`
- PR title: `refactor(output): consolidate output rules under Output Policy`
- PR body: brief summary + reference to SPIKE.md + manual test instructions (Phase 8 hook test)

**Manual test** (engineer-run, before PR merge):
- Fresh session: `rm -f /tmp/claude-research-counter-*`
- 3× `Read` on different files → reminder appears in next response
- `Write` once → counter reset
- `Read` 3× again → reminder reappears
- `Read` 1× + `Edit` → no reminder (counter reset by Edit)

**Dependencies**: Phases 1–7 complete.

**Success Criteria**:
- [ ] Hook script runs, increments counter, fires reminder at threshold 3
- [ ] Reset triggers work (Edit/Write/AskUserQuestion/TaskCreate)
- [ ] `jq . settings.json` exits 0
- [ ] `CHANGELOG.md` entries concise (no technical detail, no implementation reference)
- [ ] PR opened against `develop` with clear description

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| PR strategy | Single PR | Single migration, single review |
| Doc rename | `OUTPUT-FORMATTING.md` → `OUTPUT-EDGE-CASES.md` | After migration the doc holds only edge cases |
| "Delegation Context Principle" term | Removed | DCP mechanics are output rules; making them a separate concept duplicates the entry point |
| HTML primitive | Templates in `~/.claude/templates/html/`, not a skill | No skill invocation friction — agents reference templates directly. Skills exist for `ghoulvspol`/`voidful` because they have no agent ecosystem |
| 3rd-party skill incorporation | None — own templates, inspired by `ghoulvspol` (concepts, public-domain) and `voidful` (structural reference, MIT-licensed). Cited in template headers | `ghoulvspol` no LICENSE blocks code copy; `voidful` workflow targets GitHub Pages, not our `/tmp/` flow |
| HTML dependencies | CSS inline, system fonts, Mermaid via CDN as only external dep | Self-contained, opens offline, no Tailwind tax |
| File destination axis | `/tmp/` default; `~/Downloads/` only for `.xlsx`, `.csv`, `.pdf`, `.pptx`, `.docx` or explicit request | Engineer reported `/tmp/` is hard to access for files they will share externally |
| Hook event | `PostToolUse` first, revisit `PostToolBatch` if double-counting appears | Simpler and verified |
| Counter threshold | 3 | ≤2 reads is normal lookup, 3+ signals investigation |
| Mermaid default in markdown | Yes | 10 tokens vs 55 ASCII, renders natively in GitHub/Notion/chat |
| Markdown stays for LLM-consumed docs | KNOWLEDGE.md, PROCESS.md, DOMAIN.md, PLAN.md, TASKS.md, SPIKE.md, ANALYSIS.md, CONTEXT-MAP.md, ADRs | Per Thariq rule: model reader = markdown |
| HTML for engineer-consumed reviews | Code reviews, comparisons, decision matrices, research findings, timelines | Per Thariq rule: human reader = HTML |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Persona update misses a DCP reference | Medium | `CROSS-REFERENCES.txt` is the explicit checklist; final `grep -r` is in success criteria |
| HTML template missing browser feature on engineer's machine | Low | Self-contained, only Mermaid is external; tested in browser before commit |
| Hook false positives on quick lookups | Low | Threshold 3, reset on Edit/Write/AskUserQuestion. Reminder is advisory |
| `CLAUDE_SESSION_ID` env var name differs | Low | Phase 8 confirms during implementation; fallback `$$` |
| `~/Downloads/` write permission denied at runtime | Low | Phase 4 adds it to `additionalDirectories`; verified by JSON parse |
| Counter files accumulate in `/tmp/` | Negligible | Files are small text files; OS clears `/tmp/` on reboot. No active cleanup needed |
| HTML report large file size in `/tmp/` | Low | Self-contained but no images/binaries embedded; size cap ~500 KB realistic |
| Migration drops a rule silently | Medium | Phase 2 success criterion: re-read each old section's bullets, confirm each maps to Output Policy |

## Assumptions

- `~/Projects/4Shark/dot-claude/CLAUDE.md` is authoritative; `~/.claude/CLAUDE.md` syncs via `git pull` after merge
- `develop` is the PR base
- No other in-flight feature branch modifies `CLAUDE.md`, `read-context.sh`, `settings.json`, or `OUTPUT-FORMATTING.md` (verify before opening PR)
- Engineer runs the Phase 8 manual hook test before merge

**Status:** READY FOR TASK REGENERATION
