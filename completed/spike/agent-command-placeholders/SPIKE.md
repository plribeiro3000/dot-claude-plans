# SPIKE — Agent-Generated Commands Carrying Unresolved Placeholders

## Investigation question

Why does the agent hand the engineer commands or scripts of 10-20 lines carrying `<placeholder>` / `YOUR_X` / unset `$VAR` tokens the agent could resolve itself from 4Shark's own infrastructure (Terraform state, the ECS/EC2 discovery skills, SSM/Secrets Manager), instead of a complete, ready-to-run command? What already forbids this implicitly, why does that not hold, where is every common placeholder actually resolvable from, how should a genuine unresolvable credential be handled (prompt-at-start vs. a temp-file the engineer supplies once), and what mechanical enforcement is possible and what is its ceiling?

## Sources consulted

- `~/.claude/CLAUDE.md:655` — the Decision Authority default ("Claude resolves the ambiguity it meets... The PR is the review gate — not a mid-task question").
- `~/.claude/CLAUDE.md:658,663` — the resolution ladder naming "a point a Grep/Read/describe-* would settle is research not yet done, NOT a question."
- `~/.claude/CLAUDE.md:668` — `anthropics/claude-code#31497`, the model's own account of the effort-minimization pattern ("Asking you had no 'cost' → so I kept asking instead of thinking").
- `~/.claude/CLAUDE.md:51,1185` — the Bash Single-Line Policy's "No Claude-generated execution scripts" rule and its canonical escape hatches.
- `~/.claude/CLAUDE.md:703` — Script Discipline's delivery-channel rule ("delivered as a fenced code block IN THE CHAT... never as a file").
- `~/.claude/CLAUDE.md:1071` — Output Policy Layer 2, the "code that runs SOMEWHERE ELSE" row (in-chat, fenced, any length).
- `~/.claude/CLAUDE.md:1031` — Layer 0, "acknowledge it by category only — never the value."
- `~/.claude/scripts/validate-console-script.sh` (172 lines, read in full) — the only existing Stop-boundary gate that inspects a generated script's text, and the closest structural precedent for a placeholder gate.
- `~/.claude/scripts/validate-decision-evidence.sh` (193 lines, read in full) — the sibling Stop gate for "options fork with no legitimate reason," same `stop_hook_active` budget, same fail-open posture.
- `~/.claude/skills/apps/SKILL.md:42-61` — the `apps-services.sh` discovery script resolving cluster/service names from AWS tags, never a stored list.
- `~/.claude/skills/ec2-instances/SKILL.md:30-49` — the `ec2-instances.sh` discovery script resolving standalone-instance IDs by `Project`/`Client`/`Role` tags.
- `~/.claude/skills/connection-poolers/SKILL.md:16-24` — the pooler's internal DNS name pattern (`connection-pooler-{environment}.4shark.internal:6432`), a resolvable DB-endpoint placeholder.
- `~/.claude/scripts/terraform.sh:85` — the read-subcommand allow-list, confirming `output` and `state show` are wrapper-supported reads.
- `~/Projects/4Shark/terraform/app-demo-001/.envrc:10-18` — a live example of `op item get 'Terraform ENV' ...` resolving provider credentials, run by `direnv`, never printed.
- `~/Projects/4Shark/terraform/modules/connection_pooler/main.tf:318-342` — `aws_secretsmanager_secret` resources publishing pooler credentials by ARN, never a plaintext variable.
- `~/Projects/4Shark/terraform/modules/app/outputs.tf` (grep of `output "..."`) — confirms `pooler_admin_user`, `mongo_url_parameter_arn`, `secret_parameter_arns` are published outputs, resolvable via `terraform output`.
- `~/.claude/settings.json:756-766` — the `aws * get-*:*` and `aws * describe-*:*` wildcard allow-list entries, confirming `aws ssm get-parameter` and `aws secretsmanager get-secret-value` auto-approve.
- `~/.claude/settings.json:685` (grep) — confirms `op item get` has NO standalone allow-list entry; only the bundled `elevate-engineer-access.sh` script (which calls `op` internally) is allow-listed.
- [PostgreSQL docs — `.pgpass` file permissions](https://www.postgresql.org/docs/current/libpq-pgpass.html) — verified quote on the `chmod 0600` requirement for a credential file on disk.
- WebSearch for upstream `anthropics/claude-code` reports of placeholder-command generation — no matching issue found (see Finding 4).
- See auxiliary: `agent-command-placeholders_data_1.md` — the class-by-class resolver table referenced from Finding 4.

## Findings

### Finding 1: No existing 4Shark rule names this failure directly — three adjacent rules cover parts of it but not the whole

**Evidence:** § Decision Authority forbids the mid-task options fork ("I hit problem X, here are two or three ways to solve it") and requires the agent to resolve what a `Grep`/`Read`/`describe-*` would settle. § Bash Single-Line Policy forbids generating an unprompted `/tmp/` execution script but says nothing about a *complete* single command carrying a placeholder token. § Script Discipline governs the *channel* a generated script travels through (chat, fenced, never a file) but not whether every value inside it is resolved.

**Source:** `~/.claude/CLAUDE.md:658,663` (ladder); `:51` (single-line policy); `:703` (script discipline).

**Significance:** A placeholder left in a command is structurally the same failure the resolution ladder already names — the agent hands back a lookup it could have done — but none of the three adjacent rules states the placeholder case by name. The gap is real: an engineer correcting the agent every time is exactly the cost § Decision Authority's `#31497` citation describes for the options-fork case, applied to a different surface.

**Verification:** File read directly (`~/.claude/CLAUDE.md`), line numbers confirmed by `grep -n`, quotes copied verbatim from the read content.

### Finding 2: The closest documented root cause is effort-minimization, already evidenced for a sibling failure — a training-data convention is a plausible second cause but is NOT independently sourced for this exact shape

**Evidence:** `anthropics/claude-code#31497`, quoted in CLAUDE.md: *"Asking you had no 'cost' → so I kept asking instead of thinking...you were too patient, and I exploited that."* That issue is about the model asking mid-task questions rather than resolving them — the same "hand the lookup back" shape a placeholder produces, just spelled as `<host>` instead of a question mark.

A second candidate — that tutorials, man pages, and Stack Overflow answers use `<placeholder>` tokens as the register a model reproduces by default — is intuitively strong but **could not be independently verified from a fetched source**. A WebSearch on "LLM tutorial documentation placeholder convention" returned no source directly analyzing why models reproduce this pattern; a tangential comment on a Karpathy gist discusses writing stable values "out in full" in *documentation* to avoid drift, not command generation, and is not evidence for this claim.

**Source:** `~/.claude/CLAUDE.md:668` (the `#31497` quote, verified in Finding 1); [Karpathy gist, comment by WadeGIMPBC](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — quote fetched and confirmed present, but its subject is documentation-drift, not command placeholders, so it is cited only as adjacent, not as direct support.

**Significance:** One root-cause candidate (effort minimization) is grounded in a verified, on-topic source; the other (training-data register) is plausible but unsourced for this exact shape. Treating the second as established would violate the citation discipline's "no invented term attributions" rule — it is recorded here as a hypothesis, not a finding.

**Verification:** URL fetched (Karpathy gist); verbatim quote checked; quote substring confirmed present in the fetched content, but the quote's subject does not match the claim it was searched for, so it is marked adjacent rather than confirming.

### Finding 3: No upstream `anthropics/claude-code` issue reporting this exact behavior was found

**Evidence:** Three WebSearch queries targeting "Claude Code agent placeholder command," "AI agent generates script with TODO/YOUR_ placeholder," and general LLM placeholder-reproduction research returned no matching upstream issue. The one placeholder-shaped issue surfaced (`#49944`, "`[Pasted text #N]` placeholder instead of actual pasted content") is a different phenomenon — a UI-level paste-substitution bug in team-mode context relay, not a model choosing to emit an unresolved token in generated output.

**Source:** WebSearch results (three queries, see tool trace); [`anthropics/claude-code#49944`](https://github.com/anthropics/claude-code/issues/49944) — read and excluded as off-topic.

**Significance:** Per Citation Discipline, "the community does not name this practice" is a valid conclusion rather than a gap to paper over. There is no known upstream tracking issue to point to, and no confirmation that Anthropic has characterized this as a distinct failure mode the way it has for premature termination (`#52241`, `#10980`) or excess-question behavior (`#31497`). The candidate mechanical fix in Finding 6 is therefore a 4Shark-original design, not an adoption of a documented upstream mitigation.

**Verification:** Searches run and results recorded; `#49944` fetched via search summary and its subject matter confirmed distinct from the investigation question.

### Finding 4: A concrete resolver exists for every infrastructure-shaped placeholder class 4Shark's skills already cover

**Evidence:** `apps-services.sh` discovers ECS cluster/service names by `Project=app`/`Project=app-outbound` tags — no stored list (`~/.claude/skills/apps/SKILL.md:18`: *"Which environments exist is read from AWS on every invocation, never from a list in this skill."*). `ec2-instances.sh` discovers standalone instance IDs by `Project`/`Client`/`Role` tags (`~/.claude/skills/ec2-instances/SKILL.md:32`). The connection-pooler's internal DB endpoint is a fixed DNS pattern, `connection-pooler-{environment}.4shark.internal:6432` (`~/.claude/skills/connection-poolers/SKILL.md:22`). Terraform-managed values (VPC/subnet IDs, DB cluster endpoints, ARNs) are readable via `terraform.sh <stack-dir> output` or `state show`, both wrapper-supported read subcommands (`~/.claude/scripts/terraform.sh:85`: `init|plan|validate|fmt|show|output|version|state`). AWS region/profile conventions are written down per-project (`app` → `us-east-1`, `app-outbound`/integrator → `sa-east-1`; default profile for reads, `engineer-elevated` for writes).

**Source:** `~/.claude/skills/apps/SKILL.md:18,42-61`; `~/.claude/skills/ec2-instances/SKILL.md:12-49`; `~/.claude/skills/connection-poolers/SKILL.md:16-24`; `~/.claude/scripts/terraform.sh:85`.

**Significance:** For the placeholder classes the engineer named — server/cluster/service names — 4Shark already ships the exact read-only command that resolves each one, and every one of those commands is allow-listed (matches `Bash(bash ~/.claude/skills/<name>/scripts/<script>.sh:*)` entries or the `aws * describe-*:*`/`aws * get-*:*` wildcards). A placeholder for one of these is not a missing capability; it is the capability not being invoked before the command is handed over. See auxiliary: `agent-command-placeholders_data_1.md` for the full class-by-class breakdown.

**Verification:** Files read directly, line numbers and quotes confirmed by grep/Read.

### Finding 5: Most "credential" placeholders are also 4Shark-owned and resolvable, but resolving them collides with Layer 0 — the value can be USED but never PRINTED

**Evidence:** The `aws * get-*:*` and `aws * describe-*:*` wildcard allow-list entries (`~/.claude/settings.json:756-758`) match `aws ssm get-parameter --with-decryption` and `aws secretsmanager get-secret-value` — both auto-approve under the default read-only profile, no permission prompt. Terraform modules that need a credential generate it internally and publish only the ARN or parameter name as an output, never the value (`~/Projects/4Shark/terraform/modules/connection_pooler/main.tf:318-342`, `aws_secretsmanager_secret.userlist`/`stats_password`; the value is injected into the ECS task definition via `valueFrom`, never surfaced). This matches the documented credential corollary: *"the module publishes to SSM SecureString / Secrets Manager and outputs the ARN or parameter name, never the value."*

Separately, `op item get 'Terraform ENV' ...` is the live pattern for 4Shark's own third-party provider bootstrap credentials (`~/Projects/4Shark/terraform/app-demo-001/.envrc:10-18`), but that call runs inside `direnv`'s `.envrc` execution — a shell context the agent does not control — and `op item get` carries **no standalone allow-list entry** for the agent to invoke directly (confirmed: `grep -n "elevate-engineer-access\|elevate-policy-arbiter" ~/.claude/settings.json` returns only the bundled elevation script's own entry). An agent-issued `op item get` would trigger a permission prompt and, if the result were echoed to resolve a placeholder, would risk a Layer 0 violation the instant the value reached the chat.

**Source:** `~/.claude/settings.json:756-766` (grep, AWS wildcards); `~/Projects/4Shark/terraform/modules/connection_pooler/main.tf:318-342`; `~/.claude/CLAUDE.md` § Terraform Module Boundary (credential corollary, quoted from the summary already loaded); `~/Projects/4Shark/terraform/app-demo-001/.envrc:10-18`; `~/.claude/settings.json:685` (grep confirming no bare `op` entry).

**Significance:** The engineer's proposed distinction ("you HAVE access to most placeholders — go get it") holds for the AWS-native paths: an ARN, a parameter name, or a value fetched via `aws ssm get-parameter`/`aws secretsmanager get-secret-value` can be resolved read-only, with no permission friction, and used INSIDE a generated script (e.g. `valueFrom` in a task definition, or a line the script itself fetches at runtime) without ever appearing in the chat. The 1Password path (`op item get`) is narrower — reachable in principle, but not currently allow-listed for ad hoc agent use outside the two elevation skills, and carries the Layer 0 risk on print. This is a real distinction the resolver table must carry, not a single rule.

**Verification:** Files and settings read directly; grep outputs confirmed the presence/absence of allow-list entries.

### Finding 6: For a credential 4Shark genuinely does not hold (customer-supplied), the engineer's two proposed fallbacks are both sound, but neither has existing 4Shark precedent to point to — a matching external convention exists for the temp-file shape

**Evidence:** No existing 4Shark script under `~/.claude/scripts/` or any `skills/*/scripts/` uses `read -rs`/`read -s` to prompt for a secret at the start of a script (`grep -rn "read -rs\|read -s " ...` returned no matches), and no doc states a `chmod`/`umask` convention for a temp file holding a credential (`grep -n "chmod 600\|umask" ~/.claude/docs/*.md` returned no matches). Both fallbacks the engineer proposed are therefore genuinely new territory for 4Shark, not an existing pattern being rediscovered.

An external, well-established convention exists for the temp-file shape: PostgreSQL's own `.pgpass` mechanism requires the file be `chmod 0600` and states the consequence of skipping it plainly — *"the permissions on a password file must disallow any access to world or group... If the permissions are less strict than this, the file will be ignored."*

**Source:** `grep -rn "read -rs\|read -s "` (no matches, searched paths in tool trace); `grep -n "chmod 600\|umask"` (no matches); [PostgreSQL docs, `.pgpass`](https://www.postgresql.org/docs/current/libpq-pgpass.html).

**Significance:** The prompt-at-start and temp-file-input shapes the engineer described are not blocked by any existing 4Shark rule, and an external precedent (`.pgpass`'s 0600 requirement) gives a concrete permission convention to borrow for the temp-file variant. Neither shape currently has a 4Shark script to point to as "the existing pattern" — a candidate rule adopting either would be introducing a new convention, not codifying one already in use.

**Verification:** URL fetched (PostgreSQL docs); verbatim quote checked; quote substring confirmed present at the "Password File" section of the fetched page.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Doc-only rule (a `## Complete Commands` CLAUDE.md section, no hook) | Cheap to add; consistent with how most 4Shark rules start | Same class of rule (§ Decision Authority) already existed as prose and the model kept the forbidden behavior anyway per `#31497` — prose alone is documented as insufficient for this class of failure | `~/.claude/CLAUDE.md:668` |
| `Stop`-boundary gate scanning fenced ```bash/```sh/```ruby/```sql blocks for placeholder shapes | Same structural precedent as `validate-console-script.sh` and `validate-decision-evidence.sh` — inspects the reply text at the one point a generated command is visible before the turn closes | Ceiling: a fake-but-plausible value (`server-001`) passes every matcher; `<T>`/`<%= %>`/generic-language angle brackets are false-positive risks needing careful exclusion; shares the one-block-per-turn budget with the two existing Stop gates | `~/.claude/scripts/validate-console-script.sh` (read in full); `~/.claude/scripts/validate-decision-evidence.sh` (read in full) |
| A dedicated Tier 2 resolver doc (`COMMAND-VALUE-RESOLUTION.md`) that the rule points to | Turns "go and get it" into a concrete, checkable map per placeholder class, the same shape as the DEPLOY-REFERENCE.md pattern already in use for deploy triggers | A doc with no summary in CLAUDE.md does not reliably reach the session (measured precedent in § Documentation Loading Model: *"A rule with no summary here does not reach the session"*) — would need at least a one-line CLAUDE.md summary | `~/.claude/CLAUDE.md` § Documentation Loading Model (already loaded) |
| Extending `inject-output-policy-reminder.sh` with one more line | No new hook, reuses an existing every-turn injection point | § Documentation Loading Model's "one rule per hook" constraint (measured: four rules in one hook busted the 10,000-character cap on a `.rb` write) argues against piling more onto a shared injector; a reminder is also pre-turn only, not a boundary gate | `~/.claude/CLAUDE.md` § Documentation Loading Model |

## What remains uncertain

- Whether a training-data convention (tutorial/man-page placeholder register) is actually a meaningful contributing cause, versus effort-minimization alone explaining the whole behavior — no source was found directly analyzing this for command generation specifically (Finding 2).
- Whether Anthropic or the wider community has characterized this failure mode under any name — no matching upstream issue or academic taxonomy entry was found (Finding 3), unlike premature termination (`#52241`) or excess questioning (`#31497`), both of which already have a name and a citation in 4Shark's own docs.
- Whether a `Stop`-gate regex can reliably distinguish a real unresolved placeholder from a legitimate angle-bracket use (a Ruby/Java/C# generic `<T>`, an ERB `<%= %>`, HTML inside a heredoc, shell redirection `<`/here-strings `<<<`) without an unacceptable false-positive rate — this needs a prototype-and-test pass against real generated commands before it can be assessed, which is outside this spike's scope.
- Whether the multi-line-command shape (already forbidden by § Bash Single-Line Policy) is worth catching in the SAME gate as placeholders, or should stay exclusively enforced by the existing `validate-bash-command.sh` PreToolUse block — the two failures are related (both hand incomplete work to the engineer) but sit at different lifecycle points (one is caught before execution on a tool call, the other would need to be caught in generated TEXT before the turn closes, same as `validate-console-script.sh`).
- Whether `op item get` should gain a scoped, read-only allow-list entry for resolving 4Shark's own non-elevated third-party keys (Datadog, Rollbar labels already documented in § Third-Party Service Key Standard) — this spike surfaces the gap (Finding 5) but does not evaluate the security trade-off of widening that allow-list.

## Suggested options for main and the engineer

- Option A: Add a `## Complete Commands` (or similarly named) section to `CLAUDE.md` stating the rule in prose — a command or script handed to the engineer carries no placeholder; every value 4Shark holds is resolved before the reply; a value genuinely absent from 4Shark's infrastructure becomes a prompt-at-start or a temp-file input, never a bare token. Cheapest, but the closest sibling rule (§ Decision Authority, prose-only) is documented as having not held on its own.
- Option B: Add a `Stop`-boundary hook (e.g. `validate-command-placeholders.sh`) alongside the two existing Stop gates, scanning fenced code blocks for placeholder shapes (`<word>`, `YOUR_`, `REPLACE`, `CHANGE_ME`, standalone `...`, an unset `$VAR`) and multi-line command blocks. Same structural pattern as `validate-console-script.sh`; inherits its known ceiling (a plausible fake value passes) and shares the one-block-per-turn budget.
- Option C: Add a resolver-table Tier 2 doc (`~/.claude/docs/COMMAND-VALUE-RESOLUTION.md`) mapping each placeholder class to its concrete read-only command, with a one-line CLAUDE.md summary pointing to it — giving "go and get it" a checkable reference, independent of whether A or B is also adopted.
- Option D: Extend `inject-output-policy-reminder.sh` (or a new dedicated injector, per the one-rule-per-hook constraint) with a pre-turn reminder of the rule from Option A — cheap, but a reminder is documented elsewhere in CLAUDE.md as insufficient alone for a behavior this persistent, so it would likely need to pair with B or C rather than stand alone.
- Option E (credential fallback only): adopt the prompt-at-start (`read -rs`) and/or temp-file (`chmod 0600`, deleted after use, never in an argument that shows in `ps`) shapes as documented conventions in `SCRIPT-DISCIPLINE.md`, borrowing the `.pgpass` permission convention (Finding 6) since no 4Shark precedent currently exists for either.

These options are not mutually exclusive — B and C in particular address different halves of the same gap (detection vs. resolution reference) and a combination is a plausible outcome, but the choice is the engineer's.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
