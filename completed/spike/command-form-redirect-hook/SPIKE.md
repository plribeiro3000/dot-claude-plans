# SPIKE — Command-Form Redirect Hook: Pre-Flight Rewrite of Bash Commands Into Canonical Form

> **CLOSED 2026-07-16 — the framing below is WRONG, and knowing why is the value here.**
>
> **The axis is wrong.** This spike compared *rewrite vs. block*. The engineer's actual cost is a session frozen on a PROMPT waiting for a human — and a block does NOT stall: Anthropic's docs state a `deny` or `exit 2` hands the reason to Claude and the agent keeps working. Only `ask` freezes. Everything below that treats block and prompt as equivalent is measuring the wrong thing.
>
> **The premise is wrong.** The whole spike assumes sessions stall because the agent uses a wrong FORM of an allow-listed command. Measuring 176 transcripts (10,906 paired Bash calls) refuted it: the wrong-form problem has ~18 real occurrences, all one shape (an absolute path against a `~` allow entry), already fixed by `redirect-home-path.sh` in dot-claude PR #425. What actually stalls is CHAINING — a simple read-only command stalled >60s in 0.16% of 1,263 calls; the same commands chained, 0.90% of 2,568 (5.7×). Shipped as dot-claude PR #428.
>
> **Finding A2's central uncertainty is resolved, and not by this spike.** It could not establish whether `updatedInput` is re-checked against the allow list. `redirect-home-path.sh`'s author settled it empirically the same week — it IS re-evaluated; the rewritten command is matched, not the original. See that script's header for the method (a throwaway hook via `claude --settings <file>`, one variable at a time against a live control). That is the standard this spike should have met and did not.
>
> **What still holds and is worth reading**: Finding A5 (the normalizer already in `validate-bash-command.sh`, and the two-hand-edited-lists liability it creates), Finding C's catalog of wrong-form → canonical-form pairs, Finding D's safety/form boundary, and the community sweep in B1 (of 15 published hook projects, exactly one rewrites a Bash command, and rewriting is that vendor's product — not a pattern the community endorses).
>
> **The downstream `PLAN.md`/`PLAN-SPIKE.md` built on this spike are archived unimplemented** at `completed/dot-claude/permission-request-normalizer/`, with their own note.

## Investigation question

Is there a hook (or hook composition) that can, BEFORE a Bash command executes, (a) determine whether the command as written will auto-approve against `permissions.allow` or be blocked by one of the `validate-*.sh` PreToolUse hooks, and (b) when an equivalent already-allowed canonical form exists, REWRITE the command into that form automatically instead of letting it hit a prompt or a block — so the agent stops needing to remember the canonical form, and the mechanism enforces it instead?

Refined from the engineer's framing: 4Shark has already built and allow-listed the canonical wrapper scripts (`ruby.sh`, `terraform.sh`, `start-instance.sh`, `hubflow.sh`, `ecs-scale.sh`, …), yet the agent keeps typing the raw/wrong-shape form and triggering a prompt or a block the engineer then has to correct. The question is whether this correction can be made mechanical rather than relying on the agent remembering the rule every time.

## Sources consulted

- `/Users/plribeiro3000/.claude/settings.json:198–417` — full `hooks` wiring; 12 `PreToolUse` hook entries carry matcher `Bash` (lines 199–346). 11 of the 12 have no `if` filter and fire on every Bash call; the 12th (`inject-terraform-context.sh`, lines 249–271) nests `if` conditions on its 3 sub-hooks that further scope to terraform-shaped commands, but the group itself still matches every Bash call before that narrowing.
- `/Users/plribeiro3000/.claude/settings.json:422–703` — full `permissions.allow` and `permissions.ask` arrays.
- `/Users/plribeiro3000/.claude/scripts/redirect-terraform.sh` — the working precedent: rewrites raw read-only terraform into the `terraform.sh` wrapper via `updatedInput`.
- `/Users/plribeiro3000/.claude/scripts/redirect-ecs-scale.sh` — the second working precedent: rewrites raw `aws ecs update-service` scale calls into `ecs-scale.sh`.
- `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh` (612 lines, read in full) — the block/ask hook; every blocked or asked shape enumerated in Finding C/D below.
- `/Users/plribeiro3000/.claude/scripts/ruby.sh`, `/Users/plribeiro3000/.claude/scripts/terraform.sh` — the wrapper targets the redirects rewrite into.
- `/Users/plribeiro3000/.claude/scripts/auto-approve-aws-readonly.sh` — a third pre-flight pattern (auto-approve, not rewrite) with its own documented rationale for why it exists as a hook rather than an allow-list wildcard.
- `/Users/plribeiro3000/.claude/scripts/validate-installed-config-edit.sh` — confirms Edit/Write hooks use the same `hookSpecificOutput` shape but for a different tool.
- `/Users/plribeiro3000/.claude/docs/adr/ADR-002-permission-resolver-precedence.md` — the only 4Shark-internal document that already investigated and cited the deny→ask→allow precedence and the "hooks do not bypass permission rules" rule, with official-doc citations.
- `/Users/plribeiro3000/.claude/docs/adr/ADR-001-rules-loading-mechanism.md` — confirms the 10,000-character hook-output cap and its practical effect (a ~2KB preview when exceeded), independently of this spike's own fetches.
- `/Users/plribeiro3000/.claude/docs/COMMAND-SAFETY.md`, `/Users/plribeiro3000/.claude/docs/RUBY-COMMAND-EXECUTION.md` — the WHY behind the wrong shapes this spike catalogs (env-prefix defeats prefix-match, `$(...)` is an independent approval layer, decoration breaks matching).
- [Configure permissions — Claude Code Docs](https://code.claude.com/docs/en/permissions) — fetched in full 2026-07-16; see auxiliary `command-form-redirect-hook_doc_1.md` for the load-bearing excerpt.
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) — fetched via four separate targeted queries 2026-07-16; see auxiliary `command-form-redirect-hook_doc_2.md`.
- [Claude Code Hooks Explained — blakecrosley.com](https://blakecrosley.com/blog/claude-code-hooks-explained) — third-party/community source, fetched and re-fetched (self-check) 2026-07-16; see auxiliary `command-form-redirect-hook_doc_3.md`. **Not an Anthropic source** — flagged accordingly in Finding A3.
- [shaxxx/claude-permission-hook](https://github.com/shaxxx/claude-permission-hook) and [kornysietsma/claude-code-permissions-hook](https://github.com/kornysietsma/claude-code-permissions-hook) — prior-art search, Finding B1.
- See auxiliary: `command-form-redirect-hook_options_1.html` — the options comparison for § Suggested options, adapted from `~/.claude/templates/html/comparison-board.html` with the recommendation block removed (spike agents do not recommend).

## Findings

### Finding A1: The rewrite primitive exists and is already in production use

**Evidence:**

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"...","updatedInput":{"command":"..."}}}
```

`/Users/plribeiro3000/.claude/scripts/redirect-terraform.sh:122–124`:
```
jq -cn --arg cmd "$wrapper" --arg reason "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$reason,updatedInput:{command:$cmd}}}'
exit 0
```

**Source:** [Hooks reference](https://code.claude.com/docs/en/hooks), schema quoted in full in auxiliary `command-form-redirect-hook_doc_2.md`: `updatedInput` is documented as "directly replaces the tool's arguments before it runs," alongside `permissionDecision` (`allow`/`deny`/`ask`/`defer`) and `additionalContext`.

**Significance:** The primitive the investigation asks about — rewrite-then-allow — is not hypothetical. It is documented by Anthropic and already running in 4Shark production for two shapes (terraform reads, ECS scale calls). The open question is not "can a hook rewrite a command" (yes) but "can this be generalized safely to the rest of the catalog, and what exactly does the rewrite bypass or not bypass."

### Finding A2: Whether a rewritten command re-enters permission-rule matching is not documented by Anthropic

**Evidence:** Four separate targeted `WebFetch` queries against `https://code.claude.com/docs/en/hooks`, asking specifically whether `updatedInput` is re-validated against `permissions.allow`/`ask`/`deny` before the tool runs, each returned a "not found" result. Full transcript of what was and was not found is in auxiliary `command-form-redirect-hook_doc_2.md`, § "Explicitly NOT FOUND." Verbatim from the third query: "The documentation does not specify whether: Tool input rewritten by `updatedInput` in a PreToolUse hook is re-validated against the deny/ask/allow permission rules [...] This represents a gap in the documented behavior for decision control with input modification."

**Source:** `command-form-redirect-hook_doc_2.md` (this spike's own fetch transcript), § "Explicitly NOT FOUND," items 2–3.

**Significance:** This is the load-bearing unknown for the whole investigation. If the rewritten command is re-checked against `allow`/`ask`/`deny`, a redirect targeting an already-allow-listed wrapper (like `terraform.sh`, `ruby.sh`) is doubly safe — even a wrong rewrite would still have to clear the allow-list gate. If it is NOT re-checked and the `permissionDecision: "allow"` from the SAME hook call is simply final, then the correctness of the rewrite rests entirely on the redirect script's own logic, with no second gate. The existing 4Shark redirects (`redirect-terraform.sh`, `redirect-ecs-scale.sh`) are written to be safe either way — they only ever rewrite INTO a target that is independently allow-listed and read-only/scale-only by construction — but a future redirect author cannot assume re-validation happens.

### Finding A3: Multiple parallel hooks on the same event have a documented deny-wins precedence for DECISIONS, but no documented rule for competing REWRITES — and 4Shark's own settings.json has a live, unexercised example of the collision

**Evidence (decision precedence, official):**

> "Hook decisions don't bypass permission rules. Claude Code evaluates deny and ask rules regardless of what a PreToolUse hook returns: a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned "allow" or "ask". [...] A blocking hook also takes precedence over allow rules. A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed."

**Source:** [Configure permissions § Extend permissions with hooks](https://code.claude.com/docs/en/permissions), quoted in full in `command-form-redirect-hook_doc_1.md`.

**Evidence (parallel execution, official):**

> "All matching hooks run in parallel, and identical handlers are deduplicated automatically."

**Source:** [Hooks reference](https://code.claude.com/docs/en/hooks), quoted in `command-form-redirect-hook_doc_2.md`.

**Evidence (third-party, precedence AND rewrite-collision, UNVERIFIED by Anthropic):**

> "when multiple `PreToolUse` hooks disagree, precedence is `deny` > `defer` > `ask` > `allow`."
> "When several PreToolUse hooks rewrite the same tool's arguments, the last to finish wins."

**Source:** [blakecrosley.com — Claude Code Hooks Explained](https://blakecrosley.com/blog/claude-code-hooks-explained), quoted and re-fetched (self-check, same substrings confirmed on a second independent fetch) in `command-form-redirect-hook_doc_3.md`. This is a community blog, not an Anthropic source, and the official docs are silent on this exact point after four direct attempts (Finding A2). Treated as corroborating-but-unverified, not as ground truth.

**A concrete, code-grounded worked example of the collision, already present in production today:**

`/Users/plribeiro3000/.claude/scripts/redirect-terraform.sh:114–119` rewrites `terraform -chdir=<stack> plan [args...]` into `bash ~/.claude/scripts/terraform.sh <stack> plan [args...]` with NO special-casing of a `-out=<path>` argument — the loop just appends every remaining arg verbatim:
```bash
wrapper="bash $HOME/.claude/scripts/terraform.sh $stack_dir $subcommand"
for arg in ${rest[@]+"${rest[@]}"}; do
  wrapper="$wrapper $arg"
done
```

`/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:567–590` (raw `-out` outside `/tmp` guard) matches the SAME raw command shape (`terraform [-chdir=...] plan ... -out=<non-/tmp path>`) and returns `exit 2` (a block):
```bash
if printf '%s' "$normalized_command" | grep -qE '^terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+plan([[:space:]]|$)' \
   && printf '%s' "$normalized_command" | grep -qE '[[:space:]]-out[=[:space:]]' \
   && ! printf '%s' "$normalized_command" | grep -qE '[[:space:]]-out[=[:space:]]+/tmp/'; then
  ...
  exit 2
fi
```

**Significance:** For a raw command like `terraform -chdir=/abs/stack plan -out=tf.plan` (no `/tmp` prefix), BOTH hooks fire in parallel on the SAME original input: `redirect-terraform.sh` returns `allow` + `updatedInput` (rewriting to the wrapper form, which internally would have forced `-out` to `/tmp` — see `terraform.sh:109–156`), while `validate-bash-command.sh` returns `exit 2` (block). Per the documented deny/block-over-allow precedence (Finding A3, official quote above), the block should win — meaning this specific raw-path edge case is NOT, in practice, silently rewritten by the existing redirect; it is blocked, and the block message itself tells the agent to either use the wrapper or point `-out` at `/tmp` manually. This is not a hypothetical scenario invented for this spike — it is the current, live behavior of two hooks that have coexisted in production for months. It demonstrates, with actual code rather than an assumption, that an `exit 2` block from one hook is not silently defeated by an `allow`+`updatedInput` from a different parallel hook on the same original command — consistent with the official precedence rule, and evidence (not proof, since the internal resolver code is not published) that the mechanism behaves as documented in at least this one exercised case.

### Finding A4: The 10,000-character hook output cap bounds any table-driven or verbose-announcement design

**Evidence:** "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

**Source:** [Hooks reference](https://code.claude.com/docs/en/hooks), quoted in `command-form-redirect-hook_doc_2.md`; independently corroborated inside the repo at `/Users/plribeiro3000/.claude/docs/adr/ADR-001-rules-loading-mechanism.md:9` ("Hook output is capped at 10,000 characters... the hook emitted ~119KB at SessionStart (→ a ~2KB preview of the first doc, nothing else)").

**Significance:** This caps ONE hook's output on ONE invocation, not the aggregate of 12 parallel hooks — so a generalized redirect script (Option A in § Suggested options) is not directly threatened by the cap for its `updatedInput`/`permissionDecisionReason` fields, which are typically a single short line. It DOES bound any design that adds a verbose `additionalContext` announcement per rewrite (Option D) if that announcement is combined with a large table dump rather than a one-line note.

### Finding A5: `validate-bash-command.sh` already reimplements a mini permission-matcher against a hardcoded mirror of the `ask` list — proof the "reimplement and pre-check" approach works today, and a live example of the maintenance-liability it creates

**Evidence:** `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:502–539` is titled "=== Ask-bypass detection ===" and its own comment states the mechanism directly:

```
# Sensitive write operations are listed in settings.json under permissions.ask
# so they require human approval. The matcher does string-prefix match against
# the command, which means an env-var prefix (`AWS_PROFILE=x terraform apply`),
# an `env` wrapper, or an absolute path (`/usr/local/bin/terraform apply`)
# defeats the match — the command falls through to the allow default with no
# prompt. PR #408 documented the bypass in production.
#
# The fix: normalize the command (strip leading env-var assignments, `env`
# wrapper, absolute path of the binary) and re-match against the canonical
# write-op list.
```

The re-match list is hand-maintained at lines 541 (`aws ec2 start|stop-instances`), 559 (`terraform apply|destroy|import|taint|untaint`), 563 (`terraform state rm|mv`), 592 (`aws ecs run-task`), 596 (`gh release create`), 600 (`git tag`), 604 (`git rm`) — each one a duplicate, in a different syntax, of an entry that also exists in `settings.json`'s `permissions.ask` array (`/Users/plribeiro3000/.claude/settings.json:662–703`).

**Significance:** This is direct, in-repo evidence that (a) a hook CAN reimplement a normalize-then-match check against a rule list, and it already does, in production, today; and (b) doing so creates exactly the maintenance liability the investigation asked about — the `ask` list in `settings.json` and its mirror in `validate-bash-command.sh` are two independent hand-edited lists that must be kept in sync manually. A new destructive `gh`/`aws`/`terraform` subcommand added to `permissions.ask` in a future PR would NOT automatically also close the env-prefix bypass for it unless the same PR also updates `validate-bash-command.sh`'s normalize-then-match block. Nothing in the codebase enforces that the two lists stay identical.

### Finding B1: No prior art found for a "pre-flight allow-check + auto-rewrite" hook; the two closest community projects reimplement the matcher but do not rewrite

**Evidence:** [shaxxx/claude-permission-hook](https://github.com/shaxxx/claude-permission-hook) — "This hook provides fine-grained control over Claude Code's tool usage through regex-based pattern matching," evaluating commands as deny → allow → passthrough. [kornysietsma/claude-code-permissions-hook](https://github.com/kornysietsma/claude-code-permissions-hook) — "A PreToolUse hook for Claude Code that provides granular control over which tools Claude can use, with support for allow/deny rules, pattern matching, and security exclusions."

**Source:** Both quoted directly from the repos' own README text via `WebFetch`, 2026-07-16.

**Significance:** Both projects independently reimplement a regex-based allow/deny matcher as a hook (corroborating Finding A5's maintenance-liability point at community scale, not just inside 4Shark) — but neither one REWRITES a command into a canonical form; they only permit, block, or pass through unchanged. Not found: a published, named community pattern for "check + auto-correct to canonical form" of the kind 4Shark's `redirect-terraform.sh`/`redirect-ecs-scale.sh` already implement. This is either because the pattern is uncommon, or because it was not surfaced by the specific search queries run; stated as "not found," not as "does not exist."

### Finding B2: No official "would this be allowed" dry-run query was found

**Evidence:** No section of the fetched `permissions.md` or `hooks.md` content (both fetched in full, see auxiliaries) describes a CLI flag, SDK call, or hook-callable function that answers "would command X be allowed" without actually attempting the tool call. The closest documented mechanism is the permission rule set itself (`allow`/`ask`/`deny`, string-prefix and glob matching, fully specified in [Configure permissions § Permission rule syntax](https://code.claude.com/docs/en/permissions)) — which a hook script CAN reimplement by parsing `settings.json` directly (Finding A5 already does a hardcoded subset of this), but there is no first-party function that performs the match FOR the hook.

**Significance:** A redirect hook that wants to know "will my rewritten form actually auto-approve" has exactly two options: (1) hardcode/mirror the specific allow-list entries it targets (as every existing 4Shark redirect and validator does), accepting the drift risk from Finding A5; or (2) parse `settings.json`'s `permissions.allow` array itself at hook-run time and apply the documented glob/prefix rules (§ Permission rule syntax) — a small but real reimplementation of Claude Code's own matcher, with its own maintenance burden (the matcher's exact semantics — process-wrapper stripping, mid-string wildcard handling, `:*` suffix equivalence — are all independently documented but nontrivial to reproduce bug-for-bug; `auto-approve-aws-readonly.sh:14–20` cites a real case, `anthropics/claude-code#29616`, where the built-in wildcard matcher itself did not behave as its own rules implied).

### Finding C: The rewrite catalog

Each candidate pair is drawn from `validate-bash-command.sh` (blocks/asks) or from a documented allow-list miss (a legitimate command that simply fails to auto-approve, with no competing block). "Mechanically safe" means: deterministic, no invented parameter, and (per Finding A3) not competing with an existing `exit 2` block on the same original input.

| # | Wrong shape | Canonical shape | Mechanically safe today? | Why / why not |
|---|---|---|---|---|
| 1 | `GIT_MERGE_AUTOEDIT=no git hf <flow> finish <ver> "<msg>"` | `bash ~/.claude/scripts/hubflow.sh <flow> finish <ver> "<msg>"` | **Yes** | No competing block in `validate-bash-command.sh` for this shape — it is a pure allow-list miss (per CLAUDE.md § HubFlow Policy: "prompts on every release/hotfix because a leading VAR=value prefix never matches the allow-list"), same class as `redirect-ecs-scale.sh`'s target. 1:1 field mapping, no invented values. |
| 2 | `cd <dir> && git <subcmd>` / `cd <dir> && gh <subcmd>` | `git -C <dir> <subcmd>` / `gh -R <owner>/<repo> <subcmd>` | **Yes, narrowly** | `validate-bash-command.sh:98–117` blocks the `cd && ` chain generically; a redirect could special-case ONLY the git/gh sub-shape (deterministic path substitution), because a single hook call cannot split into two tool calls (Finding A4/schema — `updatedInput` is one object, one `command` string; there is no field to enqueue a second call). For `gh -R`, the `<owner>/<repo>` cannot always be derived from `<dir>` alone without a `git remote` read, so this sub-case needs the redirect to shell out and read the remote first — still deterministic, but a wider blast radius than a pure string substitution. |
| 3 | `cd <dir> && bundle exec <cmd>` (or `rails`/`rake`/`rspec`/`rubocop`/`bin/*`) | `bash ~/.claude/scripts/ruby.sh --dir <dir> <cmd>` | **Yes** | `ruby.sh` already accepts `--dir` for exactly this case (Ruby Version Manager doc: "subagents ... must pass `--dir <abs-project-dir>`"). The mapping from `cd <dir> && <ruby-tool> <args>` to `ruby.sh --dir <dir> <tool> <args>` is a pure, deterministic string reshuffle with no invented values. |
| 4 | `cd <dir> && <arbitrary other tool>` | — | **No** | No general rewrite exists; the block message itself lists command-specific escape hatches only (`git -C`, `gh -R`, `BUNDLE_GEMFILE=`, "pass path as argument"), confirming there is no universal answer — CLAUDE.md § Working Directory Behavior: "When no canonical pattern applies — surface the constraint to the engineer." |
| 5 | Multi-line `\`-continued command | Single-line join of the same tokens | **Yes — the safest general-purpose candidate found** | Purely a whitespace/continuation normalization; it does not change which tokens run, only how they are joined. `\`+newline stripped, joined with a single space. No judgment, no invented values, and (unlike items 1–4) not scoped to one specific tool — this is the one candidate in the catalog that is genuinely general-purpose. Documented root cause: CLAUDE.md § Bash Single-Line Policy, citing `anthropics/claude-code#11932` ("the Claude Code permissions matcher does string-prefix match against permissions.allow without normalizing line continuations"). |
| 6 | `<allow-listed-cmd>; echo "exit:$?"` decoration | Bare `<allow-listed-cmd>` | **Explicitly rejected by 4Shark, on record** | CLAUDE.md § Command Safety Policy states this is "doc-only (no hook — an otherwise-allow-listed command wrapped in `; echo` is too fuzzy to detect without false positives)" — a direct, prior, documented decision AGAINST building this specific rewrite, made before this spike. |
| 7 | `RAILS_MASTER_KEY=$(cat ...) ~/.rvm/wrappers/.../bundle exec ...` | `bash ~/.claude/scripts/ruby.sh <tool> <args>` | **No — currently on the BLOCK side** | `validate-bash-command.sh:242–259` blocks this shape outright (`exit 2`) precisely because it contains `$(...)`. Per Finding A3, a parallel redirect returning `allow`+`updatedInput` on the SAME original string would lose to this block. Moving this to a rewrite requires DELETING or narrowing the existing block in `validate-bash-command.sh` — it cannot be added as a purely-additive new hook. |
| 8 | Raw `aws ec2 start-instances` / `stop-instances` | `bash ~/.claude/scripts/start-instance.sh` / `stop-instance.sh` | **No — currently on the BLOCK side** | `validate-bash-command.sh:541–557` blocks this outright (`exit 2`). Same structural point as item 7 — the fix message already gives the exact 1:1 command substitution, but per Finding A3 a purely-additive redirect hook would not win against this existing block. |
| 9 | `git checkout -b release/X.Y.Z` (plain, non-HubFlow) | `git hf release start X.Y.Z` | **No — safety-adjacent, not a pure syntax swap** | `validate-bash-command.sh:261–282` blocks this because `git hf release start` performs precondition CHECKS (base is `develop`, base equals `origin`, clean tree, tag absent — CLAUDE.md § HubFlow Policy) that `checkout -b` skips entirely. The two commands are not behaviorally equivalent — `git hf release start` can legitimately FAIL where `checkout -b` would have "succeeded" differently. Also touches § Git Tag & Version Policy's tag-adjacent-action territory (starting a release is a version-number-adjacent step). Best classified as a SAFETY boundary case, not a FORM one — see Finding D. |
| 10 | Infra command piped into text processing (`aws ... \| jq ...`) | Two separate calls: `aws ... > /tmp/x.json` then `jq ... /tmp/x.json` | **No — not expressible in one hook call** | `updatedInput` replaces the CURRENT tool call's arguments; the schema has no field to enqueue a second, later tool call (Finding A1's full schema list: `hookEventName`, `permissionDecision`, `permissionDecisionReason`, `updatedInput`, `additionalContext` — nothing else). This is a hard capability boundary, not a design choice. |
| 11 | Work script piped into `tail`/`head`/`sed -n` | `bash <script> > /tmp/out.log 2>&1` then a separate `Read` | **No — not expressible in one hook call** | Same structural reason as item 10 — the follow-up read is necessarily a second tool call. |

### Finding D: The safety/form boundary

**SAFETY blocks — never rewrite, block-and-tell only.** Evidence, each a distinct `validate-bash-command.sh` block whose stated purpose is to stop an IRREVERSIBLE or POLICY-violating action, not to correct a shape: `git reset --hard` (lines 373–388, "unstaged changes have no reflog entry"), `git clean -f` (390–403, "permanently deletes untracked files. Not in git history"), `git branch -D` (405–418, "commits become unreachable"), `git checkout .` / `-- <path>` (437–451, "there is no recovery path"), `git push --force` to `develop`/`master` (306–371), `gh pr merge` / `gh api .../merge` (453–469, "Merging a PR is the engineer's decision, not the agent's [...] The agent merged a PR on its own once"), OS-level DB management (471–500, "the engineer ends up with an idle DB process consuming machine resources permanently"), plain `release`/`hotfix` branch creation (261–282, item 9 above), and branch creation in the main working tree (284–304, where the missing parameter is a worktree NAME the hook cannot invent). Each of these is either (a) genuinely irreversible with no equivalent-outcome substitute, or (b) requires a judgment call / invented parameter (a worktree name, a version number, an engineer's explicit go-ahead) that a hook has no source for. Every one of these block messages ends with "the engineer runs the command manually" — never "here is the corrected command, retry."

**FORM blocks — the command is legitimate, only the shape is wrong; rewrite is the whole point.** Evidence: the ask-bypass normalization block itself (502–539) exists ONLY to re-route a wrong SHAPE (env-prefixed, `env`-wrapped, or absolute-pathed write command) back into the SAME `ask` prompt the bare form would have hit — it is not trying to stop the write, only to stop the write from silently skipping its own gate. `redirect-terraform.sh` and `redirect-ecs-scale.sh` both target pure FORM problems: the underlying operation (a terraform read, an ECS scale) is already sanctioned; only the invocation syntax was wrong. Items 1, 2, 3, 5 in the catalog (Finding C) are FORM problems in this sense.

**The load-bearing sub-finding — a redirect cannot silently cross the safety boundary by accident.** Per Finding A3's worked example and the official deny/block-over-allow precedence, a NEWLY ADDED purely-additive redirect hook returning `allow`+`updatedInput` on a shape that `validate-bash-command.sh` ALSO blocks with `exit 2` on the same original string would lose to the existing block (this is the observed behavior for the terraform `-out` case, and the documented rule for every other case in items 7, 8, 9 of Finding C). This means: today's safety blocks are NOT at risk of being silently bypassed merely by someone adding a new redirect hook elsewhere in `settings.json` — the only way to move a currently-blocked shape onto the rewrite side is to deliberately edit the block script itself to stop matching that shape. That edit is a visible, reviewable, single-purpose change (exactly the kind of change `Configuration Changes Policy` already routes through a `dot-claude` PR) — not a side-effect of building a redirect elsewhere.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Generalized `redirect-bash-form.sh` (Option A) | One file to maintain; catalog is the code | Shared-logic bug risks every shape at once; diverges from today's per-tool pattern | Finding C, `redirect-terraform.sh`/`redirect-ecs-scale.sh` as precedent |
| N per-tool redirects, continue today's pattern (Option B) | Proven (2 working examples); isolated blast radius per script | New shape = new hook registration; boilerplate duplication across files | `settings.json:198–346` (12 existing Bash-matched hook entries) |
| Block-and-tell only, no rewrite (Option C) | Zero exposure to the Finding A2/A3 uncertainty; no new mechanism | Does not meet the engineer's stated goal ("the mechanism enforces it"); costs a retry every time | `validate-bash-command.sh` (the existing pattern for every currently-blocked shape) |
| Rewrite-and-announce (Option D) | Meets the stated goal while keeping a visible audit trail | Still exposed to Finding A2/A3 for any NEWLY-migrated shape; `additionalContext` competes for the 10,000-char cap | Finding A1, A4 |
| Reimplementing the full permission matcher inside a hook | Would let a hook answer "will this actually auto-approve" with certainty | No first-party function to call (Finding B2); the matcher's exact semantics are nontrivial and have their OWN documented bugs (`auto-approve-aws-readonly.sh:14–20`, citing `anthropics/claude-code#29616`) | Finding A5, B2 |
| Pattern-matching only known wrong shapes (no matcher reimplementation) | Matches what 4Shark already does for both existing redirects; smaller, auditable surface | Only covers shapes someone has already hit and cataloged — a genuinely new wrong shape gets no help until added | Finding C (the catalog itself is this approach, applied) |

## What remains uncertain

- Whether a command rewritten via `updatedInput` is re-validated against `permissions.allow`/`ask`/`deny` before running, or whether the `permissionDecision: "allow"` from the SAME hook call is simply final. Not found in official docs after four targeted queries (Finding A2). **Proposed empirical test** (not performed by this spike — main/engineer decide whether to run it): register a temporary test hook that rewrites an intentionally-not-allow-listed dummy command into an intentionally-DENY-listed dummy command via `updatedInput`, observe whether the deny fires or the tool silently runs. This would definitively answer the question without relying on inference from the one worked example in Finding A3.
- The exact precedence and last-write-wins behavior for competing `updatedInput` values from multiple parallel hooks is sourced only from a third-party blog (Finding A3), not from Anthropic. Not independently verified against Claude Code's own source (which is closed).
- Whether the existing terraform `-out` collision (Finding A3's worked example) has ever actually been exercised in a real session — this spike inferred the outcome from reading both scripts' trigger conditions and the documented precedence rule; it did not observe an actual blocked/rewritten transcript. If this exact command has never been run, the inference is sound but unconfirmed by observation.
- Whether a future Claude Code release could change the parallel-hooks-conflict resolution without a changelog entry calling it out specifically as a hook-conflict-resolution change (ADR-002 raises the same category of concern for the deny/ask/allow precedence and pins the assumption for exactly this reason).

## Suggested options for main and the engineer

See auxiliary `command-form-redirect-hook_options_1.html` for the full side-by-side comparison (pros/cons/effort/risk per option) and a neutral "decision criteria" list. Summarized:

- **Option A** — one generalized `redirect-bash-form.sh` with an internal rewrite table covering the mechanically-safe catalog entries (Finding C, items 1/2/3/5).
- **Option B** — continue today's pattern: one new redirect script per shape (`redirect-hubflow.sh`, `redirect-multiline-join.sh`, …), mirroring `redirect-terraform.sh`/`redirect-ecs-scale.sh`.
- **Option C** — no rewrite mechanism at all; invest instead in making every `validate-bash-command.sh` block message carry the exact corrected command (most already do) and rely on the agent retrying.
- **Option D** — Option A or B, plus a visible `additionalContext` announcement on every rewrite, so the correction is never fully silent.

None of the four options touch the safety-blocked shapes in Finding D (items 7, 8, 9 of the catalog) without a separate, deliberate edit to `validate-bash-command.sh` itself — that is a distinct decision from choosing among A–D, and Finding D's sub-finding is that this separation is structural, not merely a convention.

(No recommendation — surface options, let main and the engineer choose.)
