# SPIKE — Agent Work-Script Pipe Truncation: Enforcement Gap

## Investigation question

Claude Code repeatedly generates commands of the form `bash <work-script> 2>&1 | tail -N` — a compound command that pipes a non-idempotent work script's output into a truncation sink. Neither existing enforcement hook blocks this pattern. The question: what mechanism (or combination of mechanisms) would reliably prevent this from recurring, and what are the trade-offs of each option?

Three sub-questions defined by the engineer:
- Q1: Why do LLM agents structurally over-use shell pipes (training-data bias, RLHF, tool-call reduction)? — answered in full in the sibling spike `llm-agent-command-chaining/SPIKE.md` Findings 1 and 2; referenced here, not duplicated.
- Q2: How is the Claude Code community handling pipe/compound command issues?
- Q3: What mechanisms actually change the behavior versus prose rules?

The engineer's explicit constraint: "liberar esse comando não vai resolver — temos que garantir que não vai mais ter problema." Approving the problematic command does not solve the structural incentive; a deterministic enforcement mechanism is required.

## Sources consulted

- `~/.claude/scripts/validate-bash-command.sh:159-200` — infra+compound detection block; source of the enforcement gap
- `~/.claude/scripts/inject-output-preservation-reminder.sh:1-147` — full hook; design rationale for advisory-only approach and existing false-positive exclusion logic
- `~/.claude/plans/active/spike/llm-agent-command-chaining/SPIKE.md` — sibling spike; Findings 1-5 cover the general command-chaining problem (training-data bias, Claude Code permission model, community patterns, PreToolUse hooks); this spike narrows to the specific bash-pipe-truncation enforcement gap
- `~/.claude/plans/active/spike/llm-agent-command-chaining/chaining_excerpt_2.txt` — Claude Code permissions documentation key quotes: compound command splitting behavior, built-in read-only command exemptions, PreToolUse exit code 2 semantics
- `~/.claude/plans/active/spike/llm-agent-command-chaining/chaining_excerpt_3.txt` — GitHub issues on compound command permission matching (#16561, #20085, #20985, #28183, #28784, #31523, #36637, #48762)
- See auxiliary: [`agent-pipe-chaining_excerpt_1.sh`](./agent-pipe-chaining_excerpt_1.sh) — `validate-bash-command.sh` lines 159-200 with gap analysis annotations
- See auxiliary: [`agent-pipe-chaining_excerpt_2.sh`](./agent-pipe-chaining_excerpt_2.sh) — `inject-output-preservation-reminder.sh` key sections with design notes

## Findings

### Finding 1: The specific pattern is not blocked by either existing enforcement hook

**Evidence:**

`validate-bash-command.sh` (lines 178-180) detects compound operators only when an infrastructure token is also present in the command. The infra token regex at line 180 is:

```
(aws|terraform|kubectl|docker|ansible|gcloud|helm)
```

`bash` and `sh` are not in this list. A command like `bash ~/.claude/scripts/setup-worktree.sh ~/path 2>&1 | tail -10` contains a compound operator (`|`) but no infra token — so the check at lines 179-180 evaluates to false and the command passes through silently.

`inject-output-preservation-reminder.sh` (lines 41-44) states its design contract explicitly:

```
# Emits additionalContext ONLY — never a permissionDecision. The command
# continues through the normal permission flow; this hook only adds context.
#
# Always exits 0. A failing hook must NEVER block a Bash command.
```

Additionally, the reminder is rate-limited to once per session (line 105: `[[ -f "$marker_file" ]] && emit_empty`). After the first firing, all subsequent pipe-truncation commands in the same session receive no reminder and no block.

**Source:** `validate-bash-command.sh:178-200` (infra token list and compound check); `inject-output-preservation-reminder.sh:41-44` (advisory-only contract); `inject-output-preservation-reminder.sh:105` (session rate-limiting). See also: [`agent-pipe-chaining_excerpt_1.sh`](./agent-pipe-chaining_excerpt_1.sh), [`agent-pipe-chaining_excerpt_2.sh`](./agent-pipe-chaining_excerpt_2.sh).

**Significance:** The gap is structural, not accidental. `validate-bash-command.sh` was designed to block infra compound commands specifically — `bash work-script | tail` is out of scope by design. The reminder hook was intentionally designed as advisory-only: the comment on line 44 is a stated design principle, not an oversight. Closing the gap requires either extending the scope of `validate-bash-command.sh` or revising the design principle of `inject-output-preservation-reminder.sh`.

Verification block: `validate-bash-command.sh` read at lines 140-200; infra token list confirmed at line 180. `inject-output-preservation-reminder.sh` read in full (lines 1-147); advisory-only statement confirmed at lines 41-44; rate-limit marker check confirmed at line 105.

---

### Finding 2: "Approve and don't ask again" actively worsens the situation — it broadens the gap

**Evidence:**

The Claude Code permissions documentation (fetched 2026-06-08; in `chaining_excerpt_2.txt` lines 6-16) states:

> "Claude Code is aware of shell operators, so a rule like Bash(safe-cmd *) won't give it permission to run the command safe-cmd && other-cmd. The recognized command separators are &&, ||, ;, |, |&, &, and newlines. A rule must match each subcommand independently."

The same document states (lines 18-21):

> "Claude Code recognizes a built-in set of Bash commands as read-only and runs them without a permission prompt in every mode. These include ls, cat, echo, pwd, head, tail, grep, find, wc, which, diff, stat, du, cd, and read-only forms of git."

Since `tail` is in the built-in read-only list, it never triggers an approval prompt on its own. When `bash work-script 2>&1 | tail -10` fires a prompt, the prompt fires only for the `bash work-script` segment. When the engineer approves "Yes, don't ask again," a rule is saved for `bash work-script` alone. This rule then permits `bash work-script` with or without any subsequent pipe — making future pipe-truncation of the same script auto-approved.

**Source:** `llm-agent-command-chaining/chaining_excerpt_2.txt:6-16` (per-subcommand rule saving); `llm-agent-command-chaining/chaining_excerpt_2.txt:18-21` (built-in read-only list including `tail`).

**Significance:** The engineer's statement "liberar esse comando não vai resolver" is mechanically correct. Approving the compound command does not save the compound form as a rule — it saves the prefix `bash work-script`, which grants permission for the bare script AND the pipe-truncated form equally. The approval path cannot enforce the distinction the engineer needs. Only a pre-approval block (PreToolUse exit 2) can intercept the command before the permission system is consulted.

Verification block: `chaining_excerpt_2.txt` read at lines 1-37. Compound-command rule quote confirmed at lines 6-16. Built-in read-only list quote confirmed at lines 18-21; `tail` appears literally: "These include ls, cat, echo, pwd, head, tail, grep..."

---

### Finding 3: Exit code 2 from PreToolUse provides a hard block in the main session — confirmed working in production

**Evidence:**

The Claude Code permissions documentation (`chaining_excerpt_2.txt` lines 29-32) states:

> "A blocking hook also takes precedence over allow rules. A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed."

This mechanism is confirmed working in production: `validate-bash-command.sh` successfully blocks infra compound commands via `exit 2` at line 200 (`exit 2` after the infra compound check at lines 179-199). The hook is wired as `PreToolUse` in `settings.json` and has been in production across multiple sessions without reported failures.

The sibling spike `llm-agent-command-chaining/SPIKE.md` Finding 5 documents a confirmed platform limitation: exit code 2 from PreToolUse hooks is ignored for subagent (Task tool) Bash calls. This means any hard-block in `validate-bash-command.sh` protects only the main Claude Code session — subagents invoked via the Task tool are not covered.

**Source:** `llm-agent-command-chaining/chaining_excerpt_2.txt:29-32` (exit 2 semantics); `validate-bash-command.sh:199-200` (production exit 2 in existing hook); `llm-agent-command-chaining/SPIKE.md` Finding 5 (subagent exit-2 limitation).

**Significance:** A hard block via exit 2 is mechanically viable for the main session and uses a pattern already in production in the same file. Adding a new block to `validate-bash-command.sh` is a surgical change to an existing, tested file rather than a new architectural component. The subagent limitation is a Claude Code platform constraint outside 4Shark's control — it must be documented as a residual gap for any option relying on exit 2.

Verification block: `chaining_excerpt_2.txt` read at lines 29-32; exit-2 quote confirmed verbatim. `validate-bash-command.sh` read at lines 140-200; `exit 2` confirmed at line 200 following the infra compound check. Cross-reference to `llm-agent-command-chaining/SPIKE.md` Finding 5 is a reference to the existing spike's sourced content, not independently re-fetched here.

---

### Finding 4: The false-positive challenge is specific to blocking `bash|sh <script> | tail`

**Evidence:**

`inject-output-preservation-reminder.sh` (lines 92-99) already handles the false-positive problem correctly for the reminder path — it excludes commands whose first program is a pure-local idempotent read:

```bash
case "$first_program" in
    grep|rg|cat|ls|find|fd|wc|sort|uniq|head|tail|echo|printf|awk|sed|cut \
        |tr|jq|yq|column|tac|nl|od|xxd|diff|comm|paste|cut|git)
        emit_empty ;;
esac
```

When the first token is `bash` or `sh`, this case statement does not match — so the reminder fires. This is the correct behavior for an advisory reminder. For a hard block, however, the first token `bash` or `sh` is insufficient to determine whether the script does real work or only local reads: `bash get_version.sh | head` and `bash setup-worktree.sh ~/path | tail -10` are syntactically identical, but the first is a safe idempotent read and the second is a non-idempotent work command.

The existing infra-token approach in `validate-bash-command.sh` (line 180) avoids this problem by matching specific, unambiguous program names (`aws`, `terraform`, etc.) — which are never pure local reads. `bash script.sh` does not have this clarity: the work-vs-read determination requires knowledge of the script's content or a path-based heuristic.

**Source:** `inject-output-preservation-reminder.sh:92-99` (existing false-positive exclusion logic); `validate-bash-command.sh:178-180` (infra token specificity as the architectural guard against false positives). See also: [`agent-pipe-chaining_excerpt_2.sh`](./agent-pipe-chaining_excerpt_2.sh) Section B.

**Significance:** Any hard-block option for `bash script | tail` must either accept false positives for idempotent `bash` scripts (pure Option A), scope the block to specific known-work paths (path-scoped Option A), or rely on the existing exclusion logic in `inject-output-preservation-reminder.sh` (Option B). The path-scoped variant is more precise but requires maintenance when new work scripts are added to `~/.claude/scripts/` or project `bin/` directories.

Verification block: `inject-output-preservation-reminder.sh:92-99` read and quoted verbatim above. `validate-bash-command.sh:178-180` read and quoted verbatim in Finding 1.

---

## Trade-offs surfaced

| Option | Mechanism | Pros | Cons | Findings |
|--------|-----------|------|------|----------|
| A (path-scoped hard block in `validate-bash-command.sh`) | Add a new exit-2 block: compound operator + first token is `bash`/`sh` + matches known work-script path prefixes (`~/.claude/scripts/`, `bin/`) + truncation sink present | Deterministic; no recurrence for matched paths in main session; surgical change to existing tested file; clear corrective stderr message with redirect-to-file form | False positives for any idempotent `bash` script at matched paths; path list requires maintenance as new scripts are added; exit 2 ignored for subagent Bash calls | 1, 3, 4 |
| B (upgrade `inject-output-preservation-reminder.sh` to hard block) | Change from `additionalContext`-only to exit 2; remove per-session rate-limiting | Already has correct false-positive exclusion logic (lines 92-99); single file change; correct classification of `bash` vs. known-idempotent first tokens | Violates the stated design principle ("A failing hook must NEVER block a Bash command"); first occurrence in session still passes through before rate-limit marker is set (unless rate-limiting is also removed); exit 2 ignored for subagent Bash calls | 1, 2, 3 |
| A+B combined | Path-scoped hard block in `validate-bash-command.sh` for known work-script paths (Option A) + exit-2 upgrade in `inject-output-preservation-reminder.sh` for broader coverage (Option B) | Layered enforcement; Option B's existing exclusion logic reduces false positives for the broader match; main session protected for both known and unknown script paths | Two files to change; subagent gap remains in both; changes two hooks with different design philosophies | 1, 3, 4 |
| C (status quo + stronger prose rule) | No code change | Zero implementation effort | Explicitly rejected by engineer: "liberar esse comando não vai resolver"; reminder already fires once per session without preventing recurrence | 1, 2 |

---

## What remains uncertain

- **False-positive rate for Option A path-scoped approach**: how many legitimate `bash script.sh | head` patterns exist in 4Shark workflows at the paths `~/.claude/scripts/` or `bin/`? If the answer is "none in practice," the false-positive risk is theoretical. If there are idempotent scripts at those paths, the block would need an explicit opt-out mechanism.
- **Whether the "always exits 0" design principle in `inject-output-preservation-reminder.sh` is a 4Shark team decision or a platform recommendation**: the comment at line 44 reads as an architectural constraint ("A failing hook must NEVER block a Bash command"), but it may be overstated — `validate-bash-command.sh` exits 2 successfully in production. If the principle is specific to reminder-class hooks (advisory by intent), upgrading to exit 2 changes the hook's category, not just its exit code.
- **Subagent exit-2 gap timeline**: the `llm-agent-command-chaining/SPIKE.md` Finding 5 documents that exit 2 is ignored for subagent Bash calls. Whether this is a known bug with a fix timeline or a deliberate design decision is not sourced in the existing spike. All options that rely on exit 2 have this residual gap for subagent sessions.
- **Whether a path-prefix approach is sufficient long-term**: blocking only `~/.claude/scripts/*.sh` and `bin/*.sh` covers the pattern observed in production (`bash ~/.claude/scripts/setup-worktree.sh ~/path 2>&1 | tail -10`) but would miss ad-hoc `bash /tmp/fix.sh | tail` patterns that an agent might generate during script-discipline flows.

---

## Suggested options for main and the engineer

- **Option A** (extend `validate-bash-command.sh` with a path-scoped hard block): add a new block that detects compound operator + first token is `bash` or `sh` + script path matches known work-script path prefixes (`~/.claude/scripts/`, `bin/`) + truncation sink (`head`, `tail`, `sed -n`) is present. Emit corrective stderr with the redirect-to-file form. Hard block via exit 2. Maintains the architectural principle that blocks name specific bad patterns. Does not protect subagents. Requires path-list maintenance.

- **Option B** (upgrade `inject-output-preservation-reminder.sh` to hard block): change the hook from advisory to blocking by emitting exit 2 after the `additionalContext` injection (or instead of it). Remove the per-session rate-limiting so the block fires on every occurrence. The existing false-positive exclusion logic at lines 92-99 already handles `bash`/`sh` correctly. Does not protect subagents. Changes a hook whose stated design is "always exits 0."

- **Option A+B combined**: implement path-scoped hard block in `validate-bash-command.sh` (Option A) to cover known work-script paths precisely, and upgrade `inject-output-preservation-reminder.sh` (Option B) as a broader safety net for ad-hoc script patterns. Provides layered enforcement. Subagent gap remains under both layers.

(NO recommendation — main and the engineer choose.)
