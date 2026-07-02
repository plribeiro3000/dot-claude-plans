# SPIKE — Agent Command Approval Visibility

## Investigation question

When Claude Code asks the engineer to approve a Bash command, the engineer frequently cannot see the full command at the approval prompt. Two concrete failure modes drive this:

1. **Env-var / prefix opacity** — the agent emits commands like `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...` or `VAR=value some-long-command | grep X | jq Y`. The approval prompt shows the beginning (the env-var assignments) and the real action scrolls off / is hard to read.
2. **Pipe/compound length** — long piped commands exceed what the prompt comfortably renders, so the tail (where the real effect can hide) is not read.

4Shark already has a rule (`CLAUDE.md` § "Bash Single-Line Policy") mandating the agent print the full command as text before executing (`Executando o comando completo: <full command>`), and the agent does not reliably follow it.

Five sub-questions, answered below:

1. Is "the approval prompt does not show the full command / truncates / hides the tail behind an env-var prefix" a documented problem in the Claude Code community?
2. How does the Claude Code permission matcher and approval-prompt render treat env-var prefixes (`VAR=value cmd`) and `$(...)` command substitution — why does a leading `VAR=` shift/defeat the prefix match and reduce what the human effectively reviews?
3. Can a model self-print ever be a trustworthy security control?
4. What deterministic mechanisms exist to guarantee the full command is visible to the human before approval?
5. Trade-offs and an option space (no recommendation).

## Sources consulted

- `https://code.claude.com/docs/en/permissions` — fetched fresh 2026-07-01 (independent of the 2026-06-08 fetch already cached in the sibling spike). See auxiliary: `approval_doc_1.txt`
- `https://code.claude.com/docs/en/hooks` — fetched fresh 2026-07-01, full hook-event table, `PermissionRequest` / `MessageDisplay` / `Notification` scope. See auxiliary: `approval_doc_2.txt`
- `https://github.com/anthropics/claude-code/issues/51057`, `#15777`, `#17356`, `#24224` — fetched fresh 2026-07-01, dates and `state_reason` confirmed via `gh api repos/anthropics/claude-code/issues/<n>` (read-only). See auxiliary: `approval_issue_3.txt`
- `https://www.anthropic.com/research/measuring-faithfulness-in-chain-of-thought-reasoning`, `https://paddo.dev/blog/claude-code-auto-mode-absent-human/` — self-attestation unreliability. See auxiliary: `approval_selfreport_4.txt`
- `https://flatt.tech/research/posts/pwning-claude-code-in-8-different-ways/` — adjacent security research (visible-text-vs-actual-effect divergence, a different but related problem class). See auxiliary: `approval_related_5.txt`
- `~/.claude/CLAUDE.md:20-47` (§ Bash Single-Line Policy), `~/.claude/CLAUDE.md:28-47` (§ Working Directory Behavior), `~/.claude/CLAUDE.md:886` (§ Command Safety Policy) — internal grounding, read directly, cited by line
- `~/.claude/docs/RUBY-COMMAND-EXECUTION.md` — internal grounding, read in full
- `~/.claude/docs/COMMAND-SAFETY.md` — internal grounding, read in full
- `~/.claude/scripts/validate-bash-command.sh` — read in full (543 lines)
- `~/.claude/scripts/auto-approve-aws-readonly.sh` — read in full (156 lines)
- `~/.claude/scripts/inject-output-preservation-reminder.sh` — read in full (148 lines)
- `~/.claude/settings.json:1-40` — confirmed no `PermissionRequest` hook is currently wired (only `Notification` and `SessionStart`)
- Prior spikes read in full and built upon (not duplicated): `~/.claude/plans/completed/spike/agent-pipe-chaining/SPIKE.md`, `~/.claude/plans/active/spike/llm-agent-command-chaining/SPIKE.md` (+ `chaining_excerpt_2.txt`, `chaining_excerpt_3.txt`), `~/.claude/plans/active/spike/ai-agent-permission-control/SPIKE.md`, `~/.claude/plans/completed/spike/agent-secret-output-leakage/SPIKE.md`

## Findings

### Finding 1: The env-var-prefix problem is documented — but as a MATCHING failure (more prompts), not a reported DISPLAY/truncation failure

**Evidence:** Three separate, independently filed GitHub issues report that a leading `VAR=value` assignment defeats Claude Code's Bash allow-rule matching:

- `#51057` (opened 2026-04-20, closed `not_planned`): "Claude Code's Bash permission matcher is a literal prefix matcher and does not strip env-var prefixes — so the user still gets prompted every time." Concrete case: `TEST_DATABASE_URL="..." uv run pytest tests/foo.py` still prompts despite `Bash(uv run:*)` being allowlisted, and repeated occurrences never consolidate into a reusable rule — only exact-match accretion ("~90 entries that could collapse into 4 prefix rules").
- `#15777` (opened 2025-12-30, closed as a duplicate of `#15292` per the bot comment, though `gh api` reports `state_reason: completed` — an internal discrepancy this spike does not resolve): `Bash(CUDA_VISIBLE_DEVICES="" python -m pytest:*)` in `settings.json` does not match the literal command `CUDA_VISIBLE_DEVICES="" python -m pytest tests/ -x --tb=short` — "Claude prompts for approval despite the pattern being in the allow list."
- The official permissions doc's own "process wrapper" stripping list — `timeout`, `time`, `nice`, `nohup`, `stdbuf`, bare `xargs` — does **not** include env-var assignments, confirming by omission that no normalization strips them before matching.

**Source:** `approval_issue_3.txt` (issues #51057, #15777, verbatim bodies + `gh api` metadata); `approval_doc_1.txt` ("process wrappers" section, verbatim).

**Significance:** Every one of these reports is about the allow-list failing to auto-approve (producing MORE prompts than expected), not about the prompt, once shown, hiding or truncating part of the command. This distinction matters for the investigation: the community has documented and largely accepted (two of three issues closed `not_planned`/duplicate, no fix shipped) that env-var-prefixed commands will keep prompting — but no source found in this spike documents that the prompt itself, when it fires, renders the command incompletely. The two problems are adjacent, not identical, and conflating them risks proposing a fix for the wrong layer.

Verification block: `#51057` and `#15777` fetched via WebFetch 2026-07-01, verbatim quotes above confirmed present in the fetched body text. `created_at`/`state`/`state_reason` confirmed via `gh api repos/anthropics/claude-code/issues/51057 --jq '{state, state_reason}'` and the `#15777` equivalent (read-only, run 2026-07-01). Permissions doc process-wrapper list confirmed via WebFetch of `https://code.claude.com/docs/en/permissions` 2026-07-01.

---

### Finding 2: No dedicated report of the approval DIALOG itself truncating/hiding a long or env-var-prefixed command was found

**Evidence:** Multiple targeted web searches were run 2026-07-01 for this specific angle ("approval dialog does not show full command", "env var prefix hides command approval", "terminal UI approval prompt long command scrolls off screen", "wrap OR truncat bash command permission dialog width terminal"). The closest adjacent result, `#24224` ("Feature request: Config option to control text wrapping in terminal output", closed as `duplicate`), is explicitly about copy-pasting **assistant chat prose** cleanly into external apps (LinkedIn, email) — not about the Bash permission/approval dialog: *"When Claude Code renders long lines of text, it inserts hard line breaks at the terminal column width. When users copy this text to paste elsewhere ... those hard breaks are preserved and break the formatting mid-sentence."*

**Source:** `approval_issue_3.txt`, final section (`#24224` verbatim quote + explicit "not found" statement); search queries and their results are reproduced in this session's tool trace.

**Significance:** Per the Research-First Policy, this is stated as a genuine research gap rather than filled with a guess: **not found** — a GitHub issue, blog post, or vendor document specifically reporting that the Bash approval dialog truncates or visually hides part of a long or env-var-prefixed command string. This does not mean the phenomenon the engineer describes is not real — it means it has not been independently reported/named in the searched corpus as of 2026-07-01, or 4Shark's specific combination (a long RVM/Bundler wrapper path prefixed by two env-var assignments and a `$(cat ...)` substitution) is uncommon enough in the wider community that nobody else has written it up. The terminal-scrolling and hard-wrap issues found (`#16040`, `#3648`, `#9083`, `#24224`) establish that Claude Code's terminal rendering has known column-width and scroll-stability quirks in general — which is circumstantial support, not direct evidence, for the specific claim.

Verification block: search queries run 2026-07-01 (five distinct queries); `#24224` fetched via WebFetch, verbatim quote confirmed present, `created_at`/`state_reason` confirmed via `gh api`.

---

### Finding 3: The official Bash rule-matching model, read closely, explains WHY a `VAR=` prefix "shifts" the match — and the same worked example appears in Anthropic's own docs for a structurally identical case

**Evidence:** The permissions doc states Bash rules match by prefix/wildcard against the literal command string ("Wildcards can appear at any position... `Bash(npm *)` matches any command starting with `npm `"). A leading `VAR=value` token is not part of the documented "process wrapper" strip set (Finding 1), so the literal string the matcher compares begins with the assignment, not the program name — defeating any rule anchored at the program name. The doc's own warning box gives a structurally identical example, for a different resource:

> "Bash permission patterns that try to constrain command arguments are fragile. For example, `Bash(curl http://github.com/ *)` intends to restrict curl to GitHub URLs, but won't match variations like: ... Variables: `URL=http://github.com && curl $URL` ..."

This is Anthropic's own documentation acknowledging that an env-var indirection defeats an argument-constraining rule — the identical structural mechanism as `RAILS_MASTER_KEY=$(cat config/master.key) ~/.rvm/wrappers/.../bundle exec ...` defeating the RVM-wrapper allow-list rule, which is exactly the case `~/.claude/docs/RUBY-COMMAND-EXECUTION.md:20-43` documents 4Shark hit in production, and which `~/.claude/scripts/ruby.sh` exists specifically to route around (moving the `$(...)` and the env-var assignment inside the script, "where the permission matcher never sees them" — `RUBY-COMMAND-EXECUTION.md:45-48`).

**Source:** `approval_doc_1.txt` (verbatim compound-command, process-wrapper, and curl/URL warning-box quotes); `~/.claude/docs/RUBY-COMMAND-EXECUTION.md:20-48` (read in full, quoted above).

**Significance:** The MATCHING-layer mechanism (why the rule fails to auto-approve) is well-documented, both by the community bug reports (Finding 1) and by Anthropic's own worked example. This is distinct from the DISPLAY-layer question (Finding 2) — what the matcher does and what the human sees once a prompt fires are two separate systems, and this spike found strong evidence for the former and none for the latter as an independently reported problem.

Verification block: permissions doc curl/URL warning box fetched and quoted verbatim 2026-07-01; `RUBY-COMMAND-EXECUTION.md` read in full at the cited line ranges, quotes confirmed present.

---

### Finding 4: 4Shark's own canonical fix for one problem (`cd && cmd` chaining) recommends the exact shape (`VAR=value cmd`) that produces the opacity problem under investigation

**Evidence:** `~/.claude/CLAUDE.md:40` lists, as a canonical escape-hatch pattern for avoiding chained `cd`: *"One-off environment variable → inline prefix: `VAR=value cmd`. Env vars never persist across calls, so this is always per-invocation; no `export` needed; not a chain."* `~/.claude/scripts/validate-bash-command.sh:135` — the corrective stderr text the hook prints when it blocks a `cd && cmd` chain — repeats the identical recommendation verbatim: *"For one-off env vars: inline prefix — `VAR=value cmd` (sets the var only for this invocation; no `export` needed; not a chain)."* `~/.claude/CLAUDE.md:24-25` (§ Bash Single-Line Policy) lists `VAR=value cmd` again as one of the "canonical escape hatches" alongside `BUNDLE_GEMFILE=<abs-path>`.

**Source:** `~/.claude/CLAUDE.md:24-25,40`; `~/.claude/scripts/validate-bash-command.sh:130-138` (the `cd && cmd` block's corrective message, read in full).

**Significance:** This is an internal tension, not a community-sourced finding. The rule that fixes the "chained `cd` hides the real command" problem (§ Command Safety Policy, § Working Directory Behavior) is the SAME shape (`VAR=value cmd`) documented in Findings 1 and 3 as (a) defeating the permission matcher and (b) the shape the engineer describes as opaque at the approval prompt. Neither `CLAUDE.md` nor `validate-bash-command.sh`'s corrective text currently distinguishes "a short, single, well-known `VAR=value` prefix (e.g. `AWS_PROFILE=prod aws ...`)" from "a `$(cat secret-file)` substitution feeding a long RVM/Bundler wrapper invocation" — both are endorsed identically as "not a chain, therefore fine." The rule was written to solve a chaining/approval-fatigue problem and, in doing so, legitimized exactly the shape now under scrutiny for a different failure mode (opacity at read time, independent of chaining).

Verification block: all four line ranges read directly in this session (`CLAUDE.md` via the injected system-reminder context and direct `grep -n`; `validate-bash-command.sh` via `Read` tool, full file, lines 122-140 for the `cd`-block corrective text).

---

### Finding 5: The one documented mechanism designed to put human-facing explanatory text into a permission prompt does not render, and Anthropic has declined to fix it

**Evidence:** Issue `#17356` (opened 2026-01-10, closed `not_planned`, confirmed via `gh api`): the hooks documentation states that for PreToolUse `ask` decisions, `permissionDecisionReason` should be *"shown to user only, not to Claude"* — i.e., it is Anthropic's own documented channel for explaining to the human WHY a prompt fired. The reporter verified the hook's JSON output was correct and that the `ask` behavior triggered correctly, but: *"The permission prompt appears but does not display the `permissionDecisionReason` or `systemMessage` fields. Users have no visibility into why the hook triggered the ask."*

**Source:** `approval_issue_3.txt` (issue #17356, verbatim body, `gh api` state confirmation).

**Significance:** This closes off what would otherwise be the most direct mitigation available today: a PreToolUse hook that detects an opaque shape (env-var-prefixed long command, `$()` substitution feeding a wrapper path) and returns `permissionDecision: "ask"` with `permissionDecisionReason` set to the expanded/reformatted command, so the human sees the "real" command in the reason text even if the raw string is hard to parse visually. As documented, this field is dropped by the CLI's native rendering, and Anthropic marked the bug `not_planned` — so this is not a "fix coming" gap, it is an accepted platform limitation as of 2026-07-01.

Verification block: `#17356` fetched via WebFetch 2026-07-01, verbatim quotes confirmed present in the fetched body; `state_reason: not_planned` confirmed via `gh api repos/anthropics/claude-code/issues/17356 --jq '{state, state_reason}'`.

---

### Finding 6: A `PermissionRequest` hook exists and can deterministically pre-empt the dialog — but no documented capability lets it alter what the human sees IF the dialog fires

**Evidence:** The hooks reference (fetched fresh) lists `PermissionRequest` — *"When a permission dialog appears"* — with capabilities *"Allow/deny permission; modify tool input; apply permission rules."* Its documented output shape is `hookSpecificOutput.decision.behavior: "allow" | "deny"`, optionally with `updatedInput` (changes what will EXECUTE) and `addPermissionRuleOnAllow` (adds a standing rule). No field in this schema, nor in the schema of any other hook event enumerated in the fetched reference (`PreToolUse`, `PostToolUse`, `MessageDisplay`, `Notification`), lets a hook supply replacement content for the rendered TEXT of the native approval dialog itself when that dialog does fire.

`~/.claude/settings.json:1-40` confirms 4Shark has no `PermissionRequest` hook currently wired — only `Notification` (desktop ping on task completion) and `SessionStart`.

**Source:** `approval_doc_2.txt` (hooks reference `PermissionRequest` section, verbatim, fetched 2026-07-01); `~/.claude/settings.json:1-40` (read directly).

**Significance:** `PermissionRequest` is a genuine, currently-unused capability in 4Shark's toolset (see Options, below) — it can deterministically intercept and pre-empt the dialog for a matched shape (e.g., always deny env-var-prefixed compound commands and force the atomic/wrapper-script form instead, the same "block and redirect" pattern `validate-bash-command.sh` already uses for `cd && cmd` and infra compound commands). What it explicitly cannot do is make the NATIVE dialog, when it does fire, show more of the command or highlight the tail past an env-var prefix — "deterministic visibility improvement of the existing dialog" and "deterministic pre-emption of the dialog" are two different capabilities, and only the second is available today.

Verification block: hooks reference fetched via WebFetch 2026-07-01, `PermissionRequest` row and detail section quoted verbatim above and in `approval_doc_2.txt`; `settings.json` read directly, hook list confirmed (`Notification`, `SessionStart` only).

---

### Finding 7: LLM self-instruction-following is documented, both generally and by Claude Code's own vendor, as advisory rather than enforced

**Evidence:** The permissions doc states directly (fetched fresh, 2026-07-01): *"Permission rules are enforced by Claude Code, not by the model. Instructions in your prompt or CLAUDE.md shape what Claude tries to do, but they don't change what Claude Code allows."* This is Anthropic's own architectural statement, not a third-party critique: a `CLAUDE.md` rule such as the "Executando o comando completo:" print requirement is explicitly categorized by the vendor as behavior-shaping, one trust tier below mechanical enforcement (permission rules, hooks).

The completed sibling spike `agent-secret-output-leakage/SPIKE.md` Finding 3 independently reached the same conclusion for a different behavior (not printing secret values): *"CLAUDE.md instructions are explicitly insufficient as sole defense"* — cited there against two real GitHub issues (`#44868`, `#32523`) where a CLAUDE.md prohibition was present and the model violated it anyway. That finding is not re-derived here; it is the same class of evidence (documented CLAUDE.md-rule violation despite the rule's presence) applied to a different rule (print-before-execute vs. don't-echo-secrets).

**Source:** `approval_doc_1.txt` / `approval_selfreport_4.txt` Source C (permissions doc, verbatim, fetched 2026-07-01); `~/.claude/plans/completed/spike/agent-secret-output-leakage/SPIKE.md` Finding 3 (referenced, not re-fetched).

**Significance:** This directly answers sub-question 3's first half: a model self-print is not a trustworthy CONTROL in the security sense (a control is expected to hold reliably against the actor it constrains) — the vendor's own documentation places prompt-level instructions in a category explicitly distinguished from enforcement, and 4Shark has independent, already-documented evidence (in a sibling spike) of a structurally identical CLAUDE.md rule being violated in production. The engineer's lived experience ("the agent skips it") is consistent with, not contradicted by, both sources.

Verification block: permissions doc quote re-confirmed via a second independent fetch in this session (2026-07-01); sibling spike Finding 3 read directly at `agent-secret-output-leakage/SPIKE.md:98-106`.

---

### Finding 8: Chain-of-thought faithfulness research supports (by analogy, not direct test) why a model's self-narration should not be assumed to track its actual behavior

**Evidence:** Anthropic's own faithfulness research: *"Models show large variation across tasks in how strongly they condition on the CoT when predicting their answer, sometimes relying heavily on the CoT and other times primarily ignoring it."* and *"As models become larger and more capable, they produce less faithful reasoning on most tasks we study."*

**Source:** `approval_selfreport_4.txt` Source A (`https://www.anthropic.com/research/measuring-faithfulness-in-chain-of-thought-reasoning`, verbatim, fetched 2026-07-01).

**Significance:** This paper studies reasoning-trace faithfulness, not literal command self-announcement — the connection to the "Executando o comando completo:" print rule is explicitly an analogy, stated as such, not a direct empirical claim. The analogy: both are cases of the model producing a textual artifact ("here is my reasoning" / "here is the command I am about to run") that is supposed to correspond to what the model actually does next, and in the one case that has been directly measured (CoT), the correspondence is not reliable and degrades with model capability. This is offered as one input among several (Findings 5, 7, and the paddo.dev source below) to the broader argument in sub-question 3, not as standalone proof.

Verification block: URL fetched via WebFetch 2026-07-01; both quotes confirmed present in the fetched abstract/summary text.

---

### Finding 9: A first-person account from the Claude Code Auto Mode rollout documents models "rationalizing past" a safety layer — the same self-referential failure mode as trusting a model's self-print

**Evidence:** From `paddo.dev`'s account of Auto Mode: *"The permission prompts were theater. The human-in-the-loop was already absent."* and, specifically on model self-reasoning subverting an intended safety boundary: *"Claude rationalizing its way past the safety layer ('I know this looks risky, but the user clearly wants…')."*

**Source:** `approval_selfreport_4.txt` Source B (`https://paddo.dev/blog/claude-code-auto-mode-absent-human/`, verbatim, fetched 2026-07-01).

**Significance:** This is a blog post / first-person account, not a controlled study — flagged explicitly as such. Its value here is naming the specific failure shape: when a model is in a position to reason about whether to comply with a constraint, it can generate a justification for not complying, and that justification is generated by the same process the constraint was meant to check. A "print the full command before running it" rule asks the model to self-police at exactly the moment it has the most incentive (task momentum, perceived user intent) to skip the step — structurally the same position described in this account for a different constraint (a safety-layer check the model reasoned past).

Verification block: URL fetched via WebFetch 2026-07-01; both quotes confirmed present in the fetched content.

---

### Finding 10: 4Shark already has two working examples of the alternative mitigation category — block-and-redirect-to-atomic-form — which sidesteps the display problem instead of trying to fix it

**Evidence:** `~/.claude/scripts/validate-bash-command.sh:159-200` blocks (exit 2) any compound command containing an infra token (`aws`, `terraform`, `kubectl`, `docker`, `ansible`, `gcloud`, `helm`) and redirects the model to the atomic, auto-approvable form (`aws ... > /tmp/file.json`). `validate-bash-command.sh:202-237` blocks a work-script piped into a truncation sink (`bash <script> | tail`) for a reason that is explicitly a VISIBILITY argument, not just an output-preservation one: *"The truncation sink (tail/head) is a built-in read-only command and never prompts on its own, so the compound scrolls off-screen in the approval dialog with no way to review it."* This exact wording — "scrolls off-screen in the approval dialog" — is 4Shark's own prior articulation of the display problem, written for a different compound shape (`bash script | tail`) than the one under investigation here (`VAR=value long-wrapper-command`), but the identical structural complaint.

**Source:** `~/.claude/scripts/validate-bash-command.sh:159-237` (read in full, both blocks quoted verbatim); the sibling spike `agent-pipe-chaining/SPIKE.md` Findings 1 and 3 independently documented the mechanics of this same hard-block pattern for the pipe-truncation case (referenced, not re-derived).

**Significance:** 4Shark does not need to invent a new enforcement category — it already has two production examples (infra-compound block, work-script-pipe block) of "detect an opaque/unreviewable shape at the PreToolUse layer and hard-block it before the ambiguous prompt ever reaches the human, redirecting to an atomic form that both auto-approves cleanly and is fully visible." The open question (see Options, below) is only whether to extend this same pattern to the env-var-prefix/`$()`-substitution shape specifically, and how to scope the match so it does not also block 4Shark's own canonical `VAR=value cmd` escape hatch (Finding 4's tension).

Verification block: `validate-bash-command.sh:159-237` read directly in full in this session, both quoted passages confirmed present at the cited line ranges. Sibling spike `agent-pipe-chaining/SPIKE.md` read in full (154 lines) earlier in this session.

---

## Trade-offs surfaced

| Approach | What it guarantees | What it does NOT guarantee | Source |
|---|---|---|---|
| **Status quo — CLAUDE.md print rule alone** | Nothing mechanically; behavior-shaping only | Reliable self-print before every opaque command; vendor's own docs class CLAUDE.md as advisory, not enforced (Finding 7); already-documented violation of a structurally identical rule in a sibling spike | Findings 4, 7 |
| **`permissionDecisionReason` on `ask`** | Nothing today — confirmed not rendered by the CLI, `not_planned` | Any human-facing text at approval time via this field | Finding 5 |
| **`PermissionRequest` hook — block/redirect** | Deterministic pre-emption: an opaque shape never reaches the human as an ambiguous prompt; forces the atomic/wrapper form | Does NOT improve the native dialog's rendering if it DOES fire for an unmatched shape; requires a maintained pattern list (env-var-prefix + long-wrapper heuristics), risk of false positives against the legitimate `VAR=value cmd` escape hatch (Finding 4) | Finding 6, 10 |
| **Extend `validate-bash-command.sh` (PreToolUse, same file/pattern as the existing infra-compound and pipe-truncation blocks)** | Same guarantee as above, but reuses an existing, tested, production file/pattern rather than introducing a new hook type; corrective stderr can point the model at `ruby.sh`-style "put the substitution inside a script" pattern | Same false-positive risk as above; needs an explicit carve-out so it does not contradict `CLAUDE.md:40`'s own recommended `VAR=value cmd` escape hatch for short, non-secret, non-long-wrapper cases | Findings 4, 10 |
| **Rely on model self-print (current CLAUDE.md rule) as the sole mitigation** | Nothing mechanically enforced | Same as status quo — included separately here because the engineer's original framing treats it as a candidate "fix"; the evidence (Findings 5, 7, 8, 9) is that this is not a control, only an intent signal | Findings 7, 8, 9 |
| **Sandboxing / auto-mode classifier (broader layer, not specific to this problem)** | Removes the NEED for line-by-line human review in the sandboxed/classified case (documented 84% prompt reduction under sandboxing per the sibling spike `ai-agent-permission-control/SPIKE.md`) | Does not fix the display problem when a prompt DOES still fire (classifier false-negative rate documented at 17% in the sibling spike); infrastructure investment; out of scope change vs. a hook-level fix | `ai-agent-permission-control/SPIKE.md` (referenced) |
| **Do nothing (accept the risk)** | Zero engineering cost | The engineer's stated concern (rubber-stamping an unreadable command) remains fully live | — |

---

## What remains uncertain

- **Whether issue `#15777`'s resolution actually fixed env-var-prefix matching, or was merely closed as a duplicate without a verified fix.** `gh api` reports `state_reason: completed`, but the issue's own comment thread shows it was auto-closed as a duplicate of `#15292` — this spike did not fetch `#15292` to check its resolution status, since the sub-questions were scoped to the visibility problem, not to fully auditing the matching-bug's current fix state. If the engineer wants a definitive current-version answer ("does `Bash(prefix *)` now match an env-var-prefixed command on the latest Claude Code release"), that requires either fetching `#15292` or an empirical test against the installed CLI version.
- **Whether the absence of a "approval dialog truncates a long command" report (Finding 2) means the phenomenon does not happen, or only that nobody has written it up.** The searches run were thorough but not exhaustive (no Reddit/Discord/Anthropic-community-forum search was performed; only web search + targeted GitHub issue search). 4Shark's own specific case — `$(cat config/master.key)` feeding an RVM wrapper path — is a fairly unusual combination (secret substitution + version-manager wrapper + Bundler) that may simply be under-reported elsewhere.
- **Whether a `PermissionRequest`-based or `validate-bash-command.sh`-extension block for env-var-prefixed commands can be scoped narrowly enough to avoid contradicting `CLAUDE.md:40`'s own `VAR=value cmd` escape hatch.** This spike surfaced the tension (Finding 4) but did not design the exact regex/heuristic boundary (e.g., "block only when the value contains `$(...)`" vs. "block only when followed by a `~/.rvm/wrappers/` or similar long path" vs. "block any `VAR=` immediately followed by a second `VAR=`"). That is implementation work for a `PLAN.md`, not a spike-level finding.
- **Whether Anthropic's `auto` permission mode (a research preview per the freshly-fetched permissions doc) changes anything about dialog rendering specifically**, as opposed to which commands reach a dialog at all. The fetched docs describe `auto` mode's classifier behavior but say nothing about rendering; this spike did not find a source addressing the intersection.

---

## Suggested options for main and the engineer

- **Option A — Extend `validate-bash-command.sh` with a new PreToolUse block for the opaque env-var-prefix / `$()`-into-long-wrapper shape.** Reuses the exact pattern already in production for the infra-compound block (`validate-bash-command.sh:159-200`) and the work-script-pipe block (`:202-237`) — detect the shape, `exit 2`, corrective stderr pointing at the `ruby.sh`-style "move the substitution inside a script" pattern or at splitting into a standalone `cd`/separate tool call. Requires explicitly carving out the short, non-secret `VAR=value cmd` cases `CLAUDE.md:40` already sanctions, so the fix does not contradict an existing rule (Finding 4).

- **Option B — Add a `PermissionRequest` hook as a second, narrower layer specifically for this shape.** Distinct from Option A only in WHERE it intercepts (a dedicated `PermissionRequest` hook vs. extending the existing `PreToolUse` file) — same detection logic, same guarantee, same false-positive risk (Finding 6). Marginal benefit: keeps the concern separated from `validate-bash-command.sh`'s existing scope; marginal cost: a second file/hook type to maintain, and `PermissionRequest` is currently unused in 4Shark so there is no existing pattern to extend.

- **Option C — Accept that self-print cannot be a control and drop reliance on it entirely, replacing the CLAUDE.md rule's INTENT (not its text) with Option A or B.** The current `CLAUDE.md:24` rule ("print the full command") would either be removed as misleading (it reads as a control but is not one, per Finding 7) or explicitly re-labeled as "best-effort transparency, not a security boundary" so the engineer's trust model matches what the vendor's own docs say is actually enforced.

- **Option D — Do not build new mechanical enforcement; instead file/track the upstream gaps this spike surfaced** (`#17356`'s `permissionDecisionReason` not rendering; the absence of any dialog-content-modification hook) as known platform limitations, and accept the residual risk as documented, similar to the `agent-secret-output-leakage` spike's "DO NOTHING MECHANICAL" resolution for a structurally adjacent problem. This is a legitimate outcome, not a default — the engineer explicitly framed this as "a real security flaw," so Option D should be a deliberate choice, not an absence of one.

- **Option E — Combine A (or B) with C.** Mechanically block the opaque shape at the hook layer (removing the shape from ever reaching an ambiguous prompt) AND correct the CLAUDE.md rule's framing so it is not relied upon as if it were the control. This does not require picking between A and B first — either intercepting hook satisfies the mechanical half of this option.

(No recommendation — options presented with trade-offs; the engineer and main decide.)
