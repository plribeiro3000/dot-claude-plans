# SPIKE — A real gate for internal data in PR descriptions and commit messages

## Investigation question

The `inject-pr-commit-data-policy.sh` hook reinjects the "no internal data" rule at `gh pr create` and `git commit`, and it is a reminder: it fired on four consecutive pull requests that leaked anyway, and a later audit found eleven more leaked descriptions written over months. Is there a mechanism that is a **gate** rather than a reminder — something that can refuse the leak or catch it without depending on the author to judge their own text — and if so, which one covers 4Shark's actual usage?

The rule being enforced is § No Client/Infra Data in PR Descriptions and Commit Messages: the leak is a **named internal thing paired with how it behaves**. A bare entity name is legitimate; a behavioral description with no name is legitimate; the pairing is the defect. That shape is judgment about what a sentence conveys, which is why the existing documentation states no mechanical gate exists.

## Sources consulted

- [Hooks reference](https://code.claude.com/docs/en/hooks) — the five handler types, the `$ARGUMENTS` contract for prompt/agent hooks, the parallel-execution statement, and the experimental status of agent hooks.
- [`anthropics/claude-code` plugin-dev hook-development SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md) — Anthropic's own authoring guidance: supported events for prompt hooks, a PreToolUse denial example, the PreToolUse output shape, and the parallel-execution design implications. Preserved verbatim as auxiliary: `pr-body-leak-gate_source_1.md`.
- [GitHub — events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) — the `pull_request` activity types.
- `~/.claude/CLAUDE.md` § Bash Single-Line Policy — the 4Shark rule that decides which `gh pr create` form is available to a session.
- `~/.claude/CLAUDE.md` § Automated Dependency Updates — the existing 4Shark precedent for a workflow that posts a commit status.
- `.github/workflows/ci.yaml:3-5` in `dot-claude` — the repository's current `pull_request` trigger.
- Live API probe against `4shark/dot-claude` PR #508 — whether the body is reachable server-side.

## Findings

### Finding 1: a `prompt` hook CAN deny a PreToolUse tool call

**Evidence:**

```
**Supported events:** Stop, SubagentStop, UserPromptSubmit, PreToolUse
```

and, in the PreToolUse section, a worked example plus the output contract:

```json
{
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Validate file write safety. Check: system paths, credentials, path traversal, sensitive content. Return 'approve' or 'deny'."
        }
      ]
    }
  ]
}
```

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": {"field": "modified_value"}
  },
  "systemMessage": "Explanation for Claude"
}
```

**Source:** `pr-body-leak-gate_source_1.md:34`, `:127-142`, `:144-152` (fetched from `anthropics/claude-code`, path `plugins/plugin-dev/skills/hook-development/SKILL.md`).

**Significance:** This contradicts the claim currently written in `PULL-REQUEST-CONVENTIONS.md` and in CLAUDE.md that no mechanical gate is possible for this rule. A gate IS possible in kind: a second model call, whose only input is the tool payload and whose only job is one question, returning `deny`. That is a different tier from an injected reminder for the same reason a `Stop` hook block differs from a pre-turn reminder — the author can ignore a reminder; nothing proceeds through a `deny`. The same document also calls this the preferred type: *"### Prompt-Based Hooks (Recommended)"* (`:22`) and *"Focus on prompt-based hooks for most use cases. Reserve command hooks for performance-critical or deterministic checks."* (`:712`).

**Verification:** File fetched via `gh api repos/anthropics/claude-code/contents/... -H "Accept: application/vnd.github.raw"`. Verbatim quotes checked against the local copy. Substrings confirmed at the line numbers above in `pr-body-leak-gate_source_1.md`.

### Finding 2: the prompt hook receives the hook input JSON — for a Bash call, that is the command TEXT

**Evidence:** the hooks reference defines the field as

> `prompt` | yes | Prompt text to send to the model. Use `$ARGUMENTS` as a placeholder for the hook input JSON.

and the event-specific input for this event is

```
- **PreToolUse/PostToolUse:** `tool_name`, `tool_input`, `tool_result`
```

**Source:** [Hooks reference](https://code.claude.com/docs/en/hooks), "Prompt and agent hook fields" table; `pr-body-leak-gate_source_1.md:316`.

**Significance:** For a `Bash` tool call, `tool_input.command` is the command string. A judge wired this way reads exactly the characters of the command — nothing more. Whether it sees the PR body therefore depends entirely on whether the body is *in* the command, which Finding 5 shows it is not.

**Verification:** URL fetched. Verbatim quote checked. Substring confirmed in the "Prompt and agent hook fields" table and at `:316` of the auxiliary file.

### Finding 3: hooks on the same event run in PARALLEL and cannot see each other's output

**Evidence:**

```
All matching hooks run **in parallel**:
```

with the stated consequences:

```
**Design implications:**
- Hooks don't see each other's output
- Non-deterministic ordering
- Design for independence
```

The official reference states the same: *"All matching hooks run in parallel. If you define the same handler in more than one settings file, it runs once."*

**Source:** `pr-body-leak-gate_source_1.md:497`, `:514-517`; [Hooks reference](https://code.claude.com/docs/en/hooks).

**Significance:** This kills the most attractive workaround. The obvious repair for Finding 5 would be a two-hook pipeline — a deterministic `command` hook that reads `--body-file` and rewrites the call via `updatedInput` so the body is inline, followed by a `prompt` hook that judges the now-visible text. That composition is impossible: the two hooks run concurrently and the judge receives the original `tool_input`, not the rewritten one. Any design that assumes hook A's `updatedInput` reaches hook B is wrong.

**Verification:** Both sources fetched. Verbatim quotes checked. Substrings confirmed at the cited lines and in the reference's execution section.

### Finding 4: `agent` hooks can read files, and are experimental

**Evidence:**

> **Agent hooks** (`type: "agent"`): spawn a subagent that can use tools like Read, Grep, and Glob to verify conditions before returning a decision. Agent hooks are experimental and may change.

**Source:** [Hooks reference](https://code.claude.com/docs/en/hooks), hook handler types.

**Significance:** The `agent` type is the only local mechanism that can follow a `--body-file` path to its contents, because it is the only one with `Read`. It is therefore the only local design that covers 4Shark's real usage — and it carries an explicit stability warning from the vendor. Note also what could NOT be confirmed: the reference's own "Agent-based hooks" section was truncated in every fetch, so the agent hook's exact return contract on PreToolUse (whether it emits `permissionDecision` like a prompt hook) is **not verified here**.

**Verification:** URL fetched. Verbatim quote checked. Substring confirmed in the handler-types list. The deeper section is recorded under "What remains uncertain".

### Finding 5: 4Shark's own Bash Single-Line Policy forces `--body-file`, making a prompt-hook judge blind to the body

**Evidence:** `~/.claude/CLAUDE.md` § Bash Single-Line Policy:

> **NEVER write a Bash command as a multi-line statement.** No `\` line continuations, no embedded newlines, no array-style flag breaks. Always single-line, no matter how long the command becomes

**Source:** `~/.claude/CLAUDE.md` § Bash Single-Line Policy.

**Significance:** This is the structural constraint that decides the whole local-hook question. A real pull-request description is multi-paragraph prose, so passing it as `gh pr create --body "<text>"` requires embedded newlines, which this rule forbids; `--body "$(cat file)"` is also unavailable, because command substitution is independently gated. What remains is `--body-file <path>` — the form used throughout the session that produced this spike. A `prompt` hook judging `tool_input.command` would therefore receive a filesystem path, find no pairing in it, and approve every PR. **The gate would report clean while being structurally incapable of seeing the content it exists to judge**, which is worse than no gate: it manufactures false assurance.

**Verification:** Rule quoted verbatim from the installed CLAUDE.md. The `--body-file` usage is directly observable in this session's own tool trace (`gh pr edit 508 --body-file /tmp/pr_body_508_final.md`).

### Finding 6: the pull-request body IS available server-side, on every creation path

**Evidence:** an API probe of a real PR returns a populated body:

```
gh api repos/4shark/dot-claude/pulls/508 --jq '{has_body: (.body != null), body_length: (.body | length)}'
{"body_length":3085,"has_body":true}
```

The `pull_request` event fires on the activity types `opened` and `edited`, among others; by default a workflow runs on `opened`, `synchronize` and `reopened`, and other types are opted into with `types`.

**Source:** live probe against `4shark/dot-claude` PR #508; [GitHub — events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

**Significance:** Server-side, the body is plain text with no file indirection — the `--body-file` blindness does not exist there. A check at this layer also covers paths a local hook structurally cannot: a PR opened in the web UI, opened from another engineer's machine, opened by a session with hooks disabled, or a body edited after creation (`edited`). The trade-off is timing: the body is already published when the check runs, so this layer **detects** rather than prevents. The existing remediation (delete the revision from the PR's edit history) makes that recoverable for a description, and § No Client/Infra Data already records that a commit message has no such path.

**Verification:** Command executed and output recorded above. Activity-type list fetched and checked.

### Finding 7: `dot-claude` already triggers on `pull_request`, and 4Shark has precedent for a status-posting workflow

**Evidence:** `.github/workflows/ci.yaml:3-5`:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]
```

and `~/.claude/CLAUDE.md` § Automated Dependency Updates describes the established shape: a workflow that *"posts a commit status named `Verify Minimum Age` with state `pending`/`success`/`error`"*, made required for merge through classic branch protection.

**Source:** `.github/workflows/ci.yaml:3-5`; `~/.claude/CLAUDE.md` § Automated Dependency Updates.

**Significance:** A server-side body check needs no new machinery pattern — it is the `Verify Minimum Age` shape applied to a different subject, and the trigger it needs already exists (adding `edited` to the `types` list). The precedent also carries the enforcement half: a commit status can be made required, which converts detection into a merge block.

**Verification:** Workflow file read directly. CLAUDE.md section quoted verbatim.

### Finding 8: no Actions secret exists in `dot-claude`, and org-level secrets could not be read

**Evidence:** `gh api repos/4shark/dot-claude/actions/secrets --jq '.secrets[].name'` returned an empty list. The org-level equivalent returned:

```
{"message":"You must be an org admin or have the actions secrets fine-grained permission.", "status":"403"}
```

**Source:** live API probes.

**Significance:** Any server-side check that calls a model needs a credential in Actions. None exists at the repository level, and whether one exists at the organization level is **UNVERIFIED** — the current token cannot read that list. Provisioning a credential is a security/permission boundary and therefore the engineer's decision, not a detail to resolve inside an implementation.

**Verification:** Both commands executed; outputs recorded above. The org-level answer is explicitly marked unverified and may not sustain a conclusion.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| `prompt` hook on `Bash` matching `gh pr create` | Prevents publication; supported and vendor-recommended type; no credential to provision | **Blind to `--body-file`, which our own single-line rule forces** — approves everything while looking green | F1, F2, F5 |
| `agent` hook on the same matcher | Only local option that can `Read` the body file; genuine prevention | Vendor-marked experimental; its PreToolUse return contract unverified here | F4 |
| `command` hook that shells out to a model itself | Can read the file; deterministic wiring; not experimental | Needs a credential on every engineer's machine; slowest path; most machinery to maintain | F3 (rules out the cheaper two-hook composition) |
| Two-hook composition (command inlines body → prompt judges) | Would have solved the blindness with supported types only | **Impossible** — hooks run in parallel and cannot see each other's output | F3 |
| GitHub Action on `pull_request` (`opened`, `edited`) | Body is plain text; covers every creation path and every machine; cannot be bypassed; reuses an existing 4Shark pattern; can be made merge-blocking | Detects after publication rather than preventing; needs a model credential in Actions, which may not exist | F6, F7, F8 |
| Periodic audit of recent PR bodies | Cheapest; no critical-path latency; false positives cost nothing | Pure detection with the widest window; does not stop anything | F6 |

## What remains uncertain

- The "Agent-based hooks" section of the official reference was truncated in every fetch, so the agent hook's exact return contract on `PreToolUse` — specifically whether it emits `permissionDecision` the way a prompt hook does — is not established. This decides whether the only local design that covers our usage can actually deny.
- Whether an organization-level Anthropic API credential already exists for GitHub Actions (403 on the listing; F8).
- The false-negative rate of any model judge on this specific pairing test is unmeasured. No source claims a figure, and none should be invented; it would have to be measured against the fifteen known-leaked descriptions already identified (four from the recent PRs, eleven from the audit), which are available as a ready-made evaluation set.
- Whether a required commit status on this check would obstruct the HubFlow back-merge path, the same concern that made § Automated Dependency Updates choose classic branch protection over Repository Rulesets.

## Suggested options for the engineer

- **Option A — server-side check only.** A workflow on `pull_request` (`opened`, `edited`) that judges the body and posts a commit status, optionally required for merge. Covers every path, no `--body-file` problem, reuses the `Verify Minimum Age` shape. Detects rather than prevents; needs a credential.
- **Option B — local agent hook only.** Prevention at `gh pr create`, at the cost of building on an experimental type whose denial contract is still unverified, and which protects only machines with the hook installed.
- **Option C — both layers.** Local prevention where it works, server-side detection as the backstop that catches everything the local layer misses (other machines, web UI, later edits).
- **Option D — server-side check plus a scheduled audit** of recent descriptions, deferring any local hook until the agent type stabilizes.

## Outcome

**Option B, in its `command`-hook form — prevention before publication, not detection after it.** The deciding constraint is that a server-side check can only run once the text is already published, and a published description was public before anyone read the report; the engineer's requirement was that nothing reaches GitHub carrying the pairing, so a layer that reports after the fact does not satisfy it.

The prompt-hook variant Finding 5 rules out is avoided by making the hook a `command` type: it reads the `--body-file` off disk itself and passes the text to a separate `claude -p` call, so the judge sees the body rather than a path. `scripts/validate-pr-body-internal-data.sh` is that hook, and it fails CLOSED — an unreachable judge, an unreadable file, or an unintelligible verdict all block, inverting the fail-open posture of its `validate-*` siblings because a published body cannot be un-published.

What this does not reach is bounded and stated rather than assumed: a body the command neither carries nor points at, a `git commit` opened in an editor, and any publication from a machine without the hook, from the web UI, or by another person. The judge is a model, so a false negative stays possible.

---

> **Authoring:** written by the main session (no subagent), as time-boxed research answering the engineer's question about whether a real gate exists. Every claim carries its source; the two claims that could not be verified are marked UNVERIFIED under "What remains uncertain" and sustain no conclusion. The outcome is separated from the findings and labelled, because the findings are neutral and the choice was the engineer's.
