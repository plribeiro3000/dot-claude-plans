# PLAN — Terraform PreToolUse Context Hook

> Reference: SPIKE.md (`~/.claude/plans/active/spike/pretooluse-command-triggers/SPIKE.md`), ADR-001 (`~/Projects/4Shark/dot-claude/docs/adr/ADR-001-rules-loading-mechanism.md`)

## Objective

Add a `PreToolUse` hook to the dot-claude repository that injects Terraform Policy, Identity Stack, and Terraform Conventions content into Claude's context every time the agent is about to run a `terraform` command. This converts the existing implicit SessionStart Tier 2 pointer into an explicit, guaranteed injection at command-execution time.

This plan also extracts the inline "Terraform Policy" and "Identity Stack and Engineer Permissions" sections from `CLAUDE.md` into dedicated files in `docs/` so that the new hook reads from a single source of truth, not from heredoc duplicates of `CLAUDE.md` content.

## Scope

### In Scope

- Extract `### Terraform Policy` from `CLAUDE.md` into a new file `docs/TERRAFORM-POLICY.md`
- Extract `### Identity Stack and Engineer Permissions` from `CLAUDE.md` into a new file `docs/IDENTITY-STACK.md`
- Replace those two sections in `CLAUDE.md` with one-line references pointing to the new files
- Update `CLAUDE.md` Repository Structure tree to list the new doc files
- New script `scripts/inject-terraform-context.sh` that reads the three rule files and emits the `additionalContext` JSON
- New `PreToolUse` hook entry in `settings.json` with `"if": "Bash(terraform *)"` matcher
- Update `scripts/read-context.sh` to annotate the existing Terraform pointer (pointer is kept — hybrid strategy)
- Update `CLAUDE.md` § "Documentation Loading Model" to describe the new mechanism
- `CHANGELOG.md` entries under `[Unreleased] / Added`

### Out of Scope

- Does NOT generalize to other commands (`kubectl`, `aws`, `ansible`, etc.)
- Does NOT remove the SessionStart Tier 2 pointer (hybrid by design)
- Does NOT modify the content of `TERRAFORM-CONVENTIONS.md`, the extracted Terraform Policy, or the extracted Identity Stack — extraction is verbatim
- Does NOT migrate any doc to `~/.claude/rules/` (ADR-001 decision stands)
- Does NOT add a new ADR — the approach is a tactical addition within the existing ADR-001 framework (Alternative 3 in ADR-001 is now being implemented as a complement, not a replacement)

---

## Execution Phases

### Phase 1: Extract Terraform Sections from CLAUDE.md

**Objective**: Move the inline `### Terraform Policy` and `### Identity Stack and Engineer Permissions` sections out of `CLAUDE.md` into dedicated files in `docs/`. Replace each section in `CLAUDE.md` with a one-line reference. This establishes the single source of truth that the injection script reads.

**Files to create:**

| Path (relative to `~/Projects/4Shark/dot-claude/`) | Status | Purpose | Approx. size |
|---|---|---|---|
| `docs/TERRAFORM-POLICY.md` | New file | Terraform Policy bullets — extracted verbatim from `CLAUDE.md` § "Terraform Policy" | ~1,000 chars |
| `docs/IDENTITY-STACK.md` | New file | Identity Stack rules — extracted verbatim from `CLAUDE.md` § "Identity Stack and Engineer Permissions" | ~1,710 chars |

**Files to modify:**

| Path | Change |
|---|---|
| `CLAUDE.md` § "Terraform Policy" | Replace bullet list with one-line reference: `> See: ~/.claude/docs/TERRAFORM-POLICY.md — also auto-injected by PreToolUse hook on every terraform command.` |
| `CLAUDE.md` § "Identity Stack and Engineer Permissions" | Replace bullet list with one-line reference: `> See: ~/.claude/docs/IDENTITY-STACK.md — also auto-injected by PreToolUse hook on every terraform command.` |
| `CLAUDE.md` § "Repository Structure" docs/ tree | Add `TERRAFORM-POLICY.md` and `IDENTITY-STACK.md` entries in alphabetical order |

**Extraction notes:**

- Copy the bullets verbatim — same wording, same Markdown formatting. Do not rephrase.
- The new files have no frontmatter (consistent with other files in `docs/`).
- The new files start with a top-level heading matching the original section heading: `# Terraform Policy` and `# Identity Stack and Engineer Permissions`.
- The "See: `~/.claude/docs/TERRAFORM-CONVENTIONS.md` ..." line in the original Terraform Policy section is preserved in the new `TERRAFORM-POLICY.md` because it's still a valid pointer to the deeper canonical reference.

**Why extract instead of inline heredocs**: The original draft of this plan embedded Terraform Policy and Identity Stack as heredocs in the injection script. The team rejected that approach as "hidden complexity" — duplicating content between `CLAUDE.md` and a shell script creates a drift risk: when one is updated, the other can be missed. Extracting both sections to dedicated files ensures the script reads the same canonical content the engineer reads via `CLAUDE.md` references. CLAUDE.md gets ~2.7k chars lighter as a side effect.

**Dependencies**: None.

**Success Criteria:**

- [ ] `docs/TERRAFORM-POLICY.md` exists, content matches the original `CLAUDE.md` § "Terraform Policy" bullets verbatim
- [ ] `docs/IDENTITY-STACK.md` exists, content matches the original `CLAUDE.md` § "Identity Stack and Engineer Permissions" bullets verbatim
- [ ] `CLAUDE.md` § "Terraform Policy" body replaced with a single-line reference to the new file
- [ ] `CLAUDE.md` § "Identity Stack and Engineer Permissions" body replaced with a single-line reference to the new file
- [ ] `CLAUDE.md` § "Repository Structure" docs/ tree lists both new files in alphabetical order
- [ ] `CLAUDE.md` is still valid Markdown

---

### Phase 2: Create the Injection Script

**Objective**: Create `scripts/inject-terraform-context.sh` that reads the three Terraform rule files and emits valid `hookSpecificOutput` JSON with the concatenated content as `additionalContext`.

**File to create:**

| Path (relative to `~/Projects/4Shark/dot-claude/`) | Status | Purpose | Approx. size |
|---|---|---|---|
| `scripts/inject-terraform-context.sh` | New file | Reads three rule files, emits `additionalContext` JSON | ~50 lines / ~1.2 KB |

**Exact script behavior:**

**Inputs**: The script receives the `PreToolUse` JSON payload on stdin from Claude Code. The payload shape (per https://code.claude.com/docs/en/hooks) is:

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "terraform plan ..." },
  "session_id": "...",
  "transcript_path": "..."
}
```

The script does not need to parse this payload — no conditional logic depends on the exact subcommand. The `if` matcher in `settings.json` already guarantees the script only runs for `terraform *` commands. The stdin payload is consumed but not used.

**Files read** (in order, all relative to `$HOME/.claude/docs/`):

1. `TERRAFORM-POLICY.md` (~1,000 chars) — the policy bullets extracted from `CLAUDE.md` in Phase 1
2. `IDENTITY-STACK.md` (~1,710 chars) — the identity stack rules extracted from `CLAUDE.md` in Phase 1
3. `TERRAFORM-CONVENTIONS.md` (~7,374 chars) — the canonical workflow reference

The script concatenates them with a separator header line between each section.

**Output format**: JSON to stdout, matching the documented `hookSpecificOutput` shape:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "=== TERRAFORM RULES (injected by PreToolUse hook) ===\n\n<TERRAFORM-POLICY.md content>\n\n---\n\n<IDENTITY-STACK.md content>\n\n---\n\n<TERRAFORM-CONVENTIONS.md content>"
  }
}
```

`permissionDecision: "allow"` means the hook does not block the terraform command — it only annotates the context. Source: https://code.claude.com/docs/en/hooks (E2 in SPIKE.md).

**Error handling**:

- If any of the three files is not found: log the missing-file path to stderr, continue with whatever files are present, emit allow JSON, exit 0. The terraform command MUST NOT be blocked due to a hook error.
- If `jq` is not available: fall back to `printf` to construct the JSON manually. The payload has only string content; `printf` with proper JSON escaping (newlines → `\n`, double quotes → `\"`, backslashes → `\\`) is sufficient.
- The script always exits 0. Exit 2 would block the terraform command — this is a context-injection hook, not a validation hook.

**Payload size calculation:**

| Component | Characters |
|---|---|
| `TERRAFORM-POLICY.md` content | ~1,000 |
| `IDENTITY-STACK.md` content | ~1,710 |
| `TERRAFORM-CONVENTIONS.md` content | 7,374 |
| Header + separators | ~80 |
| **Total** | **~10,164** |

This is **slightly over** the 10,000-character inline limit documented in E2 of the SPIKE. Beyond 10,000 chars, Claude Code writes the content to a file and injects a preview — functional but less clean. Two paths to handle this:

**Option A**: Accept the 164-char overflow. Claude Code's file-preview fallback is documented and works. The engineer experience is the same.

**Option B**: Trim redundancy in the extracted files. Specifically: the `TERRAFORM-POLICY.md` ends with a "See: TERRAFORM-CONVENTIONS.md" line that becomes redundant when both files are concatenated in the same `additionalContext`. Removing that line saves ~280 chars and brings the total back under 10k. This is the recommended approach because it keeps the inline injection clean.

**Decision**: The script removes the trailing "See: TERRAFORM-CONVENTIONS.md" line from the policy content **at concatenation time** (not from the source file — the source file keeps the link for engineers reading it standalone). The script uses `grep -v` or equivalent to strip the line before concatenating.

**Adjusted total: ~9,884 chars** — fits inline.

**Dependencies**: Phase 1 must be complete (the script reads files that Phase 1 creates).

**Success Criteria:**

- [ ] Script exists at `scripts/inject-terraform-context.sh`
- [ ] Script is executable (`chmod +x`)
- [ ] Script exits 0 on success
- [ ] Script exits 0 even when one or more of the three files is missing (logs to stderr, emits allow JSON with whatever it could read)
- [ ] Script emits valid JSON with `hookSpecificOutput.hookEventName == "PreToolUse"` and `permissionDecision == "allow"`
- [ ] Total `additionalContext` string length is under 10,000 characters
- [ ] Script does not require `jq` (uses `printf` fallback)

---

### Phase 3: settings.json Hook Entry

**Objective**: Register the new script as a `PreToolUse` hook scoped to `Bash(terraform *)`.

**File modified:**

| Path | Status | Change | Approx. size |
|---|---|---|---|
| `settings.json` | Existing file | Add new entry to `hooks.PreToolUse` array | +10 lines |

**Exact JSON structure to add** (append a new object to the `"PreToolUse"` array, after the existing `validate-bash-command.sh` entry):

```json
{
  "hooks": [
    {
      "if": "Bash(terraform *)",
      "type": "command",
      "command": "$HOME/.claude/scripts/inject-terraform-context.sh",
      "timeout": 10
    }
  ]
}
```

**Structural notes:**

- The new entry does NOT use the outer `"matcher"` field — the `"if"` field inside the nested `"hooks"` array is the scoping mechanism (per E3 in SPIKE.md). The outer object wraps the inner hooks array; the `if` field lives on the inner hook object.
- The pattern of an outer object containing only a `"hooks"` array (no `"matcher"`) is valid — matches all tool types, then relies on `"if"` for command filtering.
- `"timeout": 10` — the script reads three files (~10 KB total) and emits JSON; 10 seconds is generous. The existing `validate-bash-command.sh` uses 5 seconds; 10 is used here because three sequential file reads add latency on slow disks.
- The existing `validate-bash-command.sh` hook is not modified. Both hooks execute independently for terraform commands (validate-bash fires because `"matcher": "Bash|..."` matches; inject-terraform fires because `"if": "Bash(terraform *)"` matches). There is no conflict.

**Verify matcher syntax**: The `"if": "Bash(terraform *)"` syntax is the same permission rule syntax used in `permissions.allow` at `settings.json:226-241` (e.g., `"Bash(terraform init:*)"`, `"Bash(terraform plan:*)"`). Per E3 in SPIKE.md, this syntax is stable since v2.1.85 (March 2026).

**Dependencies**: Phase 2 must be complete (script must exist before the hook entry references it).

**Success Criteria:**

- [ ] `settings.json` is valid JSON after the edit
- [ ] `"PreToolUse"` array contains the existing `validate-bash-command.sh` entry plus the new `inject-terraform-context.sh` entry
- [ ] The new entry has `"if": "Bash(terraform *)"` and `"timeout": 10`
- [ ] `$HOME/.claude/scripts/inject-terraform-context.sh` resolves correctly (the `$HOME` expansion matches the pattern of other hook entries in the file)

---

### Phase 4: SessionStart Pointer Update

**Objective**: Annotate the existing Terraform Tier 2 pointer in `scripts/read-context.sh` to acknowledge the new hook.

**File modified:**

| Path | Status | Change | Approx. size |
|---|---|---|---|
| `scripts/read-context.sh` | Existing file | Update pointer description text | ~3 chars net |

**Decision: keep the pointer.** The hybrid strategy retains the SessionStart pointer as a session-level reminder. The pointer fires at session start (before any terraform command), giving Claude early awareness that Terraform conventions exist. The PreToolUse hook is the enforcement layer — it fires unconditionally at command time. The two mechanisms complement each other:

- SessionStart pointer: fires once per session, cheap, reminds Claude that Terraform rules exist before the first command
- PreToolUse hook: fires on every terraform command, guarantees the content is in context at the moment of need

**Proposed change** to the existing `pointer "TERRAFORM-CONVENTIONS.md"` block in `scripts/read-context.sh`:

```bash
# Current:
pointer "TERRAFORM-CONVENTIONS.md" \
    "Terraform — apply-before-merge, init/plan/apply flags, plan capture pattern, plan review" \
    "running any terraform command"

# Updated:
pointer "TERRAFORM-CONVENTIONS.md" \
    "Terraform — apply-before-merge, init/plan/apply flags, plan capture pattern, plan review" \
    "running any terraform command (also auto-injected by PreToolUse hook on every terraform invocation)"
```

This is a cosmetic change — the pointer behavior is identical; the trigger description gains a parenthetical note informing Claude that the hook provides redundant coverage.

**Dependencies**: None. Can be done alongside Phase 1-3.

**Success Criteria:**

- [ ] Pointer for `TERRAFORM-CONVENTIONS.md` is still present in `scripts/read-context.sh`
- [ ] Trigger description updated to mention the auto-injection

---

### Phase 5: CLAUDE.md Documentation Loading Model Update

**Objective**: Update the "Documentation Loading Model" section in `CLAUDE.md` to describe the new PreToolUse mechanism alongside the existing two tiers.

**File modified:**

| Path | Status | Change | Approx. size |
|---|---|---|---|
| `CLAUDE.md` | Existing file | Update "Documentation Loading Model" section | ~8 lines added |

**Note**: This is a separate edit from the Phase 1 changes to CLAUDE.md (which replaced the Terraform Policy and Identity Stack section bodies). Phase 5 only touches the "Documentation Loading Model" section.

**Locate the section**: Search for `### Documentation Loading Model` in `CLAUDE.md`.

**Proposed addition** — append after the existing two-tier description, before the closing of the section:

```markdown
**Tier 2+ — PreToolUse active injection (command-execution triggers)**

A third loading path complements the Tier 2 pointer for rules whose real trigger is a Bash command invocation, not a file read:

- `Bash(terraform *)` — the `inject-terraform-context.sh` hook fires before every terraform invocation and injects `TERRAFORM-POLICY.md`, `IDENTITY-STACK.md`, and `TERRAFORM-CONVENTIONS.md` directly into Claude's context via `additionalContext`. This converts the Tier 2 pointer from an implicit hint into an explicit guarantee at the moment the command is about to run.

This mechanism is a 4Shark extension built on top of the Claude Code `PreToolUse` hook with `if` matcher (shipped v2.1.85, March 2026). It exists because `paths:` frontmatter in `~/.claude/rules/` only fires on file Read — not on Bash invocations. See ADR-001 for the full decision record.
```

**Dependencies**: Phase 1, 2, and 3 should be complete or at least decided before documenting the mechanism.

**Success Criteria:**

- [ ] "Documentation Loading Model" section describes the new PreToolUse active injection path
- [ ] The description references ADR-001
- [ ] The description names the specific hook script and the three injected files

---

### Phase 6: CHANGELOG Entry

**Objective**: Add changelog entries under `[Unreleased] / Added` and `[Unreleased] / Changed`.

**File modified:**

| Path | Status | Change |
|---|---|---|
| `CHANGELOG.md` | Existing file | Add one entry to `### Added` and one to `### Changed` |

**Entries to add:**

Under `## [Unreleased] / ### Added`:
```markdown
- Terraform context auto-injection via PreToolUse hook
```

Under `## [Unreleased] / ### Changed`:
```markdown
- Terraform Policy and Identity Stack sections extracted to dedicated docs files
```

Per CLAUDE.md Changelog Policy: simple subjects, no implementation details. The section titles ("Added", "Changed") provide the context; the entries name what was added/changed.

**Dependencies**: All other phases complete.

**Success Criteria:**

- [ ] One entry present under `## [Unreleased] / ### Added`
- [ ] One entry present under `## [Unreleased] / ### Changed`
- [ ] Both entries are one line each, no technical details

---

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Strategy | Hybrid (keep pointer + add hook) | Belt-and-suspenders: pointer fires once at session start as a reminder; hook guarantees injection at command time. Both are cheap. SPIKE recommendation C5. |
| Source of Terraform Policy and Identity Stack content | Extract to dedicated files in `docs/`; the script reads them | Single source of truth — no drift between `CLAUDE.md` and a shell script. The extracted files are discoverable, the script is simple, the engineer reads the same content via `~/.claude/docs/` that the agent receives via injection. |
| Trim redundant `See` line from policy at concatenation | Yes | The `TERRAFORM-POLICY.md` ends with "See `TERRAFORM-CONVENTIONS.md`" — when both are concatenated into the same `additionalContext`, the link is redundant and pushes the payload over 10k. Strip at concatenation time, keep in source for standalone readers. |
| Identity Stack inclusion | Always (not conditional on `-chdir=identity`) | Section is small; parsing stdin to filter is not worth the complexity. SPIKE Risk table confirms this. |
| Script error behavior | Exit 0 with error in `additionalContext` or stderr | Hook is for context injection, not validation. A failing hook must never block a terraform command. |
| Hook `timeout` | 10 seconds | Three file reads (~10 KB total) + JSON emit. Generous but not unbounded. Existing hooks use 5s for pure computation; sequential disk I/O warrants 2x. |
| `jq` dependency | Optional fallback to `printf` | `jq` is not guaranteed in all engineer environments. `printf` fallback ensures the script works everywhere. |
| Replace CLAUDE.md sections with one-line refs | Yes | Reduces CLAUDE.md by ~2.7k chars. Engineers follow the link when they need the detail; the hook injects the detail when terraform runs. |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Script error blocks terraform commands | High | Script always exits 0. Exit 2 is never used. Documented in script header. |
| Payload exceeds 10k chars after future edits to the three files | Medium | Current adjusted payload is ~9,884 chars (116 chars headroom). If the source files grow combined past ~9.9k, the next-largest section (Identity Stack) is the lowest-priority addition and would be truncated first. The PLAN documents this so future authors are aware. |
| `additionalContext` re-injected on every terraform call in a session | Low | Harmless. Claude Code deduplicates context by content in practice. SPIKE Risk table row 2. |
| Engineer runs terraform before `git pull`-ing the change | Low | Their session uses the old SessionStart pointer only (no regression — same behavior as today). Hook activates only after `~/.claude/` is updated. |
| `if` matcher syntax changes in a future Claude Code release | Low | Syntax is stable since v2.1.85 (March 2026). Same syntax already used in `permissions.allow`. If it breaks, the SessionStart pointer continues to work as a fallback. |
| Section content drift after extraction | Low | Mitigated by extraction itself — the only sources are now `docs/TERRAFORM-POLICY.md` and `docs/IDENTITY-STACK.md`. The CLAUDE.md references point at those files, so updates land in one place. |
| Engineer reads CLAUDE.md and misses the policy detail because it was extracted | Low | The replaced section keeps the heading and a one-line reference; the structure of CLAUDE.md is preserved. The `See:` reference is unambiguous. |

---

## Assumptions

- Engineers have `~/.claude/` updated from the dot-claude repo before starting a session (standard onboarding)
- All four content files (`TERRAFORM-POLICY.md`, `IDENTITY-STACK.md`, `TERRAFORM-CONVENTIONS.md`, plus the script) live under `$HOME/.claude/` — the script uses `$HOME`, not hardcoded paths
- The dot-claude repo target is `~/Projects/4Shark/dot-claude/` — all file paths in this plan are relative to that directory, and all deployments target `~/.claude/` via the engineer's `git pull`
- No changes are ever made directly to `~/.claude/` — all edits go through the dot-claude PR workflow (per CLAUDE.md "Configuration Changes Policy")

---

## Rollout Strategy

**Branch name**: `feature/terraform-pretooluse-hook`

**Commit strategy**: Single commit per CLAUDE.md policy. All files (2 new docs, 1 new script, 1 settings.json edit, 2 CLAUDE.md edits, 1 read-context.sh edit, 1 CHANGELOG edit) in one commit.

**Commit message format**:

```
feat(hooks): inject terraform rules via PreToolUse on command invocation
```

Type `feat`, scope `hooks` (the primary change is hook infrastructure), subject describes the what.

**Active session impact**: Engineers who `git pull` to `~/.claude/` while a session is open will not see the new hook until they restart their Claude Code session. Sessions started before the pull keep using the SessionStart pointer only — no regression. The PR description must include a note: "Restart your Claude Code session after pulling to activate the new hook."

**PR target**: `develop` (GitFlow feature branch from `develop`).

---

## Test Plan

### Step 1 — Verify extracted docs match originals

After Phase 1, confirm the new files are byte-equivalent to the original sections (modulo the heading change and surrounding context):

```bash
diff <(awk '/^### Terraform Policy$/,/^### Identity Stack/' ~/Projects/4Shark/dot-claude/CLAUDE.md.backup | head -n -1) <(tail -n +2 ~/Projects/4Shark/dot-claude/docs/TERRAFORM-POLICY.md)
```

(Substitute `CLAUDE.md.backup` with whatever pre-edit copy is available, or use `git show HEAD:CLAUDE.md` to compare against the committed version before the change.)

### Step 2 — Verify script output in isolation

Run the script directly from the shell, simulating the stdin payload Claude Code would send:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"terraform plan"},"session_id":"test","transcript_path":"/tmp/test"}' | bash ~/Projects/4Shark/dot-claude/scripts/inject-terraform-context.sh
```

Expected: valid JSON printed to stdout with `hookSpecificOutput.permissionDecision == "allow"` and `additionalContext` containing the concatenated rule text.

Validate JSON is well-formed:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"terraform plan"},"session_id":"test","transcript_path":"/tmp/test"}' | bash ~/Projects/4Shark/dot-claude/scripts/inject-terraform-context.sh | python3 -c "import sys, json; data = json.load(sys.stdin); print('OK — additionalContext length:', len(data['hookSpecificOutput']['additionalContext']))"
```

Expected output: `OK — additionalContext length: <number under 10000>`.

### Step 3 — Verify failure mode (missing file)

Temporarily rename one of the source files, run the script, verify it exits 0 and emits an allow JSON with the remaining content:

```bash
mv ~/.claude/docs/TERRAFORM-CONVENTIONS.md ~/.claude/docs/TERRAFORM-CONVENTIONS.md.bak ; echo '{}' | bash ~/Projects/4Shark/dot-claude/scripts/inject-terraform-context.sh ; echo "exit code: $?"
```

Expected: exit code 0, JSON with `permissionDecision: "allow"`, error logged to stderr.

Restore: `mv ~/.claude/docs/TERRAFORM-CONVENTIONS.md.bak ~/.claude/docs/TERRAFORM-CONVENTIONS.md`

### Step 4 — Verify settings.json is valid JSON after edit

```bash
python3 -m json.tool ~/Projects/4Shark/dot-claude/settings.json > /dev/null && echo "settings.json: valid JSON"
```

### Step 5 — Verify SessionStart hook still works

Start a new Claude Code session after pulling the change. Confirm the session-start output still includes the Terraform pointer (the `read-context.sh` output block should still list TERRAFORM-CONVENTIONS.md with the updated trigger description).

### Step 6 — End-to-end hook invocation test

In a Claude Code session (after pulling the change and restarting), ask Claude to run a simple read-only terraform command against the `terraform` repo:

```
Run: terraform version
```

Observe: the hook fires (Claude's context includes the Terraform rules injected by the hook). Verify by asking Claude immediately after: "what are the terraform conventions you just received?" — it should be able to cite the apply-before-merge workflow from the injected `additionalContext`.

---

**Status:** READY FOR TASK CREATION
