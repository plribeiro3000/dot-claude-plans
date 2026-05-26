# PLAN — Migrate Tier 2 path-scoped docs to `.claude/rules/`

> Reference: SPIKE.md (`~/.claude/plans/active/spike/claude-md-rules-migration/SPIKE.md`)

## Objective

Migrate seven Tier 2 docs with clean path scopes from the `read-context.sh` hook pointer model
to Anthropic's native `~/.claude/rules/` path-scoped loading. Extract two CLAUDE.md sections
(Terraform Policy, Identity Stack) into dedicated rules files. Slim the hook to semantic-trigger
and always-on docs only.

All edits target `~/Projects/4Shark/dot-claude/`. No direct edits to `~/.claude/`.

---

## Scope

### In Scope

- Create `~/.claude/rules/` directory layout in the working copy
- Migrate 7 Tier 2 docs to `rules/` with `paths:` frontmatter
- Extract 2 CLAUDE.md sections to `rules/` files
- Remove 7 pointer entries from `scripts/read-context.sh`
- Update "See: ~/.claude/docs/..." pointers in CLAUDE.md for migrated docs
- Update the "Documentation Loading Model" section in CLAUDE.md
- Update the `docs/` listing in the Repository Structure section of CLAUDE.md
- Update CHANGELOG.md under `## [Unreleased]`

### Out of Scope

- Reducing the 40 k warning (universal docs stay; the warning is cosmetic)
- Migrating Tier 1 docs (ALPHABETICAL-ORDERING, CHANGELOG, CODE-STYLE-RULES,
  COMMAND-SAFETY, NO-HIDDEN-COMPLEXITY, NO-PREMATURE-DRY) — they are universal or
  multi-language; moving them to always-on rules files saves zero context
- Migrating semantic-trigger Tier 2 docs (AUTOMATED-DEPENDENCY-UPDATES, AWS-MFA,
  OUTPUT-FORMATTING, PULL-REQUEST-CONVENTIONS, 1PASSWORD-WSL2-SETUP) — no `paths:`
  equivalent for their triggers
- Touching `agents/` or `commands/`
- Changing the hook's Tier 1 inline behavior
- Adding or removing permissions in `settings.json`

---

## Per-File Migration Table

All destination paths are relative to `~/Projects/4Shark/dot-claude/`.

### Docs that migrate to `rules/`

| # | Source (`docs/`) | Destination (`rules/`) | `paths:` frontmatter | Original `docs/` file | Hook edit | CLAUDE.md pointer edit |
|---|---|---|---|---|---|---|
| 1 | `FACTORYBOT-CONVENTIONS.md` | `rules/ruby/factorybot-conventions.md` | `spec/factories/**/*.rb` | Delete | Remove `pointer "FACTORYBOT-CONVENTIONS.md"` block (lines 73–75 of `read-context.sh`) | Remove "See: ~/.claude/docs/FACTORYBOT-CONVENTIONS.md" from Testing Policy section |
| 2 | `NO-SAFE-NAVIGATION.md` | `rules/ruby/no-safe-navigation.md` | `**/*.rb`, `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.jsx` | Delete | Remove `pointer "NO-SAFE-NAVIGATION.md"` block (lines 81–83) | No `See:` pointer in CLAUDE.md (rule inline; no pointer to remove) |
| 3 | `NO-UNLESS-CONVENTION.md` | `rules/ruby/no-unless-convention.md` | `**/*.rb` | Delete | Remove `pointer "NO-UNLESS-CONVENTION.md"` block (lines 85–87) | No `See:` pointer in CLAUDE.md |
| 4 | `RAILS-CONVENTIONS-CONTEXT.md` | `rules/ruby/rails-conventions-context.md` | `**/*.rb`, `app/**/*`, `config/**/*`, `db/**/*` | Delete | Remove `pointer "RAILS-CONVENTIONS-CONTEXT.md"` block (lines 99–101) | No `See:` pointer in CLAUDE.md |
| 5 | `RSPEC-CONVENTIONS.md` | `rules/ruby/rspec-conventions.md` | `spec/**/*.rb`, `**/*_spec.rb` | Delete | Remove `pointer "RSPEC-CONVENTIONS.md"` block (lines 103–105) | Remove "See: ~/.claude/docs/RSPEC-CONVENTIONS.md" from Testing Policy section |
| 6 | `TERRAFORM-CONVENTIONS.md` | `rules/terraform/terraform-conventions.md` | `**/*.tf`, `**/*.tfvars`, `**/*.tfvars.json` | Delete | Remove `pointer "TERRAFORM-CONVENTIONS.md"` block (lines 107–109) | Remove "See: ~/.claude/docs/TERRAFORM-CONVENTIONS.md" from Terraform Policy section |
| 7 | `TESTING-PHILOSOPHY.md` | `rules/testing/testing-philosophy.md` | `spec/**/*`, `test/**/*`, `**/*_spec.rb`, `**/*.test.ts`, `**/*.test.tsx`, `**/*.spec.ts`, `**/*.spec.tsx`, `**/*.test.js`, `**/*.spec.js` | Delete | Remove `pointer "TESTING-PHILOSOPHY.md"` block (lines 111–113) | Remove "See: ~/.claude/docs/TESTING-PHILOSOPHY.md" from Testing Policy section |

**Justifications for `paths:` globs:**

- `FACTORYBOT-CONVENTIONS.md` (SPIKE.md §E5): "writing or modifying FactoryBot factories" → factories live exclusively in `spec/factories/`. Glob: `spec/factories/**/*.rb`.
- `NO-SAFE-NAVIGATION.md` (SPIKE.md §E5): "writing Ruby or TypeScript code" → all `.rb`, `.ts`, `.tsx`, `.js`, `.jsx` files. The doc explicitly names Ruby's `&.` and TypeScript/JavaScript's `?.` (`NO-SAFE-NAVIGATION.md` lines 5–8).
- `NO-UNLESS-CONVENTION.md` (SPIKE.md §E5): "writing Ruby code" → `**/*.rb` only. The doc title and all examples are Ruby-only (`NO-UNLESS-CONVENTION.md` lines 1–3).
- `RAILS-CONVENTIONS-CONTEXT.md` (SPIKE.md §E5): "writing Rails code" → Rails source lives in `app/`, `config/`, `db/`, plus any `.rb` file in the project. Broad by design — Rails conventions apply anywhere in a Rails codebase.
- `RSPEC-CONVENTIONS.md` (SPIKE.md §E5): "writing tests in a Ruby/RSpec codebase" → spec files follow `spec/**/*.rb` and `**/*_spec.rb` conventions.
- `TERRAFORM-CONVENTIONS.md` (SPIKE.md §E5): "running any terraform command" → any `.tf` or `.tfvars` file opens during terraform work. Glob: `**/*.tf`, `**/*.tfvars`, `**/*.tfvars.json`.
- `TESTING-PHILOSOPHY.md` (SPIKE.md §E5): "writing any test, in any language" → test directories are `spec/`, `test/`, and language-specific test file suffixes. Multiple globs cover Ruby, TypeScript, and JavaScript test files.

### Docs that do NOT migrate (stay in hook as Tier 2 pointers)

| Doc | Reason |
|---|---|
| `AUTOMATED-DEPENDENCY-UPDATES.md` | Trigger is semantic ("answering questions about Renovate") — no `paths:` equivalent (SPIKE.md §E5, §C4) |
| `AWS-MFA.md` | Trigger is a workflow action ("guiding AWS MFA setup") — no `paths:` equivalent |
| `LINTING.md` | Trigger is "writing code" (including code written inside planning docs / markdown) — `paths:` would not fire on `.md` files. Engineer decision (2026-05-05): keep in hook because biggest violations happen during planning, not just implementation |
| `OUTPUT-FORMATTING.md` | Trigger is conversational context ("output rendered wrong") — no `paths:` equivalent |
| `PULL-REQUEST-CONVENTIONS.md` | Trigger is a workflow action ("creating any pull request") — no `paths:` equivalent |
| `1PASSWORD-WSL2-SETUP.md` | Trigger is OS environment (WSL2 detection) — no `paths:` equivalent; hook already handles this conditionally |

### Tier 1 docs that stay inlined in hook (no migration)

| Doc | Reason |
|---|---|
| `ALPHABETICAL-ORDERING.md` | Covers Ruby + TS but also bash/SQL/HCL — multi-language; splitting to multiple rules files adds complexity without guaranteed coverage (SPIKE.md §E3) |
| `CHANGELOG.md` | Trigger is a workflow action, not a file type (SPIKE.md §E3) |
| `CODE-STYLE-RULES.md` | Variable naming applies to all languages; splitting would need 5+ rules files (SPIKE.md §E3) |
| `COMMAND-SAFETY.md` | Governs every Bash tool call regardless of file type (SPIKE.md §E3) |
| `NO-HIDDEN-COMPLEXITY.md` | Ruby-dominant principle but applies to TS; keeping inline is simpler than multi-glob rules (SPIKE.md §E3) |
| `NO-PREMATURE-DRY.md` | Same as NO-HIDDEN-COMPLEXITY (SPIKE.md §E3) |

**Engineer decision on Tier 1 "Partial" docs:** Per SPIKE.md §C2, ALPHABETICAL-ORDERING, CODE-STYLE-RULES, NO-HIDDEN-COMPLEXITY, and NO-PREMATURE-DRY could technically be migrated with multi-language `paths:` arrays. The default is keeping them in the hook for simplicity. If the engineer wants to migrate them in a follow-up, the `paths:` would be `**/*.rb`, `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.sh`, `**/*.sql`, `**/*.tf`, `**/*.tfvars` — but this is broad enough to trigger on nearly every file, making path-scoping largely illusory. Deferring is the right call.

---

## CLAUDE.md Surgery — Two Clean-Scope Sections

### Terraform Policy (CLAUDE.md lines 316–324)

**Decision: Extract to `rules/terraform/terraform-policy.md`.**

Justification: "Terraform Policy" in CLAUDE.md has clean path scope (`**/*.tf`, `**/*.tfvars`) confirmed by the spike (SPIKE.md §E4). The section is 8 bullet points (~500 bytes). Extracting it:
- Reduces CLAUDE.md by ~500 bytes
- Collocates Terraform Policy with TERRAFORM-CONVENTIONS.md in `rules/terraform/`
- No coverage loss — path-scoped rules load whenever any `.tf` file is opened

The `rules/terraform/terraform-policy.md` file will carry the same `paths:` frontmatter as `terraform-conventions.md` (`**/*.tf`, `**/*.tfvars`, `**/*.tfvars.json`).

After extraction, the CLAUDE.md "Terraform Policy" section is replaced with a one-line reference:
```
> Terraform rules are in `~/.claude/rules/terraform/terraform-policy.md` and `~/.claude/rules/terraform/terraform-conventions.md` — loaded automatically when editing `.tf`/`.tfvars` files.
```

The "AWS Policy" section cross-reference to Terraform behavior (CLAUDE.md line 313) stays inline — it is a brief note inside a universal section, not a standalone section.

### Identity Stack and Engineer Permissions (CLAUDE.md lines 326–335)

**Decision: Extract to `rules/terraform/identity-stack.md`.**

Justification: "Identity Stack" in CLAUDE.md has the cleanest possible path scope (`identity/**/*.tf`) confirmed by the spike (SPIKE.md §E4). The section is 3 bullet groups (~700 bytes). Extracting it:
- Reduces CLAUDE.md by ~700 bytes
- The `identity/` stack is only relevant when editing files in `identity/` — strict path scope
- Collocates with other Terraform rules in `rules/terraform/`

The `rules/terraform/identity-stack.md` file will carry `paths: ['identity/**/*.tf', 'identity/**/*.tfvars']`.

After extraction, the CLAUDE.md "Identity Stack" section is replaced with a one-line reference:
```
> Identity stack rules are in `~/.claude/rules/terraform/identity-stack.md` — loaded automatically when editing files under `identity/`.
```

---

## Hook Changes — `scripts/read-context.sh`

All line numbers reference the current file at `~/.claude/scripts/read-context.sh`.

### Tier 2 pointer entries to remove (7 entries)

| Lines | Entry | Reason |
|---|---|---|
| 73–75 | `pointer "FACTORYBOT-CONVENTIONS.md" ...` | Migrated to `rules/ruby/factorybot-conventions.md` |
| 81–83 | `pointer "NO-SAFE-NAVIGATION.md" ...` | Migrated to `rules/ruby/no-safe-navigation.md` |
| 85–87 | `pointer "NO-UNLESS-CONVENTION.md" ...` | Migrated to `rules/ruby/no-unless-convention.md` |
| 99–101 | `pointer "RAILS-CONVENTIONS-CONTEXT.md" ...` | Migrated to `rules/ruby/rails-conventions-context.md` |
| 103–105 | `pointer "RSPEC-CONVENTIONS.md" ...` | Migrated to `rules/ruby/rspec-conventions.md` |
| 107–109 | `pointer "TERRAFORM-CONVENTIONS.md" ...` | Migrated to `rules/terraform/terraform-conventions.md` |
| 111–113 | `pointer "TESTING-PHILOSOPHY.md" ...` | Migrated to `rules/testing/testing-philosophy.md` |

### Tier 2 pointer entries that stay (6 entries)

| Lines | Entry | Reason |
|---|---|---|
| 64–66 | `pointer "AUTOMATED-DEPENDENCY-UPDATES.md" ...` | Semantic trigger — no `paths:` equivalent |
| 68–70 | `pointer "AWS-MFA.md" ...` | Workflow trigger — no `paths:` equivalent |
| 77–79 | `pointer "LINTING.md" ...` | "Writing code" trigger fires in markdown/planning files too — keep in hook |
| 89–91 | `pointer "OUTPUT-FORMATTING.md" ...` | Conversational trigger — no `paths:` equivalent |
| 93–95 | `pointer "PULL-REQUEST-CONVENTIONS.md" ...` | Workflow trigger — no `paths:` equivalent |
| 114–118 | `pointer "1PASSWORD-WSL2-SETUP.md" ...` (inside WSL2 conditional) | OS-conditional — no `paths:` equivalent |

### Tier 1 inline entries that stay (6 entries, lines 53–58)

All six `cat_doc` calls for ALPHABETICAL-ORDERING, CHANGELOG, CODE-STYLE-RULES,
COMMAND-SAFETY, NO-HIDDEN-COMPLEXITY, NO-PREMATURE-DRY remain unchanged.

### Nomenclature update

The hook's Tier 1/Tier 2/Tier 3 header comments (lines 1–17) remain accurate after migration —
the migrated docs are no longer in `docs/` so they are no longer Tier 3 candidates either.
Update the header comment at lines 8–9 to mention `.claude/rules/` as the fourth loading
mechanism: "Path-scoped docs now live in `~/.claude/rules/` and are loaded automatically
by Claude Code — they are not surfaced here."

Update the Tier 2 section header echo at line 61:
```bash
echo "=== TIER 2 — Contextual pointers (semantic/workflow/OS triggers only) ==="
```

---

## README / CLAUDE.md Documentation Update

### "Documentation Loading Model" section (CLAUDE.md lines 50–57)

Replace the current two-tier description with a three-mechanism model:

```markdown
### Documentation Loading Model

Additional rules live in two locations, loaded by different mechanisms:

**`~/.claude/rules/` (Anthropic native)** — Path-scoped rules, loaded automatically by
Claude Code when a matching file is opened. No hook needed. Subdirectories:
- `rules/ruby/` — Ruby, Rails, RSpec, FactoryBot conventions
- `rules/terraform/` — Terraform workflow and identity-stack rules
- `rules/testing/` — Testing philosophy (all languages)

**`~/.claude/docs/` (custom hook)** — Surfaced at session start by `scripts/read-context.sh`
in two tiers:
- **Tier 1** — full content inlined. Universal rules (alphabetical ordering, changelog format,
  code style, command safety, no-hidden-complexity, no-premature-dry)
- **Tier 2** — pointer only. Semantic/workflow/OS-conditional docs listed with a
  "Read BEFORE X" hint. The agent opens the file when the context applies
  (PR conventions, AWS MFA, Renovate behavior, 1Password WSL2)

Files in `~/.claude/docs/` not surfaced by the hook are Tier 3 — niche references,
discovered via filesystem when relevant. Classification lives in `scripts/read-context.sh`.
```

### Repository Structure section (CLAUDE.md lines 401–461)

Add `rules/` to the directory tree under `~/.claude/`:

```
├── rules/                    # Path-scoped rules (Anthropic native loading)
│   ├── ruby/                 # Ruby, Rails, RSpec, FactoryBot
│   ├── terraform/            # Terraform workflow and identity stack
│   └── testing/              # Testing philosophy (all languages)
```

Update the `docs/` listing to remove the 7 migrated docs and the 2 extracted CLAUDE.md sections:

Docs remaining in `docs/`:
- `1PASSWORD-WSL2-SETUP.md` — WSL2-conditional
- `ALPHABETICAL-ORDERING.md` — universal (Tier 1)
- `AUTOMATED-DEPENDENCY-UPDATES.md` — semantic trigger (Tier 2)
- `AWS-MFA.md` — workflow trigger (Tier 2)
- `CHANGELOG.md` — universal (Tier 1)
- `CODE-STYLE-RULES.md` — universal (Tier 1)
- `COMMAND-SAFETY.md` — universal (Tier 1)
- `LINTING.md` — "writing code" trigger (Tier 2)
- `NO-HIDDEN-COMPLEXITY.md` — universal (Tier 1)
- `NO-PREMATURE-DRY.md` — universal (Tier 1)
- `OUTPUT-FORMATTING.md` — conversational trigger (Tier 2)
- `PULL-REQUEST-CONVENTIONS.md` — workflow trigger (Tier 2)

Docs removed from `docs/` listing (moved to `rules/`):
- `FACTORYBOT-CONVENTIONS.md` → `rules/ruby/`
- `NO-SAFE-NAVIGATION.md` → `rules/ruby/`
- `NO-UNLESS-CONVENTION.md` → `rules/ruby/`
- `RAILS-CONVENTIONS-CONTEXT.md` → `rules/ruby/`
- `RSPEC-CONVENTIONS.md` → `rules/ruby/`
- `TERRAFORM-CONVENTIONS.md` → `rules/terraform/`
- `TESTING-PHILOSOPHY.md` → `rules/testing/`

### CLAUDE.md Testing Policy section

Three "See:" pointers reference docs moving to `rules/`:
- "See: `~/.claude/docs/RSPEC-CONVENTIONS.md`" → update to `~/.claude/rules/ruby/rspec-conventions.md`
- "See: `~/.claude/docs/FACTORYBOT-CONVENTIONS.md`" → update to `~/.claude/rules/ruby/factorybot-conventions.md`
- "See: `~/.claude/docs/TESTING-PHILOSOPHY.md`" → update to `~/.claude/rules/testing/testing-philosophy.md`

### CLAUDE.md Linting Policy section

No change — `LINTING.md` stays in `docs/`, existing pointer remains valid.

### CLAUDE.md Terraform Policy section

Replaced entirely by the extraction (see CLAUDE.md Surgery above).

---

## Rollout Strategy

### Sequencing — rules files BEFORE hook edits

**Add rules files first, then remove hook pointers in the same PR.**

Rationale: the 7 Tier 2 entries being removed are *pointers* (one-line hints), not inline content.
The pointer tells the agent "read this file when X". If both the pointer AND the rules file
exist simultaneously, the rules file loads automatically on path match AND the hook pointer
also fires — but the hook pointer only emits a hint ("Read BEFORE ..."), not the file content.
The double-load risk (SPIKE.md §E7) is: hint says "read the file" + rules file already loaded
the file = redundant nudge, not duplicate content injection. This is low-severity.

However, to eliminate even the redundant nudge, the cleanest approach is:

1. Create all `rules/` files in one commit.
2. Remove hook pointers and CLAUDE.md references in the same commit.
3. Both changes land in one PR (one commit per PR per CLAUDE.md policy).

This is one coordinated change, not a multi-PR rollout. The double-load window does not exist
because the pointer removal and the rules file creation are in the same merge.

### Branch strategy

One PR per the "ALWAYS one commit per pull request" policy (CLAUDE.md lines 64–65).

Branch: `feature/claude-md-rules-migration`

One commit on that branch covering:
- All 9 new `rules/` files (7 migrated docs + 2 extracted CLAUDE.md sections)
- Deletion of 7 `docs/` files
- Edit to `scripts/read-context.sh` (remove 7 pointer blocks, update header)
- Edit to `CLAUDE.md` (Documentation Loading Model, Repository Structure, Testing Policy, Terraform Policy section, Identity Stack section)
- Edit to `CHANGELOG.md`

### Compatibility — team members on other machines

Team members get the change via `git pull` into their `~/.claude/` working copy.

**PR description must warn:**

> After merging and pulling into `~/.claude/`, restart any active Claude Code sessions.
> The `rules/` directory is new — it is not created automatically by a session that started
> before the pull. Sessions started after the pull will load the new rules correctly.
> No manual migration step is needed beyond `git pull`.

The seven docs deleted from `docs/` are no longer referenced by the hook after this PR —
any session that pulled but has an open window with the old hook output (the pointer hint)
will find the file missing when attempting to `cat` it. This is a minor UX degradation
(the agent gets a "file not found" instead of the doc content) for the brief window between
a pull and a session restart. The PR description should note this.

Active-session risk mitigation: the migrated docs are Tier 2 pointers, not Tier 1 inlines.
They were never loaded into the session at start — the agent read them on demand. A session
that started before the pull and then opens a `.rb` file will get the rules file via the
new rules mechanism (since `rules/` is loaded from `~/.claude/rules/` at file-open time,
not from the session start message). The actual risk is only if the agent tries to manually
`cat` one of the deleted `docs/` files following a stale pointer — which is low probability
and low severity.

---

## Execution Phases

### Phase 1: Create `rules/` directory layout and migrate doc files

**Objective:** Create all 9 new `rules/` files with correct frontmatter and content.

**Files to create:**

```
~/Projects/4Shark/dot-claude/rules/ruby/factorybot-conventions.md
~/Projects/4Shark/dot-claude/rules/ruby/no-safe-navigation.md
~/Projects/4Shark/dot-claude/rules/ruby/no-unless-convention.md
~/Projects/4Shark/dot-claude/rules/ruby/rails-conventions-context.md
~/Projects/4Shark/dot-claude/rules/ruby/rspec-conventions.md
~/Projects/4Shark/dot-claude/rules/terraform/terraform-conventions.md
~/Projects/4Shark/dot-claude/rules/terraform/terraform-policy.md
~/Projects/4Shark/dot-claude/rules/terraform/identity-stack.md
~/Projects/4Shark/dot-claude/rules/testing/testing-philosophy.md
```

Each migrated doc file: copy content from `docs/<FILE>.md`, prepend YAML frontmatter with `paths:`.
Each extracted CLAUDE.md section: extract text from CLAUDE.md, create new file with frontmatter.

**Frontmatter for each file:**

```yaml
# rules/ruby/factorybot-conventions.md
---
paths:
  - "spec/factories/**/*.rb"
---

# rules/ruby/no-safe-navigation.md
---
paths:
  - "**/*.rb"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# rules/ruby/no-unless-convention.md
---
paths:
  - "**/*.rb"
---

# rules/ruby/rails-conventions-context.md
---
paths:
  - "**/*.rb"
  - "app/**/*"
  - "config/**/*"
  - "db/**/*"
---

# rules/ruby/rspec-conventions.md
---
paths:
  - "spec/**/*.rb"
  - "**/*_spec.rb"
---

# rules/terraform/terraform-conventions.md
---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.tfvars.json"
---

# rules/terraform/terraform-policy.md
---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.tfvars.json"
---

# rules/terraform/identity-stack.md
---
paths:
  - "identity/**/*.tf"
  - "identity/**/*.tfvars"
---

# rules/testing/testing-philosophy.md
---
paths:
  - "spec/**/*"
  - "test/**/*"
  - "**/*_spec.rb"
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.spec.ts"
  - "**/*.spec.tsx"
  - "**/*.test.js"
  - "**/*.spec.js"
---
```

**Dependencies:** None.

**Success Criteria:**
- [ ] `~/Projects/4Shark/dot-claude/rules/ruby/` contains 5 files
- [ ] `~/Projects/4Shark/dot-claude/rules/terraform/` contains 3 files
- [ ] `~/Projects/4Shark/dot-claude/rules/testing/` contains 1 file
- [ ] All 9 files have valid YAML frontmatter with `paths:` array
- [ ] Content of migrated docs matches current `docs/` files exactly (no edits to the doc content itself)
- [ ] Extracted CLAUDE.md sections match the text currently in CLAUDE.md lines 316–335

### Phase 2: Delete migrated docs from `docs/`

**Objective:** Remove the 7 files that have moved to `rules/`.

**Files to delete:**

```
~/Projects/4Shark/dot-claude/docs/FACTORYBOT-CONVENTIONS.md
~/Projects/4Shark/dot-claude/docs/NO-SAFE-NAVIGATION.md
~/Projects/4Shark/dot-claude/docs/NO-UNLESS-CONVENTION.md
~/Projects/4Shark/dot-claude/docs/RAILS-CONVENTIONS-CONTEXT.md
~/Projects/4Shark/dot-claude/docs/RSPEC-CONVENTIONS.md
~/Projects/4Shark/dot-claude/docs/TERRAFORM-CONVENTIONS.md
~/Projects/4Shark/dot-claude/docs/TESTING-PHILOSOPHY.md
```

**Dependencies:** Phase 1 complete (rules files exist before docs files are deleted).

**Success Criteria:**
- [ ] None of the 7 files listed above exist in `docs/`
- [ ] The remaining 12 docs files are present and unmodified

### Phase 3: Edit `scripts/read-context.sh`

**Objective:** Remove 7 pointer blocks and update section headers.

**Edits:**

1. Remove 7 `pointer "..."` blocks (lines 73–75, 81–83, 85–87, 99–101, 103–105, 107–109, 111–113)
2. Update Tier 2 section header (line 61) to read:
   `echo "=== TIER 2 — Contextual pointers (semantic/workflow/OS triggers only) ==="`
3. Update hook file header comment (lines 8–9) — append after the Tier 2/Tier 3 comments:
   `# Path-scoped docs live in ~/.claude/rules/ and load automatically — not listed here.`

**Dependencies:** Phase 1 complete (rules files exist before pointers are removed).

**Success Criteria:**
- [ ] `scripts/read-context.sh` no longer references any of the 7 migrated docs
- [ ] Remaining Tier 2 pointers (6 entries — including LINTING.md) are unchanged
- [ ] Tier 1 `cat_doc` blocks (6 entries) are unchanged
- [ ] Script still exits 0 when run
- [ ] Tier 2 header updated

### Phase 4: Edit `CLAUDE.md`

**Objective:** Update Documentation Loading Model, Repository Structure, Testing Policy,
Terraform Policy, Identity Stack sections.

**Edits (by section):**

1. **Documentation Loading Model** (lines 50–57): Replace with three-mechanism model
   (see README/CLAUDE.md Documentation Update section above).

2. **Repository Structure — docs/ listing** (lines 429–447): Remove 7 migrated doc entries.
   Add `rules/` directory tree entry before `scripts/`.

3. **Testing Policy section**: Update three "See:" pointers to `rules/` paths.

4. **Terraform Policy section** (lines 316–324): Replace section body with one-line reference
   (keep section heading `### Terraform Policy` for navigability; replace bullet points with
   the reference note described in CLAUDE.md Surgery above).

5. **Identity Stack section** (lines 326–335): Replace section body with one-line reference
   (keep section heading `### Identity Stack and Engineer Permissions`).

**Dependencies:** Phase 1 complete.

**Success Criteria:**
- [ ] Documentation Loading Model describes three mechanisms (rules/, Tier 1, Tier 2)
- [ ] Repository Structure shows `rules/` directory with subdirectories
- [ ] `docs/` listing in Repository Structure matches the 12 remaining docs files
- [ ] No "See: ~/.claude/docs/FACTORYBOT-CONVENTIONS.md" (or any other migrated doc) remains in CLAUDE.md
- [ ] "See: ~/.claude/docs/LINTING.md" pointer in Linting Policy section remains unchanged
- [ ] Terraform Policy and Identity Stack sections replaced with single-line references
- [ ] CLAUDE.md is still valid Markdown

### Phase 5: Update `CHANGELOG.md`

**Objective:** Add migration entry under `## [Unreleased]`.

**Entry:**

```markdown
### Changed
- Documentation loading model — path-scoped rules migrated to native `.claude/rules/`
```

**Dependencies:** None (can be done in parallel with any phase).

**Success Criteria:**
- [ ] `CHANGELOG.md` has the entry above under `## [Unreleased]`, `### Changed`
- [ ] No version section created (tag not yet made)

---

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Directory layout under `rules/` | `ruby/`, `terraform/`, `testing/` subdirectories | Anthropic docs confirm recursive discovery; grouping by technology makes the rules discoverable and maintainable |
| `paths:` glob specificity | Match the trigger language of the original Tier 2 hint | The hint ("write Ruby code", "write tests") directly maps to the file types the engineer edits when that doc is relevant |
| Terraform Policy extraction | Extract to `rules/terraform/terraform-policy.md` | Same `paths:` as `terraform-conventions.md`; collocation in `rules/terraform/` groups all Terraform rules; CLAUDE.md shrinks slightly |
| Identity Stack extraction | Extract to `rules/terraform/identity-stack.md` | `identity/**/*.tf` is the narrowest clean scope in the entire codebase; extraction eliminates dead weight in the global CLAUDE.md |
| Rollout: one PR, one commit | Single PR covering all 9 new files + 7 deletions + 3 file edits | Avoids double-load window; consistent with "one commit per PR" policy |
| Sequencing within commit | Create rules files first in Phase 1, delete docs files in Phase 2 | Makes the intent clear in the commit diff; git handles atomic application |
| Original `docs/` files | Delete (not stub, not keep) | Stubs would create a misleading file at the old path; the new canonical location is `rules/`; old path should 404 to force any stale reference to be found and fixed |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Stale pointer in an open session tries to `cat` a deleted docs file | Low — agent gets "file not found" for a Tier 2 pointer, not a crash | PR description warns to restart sessions after `git pull` |
| `paths:` glob too narrow (e.g., `spec/factories/**/*.rb` misses inline factory definitions) | Low — FactoryBot factories at 4Shark live exclusively in `spec/factories/` by convention | Confirmed in RSPEC-CONVENTIONS.md pattern; if a project deviates, engineer can open the file manually |
| Team member on non-HubFlow branch pulls mid-session | Low | Session restart resolves all loading state |
| CLAUDE.md "See:" pointer left pointing to deleted file | Medium — agent gets "file not found" | Phase 4 checklist covers all "See:" pointers to migrated docs |

---

## Assumptions

- `~/Projects/4Shark/dot-claude/` working copy is on the `develop` branch and is up to date with remote.
- Anthropic's `~/.claude/rules/` is already supported in the Claude Code version in use (confirmed by SPIKE.md §E1).
- The `rules/` directory does not exist yet in `dot-claude/` — it will be created by Phase 1.
- Content of `docs/` files has not changed since the spike was conducted (2026-05-05).
- Line numbers cited for `read-context.sh` and `CLAUDE.md` are from the versions read during planning. Verify before applying edits.

---

## CHANGELOG Entry

Under `## [Unreleased]`, `### Changed`:

```
- Documentation loading model — path-scoped rules migrated to native `.claude/rules/`
```

---

## Out of Scope

- The 40 k character warning is not eliminated by this migration. Universal Tier 1 docs remain
  inline; the warning is cosmetic and the spike explicitly noted it is a soft advisory.
- The hook Tier 1 inline behavior is unchanged.
- Semantic-trigger Tier 2 docs (AUTOMATED-DEPENDENCY-UPDATES, AWS-MFA, OUTPUT-FORMATTING,
  PULL-REQUEST-CONVENTIONS, 1PASSWORD-WSL2-SETUP) are not touched.
- `agents/`, `commands/`, `templates/`, `settings.json` are not modified.
- Per-project `.claude/CLAUDE.md` files in individual repos are not modified — this migration
  is entirely within the shared user-level config.
- No changes to `AUTOMATED-DEPENDENCY-UPDATES.md` doc content.

---

**Status:** READY FOR TASK CREATION
