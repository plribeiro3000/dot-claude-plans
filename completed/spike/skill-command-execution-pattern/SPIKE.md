# SPIKE — Skill Command-Execution Pattern (Wrappers vs. Prompts)

## Investigation question

The engineer asked the agent to "rodar o integrador" (the `integrators` skill's manual run flow). The agent executed the preview step with a raw `aws ecs run-task ... AUTO_ACCEPT=false` command and hit a permission prompt. The engineer's question: *"why are you executing it this way if the skill already documents how to avoid a permission prompt?"* — with the underlying hypothesis that **every skill is missing a standard section that names, per step, which binary/wrapper to use and the allow-list-safe command form**, so the agent stops improvising raw commands that trigger prompts.

Refined into four concrete sub-questions:

1. Is the `aws ecs run-task` prompt in the integrator preview step a bug (an avoidable, badly-formed command) or is it a deliberate, mechanically-enforced policy — and if deliberate, does the codebase already carry a documented rationale for it?
2. Across all 18 skills, how is each documented execution command classified: (a) routed through an allow-listed wrapper, (b) a raw command that already auto-approves via an existing mechanism, or (c) a raw command that prompts?
3. What execution-safety mechanisms already exist (wrappers, redirect hooks, auto-approve hooks, mechanical hard-asks/blocks), and why isn't the pattern uniform across skills?
4. What is the solution space — a doc template section, new wrappers, new redirect hooks, a Skill-invocation-time context injector — and what does each option resolve vs. not resolve, at what cost and risk?

A fifth, cross-cutting distinction the engineer flagged explicitly: there are two different problems bundled together — (i) READ commands that prompt needlessly because they were never wired into the allow-list/auto-approve mechanism (pure friction, should go away), and (ii) WRITE commands that prompt correctly because the prompt is the human-review gate on a state change (must not go away). This SPIKE keeps the two separated throughout.

**Revision note (this pass):** the first draft of this SPIKE left four open questions for the engineer under "What remains uncertain" without first exhausting the accessible sources — git history, the 4Shark Terraform IaC, the `integrator` application code, and the internet (Netlify's own API spec). The engineer flagged this as a process gap (Exhaust-Before-Ask). This revision goes after each of the four items with those sources before concluding anything is a genuine engineer decision. **All four were resolved by the sources below** — see Findings 8–11. Nothing in the original "What remains uncertain" section survives as a pure unknown; what is left in that section now is forward design judgment, not unresolved fact.

## Sources consulted

- `~/.claude/skills/integrators/SKILL.md` (full file, 172 lines) — the "roda o integrador" flow and its `Invocation rules` section
- `~/.claude/skills/apps/SKILL.md`, `authenticators/SKILL.md`, `connection-poolers/SKILL.md`, `create-app-webclient/SKILL.md`, `ec2-instances/SKILL.md`, `elevate-aws-access/SKILL.md`, `harvesters/SKILL.md`, `integration-debug/SKILL.md` (476 lines, fully paged), `migrate-plans-location/SKILL.md`, `migrate-ssh-keys/SKILL.md`, `mongodb-reprovision/SKILL.md`, `onboarding/SKILL.md`, `post-mortem/SKILL.md`, `pr-triage/SKILL.md`, `runbook/SKILL.md`, `setup/SKILL.md`, `spawn-session/SKILL.md` — every skill in `~/.claude/skills/`, read in full
- `~/.claude/settings.json` (761 lines, fully paged) — `permissions.allow` / `permissions.ask` lists and the full `hooks.PreToolUse` wiring
- `~/.claude/scripts/validate-bash-command.sh` (the hard-ask and hard-block gates for `aws ecs run-task`, `aws ec2 start/stop-instances`, `terraform apply/destroy`, etc.)
- `~/.claude/scripts/auto-approve-aws-readonly.sh` (the read-verb auto-approve mechanism and its exact scope)
- `~/.claude/scripts/redirect-ecs-scale.sh`, `~/.claude/scripts/ecs-scale.sh` (the wrapper + redirect pair for a bounded WRITE)
- `~/.claude/scripts/inject-integration-debug-docs.sh` (the existing precedent for a `Skill`-matcher PreToolUse injector)
- `~/.claude/scripts/auto-approve-local-skills.sh` (a separate, orthogonal auto-approve — the `Skill` tool call itself, not the Bash commands a skill later issues)
- `~/.claude/skills/integration-debug/scripts/integration-audit-snapshot-fargate.sh` (the only script in the codebase that wraps `aws ecs run-task`)
- `~/.claude/docs/COMMAND-SAFETY.md` — read in full; contains no mention of `run-task`, `wrapper`, or `ecs` (it covers only command-chaining, infra-atomicity, and output-truncation rules)
- `~/.claude/docs/adr/` — all four ADRs listed (`ADR-001-rules-loading-mechanism.md`, `ADR-002-permission-resolver-precedence.md`, `ADR-003-policy-verifier.md`, `ADR-004-code-write-policy-enforcement.md`); `grep -l "run-task\|wrapper" ~/.claude/docs/adr/*.md` returned no matches — no ADR governs this decision
- `git -C ~/Projects/4Shark/dot-claude log` / `git show` / `git log -S` against `scripts/validate-bash-command.sh` — found the exact commit that introduced the `aws ecs run-task` always-ask rule (`95ad799`) and the exact commit that introduced the only `run-task`-wrapping script (`de146a6`), with their timestamps and author
- `~/Projects/4Shark/terraform/integrator-atento/compute_br.tf` (and its sibling `compute_{cl,co,mx}[_staging].tf` files) — the runner ECS module definition (Fargate, `desired_count = 0`)
- `~/Projects/4Shark/integrator/lib/tasks/integration.rake` — the `integration:start` rake task, the single entrypoint both the preview and the actual run invoke
- `~/Projects/4Shark/integrator/lib/application_configuration.rb` — `ApplicationConfiguration.auto_accept?`
- `https://raw.githubusercontent.com/netlify/open-api/master/swagger.yml` — fetched directly (`curl`, 6074 lines) and grepped for all 180 `operationId` entries
- Negative-result greps against `~/.claude/settings.json` for `netlify`, `stop-sessions`, `harvester`, `ssh-keygen`, `ssh-add`, and `run-task` — each returned no output, confirming an absence rather than an oversight on my part
- See auxiliary: `skill-command-execution-pattern_audit_1.csv` — the full per-skill, per-command classification table (question 2)
- See auxiliary: `skill-command-execution-pattern_netlify-operationids_1.txt` — the full Netlify operationId extraction and read/write classification (question 3)

## Findings

### Finding 1: `aws ecs run-task` is mechanically forced to always ask, with no wrapper carve-out written into the rule

**Evidence:**
```bash
# validate-bash-command.sh:620-621
if printf '%s' "$normalized_command" | grep -qE '^aws[[:space:]]+ecs[[:space:]]+run-task([[:space:]]|$)'; then
  emit_ask "aws ecs run-task — approval required regardless of env-var or path prefix."
fi
```
**Source:** `~/.claude/scripts/validate-bash-command.sh:620-621`

**Significance:** This is a `PreToolUse` hook that fires on every `Bash` tool call. When the `integrators` skill's preview step runs `aws ecs run-task --cluster integrator-{client}-cluster ...` directly (`~/.claude/skills/integrators/SKILL.md:116`), this rule matches and forces `permissionDecision: "ask"` — the exact prompt the engineer observed. The rule sits in the same list as `terraform apply/destroy/import/taint/untaint` (`validate-bash-command.sh:587-589`), `terraform state rm/mv` (`:591-593`), `gh release create` (`:624-626`), and `git tag` (`:628-630`) — the codebase's set of actions treated as always requiring a human, unconditionally, "regardless of env-var or path prefix." The prompt is not a misconfiguration; it is working exactly as this line specifies.

### Finding 2: The same AWS action is already invoked, elsewhere in the codebase, without ever prompting — via a reviewed wrapper script

**Evidence:**
```bash
# integration-audit-snapshot-fargate.sh:145
task_arn=$(aws ecs run-task --profile "$MFA_PROFILE" --region "$region" --cluster "$cluster" \
  --task-definition "$task_definition" --launch-type FARGATE \
  --network-configuration "$network_configuration" --overrides "$container_overrides" \
  --count 1 --query 'tasks[0].taskArn' --output text 2>"$WORK_DIR/$label.run-task.err") || true
```
**Source:** `~/.claude/skills/integration-debug/scripts/integration-audit-snapshot-fargate.sh:145`, invoked as `bash ~/.claude/skills/integration-debug/scripts/integration-audit-snapshot-fargate.sh` which is itself allow-listed at `~/.claude/settings.json:84`.

**Significance:** The `PreToolUse` hook only ever inspects the string submitted to the `Bash` tool. When the agent calls `bash .../integration-audit-snapshot-fargate.sh --config -`, that is the only string `validate-bash-command.sh` sees — the `aws ecs run-task` call on line 145 runs as an internal subprocess and is invisible to the hook, exactly as documented for the SSH calls inside `mongodb-reprovision.sh`: *"The permission hooks see only the string submitted to Bash; the `ssh` calls the script makes are child processes and are invisible to them"* (`~/.claude/skills/mongodb-reprovision/SKILL.md:14`). So a wrapper-around-`run-task` pattern already exists and already ships — but only for the integration-debug audit-rake dispatch, not for the integrators skill's manual "roda o integrador" preview.

### Finding 3: `aws ec2 start/stop-instances` is treated even more strictly (a hard block, not just an ask) and its wrapper carve-out is spelled out explicitly in the block's own text

**Evidence:**
```
# validate-bash-command.sh:569-583 (excerpt)
Raw `aws ec2 start-instances` / `aws ec2 stop-instances` — blocked.
...
Fix:
  - To stop:  bash ~/.claude/scripts/stop-instance.sh  [--region <r>] [--profile <p>] <id> [<id>...]
  - To start: bash ~/.claude/scripts/start-instance.sh [--region <r>] [--profile <p>] <id> [<id>...]

The wrappers call `aws ec2 start-instances` / `aws ec2 stop-instances` internally in a subshell,
so this block does not interfere with the wrapper itself — only catches direct invocations from the agent.
```
**Source:** `~/.claude/scripts/validate-bash-command.sh:569-583`

**Significance:** This is a materially different mechanism from Finding 1 (`run-task`) — `exit 2` (a hard block with corrective stderr) rather than `emit_ask` (a soft prompt) — AND the block's own comment explicitly acknowledges the wrapper as the sanctioned bypass. No equivalent sentence exists next to the `run-task` rule. Finding 8 (below) resolves why the sentence is absent: a soft `ask` never traps the model in a dead end the way a hard `exit 2` does, so an escape-hatch pointer is not structurally necessary the way it is for a block.

### Finding 4: A bounded WRITE (`ecs update-service` / scale) is already fully wrapped, allow-listed, AND silently redirected from its raw form

**Evidence:**
```bash
# ecs-scale.sh:56-62
aws ecs update-service \
  --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" \
  --desired-count "$DESIRED_COUNT" \
  --query 'service.{name:serviceName,desired:desiredCount}' --output json
```
```
# redirect-ecs-scale.sh:9-25 (header, excerpt)
- `scripts/ecs-scale.sh` is a pass-through wrapper over `aws ecs update-service` ... and is
  auto-approved in permissions.allow.
- There is NO rule for raw `aws ecs update-service` — it is neither blocked (validate-bash-command.sh)
  nor auto-approved (auto-approve-aws-readonly.sh covers only get-*/describe-*/list-*/wait). So the raw
  scale command falls into the permission prompt on every invocation, while the wrapper does not.
```
**Source:** `~/.claude/scripts/ecs-scale.sh:56-62`; `~/.claude/scripts/redirect-ecs-scale.sh:9-25`; allow-list entry at `~/.claude/settings.json:79`

**Significance:** `aws ecs update-service --desired-count` is unambiguously a WRITE (it changes how many tasks run) yet 4Shark already treats it as auto-approvable, end to end, including a hook that rewrites a raw invocation into the wrapper form automatically. This establishes that "it's a write" is not, by itself, disqualifying for wrapper-based auto-approval in this codebase — the deciding factor has so far been how bounded and 1:1 the operation is (four flags, no arbitrary command payload), not merely read-vs-write.

### Finding 5: Across all 18 skills, most discovery/scale/log commands already follow the wrapper/allow-list pattern the engineer is asking for

**Evidence:** Full classification in the auxiliary CSV. Summary counts by class:
- **Wrapper, allow-listed** (`integrator-services.sh`, `apps-services.sh`, `authenticator-services.sh`, `connection-pooler-services.sh`, `onboarding-services.sh`, `setup-services.sh`, `ec2-instances.sh`, `start-instance.sh`, `stop-instance.sh`, `elevate-aws-access.sh`, `ecs-scale.sh`, `ecs-runner-profile.sh`, `integration-audit-snapshot-{fargate,ec2}.sh`, `migrate-plans-location.sh`, `check-ssh-keys.sh`, `mongodb-reprovision.sh`, `pr-triage.sh`) — the majority of documented commands across the skill set.
- **Raw command, auto-approved via an existing mechanism** — `aws logs tail` (direct allow-list entry, `settings.json:144`), `aws * describe-*` / `list-*` / `wait` (via `auto-approve-aws-readonly.sh:149`), `gh:*` (blanket allow-list entry, `settings.json:21`).
- **Raw command that prompts, by deliberate design** — `aws ecs run-task` (Finding 1), `terraform apply`, raw `ssh:*` (see Finding 6).
- **Raw command that prompts with no documented justification anywhere — confirmed gaps** — see Finding 6.

**Source:** `skill-command-execution-pattern_audit_1.csv` (every row cites its own `file:line`)

**Significance:** The pattern the engineer intuited — "every skill should say which wrapper to use" — is, for scaling and discovery, **already the norm**, not the exception. The `integrators` skill's own `Invocation rules` section (`~/.claude/skills/integrators/SKILL.md:32-35`) and its identical siblings in `apps`, `authenticators`, `connection-poolers`, `ec2-instances`, `harvesters`, `onboarding`, and `setup` already carry boilerplate text about **one** anti-pattern (`$(...)` command substitution) but never a full command-execution taxonomy. The gap the engineer is pointing at is real, but it is narrower than "every command in every skill" — it concentrates in (a) the small number of write actions the codebase has not yet decided whether to wrap (`run-task`'s AUTO_ACCEPT=false preview), and (b) a handful of plain oversights (Finding 6).

### Finding 6: Several allow-list gaps have no policy justification at all — pure oversight, not a deliberate "always ask"

**Evidence (negative results — each grep against `~/.claude/settings.json` returned no output):**
- `harvester-services.sh` — the discovery script for `/harvesters`, documented identically to its allow-listed siblings (`~/.claude/skills/harvesters/SKILL.md:41-48`), has no allow-list entry.
- `spawn-session.sh` and `stop-sessions.sh` — both scripts of the `/spawn-session` skill (`~/.claude/skills/spawn-session/SKILL.md:17,32`) have no allow-list entry; only the `Skill` tool invocation itself is auto-approved, by a *different* mechanism (`auto-approve-local-skills.sh`, which approves the `/spawn-session` slash command, not the `bash .../spawn-session.sh` Bash call that follows it).
- `netlify api getSite` / `getEnvVars` (pure reads) and `createSite` / `createEnvVars` / `updateSite` (writes), documented throughout `~/.claude/skills/create-app-webclient/SKILL.md:21,46-51,55` — no allow-list entry, and no auto-approve hook recognizes the `netlify` binary at all (`auto-approve-aws-readonly.sh` only recognizes `aws`).
- `ssh-keygen -lf` and `ssh-add -l` (pure reads — fingerprint-only, never key material) in `~/.claude/skills/migrate-ssh-keys/SKILL.md:43,54,56` — no allow-list entry. These are distinct binaries from `ssh` itself, so the deliberate always-ask rule for `ssh:*` (`settings.json:290`) does not even apply to them; they simply fall through to the default prompt with no read-only exemption ever written for them.

**Source:** `skill-command-execution-pattern_audit_1.csv` rows for `harvesters`, `spawn-session`, `create-app-webclient`, `migrate-ssh-keys`

**Significance:** These are structurally different from Finding 1 (`run-task`) and the `ssh -T <host>` verification step in the same skill (`migrate-ssh-keys/SKILL.md:58`) — those carry an explicit, on-the-record justification (Finding 1's `emit_ask` comment; the Remote Command Execution policy's blanket `ssh:*` ask entry at `settings.json:290`). The gaps here carry no such text anywhere in the hooks, the allow-list, or the skill docs — they read as commands nobody has yet routed through the allow-list/auto-approve machinery, mirroring exactly the pattern the codebase's own commit history names for `ecs-scale.sh`'s redirect hook: *"Listing 'never call aws ecs update-service directly' in skills/apps/SKILL.md was not enough ... A hook is the deterministic fix"* (`redirect-ecs-scale.sh:18-21`) — i.e., 4Shark's own documented experience is that a gap like this stays unfixed until it produces enough friction to be noticed and hooked.

### Finding 7: A working precedent for Option D already exists — a `PreToolUse` hook on the `Skill` matcher that injects context at invocation time

**Evidence:**
```bash
# inject-integration-debug-docs.sh (excerpt)
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
[ "$tool_name" = "Skill" ] || exit 0
skill_name="$(printf '%s' "$hook_input" | jq -r '.tool_input.skill // .tool_input.name // ... // empty')"
[ "$skill_name" = "integration-debug" ] || exit 0
```
wired in `~/.claude/settings.json:741-754` under `"matcher": "Skill"`, alongside `auto-approve-local-skills.sh`.

**Significance:** This is the exact mechanism shape Option D (below) proposes — a `PreToolUse` hook keyed on the `Skill` tool and a specific skill name, injecting `additionalContext` at the moment of invocation. Today it injects mandatory-doc *paths*; the same shape could inject a skill's allow-list-safe command forms instead. It is a real, shipped, already-reviewed pattern, not a novel one — which lowers the engineering-risk side of Option D relative to a from-scratch hook design. It also demonstrates the hard constraint any such hook must respect: pointers only, never full content, because hook output is capped at 10,000 characters (documented in the same file's own comments about a prior version that inlined full docs and silently failed).

### Finding 8 (new this pass): Git history resolves the `run-task` always-ask intent question — it targets a syntactic bypass, not a rejection of the wrapper pattern, and the only `run-task`-wrapping script in the codebase was built by the same author 63 minutes earlier, the same day

**Evidence:**
```bash
# from `git -C ~/Projects/4Shark/dot-claude log --oneline -S "ecs run-task" -- scripts/validate-bash-command.sh`
95ad799 fix(validate-bash-command): close env-prefix approval bypass
```
```
# git show 95ad799 (commit body comment, verbatim)
# === Ask-bypass detection ===
# Sensitive write operations are listed in settings.json under permissions.ask
# so they require human approval. The matcher does string-prefix match against
# the command, which means an env-var prefix (`AWS_PROFILE=x terraform apply`),
# an `env` wrapper, or an absolute path (`/usr/local/bin/terraform apply`)
# defeats the match — the command falls through to the allow default with no
# prompt. PR #408 documented the bypass in production.
#
# The fix: normalize the command (strip leading env-var assignments, `env`
# wrapper, absolute path of the binary) and re-match against the canonical
# write-op list. If matched, return permissionDecision: "ask" via JSON, which
# forces the prompt regardless of how the command was prefixed.
```
```
# commit timestamps (git show -s --format=%cI)
de146a6 feat(integration-debug): automate discovery and verification phases  2026-05-08T15:51:56-03:00
95ad799 fix(validate-bash-command): close env-prefix approval bypass          2026-05-08T16:54:46-03:00
# both authored by Paulo Ribeiro <plribeiro3000@gmail.com> (git show -s --format="%an <%ae>")
```
`de146a6`'s stat confirms it is the commit that first added `scripts/integration-audit-snapshot-fargate.sh` and `scripts/integration-audit-snapshot-ec2.sh` (the `run-task`-wrapping scripts from Finding 2), plus their `settings.json` allow-list entries, 63 minutes before `95ad799` added the unconditional `run-task` ask-gate.

**Source:** `git -C ~/Projects/4Shark/dot-claude log -S "ecs run-task" -- scripts/validate-bash-command.sh`; `git show 95ad799`; `git show de146a6 --stat`; `git show -s --format=%cI de146a6 95ad799`; `git show -s --format="%an <%ae>" de146a6`. `~/.claude/docs/COMMAND-SAFETY.md` (read in full) and all four files in `~/.claude/docs/adr/` were also checked and carry no mention of `run-task` or a wrapper carve-out — the commit is the only source that speaks to intent.

**Significance:** This resolves the original "was a carve-out contemplated?" question with high confidence, though the resolution is an inference from the evidence rather than an explicit statement, and that distinction is worth keeping visible: no commit says in words "wrappers are fine for `run-task`." What the evidence shows is (1) the commit's own stated scope is narrow — closing an **env-var/path-prefix bypass** of an *already-declared* policy (the header cites `terraform apply`, already a literal `permissions.ask` entry, as the motivating case) — not a deliberation over whether `run-task` specifically should ever be wrappable; and (2) the same author had, less than 90 minutes before writing that gate, built and shipped the exact wrapper-around-`run-task` pattern this SPIKE's Finding 2 documents, for a different call site. It is very unlikely the always-ask rule was written in ignorance of the wrapper pattern, since the same session produced both. The absence of an explicit carve-out sentence (unlike the `ec2 start/stop` block, Finding 3) is better explained structurally than as a rejection: `emit_ask` is a soft prompt the agent can still act on after approval, so — unlike the `exit 2` hard block, which leaves the model stuck without a named escape hatch — there was no structural need to name one. Net: the codebase's design intent, evidenced by contemporaneous practice rather than a written policy statement, treats "a reviewed, fixed-shape wrapper around a normally-gated raw command" as sanctioned — the same practice already applied to `ec2 start/stop`, `ecs-scale`, `ruby.sh`, `terraform.sh`, and (per Finding 2) `run-task` itself for a different flow.

### Finding 9 (new this pass): The preview (`AUTO_ACCEPT=false`) and the actual run (`AUTO_ACCEPT=true`) share one entrypoint but have materially different blast radii — verified directly in the Terraform IaC and the `integrator` application code

**Evidence — the runner is a real, billable Fargate task, never a running service:**
```hcl
# terraform/integrator-atento/compute_br.tf:144-158 (identical shape repeated per country/staging variant)
module "runner_br" {
  source = "../modules/ecs_service"
  ...
  service_name   = "integrator-atento-br-runner-service"
  task_family    = "integrator-atento-br-runner"
  container_name = "integrator-atento-br-runner"
  image          = "405749097490.dkr.ecr.sa-east-1.amazonaws.com/integrator-atento-br:latest"
  cpu           = 512
  memory        = 2048
  desired_count = 0
  ...
}
```
**Evidence — both AUTO_ACCEPT values run the same task, and the fork happens after a real, unconditional database read:**
```ruby
# integrator/lib/tasks/integration.rake:49-99 (excerpt)
if Source.normalized.any?
  normalized_source = Source.find_by(normalized: true)
  connection = normalized_source.connect!          # real connection to the CUSTOMER'S normalized DB
  ...
  ThroughputCalculator::COLLECTIONS.each do |collection, column|
    count = connection.count(collection, Sequel.lit("#{column} > ?", integrated_at))  # real COUNT query
    ...
  end
...
if ApplicationConfiguration.auto_accept?
  Job::Starter.perform_async(ApplicationConfiguration.skip_throughput?)   # enqueues the FULL pipeline
  puts "\n\nStarted!"
else
  puts "\n\nAre you sure you want to continue with integration? (Y/n)"
  input = $stdin.gets                               # nil in an ephemeral ECS task -> "Aborted"
  ...
```
**Source:** `~/Projects/4Shark/terraform/integrator-atento/compute_br.tf:144-158` (and the identical `compute_{cl,co,mx}[_staging].tf` sibling modules); `~/Projects/4Shark/integrator/lib/tasks/integration.rake:49-99`; `~/Projects/4Shark/integrator/lib/application_configuration.rb:37` (`def auto_accept?`)

**Significance:** This directly answers the "how bounded is the preview, really?" question the original trade-offs table left open. Two facts, both now verified in code rather than inferred from the SKILL.md's own description:

1. **The preview is not a no-op at the infrastructure level.** `AUTO_ACCEPT=false` still launches a real Fargate task (512 CPU / 2048 MB, billable) from a fixed, Terraform-declared task definition, and that task makes a real, read-only connection to the *customer's own database* to compute counts (`connection.count(...)`). This is a bounded, fixed-shape action — same cluster, same task-definition family, same container command (`bin/rails integration:start`), only the `AUTO_ACCEPT` value differs — structurally identical in shape to the integration-debug audit-rake dispatch that Finding 2 shows is already wrapped and allow-listed. Nothing in this path writes to the integrator's MongoDB or calls the app's API.
2. **The actual run is a categorically different, mutating action.** `AUTO_ACCEPT=true` takes the identical task and, after the same read-only count query, additionally calls `Job::Starter.perform_async` — per the integrator's own `CLAUDE.md`, this enqueues the full Extract → Transform → Load pipeline across all 25 streams (Subsidiary → ... → Goal), which is what actually mutates the app's RDS and the integrator's MongoDB Resource state. This is the terraform-`apply`-class action the original SPIKE speculated about, now confirmed rather than assumed — a wrapper around this specific invocation would be auto-approving the same order of consequence as `terraform apply`, which nothing in the codebase currently does.

This resolves the second open question: the preview is a genuine, code-verified candidate for the same wrapper treatment Finding 2 already applies to a structurally identical call; the actual run is not, and the reasoning is the same one that already keeps `terraform apply` (never wrapped) separate from `terraform plan` (wrapped by `terraform.sh`).

### Finding 10 (new this pass): The Netlify API's operation naming cleanly separates read from write for every call the `create-app-webclient` skill actually documents — a blanket rule across the full API would need a curated exception list

**Evidence:**
```yaml
# raw.githubusercontent.com/netlify/open-api/master/swagger.yml (fetched directly, 6074 lines)
line 111:  get    operationId: getSite
line  81:  post   operationId: createSite
line 129:  patch  operationId: updateSite
line 247:  get    operationId: getEnvVars
line 296:  post   operationId: createEnvVars
line 1234: post   operationId: createSiteBuild
```
All six are exactly the `getSite` / `getEnvVars` / `createSite` / `createEnvVars` / `updateSite` / `createSiteBuild` calls documented in `~/.claude/skills/create-app-webclient/SKILL.md:21,46-51`.

Across the full 180-entry `operationId` list in the same file, the naming is overwhelmingly `get*`/`list*`/`show*`/`search*` for reads and `create*`/`update*`/`set*`/`delete*`/`add*`/`remove*`/`cancel*` for writes — but not exhaustively: `enableSite`, `disableSite`, `purgeCache`, `runSiteDatabaseMigrations`, `rollbackSiteDeploy`, `restoreSiteDeploy`, `restoreSiteDatabaseSnapshot`, `unlinkSiteRepo`, `notifyBuildStart`, `exchangeTicket`, `configureDNSForSite`, `markDevServerActivity`, `agentRunnerPullRequest`, `agentRunnerCommitToBranch`, `transferDnsZone`, `lockDeploy`/`unlockDeploy`, and `provisionSiteTLSCertificate` are all semantically write operations that do not carry a create/update/delete prefix (full list in the auxiliary file).

**Source:** `https://raw.githubusercontent.com/netlify/open-api/master/swagger.yml`, fetched directly via `curl` and grepped for `operationId` (180 matches, see auxiliary `skill-command-execution-pattern_netlify-operationids_1.txt` for the complete extraction)

**Significance:** This resolves the third open question for the concrete case the engineer's flagged skill actually needs: every Netlify call `create-app-webclient` documents today would be correctly classified by a simple `get*`/`list*` = read, everything else = write rule — the same shape `auto-approve-aws-readonly.sh` already uses for AWS. It does **not** resolve cleanly for a hypothetical rule covering the *entire* Netlify API — that would need the curated exception list above, mirroring how `auto-approve-aws-readonly.sh`'s own header documents an enumerated, not a blind-prefix, scope (`get-*|describe-*|list-*|batch-get-*|wait`, plus two named exceptions for `s3 ls` and the `logs` read subcommands). This is not a remaining unknown — the full exception list is now enumerated in the auxiliary file — it is a scoping fact any implementation of Option B/C for `netlify` would need to carry.

### Finding 11 (new this pass): The `Invocation rules` boilerplate is already a shared, near-identical block across 7 of 8 ECS-management skills — Option A's "shared vs. per-skill" question is settled by existing practice, not a new design choice

**Evidence:**
```
# apps/SKILL.md:36-39, authenticators/SKILL.md:30-33, connection-poolers/SKILL.md:34-37,
# integrators/SKILL.md:32-35, harvesters/SKILL.md:30-33, onboarding/SKILL.md:25-28,
# setup/SKILL.md:25-28 — byte-identical except the script path:
## Invocation rules

- **Do NOT redirect the script output to a custom file with `$(date)` or any other command substitution.** Claude Code has a hardcoded guard that prompts for permission whenever a Bash command contains `$(...)` — even when the script itself is on the allowlist. The substitution defeats the allowlist.
- To process the script output, pipe directly: `bash ~/.claude/skills/<skill>/scripts/<skill>-services.sh | jq ...`.
```
```
# ec2-instances/SKILL.md:25-28 — same two bullets, missing the trailing sentence
## Invocation rules

- **Do NOT redirect the script output to a custom file with `$(date)` or any other command substitution.** Claude Code has a hardcoded guard that prompts for permission whenever a Bash command contains `$(...)` — even when the script itself is on the allowlist.
- To process the script output, pipe directly: `bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh | jq ...`.
```

**Source:** direct comparison of the eight files' own text, each already read in full during this SPIKE (`apps/SKILL.md:36-39`, `authenticators/SKILL.md:30-33`, `connection-poolers/SKILL.md:34-37`, `integrators/SKILL.md:32-35`, `harvesters/SKILL.md:30-33`, `onboarding/SKILL.md:25-28`, `setup/SKILL.md:25-28`, `ec2-instances/SKILL.md:25-28`)

**Significance:** This resolves the fourth open question. Seven of the eight ECS-management skills already carry a byte-identical `Invocation rules` block, with only the script path substituted per skill — the eighth (`ec2-instances`) carries the same two bullets minus one clause, a small drift rather than a different design. A shared/transcluded section is not a hypothetical rollout choice for Option A — it is already how this codebase documents its one existing anti-pattern warning. Extending Option A to cover the wrapper-vs-prompt taxonomy (not just the `$(...)` rule) would follow the same shape: one shared explanatory block, plus a per-skill list of that skill's actual wrapper scripts — mirroring how the per-skill part of the existing block is already just the swapped-in script path.

## Trade-offs surfaced

| Option | What it resolves | What it does NOT resolve | Cost | Security risk |
|---|---|---|---|---|
| **A** — Standard "Command Execution" section in the SKILL.md template, naming per-step binary/wrapper + allow-list-safe form | The documentation gap itself — makes the wrapper-vs-prompt reasoning visible per skill, closes the confirmed oversights in Finding 6 by forcing every skill author to check the allow-list before shipping a doc. Finding 11 shows the shared-block rollout shape already exists as precedent, so this is a low-risk extension of an established pattern, not a new one | The mechanical prompt on a genuinely unwrapped write (e.g., `run-task` AUTO_ACCEPT=false) — as the codebase's own history shows (`redirect-ecs-scale.sh:18-21`), documentation alone did not stop the raw `aws ecs update-service` prompt; only the hook did | Low — pure doc work, no permission-surface change, no security review needed | None — never touches `permissions.allow` or any hook |
| **B** — New wrapper script(s) for currently-unwrapped shapes (`run-task` preview, `netlify` reads, `ssh-keygen`/`ssh-add`, `stop-sessions.sh`) | The actual friction, for the shapes it targets. For the `run-task` preview specifically, Findings 8–9 now provide code-verified grounding (bounded, fixed-shape, no-mutation call, same class as the already-wrapped integration-debug dispatch) rather than an open question | The actual mutating run (`AUTO_ACCEPT=true`) — Finding 9 confirms this enqueues the full 25-stream pipeline and should stay on the raw always-ask path, the same way `terraform apply` stays unwrapped while `terraform plan` is wrapped | Low for pure-read wrappers (`stop-sessions.sh`, `harvester-services.sh`, `netlify` reads — each mirrors an already-accepted pattern); moderate for a `run-task` preview wrapper, which needs the same careful, narrow parsing `redirect-ecs-scale.sh` required (~180 lines to cover ONE scale shape safely) so it matches ONLY the fixed preview shape and nothing else | Low, now that Findings 8–9 remove the main open question (intent + blast radius) — the residual risk is standard wrapper-scoping discipline, not an unresolved policy conflict |
| **C** — New redirect hook(s) rewriting a raw command into its wrapper form automatically (mirrors `redirect-ecs-scale.sh`) | Same friction as B, transparently — the agent never needs to remember to call the wrapper | Anything that must legitimately stay gated (AUTO_ACCEPT=true, `terraform apply`, `netlify` writes) — a redirect hook by this codebase's own convention only ever targets a provably-safe, 1:1 rewrite (`redirect-ecs-scale.sh`'s own scope comment: "ONLY the pure-scale shape is rewritten") | Same as B for the `run-task` preview case — the rewrite must pattern-match the exact preview shape (fixed cluster/task-def/`AUTO_ACCEPT=false` override) and refuse anything else | Low, same basis as B — Findings 8–9 remove the open policy question; what remains is ordinary scoping care |
| **D** — `PreToolUse` hook on the `Skill` matcher injecting the allow-list-safe command form at invocation time | Keeps guidance fresh in context at the moment it is needed, surviving context compaction — same rationale as `inject-code-pattern-rule.sh` / `inject-skill-tip.sh`; a working precedent already ships (`inject-integration-debug-docs.sh`, Finding 7) | The underlying prompt on a legitimately-gated write — like A, this is a context/documentation reinforcement, not a change to the permission surface | Low — mirrors an existing, working hook | None if scoped as a pure injector (no `permissionDecision`); real risk if conflated with auto-approval, per the exact incident CLAUDE.md documents for a different hook |

A and D are not mutually exclusive with B/C — they operate on different layers (documentation/context vs. the permission mechanism itself) and could be adopted together or independently.

## What remains uncertain

**All four items originally listed here were resolved by exhausting git history, the Terraform IaC, the `integrator` application code, and the Netlify API specification — see Findings 8–11.** Nothing below is a fact with no resolving source; each item is a forward design/judgment call that belongs to the engineer by nature (§ Ask, Don't Decide), not a gap in research:

- **Whether to actually build a `run-task` preview wrapper.** Findings 8–9 establish that the codebase's design intent already sanctions this pattern and that the preview's blast radius is bounded and non-mutating — but *building* it is a scope/priority decision (is the remaining friction worth a ~180-line careful-parsing wrapper, per the `redirect-ecs-scale.sh` precedent for effort), not a fact any source resolves.
- **Whether the actual run (`AUTO_ACCEPT=true`) should ever get a wrapper.** Finding 9 gives a strong reason to say no (it enqueues the full mutating pipeline, the same class of action as `terraform apply`), but "never" is a standing policy choice for the engineer to affirm, not something git history or the IaC can settle on its own.
- **Scope of a `netlify` fix.** Finding 10 resolves the technical question (the split is clean for the skill's actual 6 calls; a blanket rule needs the ~20-entry exception list, now enumerated). Whether to implement a narrow rule (just the 6 calls the skill uses) or the broader curated one is a cost/scope decision, not a fact gap.
- **Whether Option A, B, C, and/or D are adopted, and in what combination.** The trade-offs table above is now grounded in verified facts rather than open questions, but choosing among low-risk, non-exclusive options is exactly the kind of decision this SPIKE surfaces without recommending (§ Ask, Don't Decide).

## Suggested options for main and the engineer

- **Option A** — Add a standard "Command Execution" section to the SKILL.md template (and retrofit existing skills), naming per-step binary/wrapper and the allow-list-safe form, alongside the existing `$(...)` anti-pattern warning. Finding 11 shows this follows an already-established shared-block shape.
- **Option B** — Build new wrapper scripts for the confirmed unwrapped shapes: trivial for `stop-sessions.sh` and `harvester-services.sh` (mirror their siblings' allow-list entries exactly); code-grounded (Findings 8–9) but more involved for the `run-task` preview; low-risk for `netlify` reads (Finding 10).
- **Option C** — Build new redirect hooks mirroring `redirect-ecs-scale.sh` for any shape where the raw→wrapper rewrite is provably 1:1.
- **Option D** — Add a `PreToolUse`/`Skill`-matcher context injector (mirroring `inject-integration-debug-docs.sh`) that surfaces each invoked skill's command-execution guidance at invocation time.
- **A fifth, narrower action independent of the above debate** — the confirmed pure-oversight gaps in Finding 6 (`harvester-services.sh`, `spawn-session.sh`, `stop-sessions.sh`, and the `netlify` read calls) carry no documented rationale for staying ungated and are asymmetrically low-risk to close (each mirrors an already-accepted pattern for a sibling script or verb class) — these could be addressed as an immediate, narrow follow-up regardless of which broader option(s) are chosen for the `run-task` question.

No option is recommended over another — the choice of scope (doc-only vs. mechanical, narrow vs. broad) and whether to build the now-grounded `run-task` preview wrapper are for the engineer to decide.

## Delivery status (2026-07-17)

Two of the surfaced options were chosen and shipped; the rest remain open for the engineer.

**Delivered — Option B, the `run-task` preview case (PR #438, merged into `develop`).** `skills/integrators/scripts/integrator-preview.sh` wraps the preview: it derives cluster / runner network config / latest ACTIVE task definition from `--client` alone, hardcodes the `bin/rails integration:start` command and `AUTO_ACCEPT=false`, and validates the `--client` charset, so the single allow-list entry cannot be abused to launch an arbitrary task. The `aws ecs run-task` call runs inside the script, invisible to the permission hook, so the preview no longer prompts. `integrators/SKILL.md` step 4 now points to the wrapper; step 5 (the real run, `AUTO_ACCEPT=true`) was left on the raw, always-ask path by design — it enqueues the mutating pipeline, the `terraform apply` class of action.

**Delivered — the "fifth action" (Finding 6 pure-oversight gaps), across two PRs.** PR #439 (merged) added allow-list entries for `harvester-services.sh`, `spawn-session.sh`, `stop-sessions.sh`, and the two read-only `netlify api` calls (`getSite`, `getEnvVars`); the `netlify` write calls were deliberately excluded so they keep prompting as the state-change gate. PR #441 (open) closes the last Finding 6 gap — allow-list entries for `ssh-keygen -lf` and `ssh-add -l`, the bare fingerprint-read forms in `migrate-ssh-keys/SKILL.md:20,54,56`. **Known residue (deliberately left):** line 43 uses `SSH_AUTH_SOCK=... ssh-add -l` — a leading `VAR=value` env prefix defeats the allow-list prefix match (the same reason `ruby.sh`/`terraform.sh` exist), so that one form still prompts. A wrapper is not warranted for a rarely-run skill's single check; the prompt there is accepted.

**Closed by decision, not built — Options A, C, D, and the whole-Netlify wrapper.** After PRs #438/#439/#441, every skill that invokes a command already either (a) documents an allow-list-safe wrapper per-step, or (b) uses a raw command that is gated on purpose (`terraform apply`, `ssh`, `netlify` writes, the `run-task` real run). The wrapper-vs-prompt friction that motivated the SPIKE is resolved. So **Option A** (a dedicated "Command Execution" section per skill) would be redundant restatement of the existing per-step command docs — the gap was never "the skill omits the command", it was "the command it named was a raw prompting form with no wrapper", which #438 (run-task) and #439/#441 (allow-list) fixed. **Options C and D** are alternative mechanisms (a `run-task` redirect hook / a `Skill`-matcher injector) that were never requested and would be belt-and-suspenders on a now-solved problem. **The whole-Netlify-API wrapper** is unnecessary: the six calls `create-app-webclient` actually uses are covered (Finding 10). None of these is built; if consistency ever justifies Option A's sections, it is a fresh, standalone decision — not a residual from this SPIKE.

This SPIKE is closed. It moves to `completed/spike/` once PR #441 merges.
