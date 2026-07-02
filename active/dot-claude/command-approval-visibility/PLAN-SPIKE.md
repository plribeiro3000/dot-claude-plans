# PLAN-SPIKE — Command Approval Visibility (Mechanical Enforcement)

> Reference: `~/.claude/plans/active/spike/agent-command-approval-visibility/SPIKE.md` (source spike, 10 findings) + its auxiliary files (`approval_doc_1.txt`, `approval_doc_2.txt`, `approval_issue_3.txt`, `approval_selfreport_4.txt`, `approval_related_5.txt`). No DDD documents exist for this feature (standard workflow).

## Direction is locked — this document does not reopen it

The engineer already chose **Option E = A + B + C** from the source spike's option space:

- **A** — extend `~/.claude/scripts/validate-bash-command.sh` with a new PreToolUse `exit 2` block for the opaque env-var-prefix / `$(...)`-into-long-wrapper shape.
- **B** — add a `PermissionRequest` hook as a second layer for the same shape.
- **C** — correct `~/.claude/CLAUDE.md` § "Bash Single-Line Policy" so the self-print rule (`Executando o comando completo: <full command>`) is no longer framed as a control.

This document exists to surface **implementation-level** options *within* that locked direction — the carve-out heuristic, the A/B interaction, corrective wording, CLAUDE.md wording, and a test approach — so the engineer can pick concrete boundaries before `plan-composer` writes `PLAN.md`. It does not re-litigate A vs. B vs. C vs. D, and it introduces no new top-level option.

## Objective

Give the engineer a concrete, evidence-backed set of implementation choices for closing the "opaque command at approval time" gap the source spike documented: a `VAR=$(cmd) ... long-wrapper-path ...` shape (concretely, `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...`) reaches the human as a hard-to-review string. The fix is mechanical (block-and-redirect, the same production pattern `validate-bash-command.sh` already uses twice) plus a documentation correction so the CLAUDE.md self-print rule is not relied upon as if it were enforcement.

## Scope

### In scope

- Candidate detection heuristics for the new PreToolUse block (Option A), with false-positive/false-negative analysis against 4Shark's own sanctioned `VAR=value cmd` escape hatch (`CLAUDE.md:24-25,40`).
- The `PermissionRequest` hook's actual, evidence-based scope (Option B) — what it adds over A, given fresh research on subagent hook coverage and PreToolUse/PermissionRequest ordering.
- Draft corrective stderr wording for the new block.
- Two draft wording variants for the CLAUDE.md correction (Option C).
- A test approach for the new block and the new hook, grounded in how the three most similar prior blocks in the same file were actually validated.

### Out of scope (not re-opened)

- Whether A, B, C, D, or E is the right top-level direction — already decided.
- Sandboxing / Auto Mode classifier investment (the source spike's separate trade-off row) — out of scope for this implementation-level plan.
- Any change to `~/.claude/` itself. Per CLAUDE.md § "Configuration Changes Policy," the actual edits land in the `~/Projects/4Shark/dot-claude/` working copy via a feature branch and PR — this plan does not touch `~/.claude/scripts/` or `~/.claude/CLAUDE.md` directly.

## Existing patterns found

**Pattern 1: Infra-compound block** — `~/.claude/scripts/validate-bash-command.sh:159-200`

**What it does:** Blocks (`exit 2`) a compound shell command when an infrastructure token (`aws`/`terraform`/`kubectl`/`docker`/`ansible`/`gcloud`/`helm`) appears at a segment start after optional `VAR=` prefixes, following a compound operator (`&&`, `;`, `|`, or `$(`). Redirects the model to the atomic, auto-approvable form.

```bash
command_without_quotes="$(printf '%s' "$command" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
if printf '%s' "$command_without_quotes" | grep -qE '(&&|;|\||\$\()' && \
   printf '%s' "$command_without_quotes" | grep -qE '(^|[;&|`]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(aws|terraform|kubectl|docker|ansible|gcloud|helm)([[:space:]]|$)'; then
  cat >&2 <<'EOF'
Compound shell command containing an infrastructure command ... — blocked.
EOF
  exit 2
fi
```

Traced against a candidate false-positive (`TAG=$(date +%Y%m%d) docker build -t app:$TAG .`): the second regex requires the infra token to sit immediately at a segment-start anchor (`^`, or right after `;`/`&`/`|`/backtick/`$(`). In this example `docker` follows `) ` (the subshell's closing paren plus a space) — not one of the anchor characters — so the block does **not** currently fire for a single `VAR=$(...)` prefix feeding one non-chained command, infra or not. This is a real, currently-uncovered gap distinct from the compound/chained case this block targets — it is the gap Option A's new block would need to close.

---

**Pattern 2: Work-script-pipe block** — `~/.claude/scripts/validate-bash-command.sh:202-237`

**What it does:** Blocks a work script piped into a truncation sink (`tail`/`head`/`sed -n`) — the same file's second exit-2 example of "detect an opaque/unreviewable shape and hard-block it before the ambiguous prompt reaches the human."

```bash
if printf '%s' "$command" | grep -qE '(^|[;&|`]|\$\()[[:space:]]*(bash|sh)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*[^[:space:]|]*(\.claude/(scripts|skills)/|bin/)' && \
   printf '%s' "$command" | grep -qE '\|[[:space:]]*(tail|head|sed[[:space:]]+-n)([[:space:]]|$)'; then
  ...
  exit 2
fi
```

---

**Pattern 3: Ask-bypass normalization loop** — `~/.claude/scripts/validate-bash-command.sh:453-490`

**What it does:** Strips leading `VAR=value` assignments and a bare `env` wrapper (and an absolute binary path) from `$command` into `$normalized_command` *before* re-matching against the canonical write-op list (`terraform apply`, `aws ecs run-task`, `git tag`, etc.), so an env-var prefix cannot bypass an `ask` rule. This is the file's own existing solution to "an env-var prefix defeats a pattern match" — for the *opposite* direction (force a prompt) rather than the direction Option A needs (detect the opaque shape and block it before any prompt).

```bash
normalized_command="$command"
while :; do
  read -r normalize_first normalize_rest < <(printf '%s\n' "$normalized_command") || true
  case "$normalize_first" in
    [A-Za-z_]*=*|env)
      normalized_command="$normalize_rest"
      ;;
    *)
      break
      ;;
  esac
done
```

This loop is directly reusable groundwork for Option A: it already isolates "what does the command look like with every leading `VAR=`/`env` token removed" — the same information a wrapper-path carve-out (Candidate 3, below) needs.

---

**Pattern 4: `cd && cmd` block's corrective text sanctions `VAR=value cmd`** — `~/.claude/scripts/validate-bash-command.sh:130-138`, specifically line 135

**What it does:** The existing corrective stderr for the *unrelated* `cd && cmd` block recommends, verbatim: `"For one-off env vars: inline prefix — VAR=value cmd (sets the var only for this invocation; no export needed; not a chain)"`. This is the exact shape any new Option A block must NOT contradict for the short, legitimate case — `CLAUDE.md:24-25,40` repeats the same endorsement.

---

**Pattern 5: `ruby.sh`'s "absorb the substitution internally" fix** — `~/.claude/scripts/ruby.sh` (full file, 111 lines)

**What it does:** Runs Ruby/Bundler commands through a wrapper that reads `config/master.key` and resolves the version-manager wrapper *inside the script*, so the invocation the permission matcher sees is a single clean line (`bash ~/.claude/scripts/ruby.sh bundle exec rspec ...`) with no `$(...)` and no env-var prefix.

```bash
if [[ -f config/master.key ]]; then
  export RAILS_MASTER_KEY="$(< config/master.key)"
fi
...
if [[ -d "$HOME/.rvm" ]]; then
  ...
  WRAPPER_DIR="$HOME/.rvm/wrappers/${RUBY_NAME}@${GEMSET_NAME:-default}"
  ...
  exec "$WRAPPER_DIR/$TOOL" "$@"
fi
```

This is the target remediation for Option A's corrective message when the opaque shape matches the Ruby/Bundler case specifically.

---

**Pattern 6: `inject-working-dir-reminder.sh`'s existing wrapper-path detection regex (advisory, not blocking)** — `~/.claude/scripts/inject-working-dir-reminder.sh:61`

**What it does:** Already detects the exact "long version-manager wrapper path" shape as a trigger for an *advisory* (non-blocking) reminder — `additionalContext` only, never `permissionDecision`.

```bash
escape_hatch_pattern='(BUNDLE_GEMFILE=|(^|[[:space:]])ruby[[:space:]]+-C[[:space:]]|/\.rvm/wrappers/|/\.rbenv/shims/|/\.asdf/shims/)'
if ! printf '%s' "$command" | grep -qE "$escape_hatch_pattern"; then
    emit_empty
fi
```

This is a directly reusable detection regex for Candidate 3 (below) — it is already battle-tested in production for the identical path-matching problem, just at the advisory tier rather than the blocking tier. **Coordination note (not a new option):** if Option A adds a hard block for the same shape this hook already flags advisory-only, the two hooks' messages should agree on the remediation (both point at `ruby.sh` when the shape is Ruby-specific) — otherwise the model receives two different pieces of guidance for the same command in the same PreToolUse pass (`validate-bash-command.sh` and `inject-working-dir-reminder.sh` are both wired to `matcher: "Bash"` in `settings.json`).

---

## Implementation options within the locked direction

### 1. Carve-out heuristic candidates for Option A

The crux: the new block must fire on the opaque shape (`RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/.../bundle exec ...`) but NOT on the short, legitimate `VAR=value cmd` escape hatch `CLAUDE.md:40` itself sanctions (`AWS_PROFILE=prod aws ...`, `BUNDLE_GEMFILE=<abs-path> <short-tool>`). Four candidates, as named in the brief, each with false-positive/false-negative analysis and interaction with `ruby.sh`:

**Candidate 1 — trigger on `$(...)` inside an env-var VALUE**

Detection sketch: an env-var assignment token (`VAR=`) whose value contains `$(` before the next whitespace boundary, at a segment start (reusing the anchor family from Pattern 1: `^`, or after `;`/`&`/`|`/backtick/`$(`).

- **Catches:** the exact spike-cited case (`RAILS_MASTER_KEY=$(cat config/master.key) ...`).
- **False positives:** a short, legible `VAR=$(cmd) short-tool ...` with no long wrapper — e.g. `TAG=$(date +%Y%m%d) docker build -t app:$TAG .`. Traced above (Pattern 1) as currently NOT blocked by the existing infra-compound check, so this would be new friction for a case that is not actually hard to read. Per `~/.claude/docs/RUBY-COMMAND-EXECUTION.md:25-28`, `$(...)` already forces a manual approval prompt today regardless of any allow-list rule (an independent Claude Code security layer, cited to `anthropics/claude-code#31373`) — so this candidate does not create a NEW prompt where none existed; it converts an already-mandatory prompt into a block-and-restructure cycle. Whether that trade (extra tool-call round-trip for a command that was already legible) is worth it for the short case is a judgment call for the engineer.
- **False negatives:** none for the documented case. Would also catch other `$(...)`-in-`VAR=` shapes unrelated to wrapper opacity — which some would call over-triggering rather than a miss.
- **Interaction with `ruby.sh`:** direct hit for the documented case; for a non-wrapper `$(...)` case, no existing 4Shark script absorbs the substitution, so the corrective message needs a generic fallback (see Corrective Message Draft 2, below) — and that fallback is itself awkward, because `COMMAND-SAFETY.md` already documents that shell variables do NOT persist across tool calls, so "split into two calls" requires writing an intermediate value to a file, not a simple two-step split.

**Candidate 2 — trigger on stacked `VAR=` assignments (a `VAR=` immediately followed by a second `VAR=`)**

Detection sketch: two or more consecutive `VAR=value` tokens before the actual command begins.

- **Catches:** the two-var spike example (`RAILS_MASTER_KEY=... BUNDLE_GEMFILE=...`).
- **False positives:** a fully legible, two-var, no-`$(...)`, no-long-wrapper case — e.g. `NODE_ENV=test DEBUG=true npm test`. This triggers purely on the *count* of assignments, with no relationship to the opacity mechanism (secret substitution, long wrapper path) the spike actually identified as the problem. Of the four candidates, this is the one most likely to catch a pattern with no comprehension problem at all.
- **False negatives:** a *single*-var version of the documented case (`RAILS_MASTER_KEY=$(cat config/master.key) ~/.rvm/wrappers/.../bundle exec ...` — no `BUNDLE_GEMFILE=` present) is equally opaque but would NOT be caught by a "stacked assignments" rule, since there is only one `VAR=` token.
- **Interaction with `ruby.sh`:** weak — the trigger condition (count of vars) does not correlate with "this is the Ruby wrapper shape," so the corrective message cannot safely assume `ruby.sh` is the fix without also checking for a wrapper path (i.e., Candidate 2 alone is under-specified; it would likely need to be combined with Candidate 3 to know what to recommend).

**Candidate 3 — trigger on a long-wrapper path after `VAR=`/`env` stripping**

Detection sketch: reuse the existing normalization loop (Pattern 3, `validate-bash-command.sh:453-490`) to strip leading `VAR=`/`env` tokens, then match the *normalized* command against the same regex family already in production in `inject-working-dir-reminder.sh:61` (Pattern 6): `/\.rvm/wrappers/|/\.rbenv/shims/|/\.asdf/shims/`.

- **Catches:** precisely the Ruby/Bundler/RVM/rbenv/asdf wrapper case — the one concretely documented in `RUBY-COMMAND-EXECUTION.md` and the one 4Shark has actually hit in production.
- **False positives:** none from the sanctioned `AWS_PROFILE=prod aws ...` / `BUNDLE_GEMFILE=<abs> <short-tool>` shapes (they do not resolve to a `.rvm/wrappers/`-style path). One residual case to decide explicitly: should the match additionally *require* a `VAR=` prefix to be present (so a bare `~/.rvm/wrappers/ruby-3.2/gem list` with no prefix at all — not opaque, nothing hidden — is not swept in)? Scoping the match to "`VAR=` present AND wrapper-path match" (a compound condition, not either alone) avoids that false positive; scoping it to "wrapper-path match alone" would not.
- **False negatives:** does not generalize — a *future*, non-Ruby "opaque long wrapper" shape 4Shark has not hit yet (the spike's own framing is broader: "opaque env-var prefix / `$()`-into-long-wrapper shape," not Ruby-specific) would not be caught. This candidate is the narrowest, most precisely-targeted of the four, scoped to exactly one documented incident class.
- **Interaction with `ruby.sh`:** 1:1 — a match under this candidate IS the `ruby.sh` precondition shape, so the corrective message can point there unconditionally (Corrective Message Draft 1, below).

**Candidate 4 — trigger on total command length exceeding a threshold AND a `VAR=` prefix present**

Detection sketch: e.g. `${#command} -gt <N>` (some length threshold) combined with the command starting with a `VAR=` assignment.

- **Catches:** broadly, any long command with any var prefix, including the target shape.
- **False positives:** the widest surface of the four — any legitimately long single command with a short var prefix (long AWS resource names, long file paths, long `--query` JMESPath expressions already exempted elsewhere by quote-stripping) trips this purely on length, independent of whether the command is actually hard to read. Threshold-picking is itself arbitrary and unmaintainable — the source spike's Finding 2 explicitly found **no evidence** that the approval dialog's rendering truncates or hides content by column width or length (a genuine research gap, not a confirmed non-issue), so a length threshold is not grounded in a documented rendering constraint, only in an assumption about it.
- **False negatives:** a short opaque command (theoretically possible via a short alias hiding a substitution) would not be caught — low practical likelihood given wrapper paths are inherently long, but not zero.
- **Interaction with `ruby.sh`:** no direct correlation; would need the same wrapper-path check as Candidate 3 layered on top to know what to recommend.

**Combination / precedence — not chosen here**

The four candidates are not mutually exclusive. Two combination shapes surfaced by this research, presented as options rather than a recommendation:

- **1 OR 3, with 3 taking corrective-message precedence when both match** (route to `ruby.sh` whenever the wrapper-path shape is present; fall back to the generic "$(...) in a VAR=" message otherwise). This pairs the narrowest, best-evidenced candidate (3) with the broadest one that still ties directly to the documented mechanism (1).
- **3 alone** — narrowest possible scope, zero false positives found against the sanctioned escape hatch, but does not extend to any future non-Ruby opaque-wrapper case.
- Candidate 2 is not evidenced as improving either combination — its trigger condition (assignment count) does not track the opacity mechanism, and it is both broader (catches `NODE_ENV=test DEBUG=true npm test`) and narrower (misses the single-var version of the documented case) than Candidate 1 or 3 alone.
- Candidate 4 is a different axis (length, not shape) and was not found to compose cleanly with 1/2/3 — it would need its own separate false-positive analysis if the engineer wants it as an independent, additional gate rather than a refinement of the shape-based candidates.

---

### 2. Option B — `PermissionRequest` hook scope, given fresh research

Two sub-questions from the brief, answered with fresh 2026-07-01 evidence (see auxiliary `subagent_hook_scope_1.txt` for the full verbatim quotes and sourcing):

**Does `PermissionRequest` fire for subagent (Task tool) Bash calls?**

The source SPIKE.md's "What remains uncertain" section left this open, and its lineage traces through a sibling spike (`agent-pipe-chaining/SPIKE.md:89`) that attributes a "PreToolUse exit 2 ignored for subagents" claim to `llm-agent-command-chaining/SPIKE.md` Finding 5. On direct re-read of that file in full for this plan, **the current file's Finding 5 is titled "The efficiency-reviewability tradeoff is explicit in published sources" and contains no mention of subagents or the Task tool** — a full-text search across the file and its five auxiliary excerpts returns zero matches. This internal citation discrepancy is documented plainly in the auxiliary file; it is not resolved here (the sibling file may have been edited after being cited, or the citation may not have held at the time it was written), and this plan does not rely on it.

Independently, fresh external research (WebFetch, 2026-07-01) found two on-point, verified GitHub issues:

- **`#23983`** ("PermissionRequest hooks not triggered for subagent permission requests in Agent Teams"): *"Main session permission requests -> Hook fires correctly. Subagent permission requests -> Hook is bypassed, terminal prompt shown."* Scope caveat: the title names "Agent Teams" (a multi-agent `TeamCreate` feature) specifically; the fetched text does not explicitly distinguish that from a plain single-subagent `Task` tool spawn (4Shark's shape).
- **`#34692`** ("PreToolUse/PostToolUse hooks do not fire for subagent (Agent tool) tool calls", closed `not_planned`): *"any Bash, Edit, Write, Read, or Grep tool calls made by the subagent do not trigger PreToolUse or PostToolUse hooks configured in ~/.claude/settings.json. Only tool calls made directly by the main session thread fire the hooks."*

Two further issues (`#40580`, `#26923`) were surfaced by WebSearch synthesis but **not independently WebFetched and verbatim-confirmed in this pass** — marked UNVERIFIED. Their titles suggest a narrower, partly conflicting picture (hook fires, but the exit-code/block decision is ignored, rather than the hook never firing). This tension is not resolved here.

**Bottom line for the engineer's decision:** the best-supported reading from verified sources is that neither `PreToolUse` (Option A, i.e. `validate-bash-command.sh`) nor `PermissionRequest` (Option B) is evidenced to reliably intercept a subagent-originated Bash call. If that holds, **Option B does not close a subagent gap that Option A leaves open** — contrary to the framing in the source spike's Option E description ("either intercepting hook satisfies the mechanical half"), which did not have this subagent-specific evidence available. This does not undo the E=A+B+C decision; it narrows what "B" is actually expected to buy, which is relevant to how much implementation effort B deserves.

**Ordering / interaction of A and B in the main session (where both hooks DO fire):**

Combining the primary-source excerpts already in the sibling spike's auxiliaries with a fresh secondary-source quote:

- `approval_doc_1.txt`: *"A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed."*
- `approval_doc_2.txt`: `PermissionRequest` fires *"When a permission dialog appears."*
- dyad.sh blog (fresh fetch, secondary source, not primary Anthropic docs): *"If neither of them catches the request, and Claude Code would normally show a permission dialog, the PermissionRequest hook fires."*

Read together, the best-supported inference (not a single primary-source statement found in one place) is: a `PreToolUse` `exit 2` block stops the call before the "would a dialog be needed" determination happens at all — so for any command Option A's block matches, `PermissionRequest` never reaches its own firing condition for that same call, in the main session. Practically: **if A and B are scoped to detect the identical shape, B is dead code in the main session whenever A fires first** (both are `PreToolUse`-stage-adjacent, and `PreToolUse` runs earlier in the documented flow). B would only add independent main-session value if:

- its detection logic is deliberately implemented separately from A's (a genuinely different regex/heuristic, catching variants A's pattern misses — real second-layer coverage), or
- A is deliberately scoped narrower than B on purpose, so B is the broader net that catches what A does not.

Whether to pursue either of those — or to treat B, given the subagent evidence above, as lower-priority than A — is a decision point for the engineer, not resolved here.

---

### 3. Draft corrective-message wording for Option A

Two drafts, mirroring the existing blocks' structure (Why / Fix / See). Scoped for Candidate 3 (wrapper-path match, routes to `ruby.sh`) and for the broader Candidate 1 (no wrapper match, generic fallback) respectively — the engineer's candidate choice above determines which (or both) apply.

**Draft 1 — wrapper-path match (Candidate 3, or Candidate 1+3 combined when the wrapper path is present):**

```
Opaque command: an env-var assignment whose value is a `$(...)` substitution, feeding a long version-manager wrapper path (~/.rvm/wrappers/, ~/.rbenv/shims/, ~/.asdf/shims/) — blocked.

Why:
  - This shape (`VAR=$(cmd) ... ~/.rvm/wrappers/.../tool ...`) is exactly the case `~/.claude/scripts/ruby.sh` exists for — the master-key read and the wrapper resolution happen inside the script, where a human reviewing the approval prompt sees one short, legible line instead of a `$(...)`-then-long-path string.
  - `$(...)` command substitution already requires manual approval in Claude Code regardless of any allow-list rule (an independent security layer — see ~/.claude/docs/RUBY-COMMAND-EXECUTION.md). This command was going to prompt either way — this block intercepts BEFORE that prompt, so the human never has to parse the opaque form at all.

Fix:
  bash ~/.claude/scripts/ruby.sh [--dir <abs-project-dir>] <tool> [args...]

  Example: bash ~/.claude/scripts/ruby.sh bundle exec rspec spec/models/user_spec.rb

See: ~/.claude/docs/RUBY-COMMAND-EXECUTION.md
```

**Draft 2 — generic `$(...)`-in-`VAR=` match (Candidate 1 alone, no wrapper path):**

```
Opaque command: an env-var assignment whose value is a `$(...)` substitution feeding a downstream command — blocked.

Why:
  - `$(...)` already requires manual approval regardless of any allow-list rule (an independent security layer in Claude Code) — this command was already going to prompt.
  - When the value is a secret read (`$(cat ...key...)`) or feeds a long/wrapper invocation, the resulting approval prompt is hard for a human to read start-to-finish.

Fix:
  - If this is a Ruby/Bundler/RVM invocation: bash ~/.claude/scripts/ruby.sh <tool> [args...]
  - Otherwise: shell variables do NOT persist across tool calls — a `VAR=$(cmd); next-cmd` split does not work. Write the substituted value to a file in one tool call, then reference the file in the next:
      1. cmd > /tmp/value.txt                          (separate tool call)
      2. next-cmd --input-file /tmp/value.txt           (or read the file and inline its content)
  - If neither applies, surface the constraint to the engineer per CLAUDE.md § Bash Single-Line Policy. Do NOT generate a `/tmp/` script as a workaround.
```

Both drafts are candidates for the engineer to edit, merge, or replace.

---

### 4. Two wording variants for the CLAUDE.md correction (Option C)

Current text, `~/.claude/CLAUDE.md:24` (§ Bash Single-Line Policy):

> "Before executing a long command, print it explicitly so the engineer can read it before approving. Format: `Executando o comando completo: <full command>`. The single line will scroll off-screen — the printed copy preserves visibility into what is about to run"

**Variant 1 — full removal.** Delete the bullet entirely. Rationale: the source spike's Finding 7 establishes, from Claude Code's own documentation, that "permission rules are enforced by Claude Code, not by the model" — a `CLAUDE.md` instruction is explicitly one trust tier below mechanical enforcement. With Option A (and, per the analysis above, possibly B) providing the actual mechanical guarantee against the opaque shape, keeping a bullet that reads as a procedural requirement but is not one is no longer necessary and may itself be misleading.

**Variant 2 — re-label as best-effort transparency, not a security boundary.** Keep the practice, change the framing:

```
- **Best-effort transparency, not a security boundary**: before executing a long command, the agent SHOULD print it explicitly so the engineer can read it before approving (format: `Executando o comando completo: <full command>`). This is advisory only — per Claude Code's own documentation, permission rules are enforced by Claude Code, not by the model, and prompt-level instructions do not change what Claude Code allows. The actual mechanical guarantee against an opaque or unreadable command is the PreToolUse block in `validate-bash-command.sh` — see § Command Safety Policy.
```

Trade-off between the two: Variant 1 removes a rule that cannot be relied upon, avoiding the appearance of a control that isn't one; Variant 2 preserves whatever residual value the practice has (it is still a legible signal on the rare command the new mechanical block doesn't match) while being honest about its trust tier. Neither is chosen here — exact wording, placement, and whether any trace of the practice survives are all open for the engineer.

---

### 5. Test strategy

No automated test harness exists for `~/.claude/scripts/` in this repository (confirmed: no `.bats` files, no `tests/`/`spec/` directory, no CI workflow under `.github/workflows/` — `dot-claude` has no `.github/` directory at all). The established validation pattern for the three most similar prior additions to this exact file is manual, and is documented in each PR body:

| PR | Block added | Documented validation |
|---|---|---|
| `#151` (`fix(validate-bash-command): close env-prefix approval bypass`) | Ask-bypass normalization (Pattern 3) | *"Validated manually with 39 cases via `printf JSON \| bash scripts/validate-bash-command.sh`"* — checklist of bypass-blocked / still-asks / read-only-still-passes / existing-blocks-still-fire cases |
| `#239` (`feat(hooks): block compound commands that chain infrastructure tools`) | Infra-compound block (Pattern 1) | *"Verified against 8 block/pass cases"* |
| `#324` (`feat(hooks): block work scripts piped into output truncation`) | Work-script-pipe block (Pattern 2) | *"Verified against 7 cases (4 block, 3 pass) and `bash -n`"* |

`bash -n scripts/validate-bash-command.sh` is auto-approved (`settings.json:434`, `"Bash(bash -n:*)"`) — a zero-friction syntax check.

Applying the same pattern to the new block, the case matrix should at minimum include:

- **Should block:** the exact `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...` shape from `RUBY-COMMAND-EXECUTION.md:36`.
- **Should pass (regression against `CLAUDE.md:40`'s sanctioned escape hatch):** `AWS_PROFILE=prod aws sts get-caller-identity`, `BUNDLE_GEMFILE=/abs/path/Gemfile bundle exec rspec` (no long-wrapper path).
- **Should still block (regression on the two existing blocks in the same file, since checks run sequentially and each `exit`s on match — placement of the new block relative to Patterns 1 and 2 matters for any overlapping shape):** the Pattern 1 and Pattern 2 example commands.
- **Whichever false-positive case the chosen candidate is most exposed to**, from the analysis above — e.g. Candidate 1: `TAG=$(date +%Y%m%d) docker build -t app:$TAG .`; Candidate 2 (if chosen): `NODE_ENV=test DEBUG=true npm test`.
- **The corrective-message content itself** — confirm the chosen draft (§3 above) renders correctly in `stderr` and, for the wrapper-path case, that the suggested `ruby.sh` invocation is syntactically correct.

For Option B specifically: because `PermissionRequest` is a new hook TYPE for 4Shark (no prior production example in this repo to extend, per Finding 6 of the source spike), there is no equivalent prior-PR pattern to point to. Two distinct things need validating, and only the first is testable via the `printf JSON | bash script` pattern above:

1. **The hook script's own matching logic** — testable the same way as A, once the hook script exists.
2. **Whether Claude Code's runtime actually invokes the hook for the shapes and call sites it is meant to cover** — NOT testable via `printf | bash` in isolation, since that only exercises the script's own logic, not whether the platform calls it. This requires either an actual live Bash tool call in a real session (for the main-session case) or an actual live subagent spawn via the Task tool (for the subagent-coverage question raised in §2) — this is the "test-to-run, not a guess" the brief asked for regarding sub-question 1. Nothing found in this research substitutes for that live test.

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Carve-out heuristic for Option A | Candidate 1 ($(...) in VAR=) / Candidate 2 (stacked VAR=) / Candidate 3 (wrapper-path match) / Candidate 4 (length + prefix) / 1-OR-3 combination / 3 alone | 3 is narrowest and zero-FP-found; 1 is broader and ties to the same documented mechanism ($(...) always prompts); 2 has the weakest FP/FN profile of the four; 4 is not grounded in a documented rendering constraint | □ |
| Whether the match additionally requires a `VAR=` prefix present (for Candidate 3) | Require `VAR=` AND wrapper-path / wrapper-path alone | Requiring both avoids blocking a bare, non-opaque wrapper invocation with nothing hidden | □ |
| Scope and priority of Option B given the subagent evidence | Build B as originally scoped (second layer, same shape) / build B with a deliberately different/broader regex (genuine second-layer coverage) / de-prioritize B pending a live subagent test / drop B and document the residual gap | Evidence suggests B does not close the subagent gap; same-shape B is main-session dead code once A fires first | □ |
| Corrective message | Draft 1 (wrapper-specific, routes to `ruby.sh`) / Draft 2 (generic fallback) / both, conditionally | Draft 1 is precise but only fires for the wrapper case; Draft 2 covers the broader Candidate 1 surface but its non-Ruby remediation path is more awkward (file-based split, no simple two-step) | □ |
| CLAUDE.md wording (Option C) | Variant 1 (full removal) / Variant 2 (re-label as best-effort transparency) | Variant 1 avoids any appearance of a control that isn't one; Variant 2 preserves residual value while being honest about trust tier | □ |
| Coordination with `inject-working-dir-reminder.sh` | Leave the existing advisory hook as-is (duplicate/overlapping guidance across two PreToolUse hooks for the same shape) / align its message with the new block's corrective text / fold its wrapper-path detection into the new block and retire the advisory duplication for that specific shape | The existing hook is advisory-only and rate-limited per session; the new block would be a hard stop for the same trigger family — worth deciding whether both should keep firing independently | □ |

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| Carve-out too broad (Candidate 1/2/4) | New false positives against the sanctioned `VAR=value cmd` escape hatch — the mechanism intended to REDUCE prompts instead adds a restructuring step for legible commands | Prefer the narrowest candidate that still covers the documented incident (Candidate 3), or test the chosen candidate against the case matrix in §5 before merging |
| Carve-out too narrow (Candidate 3 alone) | A future non-Ruby opaque-wrapper shape is not covered, and the spike's broader framing (not Ruby-specific) is only partially addressed | Document the narrower scope explicitly in the block's own header comment (as the other blocks in this file already do), so a future incident is a known, deliberate gap rather than a surprise |
| Option B built as originally scoped provides no measurable benefit | Engineering effort (a new hook type, a new file/wiring in `settings.json`) for a layer that is main-session-dead-code (per the ordering analysis) and does not cover subagents (per the fresh evidence) | Resolve via the live-test recommendation in §5 before committing to B's exact shape, or scope B's regex deliberately differently from A's so it is not simply redundant |
| Sequential-block placement in `validate-bash-command.sh` | The file's checks run top-to-bottom, each ending in `exit 2` on match — if the new block is placed after an existing one that partially overlaps, the existing block's (possibly less precise) message fires instead of the new one's | Include placement as an explicit item in the case matrix (§5) — verify which block fires first for any command matching more than one pattern |
| Internal citation trail (agent-pipe-chaining → llm-agent-command-chaining) does not currently resolve | Reduces confidence in one input to this plan's own conclusions on subagent hook coverage — though the fresh external research (§2) reaches a similar conclusion independently | Documented plainly in `subagent_hook_scope_1.txt`; this plan does not depend on the unresolved internal citation |

## Open questions for the engineer

- Which carve-out candidate (or combination) for Option A — the decision table above needs a checkmark, not a default.
- Given the subagent evidence, does Option B still get built as originally scoped, get rescoped, or get deferred pending a live test?
- Which corrective-message draft, and does it need editing before it goes into the actual hook?
- Which CLAUDE.md wording variant for Option C — or a third wording the engineer prefers?
- Should the case matrix in §5 be run by the engineer manually before merge, or should `plan-composer`/execution include it as an explicit task with the specific case list from this document?
- Should `inject-working-dir-reminder.sh`'s existing advisory message be reconciled with the new block's corrective text, left alone, or folded together?

## Sources

- `~/.claude/plans/active/spike/agent-command-approval-visibility/SPIKE.md` (10 findings, all read in full) — the source spike this plan builds on
- `approval_doc_1.txt`, `approval_doc_2.txt`, `approval_issue_3.txt`, `approval_selfreport_4.txt`, `approval_related_5.txt` (source spike's auxiliaries, read in full)
- `~/.claude/scripts/validate-bash-command.sh` (543 lines, read in full) — Patterns 1-4 cited by line
- `~/.claude/scripts/ruby.sh` (111 lines, read in full) — Pattern 5
- `~/.claude/scripts/inject-working-dir-reminder.sh` (111 lines, read in full) — Pattern 6
- `~/.claude/docs/RUBY-COMMAND-EXECUTION.md` (read in full)
- `~/.claude/docs/COMMAND-SAFETY.md` (read in full)
- `~/.claude/CLAUDE.md:20-47` (§ Bash Single-Line Policy, § Working Directory Behavior), `:886-` (§ Command Safety Policy)
- `~/.claude/settings.json` (hooks + `permissions.allow` sections, read directly — confirmed no `PermissionRequest` hook currently wired; confirmed `"Bash(bash -n:*)"` at line 434)
- `git -C ~/Projects/4Shark/dot-claude log --oneline -- scripts/validate-bash-command.sh` (read-only, 14 commits) and `gh -R 4shark/dot-claude pr list --state merged --search ...` for PRs `#151`, `#239`, `#324` (bodies fetched, verbatim test-plan quotes above)
- `~/.claude/plans/active/spike/llm-agent-command-chaining/SPIKE.md` (full file re-read for this plan, including all 5 findings and all `chaining_excerpt_*.txt` auxiliaries) and `~/.claude/plans/completed/spike/agent-pipe-chaining/SPIKE.md:89` (the unresolved internal citation, documented not relied upon)
- `https://github.com/anthropics/claude-code/issues/23983` — fetched fresh 2026-07-01
- `https://github.com/anthropics/claude-code/issues/34692` — fetched fresh 2026-07-01
- `https://www.dyad.sh/blog/claude-code-permission-hooks` — fetched fresh 2026-07-01
- See auxiliary: `subagent_hook_scope_1.txt` — full sourcing and verbatim quotes for the subagent/hook-ordering research in §2, including the two UNVERIFIED issues (`#40580`, `#26923`) not independently confirmed in this pass
