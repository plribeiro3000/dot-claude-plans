# SPIKE — Integrators Run-Flow Skill Hardening (MongoDB Discovery Stall)

## Investigation question

Three times, the engineer asked "roda o integrador de \<cliente\>" and the `/integrators` skill's compound run flow stalled at the same point: the agent could not find the client's MongoDB EC2 instances and fell back to reading the client's Terraform stack (`compute.tf`) to discover the instance names, instead of using the `/ec2-instances` skill and the `start-instance.sh` / `stop-instance.sh` binaries that already exist for exactly this. The question: does the current `/integrators` `SKILL.md` under-specify the MongoDB-discovery step in a way that explains this recurring failure, and if so, what exact corrected text would close the gap? Secondarily: do other skills in `~/.claude/skills/` carry the same class of gap (a step that should point to an existing tool but instead invites the agent to improvise against Terraform or raw AWS commands)?

## Sources consulted

- `~/.claude/skills/integrators/SKILL.md` (166 lines, read in full) — the run-flow step under investigation
- `~/.claude/skills/ec2-instances/SKILL.md` (88 lines, read in full) — the discovery skill the run flow should point to
- `~/.claude/scripts/start-instance.sh` (48 lines, read in full) — the start wrapper
- `~/.claude/scripts/stop-instance.sh` (42 lines, read in full) — the stop wrapper
- `~/.claude/skills/ec2-instances/scripts/ec2-instances.sh` (66 lines, read in full) — the tag-discovery script backing `/ec2-instances`
- `~/.claude/skills/integrators/environments.json` (grepped for Client-tag examples)
- `~/.claude/skills/apps/SKILL.md`, `~/.claude/skills/authenticators/SKILL.md`, `~/.claude/skills/connection-poolers/SKILL.md`, `~/.claude/skills/onboarding/SKILL.md`, `~/.claude/skills/setup/SKILL.md`, `~/.claude/skills/harvesters/SKILL.md` (all read in full) — the second-scope survey
- `grep -n -i "terraform\|compute\.tf\|read the.*stack\|open the client" ~/.claude/skills/*/SKILL.md` — full-repo sweep used to locate every skill that references Terraform or "open the stack", to make sure the survey did not miss a candidate

## Findings

### Finding 1: the root cause is confirmed — the run flow tells the agent to read `compute.tf` for the MongoDB instance list, in the same sentence that also names `/ec2-instances`

**Evidence:**

```
~/.claude/skills/integrators/SKILL.md:98
2. **Ensure MongoDB is up first** — the stack starts specific MongoDB EC2
   instances before scale-up (read the `start_mongodb` scheduler in the same
   `compute.tf` for the instance list). Check them with `/ec2-instances
   --client {client} --role database`. If any is stopped, start it and
   **wait until it is running** before scaling — processing against a cold
   database fails.
```

**Significance:** the sentence gives the agent two different sources for the same fact — the MongoDB instance identity — and assigns them asymmetric verbs. Terraform is where to go "for the instance list" (the noun phrase that answers "which instances exist"); `/ec2-instances` is only where to "Check them" (a verb that reads as verification of instances already known, not discovery of instances not yet known). An agent parsing this literally has no textual reason to skip the `compute.tf` read — the instruction gives it as the primary source of the instance list, and treats the `/ec2-instances` skill as a secondary status check on instances already identified. This matches the engineer's transcript exactly: the agent opened `compute.tf`, found `mongo004/005/006` there, and only switched to `/ec2-instances` after being told twice to do so.

By contrast, the correct discovery path already exists and is documented cleanly, but in a *different* section of the same file, for a *different* engineer intent ("If the engineer asked to start MongoDB instances" — a standalone request, not the compound run flow):

```
~/.claude/skills/integrators/SKILL.md:164-166
### If the engineer asked to start MongoDB instances

Some clients have MongoDB EC2 instances managed outside ECS. The deploy
workflow handles MongoDB startup via the preflight job. For manual start,
use the `/ec2-instances` skill (filter by `--client <name> --role database`,
then start via the discovered instance IDs).
```

This second passage is the clean version of the instruction — it never mentions Terraform, gives the exact filter, and says "discovered instance IDs" (implying `/ec2-instances` is the *source* of the IDs, not a checker). But it lives outside the run-flow steps the compound "roda o integrador" flow actually executes (Step 2 at line 98), so an agent following the run flow top-to-bottom never reaches it.

**Also confirmed — the run flow never names `start-instance.sh` at all.** Line 98 says "If any is stopped, start it" with no command. The only place in the file that names the actual binary is a different flow entirely — none of `integrators/SKILL.md`'s occurrences of `start-instance.sh` or `stop-instance.sh` exist; `grep -n "start-instance\|stop-instance" ~/.claude/skills/integrators/SKILL.md` (part of the initial full read) returns nothing. The run flow's "start it" is undercited: it names no script, forcing the agent to either infer the right tool (via the pointer to `/ec2-instances`, which itself documents `start-instance.sh`) or hand-build `aws ec2 start-instances` (which is separately, mechanically blocked per `CLAUDE.md` § AWS Policy, but that block only fires after the agent has already gone down the wrong path and been corrected once).

**Root-cause hypothesis: CONFIRMED**, with one refinement. The hypothesis named the missing prescriptive step; the actual defect is worse than "missing" — the step is present but names Terraform as the primary source and the correct tool as a secondary check, inside the exact section the compound flow executes.

### Finding 2: the file's own instruction to "never guess" a MongoDB instance list is what steers the agent toward `compute.tf` in the first place

**Evidence:**

```
~/.claude/skills/integrators/SKILL.md:92
"roda o integrador", "sobe o integrador", "run the integrator" — with no
service and no count named — is a **compound flow**, NOT a request to scale
one arbitrary service. It is the manual, human-in-the-loop version of the
nightly processing cron. Do the steps below in order, and **never improvise
which service to scale or how many tasks**: the counts and the MongoDB
instances are declared in the client's Terraform stack — read them, do not
guess.
```

**Significance:** this framing sentence is the introduction to the whole compound flow, and it explicitly says "the counts **and the MongoDB instances** are declared in the client's Terraform stack — read them". For the task-count half of that sentence this is correct and necessary — the ECS `desired_count` genuinely lives only in Terraform, there is no other authoritative source, and Step 1 (line 94) correctly instructs reading it there. For the MongoDB half, the sentence is misleading: the *existence and identity* of the MongoDB EC2 instances are queryable live via AWS tags (`/ec2-instances`, backed by `ec2-instances.sh`'s `describe-instances` call) — Terraform is where they are *declared*, but not the only place, or even the best place, to *discover* them, because a live tag query also returns current `State` (`running`/`stopped`), which Terraform's static `.tf` text does not. The sentence conflates "declared in Terraform" (true for both counts and instances) with "must be read from Terraform" (true only for counts), and gives the agent a direct textual instruction — "read them, do not guess" — that, applied to MongoDB, points at the wrong file.

### Finding 3: the exact discovery mechanism `/ec2-instances` exposes, verified end-to-end

**Evidence — the filter and its backing tags:**

```
~/.claude/skills/ec2-instances/SKILL.md:12-17
**Available tags for filtering (all optional, AND-combined):**
- `Project` — `integrator` (mongo, windows-machine, sqlserver) or `app` (pgbouncer)
- `Client` — present only on client-dedicated instances. Value is the client
  without country suffix when it serves the whole client (`atento`), or
  client+country when specific (`atento-cl`)
- `Role` — `database` (mongo), `pgbouncer`, `windows-machine`, `test-sqlserver`, `vpn`

**Region:** defaults to `sa-east-1` (integrator side — mongo, windows,
sqlserver, vpn).
```

```
~/.claude/skills/ec2-instances/SKILL.md:44-45
# A client's MongoDB
bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh --client maqnelson --role database
```

**Evidence — the script's actual AWS call, confirming what the filter does:**

```
~/.claude/skills/ec2-instances/scripts/ec2-instances.sh:50-65
FILTERS=("Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down")
...
if [[ -n "$CLIENT" ]]; then
  FILTERS+=("Name=tag:Client,Values=${CLIENT}")
fi
if [[ -n "$ROLE" ]]; then
  FILTERS+=("Name=tag:Role,Values=${ROLE}")
fi

aws ec2 describe-instances \
  --region "$REGION" \
  --filters "${FILTERS[@]}" \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value,Project:Tags[?Key==`Project`]|[0].Value,Client:Tags[?Key==`Client`]|[0].Value,Role:Tags[?Key==`Role`]|[0].Value}' \
  --output json
```

**Evidence — start/stop delegate cleanly, and `start-instance.sh` blocks until running (no separate wait step needed):**

```
~/.claude/skills/ec2-instances/SKILL.md:70-78
### If the engineer asked to start instances

Find the instance IDs with Step 1, then use the existing wrapper (it starts
and waits for `running`). Do NOT call `aws ec2 start-instances` directly —
it is mechanically blocked.

bash ~/.claude/scripts/start-instance.sh --region <region> <instance-id> [instance-id...]
```

```
~/.claude/scripts/start-instance.sh:36-48
echo "Starting instances in $REGION: ${INSTANCE_IDS[*]}"
aws ec2 start-instances --region "$REGION" ... --instance-ids "${INSTANCE_IDS[@]}"

echo "Waiting for instances to be running..."
aws ec2 wait instance-running --region "$REGION" ... --instance-ids "${INSTANCE_IDS[@]}"

echo "All instances are running."
```

**Significance:** the tooling is complete and correct — `Role=database` is the confirmed tag value for integrator MongoDB (documented in both `ec2-instances/SKILL.md:6` and `integrators/SKILL.md:166`), the script returns `Id`/`Name`/`State`/`Project`/`Client`/`Role` per instance in one AWS call, and `start-instance.sh` is a single blocking call that starts and waits — there is no missing capability. The gap is purely in how `integrators/SKILL.md`'s run flow narrates the step, not in what exists.

### Finding 4: a real risk in the corrected text — the `Client` tag value convention is not guaranteed identical between the two skills

**Evidence:**

```
~/.claude/skills/integrators/SKILL.md:10
- `Client` — the client name (e.g., `almaviva`, `atento-br`, `commcenter-staging`)
```

```
~/.claude/skills/ec2-instances/SKILL.md:14
- `Client` — present only on client-dedicated instances. Value is the client
  without country suffix when it serves the whole client (`atento`), or
  client+country when specific (`atento-cl`)
```

**Significance:** `integrators/SKILL.md` documents `atento-br` (with a `-br` country suffix) as a live example of its own `Client` tag; `ec2-instances/SKILL.md` documents its own `Client` tag convention as *dropping* the country suffix for a whole-client instance (`atento`, not `atento-br`) and only appending a suffix when the instance is country-specific (`atento-cl`). Whether the two tags happen to carry the same value for a given client's MongoDB instances is not established by either file — they are two independently-tagged resource types (ECS services vs. EC2 instances) and nothing in the read files guarantees the `Client` tag was applied with the same convention on both. A corrected run-flow step that does `--client {client}` verbatim (reusing the integrator's own client slug) risks an empty result for any client where the two conventions diverge, most plausibly a country-suffixed one like `atento-br` / `atento-mx` / `atento-co` / `atento-cl`.

## Proposed corrected step (spike proposal only — not applied)

The following is a proposed replacement for `~/.claude/skills/integrators/SKILL.md`'s Step 2 (currently line 98, "Ensure MongoDB is up first"), and a proposed one-word softening of the framing sentence at line 92. **This spike does not edit the skill** — the text below is for the engineer to review and, if accepted, apply.

**Framing sentence (line 92) — replace "the counts and the MongoDB instances are declared in the client's Terraform stack — read them, do not guess" with:**

> the counts are declared in the client's Terraform stack — read them, do not guess. The MongoDB instances are discovered live via `/ec2-instances`, never via Terraform — Terraform declares them, but `/ec2-instances` is what tells you which ones exist right now and whether they are running.

**Step 2 (line 98) — replace in full with:**

> 2. **Ensure MongoDB is up first — discover instances via `/ec2-instances`, never by reading the Terraform stack.** Run:
>
>    ```bash
>    bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh --client {client} --role database
>    ```
>
>    This returns each MongoDB instance's `Id`, `Name`, and `State` by AWS tag (`Project=integrator`, `Client={client}`, `Role=database`) in one call — the same mechanism the `/ec2-instances` skill exposes to the engineer directly. **Do NOT open the client's Terraform stack** (`compute.tf`, the `start_mongodb` scheduler, or any `.tf` file) to find instance names or IDs — Terraform is where the instances are declared, not where their live existence or running state is queried, and reading it here is the exact detour that has stalled this flow three times.
>
>    If `--client {client}` returns an empty list, the `Client` tag on the EC2 instances may not use the same convention as the integrator's own `Client` tag (`ec2-instances/SKILL.md` documents a whole-client instance dropping the country suffix, e.g. `atento` not `atento-br` — this is not guaranteed to match). Re-run with `--role database` only (drop `--client`) and match by the `Name` tag instead of failing back to Terraform.
>
>    For each returned instance where `State` is not `running`:
>
>    ```bash
>    bash ~/.claude/scripts/start-instance.sh --region sa-east-1 <instance-id> [<instance-id>...]
>    ```
>
>    `start-instance.sh` starts and blocks on `aws ec2 wait instance-running` internally, so this single call is both the start and the wait — do not add a separate polling step. If it fails with `AccessDenied` / `ExpiredToken` / `RequestExpired`, run `/elevate-aws-access` and retry with `--profile 4shark-mfa`.
>
>    Proceed to step 3 only once every MongoDB instance for the client reports `running`.

This rewrite: (a) removes the ambiguity between "read compute.tf for the list" and "check via /ec2-instances" by giving `/ec2-instances` as the sole discovery source, with an explicit prohibition on opening `.tf` files for this purpose; (b) names `start-instance.sh` directly with the exact invocation, closing the gap where the current text says "start it" with no command; (c) surfaces the `Client`-tag-convention risk from Finding 4 with a concrete fallback (drop `--client`, match by `Name`) instead of leaving the agent to improvise a recovery path (which could itself lead back to Terraform).

## Second scope — survey of other skills for the same improvisation gap

Full-repository sweep run: `grep -n -i "terraform\|compute\.tf\|read the.*stack\|open the client" ~/.claude/skills/*/SKILL.md` (all skill directories), followed by full reads of `apps`, `authenticators`, `connection-poolers`, `onboarding`, `setup`, and `harvesters` — the skills structurally closest to `integrators` (all manage ECS clusters/services via a tag-discovery script + `ecs-scale.sh`).

**Result: no second instance of the same gap class was found among the ECS-management family.** `apps/SKILL.md:102-114`, `authenticators/SKILL.md:70-84`, `connection-poolers/SKILL.md:74-88`, `onboarding/SKILL.md:50-64`, and `setup/SKILL.md:50-64` each name `ecs-scale.sh` directly, with the exact flags, for every scale-up/scale-down step, and none of them tell the agent to open a `.tf` file to discover a resource that a wrapper script or sibling skill already discovers by tag. `harvesters/SKILL.md:85-89` explicitly marks Terraform edits as **out of scope** for that skill ("Cadence / enable / disable ... lives in Terraform ... run it directly, not through this skill") rather than instructing the agent to read `.tf` files mid-flow — this is the opposite failure mode (a clean boundary, not a gap).

**One weak candidate, different in kind — not a "duplicated discovery" gap:**

| Skill | Step | Quote | Why it is weaker than the integrators case |
|---|---|---|---|
| `integration-debug` | High-volume S3 staging step | `integration-debug/SKILL.md:84`: *"find it by reading `~/Projects/4Shark/terraform/integrator-<name>/` or `~/Projects/4Shark/terraform/app-<name>/` for the bucket variable. If you can't infer it, ask the engineer rather than guess."* | The S3 bucket name genuinely has no lookup skill or wrapper script — Terraform's declaration *is* the only accessible source for it (there is no `/buckets` skill). The text also already carries an explicit "ask the engineer rather than guess" fallback, so an agent that cannot resolve it from Terraform is directed to stop and ask, not to keep improvising. This is a structurally different situation from the integrators case, where a dedicated discovery skill (`/ec2-instances`) already exists and duplicates what Terraform declares — here, no such duplicate tool exists. Ranked last because the risk (a stall) is present but the failure mode (asking, not improvising further) is already the correct one.

No other skill in `~/.claude/skills/` (`create-app-webclient`, `mongodb-reprovision`, `elevate-aws-access`, `pr-triage`, `migrate-ssh-keys`, `migrate-plans-location`, `post-mortem`, `runbook`, `spawn-session`) surfaced a Terraform-read instruction that duplicates an existing tool's discovery. `create-app-webclient/SKILL.md:22,49` and `mongodb-reprovision/SKILL.md` (multiple references) read/write Terraform because Terraform is the actual and only owner of the resource being created or modified in those flows (a DNS record, a MongoDB replica-set member's infrastructure) — not because a wrapper or sibling skill already covers the same discovery elsewhere. These were not ranked as candidates because the pattern this spike investigates — "a step relies on the agent improvising when a documented tool already exists for exactly that step" — does not hold for them: there is no such competing tool being bypassed.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Apply the proposed Step 2 rewrite verbatim | Closes the exact defect found in Finding 1; names the binary invocation directly (Finding 3); pre-empts the Client-tag mismatch (Finding 4) | Lengthens an already-166-line `SKILL.md`; the engineer may want different wording | This spike's proposal |
| Apply only a minimal fix (delete the `compute.tf` clause, keep the rest) | Smaller diff, faster to review | Leaves "start it" un-cited (no `start-instance.sh` invocation named) and leaves the Client-tag mismatch unaddressed — a second, related stall could still occur | Finding 1, Finding 4 |
| Leave `SKILL.md` unchanged, rely on the engineer correcting the agent live each time | Zero editing cost now | The failure has already recurred three times per the engineer's report; the cost is paid repeatedly instead of once | Engineer's problem statement |

## What remains uncertain

- **The exact `Client` tag value on a given client's MongoDB EC2 instances** — Finding 4 establishes that the two skills document non-identical conventions (`atento-br` in `integrators/SKILL.md:10` vs. `atento`/`atento-cl` in `ec2-instances/SKILL.md:14`), but this spike did not run `aws ec2 describe-instances` (out of scope — the task restricted this investigation to `ls`/`cat`/`grep`/`wc`) to confirm which convention is actually applied to any specific client's mongo instances. The proposed corrected step includes a fallback (drop `--client`, match by `Name`) precisely because this is unverified from the files alone.
- **Whether every integrator client's MongoDB instances carry `Role=database`** — this value is documented consistently in both files (`ec2-instances/SKILL.md:6` and `integrators/SKILL.md:166`) but, like the `Client` tag, was not verified against live AWS state in this spike.
- **Whether the `integration-debug` candidate (S3 bucket discovery) is worth a follow-up spike of its own** — it is a materially different situation (no duplicate tool exists) so this spike ranks it low, but the engineer may still want it hardened with a more explicit "ask" trigger.

## Suggested options for main and the engineer

- **Option A** — apply the full proposed rewrite (framing sentence + Step 2) to `~/.claude/skills/integrators/SKILL.md` as written in this spike, then verify the `Client`/`Role` tag values against live AWS state (`aws ec2 describe-instances`, read-only) for at least one client before considering the fix closed.
- **Option B** — apply a trimmed version of the rewrite (drop the Client-tag-mismatch fallback paragraph, keep the Terraform prohibition and the `start-instance.sh` invocation) if the engineer judges the mismatch risk to be low or wants to verify it separately first.
- **Option C** — treat this spike's fix as sufficient for now and defer the `integration-debug` S3-bucket-discovery candidate to a later, separate investigation, since it is a different-in-kind, lower-priority gap with no known recurrence reported by the engineer.
