# SPIKE — Migrating 4Shark shared Claude Code config from custom Tier 1/Tier 2 hook model to Anthropic's native `.claude/rules/` model

**Conducted by:** Paulo Ribeiro
**Date:** 2026-05-05
**Status:** Research complete — pending decisions

---

## Goal

Determine whether the 4Shark shared Claude Code configuration should be migrated from its custom `scripts/read-context.sh` hook model (Tier 1 full-inline / Tier 2 pointer-with-hint) to Anthropic's native `.claude/rules/` directory with `paths:` frontmatter. Answer six specific questions: mechanics of `.claude/rules/`, audit of current Tier 1 docs, what "always-on" looks like in the new model, what we lose from the hook, risks and migration cost, and a recommendation.

Prior research (not repeated here) established: the 40k char warning is a soft advisory, not a hard limit; the threshold is hardcoded; `@imports` do not reduce context; issue #2766 was closed "not planned". See the original context for those source URLs.

---

## Method

- Read Anthropic's official memory documentation at `https://code.claude.com/docs/en/memory` (fetched directly, verified against the live page).
- Read `~/.claude/scripts/read-context.sh` to establish the exact current Tier 1/Tier 2 split.
- Read all six Tier 1 docs (`ALPHABETICAL-ORDERING.md`, `CHANGELOG.md`, `CODE-STYLE-RULES.md`, `COMMAND-SAFETY.md`, `NO-HIDDEN-COMPLEXITY.md`, `NO-PREMATURE-DRY.md`) to classify path-scoped vs. universal content.
- Measured byte counts for `CLAUDE.md` and all docs under `~/.claude/docs/`.
- Cross-referenced Tier 2 doc triggers in the hook against their file sizes to assess the contextual-pointer model.

---

## Evidence

### E1 — `.claude/rules/` mechanics (source: https://code.claude.com/docs/en/memory)

**Directory structure:**
```
your-project/
├── .claude/
│   ├── CLAUDE.md
│   └── rules/
│       ├── code-style.md
│       ├── testing.md
│       └── security.md
```

All `.md` files are discovered recursively; subdirectories like `frontend/` or `backend/` are supported.

**Frontmatter shape:** YAML frontmatter with a `paths` field.

```markdown
---
paths:
  - "src/api/**/*.ts"
---
```

**Glob support:** Standard glob patterns. Confirmed supported patterns:

| Pattern | Matches |
|---|---|
| `**/*.ts` | All TypeScript files in any directory |
| `src/**/*` | All files under `src/` directory |
| `*.md` | Markdown files in the project root |
| `src/components/*.tsx` | React components in specific directory |

Brace expansion works across multiple extensions: `"src/**/*.{ts,tsx}"`.
Multiple patterns are supported as a YAML array under `paths`.

**Always-on rules (no `paths`):** "Rules without a `paths` field are loaded unconditionally and apply to all files." They load at launch "with the same priority as `.claude/CLAUDE.md`." Confirmed: no `paths` = always loaded, same as inlining in CLAUDE.md.

**Path-scoped trigger:** "Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use." This means the rule file enters context only when Claude opens a matching file, not proactively.

**Composition:** All rules compose additively — they are concatenated into context, not merged or overridden. No conflict-resolution mechanism beyond Claude's own instruction-following.

**User-level rules (source: https://code.claude.com/docs/en/memory, section "User-level rules"):**
`~/.claude/rules/` applies to every project on the machine. "User-level rules are loaded before project rules, giving project rules higher priority." This confirms the 4Shark shared config at `~/.claude/` is the correct location for user-level rules.

**Symlink support:** "The `.claude/rules/` directory supports symlinks... Symlinks are resolved and loaded normally, and circular symlinks are detected and handled gracefully." Confirmed usable for sharing rules across multiple project repos.

**`@imports` (confirmed from prior research):** Imported files expand into context at launch. No lazy-loading occurs. No context savings.

**Size guidance from official docs:** "target under 200 lines per CLAUDE.md file." Path-scoped rules are explicitly the recommended solution for files that exceed this: "use path-scoped rules so instructions load only when Claude works with matching files."

---

### E2 — Current config size measurements

File sizes measured via `wc -c`:

| File | Bytes | Notes |
|---|---|---|
| `~/.claude/CLAUDE.md` | 59,268 | Over the 40k warning; 833 lines |
| `docs/ALPHABETICAL-ORDERING.md` | 5,800 | Tier 1 |
| `docs/CHANGELOG.md` | 13,808 | Tier 1 |
| `docs/CODE-STYLE-RULES.md` | 8,500 | Tier 1 |
| `docs/COMMAND-SAFETY.md` | 4,463 | Tier 1 |
| `docs/NO-HIDDEN-COMPLEXITY.md` | 7,281 | Tier 1 |
| `docs/NO-PREMATURE-DRY.md` | 5,576 | Tier 1 |
| `docs/AUTOMATED-DEPENDENCY-UPDATES.md` | 6,647 | Tier 2 |
| `docs/AWS-MFA.md` | 10,473 | Tier 2 |
| `docs/FACTORYBOT-CONVENTIONS.md` | 5,917 | Tier 2 |
| `docs/LINTING.md` | 3,010 | Tier 2 |
| `docs/NO-SAFE-NAVIGATION.md` | 2,139 | Tier 2 |
| `docs/NO-UNLESS-CONVENTION.md` | 3,461 | Tier 2 |
| `docs/OUTPUT-FORMATTING.md` | 4,224 | Tier 2 |
| `docs/PULL-REQUEST-CONVENTIONS.md` | 1,365 | Tier 2 |
| `docs/RAILS-CONVENTIONS-CONTEXT.md` | 12,072 | Tier 2 |
| `docs/RSPEC-CONVENTIONS.md` | 11,573 | Tier 2 |
| `docs/TERRAFORM-CONVENTIONS.md` | 7,374 | Tier 2 |
| `docs/TESTING-PHILOSOPHY.md` | 12,321 | Tier 2 |
| `docs/1PASSWORD-WSL2-SETUP.md` | 4,806 | Tier 2 (WSL2-conditional) |
| **All docs total** | **130,810** | |

Current per-session context load: `CLAUDE.md` (59,268 bytes) + 6 Tier 1 docs inlined by hook (45,428 bytes) = **~104,696 bytes loaded every session unconditionally**.

---

### E3 — Tier 1 doc classification: path-scoped vs. universal

Tier 1 docs are inlined unconditionally by `scripts/read-context.sh` (source: `~/.claude/scripts/read-context.sh`, lines 53–58):

| Doc | Size | Content scope | Path-scope possible? | Assessment |
|---|---|---|---|---|
| `ALPHABETICAL-ORDERING.md` | 5,800 | Rails models, RSpec lets, Angular/TS interfaces, callbacks | `**/*.rb`, `**/*.ts`, `**/*.tsx` | **Partial** — covers Ruby + TypeScript but not bash/SQL/HCL. Would need 3–4 rules files or one no-`paths` rule |
| `CHANGELOG.md` | 13,808 | Applies when creating any changelog entry, any language, any repo | None — trigger is a workflow action ("creating a changelog"), not a file type | **No natural path scope** — universal |
| `CODE-STYLE-RULES.md` | 8,500 | Line length (Rubocop 150-col), Ruby blocks, variable naming (Ruby, TS, JS, SQL, bash, HCL) | Multiple: `**/*.rb`, `**/*.ts`, `**/*.sql`, `**/*.sh`, `**/*.tf` | **Partial** — each section maps to a file type, but variable naming applies to all languages |
| `COMMAND-SAFETY.md` | 4,463 | Governs every Bash tool call by the agent regardless of file being edited | None — trigger is the agent running any shell command | **No natural path scope** — universal agent-behavior rule |
| `NO-HIDDEN-COMPLEXITY.md` | 7,281 | Ruby class/method design, TypeScript (examples are Ruby but principle is language-agnostic) | `**/*.rb` primarily; some TS relevance | **Partial** — Ruby-dominant but principle is universal |
| `NO-PREMATURE-DRY.md` | 5,576 | Ruby code examples, language-agnostic principle | `**/*.rb` primarily | **Partial** — same as above |

**Summary:** Of 6 Tier 1 docs, 0 have a clean universal path scope, 2 are genuinely universal with no path anchor (`CHANGELOG.md`, `COMMAND-SAFETY.md`), and 4 have partial path anchors that would require multiple rules files or compromise coverage.

---

### E4 — CLAUDE.md inline rules: path-scoped vs. universal

Sections of `~/.claude/CLAUDE.md` classified by whether a `paths:` trigger is applicable:

| Section | Path-scope possible? | Assessment |
|---|---|---|
| Language Policy (Portuguese comms, English code) | None — applies to all files and all interactions | Universal |
| Bash Single-Line Policy | None — governs every Bash tool call | Universal |
| Git Safety / Git Push Safety | None — workflow rule, not file-type rule | Universal |
| Git Commit Policy | None — workflow rule | Universal |
| Git Tag & Version Policy | None — workflow rule | Universal |
| Changelog Policy | None — applies at any changelog edit | Universal (but `CHANGELOG.md` could be a path anchor) |
| Pull Request Policy | None — workflow rule | Universal |
| Production Access / AWS Policy | None — governs AWS CLI calls regardless of file | Universal |
| Security (no sensitive files) | None — applies to all git operations | Universal |
| Automated Dependency Updates | None — knowledge/behavior rule | Universal |
| Linting Policy | `**/*.rb`, `**/.eslintrc`, etc. | Partial — could be path-scoped |
| Variable Naming | `**/*.rb`, `**/*.ts`, `**/*.sh`, etc. | Partial — multi-language |
| No Hidden Complexity | `**/*.rb` primarily | Partial |
| Testing Policy | `**/*_spec.rb`, `**/*.test.ts` | Partial |
| Data Processing Pattern | `**/*.rb` primarily | Partial |
| Project Layout / Git Workflow | None — project-structure knowledge | Universal |
| Configuration Changes Policy | `~/.claude/**` | Could be path-scoped to config files |
| Communication Style | None — applies to every interaction | Universal |
| Research-First Policy | None — agent behavior rule | Universal |
| Questions Are Just Questions | None — agent behavior rule | Universal |
| Execution Policy / Scope Discipline | None — agent behavior rule | Universal |
| Lookup Resolution | None — agent behavior rule | Universal |
| Output Formatting and Delivery | None — applies to every output | Universal |
| Ruby Version Manager in Bash | `**/*.rb`, `Gemfile`, `.ruby-version` | Could be path-scoped |
| Terraform Policy | `**/*.tf`, `**/*.tfvars` | **Clean path scope** |
| Identity Stack | `identity/**/*.tf` | **Clean path scope** |

**Of ~25 identifiable rule groups in CLAUDE.md:** approximately 2 have clean path scopes (Terraform rules, Identity Stack), ~6 have partial path anchors, and ~17 are genuinely universal agent-behavior or workflow rules with no file-path trigger.

---

### E5 — Tier 2 doc classification

Tier 2 docs are currently pointer-only (one-line hint), read on demand. Under `.claude/rules/`, a path-scoped rule would accomplish the same laziness:

| Doc | Current Tier 2 trigger ("Read BEFORE…") | Path-scope equivalent |
|---|---|---|
| `AUTOMATED-DEPENDENCY-UPDATES.md` | "answering questions about dependency updates or Renovate behavior" | None — trigger is semantic (topic), not a file type |
| `AWS-MFA.md` | "guiding AWS MFA setup or troubleshooting elevation issues" | None — trigger is a workflow action |
| `FACTORYBOT-CONVENTIONS.md` | "writing or modifying FactoryBot factories" | `spec/factories/**/*.rb` — **clean path scope** |
| `LINTING.md` | "modifying linting configuration or resolving linter conflicts" | `.rubocop.yml`, `.eslintrc*` — **clean path scope** |
| `NO-SAFE-NAVIGATION.md` | "writing Ruby or TypeScript code" | `**/*.rb`, `**/*.ts`, `**/*.tsx` — **clean path scope** |
| `NO-UNLESS-CONVENTION.md` | "writing Ruby code" | `**/*.rb` — **clean path scope** |
| `OUTPUT-FORMATTING.md` | "producing output for unusual destination, or pasted content rendered wrong" | None — trigger is conversational context |
| `PULL-REQUEST-CONVENTIONS.md` | "creating any pull request" | None — trigger is a workflow action (running `gh pr create`) |
| `RAILS-CONVENTIONS-CONTEXT.md` | "writing Rails code" | `**/*.rb`, `app/**/*`, `config/**/*` — **clean path scope** |
| `RSPEC-CONVENTIONS.md` | "writing tests in a Ruby/RSpec codebase" | `spec/**/*.rb` — **clean path scope** |
| `TERRAFORM-CONVENTIONS.md` | "running any terraform command" | `**/*.tf`, `**/*.tfvars` — **clean path scope** |
| `TESTING-PHILOSOPHY.md` | "writing any test, in any language" | `spec/**/*`, `test/**/*`, `**/*.test.ts`, `**/*.spec.ts` — **clean path scope** |
| `1PASSWORD-WSL2-SETUP.md` | WSL2-conditional (only on WSL2 machines) | None — trigger is OS environment |

**Of 13 Tier 2 docs:** 8 have clean path scopes, 5 have semantic/workflow triggers with no file-path anchor.

---

### E6 — What the hook provides that `.claude/rules/` does not

The current hook (`read-context.sh`) does three things:

1. **Tier 1 inline**: Reads full file content into the session message. `.claude/rules/` with no `paths:` does the same thing (always-on).
2. **Tier 2 pointer with hint**: Emits a one-line `Read BEFORE <when>` directive. This is a human-readable nudge that explains *why* and *when* to read a file, with a semantic/verb trigger ("before creating a pull request", "before running any terraform command"). `.claude/rules/` has no equivalent — it only triggers on file paths, not on workflow actions or conversational context.
3. **Platform-conditional emission**: WSL2 detection suppresses the `1PASSWORD-WSL2-SETUP.md` pointer on non-WSL2 machines. `.claude/rules/` has no runtime-conditional mechanism; frontmatter is static.

The **Tier 2 pointer ergonomic** is the key gap. For 5 of 13 Tier 2 docs (AUTOMATED-DEPENDENCY-UPDATES, AWS-MFA, OUTPUT-FORMATTING, PULL-REQUEST-CONVENTIONS, and the conditional 1PASSWORD-WSL2-SETUP), the trigger is a workflow action or environmental condition, not a file path. These cannot be replicated with `paths:` frontmatter.

---

### E7 — Risk and migration cost assessment

**Files to create:** Converting all path-scopeable content to `.claude/rules/` would require:
- 2 files for clean path-scoped CLAUDE.md sections (Terraform, Identity Stack).
- 8 files for clean path-scoped Tier 2 docs.
- Multiple partial-scope rules for docs that straddle several file types (CODE-STYLE-RULES, ALPHABETICAL-ORDERING, etc.) — conservatively 6–10 additional files.
- Total: ~16–20 new files.

**Rollout risk:** The config is a git-tracked shared repo pulled by every engineer. A migration creates:
- A window where engineers on different `git pull` states have mixed configurations (some with hook, some with rules, some with both).
- The hook (`read-context.sh`) runs at SessionStart. If rules files also exist, both load — creating duplicate context for any doc that appears in both. Anthropic notes: "if two files give different guidance for the same behavior, Claude may pick one arbitrarily."
- Hybrid operation is possible (keep hook for semantic-trigger docs, add rules for path-scoped ones) but requires carefully auditing for overlap.

**Incremental vs. all-at-once:**
- Incremental is safe for *new* path-scoped rules files (no overlap with existing hook content).
- Removing hook-inlined content and replacing with always-on rules files requires coordinated removal to avoid duplication.
- The 5 semantic-trigger Tier 2 docs cannot migrate incrementally — they require either staying in the hook or a different mechanism.

**Interaction between `~/.claude/rules/` and per-project `.claude/rules/`:**
- User-level rules load first; project rules load after and have higher priority.
- No collision risk unless a project rule explicitly contradicts a user rule. The composition is additive, not overriding.

---

## Conclusions

### C1 — `.claude/rules/` mechanics are sound and user-level works as expected

The official docs confirm that `~/.claude/rules/` (user scope) works identically to project-level `.claude/rules/`, loads before project rules (lower priority), and composes additively. Path-scoped rules genuinely reduce context — they only enter the context window when Claude opens a matching file, not every session. Always-on rules (no `paths:`) behave exactly like inlining in CLAUDE.md. Symlinks work for sharing.

### C2 — The path-scope opportunity is real but covers only a minority of current content

**Of all current unconditional content (CLAUDE.md + 6 Tier 1 docs):**
- ~2 sections/docs have clean, unambiguous path scopes: Terraform/Identity Stack rules in CLAUDE.md, and `TERRAFORM-CONVENTIONS.md` (Tier 2).
- ~6–8 docs/sections have *partial* path scopes (Ruby-dominant rules that also apply to TypeScript, bash, SQL, etc.).
- ~17+ sections in CLAUDE.md and 2 Tier 1 docs (`CHANGELOG.md`, `COMMAND-SAFETY.md`) are genuinely universal — they govern agent behavior and workflow actions, not file types. These cannot be made conditional on a `paths:` trigger without losing coverage.

**Quantified:** Of the ~104,696 bytes loaded every session unconditionally, a rough upper bound of path-scopeable content is the 8 clean-path Tier 2 docs (currently Tier 2, already not loaded per session: 48,957 bytes) + Terraform/Identity sections of CLAUDE.md (~3–5k bytes). The 6 Tier 1 docs loaded by the hook (45,428 bytes) are mostly universal or multi-language — migrating them to always-on rules files would produce zero context savings.

### C3 — Always-on rules save nothing for universal content

A rule with no `paths:` loads every session with the same cost as inlining. For the 2 Tier 1 docs that are genuinely universal (`CHANGELOG.md` at 13,808 bytes, `COMMAND-SAFETY.md` at 4,463 bytes) and for the 17+ universal CLAUDE.md sections, moving to `.claude/rules/` files without `paths:` reduces zero context. It changes the file organization, not the runtime behavior.

### C4 — The hook's Tier 2 pointer model has no equivalent in `.claude/rules/`

For 5 of 13 Tier 2 docs, the trigger is a workflow action ("before creating a PR", "before running terraform"), a semantic topic ("answering questions about Renovate"), or an environmental condition (WSL2 detection). None of these can be expressed as a `paths:` glob. The hook's one-line `Read BEFORE <when>` hint is a simple but uniquely effective pattern for this class of contextual rule. There is no equivalent in `.claude/rules/`.

### C5 — Risks are manageable but non-trivial

The dual-loading risk (hook + rules files for the same doc) during rollout is the main hazard. It is solvable with careful sequencing (add rules files first, remove from hook separately), but requires team coordination across an `n`-engineer shared config. The migration would involve creating 16–20 new files and editing or removing content from `CLAUDE.md` and `read-context.sh`.

---

## Next Steps

### Recommendation: Option (b) — Hybrid approach

**Keep the hook for semantic-trigger and universal rules. Add `.claude/rules/` for path-scoped rules only.**

Rationale:

1. The 8 clean-path Tier 2 docs (FACTORYBOT, LINTING, NO-SAFE-NAVIGATION, NO-UNLESS-CONVENTION, RAILS-CONVENTIONS, RSPEC, TERRAFORM-CONVENTIONS, TESTING-PHILOSOPHY) are currently *already not loaded every session* — they are Tier 2 pointers. Moving them to path-scoped `.claude/rules/` replaces the one-line pointer hint with automatic loading when matching files are opened. This is a genuine ergonomic improvement: no manual "read this file" step.

2. The 2 CLAUDE.md sections with clean path scopes (Terraform policy, Identity Stack) can be extracted to `~/.claude/rules/terraform.md` and `~/.claude/rules/identity.md` — reducing CLAUDE.md by ~3–5k bytes with zero coverage loss.

3. The Tier 1 docs and the universal CLAUDE.md sections should remain as-is. Moving them to always-on rules files would change file organization without reducing context. The current hook delivers them reliably and with the Tier 2 pointer ergonomic for contextual docs.

4. The 5 semantic-trigger Tier 2 docs (AUTOMATED-DEPENDENCY-UPDATES, AWS-MFA, OUTPUT-FORMATTING, PULL-REQUEST-CONVENTIONS, 1PASSWORD-WSL2-SETUP) must remain in the hook — there is no `paths:` equivalent for their triggers.

**Expected outcome of the hybrid approach:**
- CLAUDE.md shrinks slightly (~3–5k bytes) by externalizing Terraform/Identity sections.
- 8 Tier 2 docs migrate from pointer-hint to automatic path-triggered loading — a usability improvement.
- The hook is slimmed by 8 pointer entries (the 8 clean-path Tier 2 docs).
- Total unconditional session context stays the same (universal rules cannot be made conditional).
- No regression risk for the 5 semantic-trigger docs.

**If the engineer wants to pursue this:** the next step is a PLAN.md scoping the file creation, the CLAUDE.md edits, and the hook cleanup. The migration can be incremental — rules files can be added before the hook is edited, eliminating the rollout window where both fire for the same doc.

**If the engineer prefers status quo (Option c):** the current model already achieves most of what `.claude/rules/` offers for the universal content. The warning is cosmetic. The main concrete improvement on the table is the 8 clean-path Tier 2 docs, which is a quality-of-life change, not a correctness fix.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
