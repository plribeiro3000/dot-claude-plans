# Tasks: Step 6 — re-provision the integrator MongoDB fleet onto Ubuntu 24.04

**Derived from:** `PLAN.md` § Step 6. **Status:** in progress — almaviva Phase A partially done (nodes up, not yet in the set).
**Scope:** 4 environments × 3 nodes = 12 new instances. MongoDB stays at 8.0 — this hop changes **only** the OS.

---

## What this document is

The literal command sequence for the re-provision, in the exact form it runs. Every command executed against a node during Step 6 is written here, with the reason it exists.

**This is the specification the operator skill is built from.** The version-upgrade half already has its equivalent — `~/.claude/docs/runbooks/databases/MONGODB-VERSION-UPGRADE.md` § "The commands" — and that section exists because the last hop was ~90 hand-issued SSH commands reconstructed from a session transcript afterwards. This file is written *before* the commands run, and corrected as they run, so the skill is a transcription of a procedure proven 12 times rather than a design recalled from memory.

**Two operations, two shapes — do not conflate them.** A **version** upgrade is in place, inside the instance (that is the MongoDB-sanctioned path, and it is what the runbook covers). This — an **OS** upgrade — is a **re-provision**: a fresh node is stood up beside the set, joins it, takes over, and the old one is retired. They share the `rs.*` vocabulary and nothing else.

---

## The invariants

These are the properties that must hold at every moment. Each one was paid for.

- **Never touch a node that is serving.** New nodes stand *alongside*; the old trio keeps its data and keeps running until the cutover is validated. A failure is a step back, never a restore. (This is why `-replace`-in-place was rejected on 2026-07-15 — see PLAN.md.)
- **Only the two new DATA nodes join the set. Peak is 5 members, never 6.** The new arbiter is swapped 1:1 with the old one at the very end, so the set never holds two arbiters and the voting count never goes even.
- **New data nodes join as `{ votes: 0, priority: 0 }`** and are promoted only after both are `SECONDARY`. A voting member that is still syncing can tie an election.
- **The set name is read from the primary, never assumed.** atento's set is `atento-br`, not `atento` — assuming it would have pointed a node at a set that does not exist.
- **Nothing runs during an integration window.** The primary handoff causes an election blip.
- **A node is verified back to `SECONDARY` before the next node is touched.**

---

## Per-environment specifics

One procedure, four environments. Everything that differs is here; the phases below are identical for all four.

| | almaviva | maqnelson | atento | commcenter |
|---|---|---|---|---|
| Set name | confirm from primary | confirm from primary | `atento-br` (shared, 4 countries) | confirm from primary |
| Integration window (UTC) | 01:00 | 01:30 | br 02:00 / co 09:30 / mx 10:30 / cl 14:00 | 04:00 |
| Power model | daily-shutdown | daily-shutdown | always-on | always-on |
| SSM params to repoint | 1 | 1 | **7** (per country) | 2 (prod + staging) |
| Deploys to run | 1 | 1 | **7** | 2 |
| Teardown `aws_instance` refs | **4 in `compute.tf`** | **4 in `compute.tf`** | 1 in **`alb.tf`** | none |
| Terraform PR (Phase A) | #703 (merged, applied) | — | — | — |
| Old nodes (001/002/003) | 10.1.0.51 / 10.1.0.81 / 10.1.0.95 | 10.1.2.44 / 10.1.2.79 / 10.1.2.110 | 10.12.255.19 / 10.12.255.98 / 10.12.255.113 | 10.1.3.18 / 10.1.3.105 / 10.1.3.119 |
| New nodes (004/005/006) | 10.1.0.9 / 10.1.0.70 / 10.1.0.104 | — | — | — |

**Order:** almaviva → maqnelson → atento → commcenter (the integration execution order — engineer, 2026-07-15). Engineer may move commcenter ahead of atento if atento's 14:00 window has not cleared.

**Node roles are fixed by number:** `004` and `005` are data (004 in AZ `a`, 005 in AZ `b`), `006` is the arbiter. `004` is the primary-candidate.

---

## Reaching a node

The nodes have no public address. **The VPN must be up on the engineer's machine.**

```bash
ssh -i ~/.ssh/kp-4shark.pem ubuntu@<node>
```

Every command below runs as `ssh -i ~/.ssh/kp-4shark.pem ubuntu@<node> '<command>'`. `<node>` is the private IP.

SSH to these nodes is slow to connect — use `-o ConnectTimeout=20` or higher.

**The agent runs these itself, including `systemctl restart mongod`.** `validate-bash-command.sh:479` skips the local-database guard when the command's leading token is `ssh` (the guard governs the engineer's own machine, not a remote host). The old engineer-runs-the-restart handoff is history — PLAN.md lines 271 and 364 still describe it in the present tense and are stale.

---

## Phase 0 — pre-flight

**0.1 — Confirm no integration is running.** The stack's window is its `integration-cron` scheduled task. Expect `{"taskArns": []}`.

```bash
aws ecs list-tasks --region sa-east-1 --cluster integrator-<client>-cluster --desired-status RUNNING --output json > /tmp/<client>_running_tasks.json 2>&1
```

**0.2 — Snapshot the two old DATA nodes' root volumes — BEFORE starting anything.**

**On a daily-shutdown environment the nodes are still stopped at this point, and that is exactly when to snapshot: a stopped volume has no writes in flight, so the restore point is consistent by construction.** Starting first and snapshotting a live `mongod` throws that away for nothing. (The first draft of this file had the order backwards — corrected 2026-07-15 while running almaviva.) A snapshot's point-in-time is the moment the command is issued, so the instance may be started immediately afterwards while the snapshot is still `pending`.

Volume ids first — both data nodes in one call:

```bash
aws ec2 describe-instances --region sa-east-1 --instance-ids <old-001-id> <old-002-id> --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Id:InstanceId,Vol:BlockDeviceMappings[0].Ebs.VolumeId}" --output table > /tmp/<client>_old_volumes.txt 2>&1
```

Then one snapshot per data node (the arbiter holds no data — do not bother):

```bash
aws ec2 create-snapshot --region sa-east-1 --volume-id <root-volume-id> --description "pre-os-reprovision <node> focal-to-noble" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Purpose,Value=pre-os-reprovision},{Key=Stage,Value=focal-to-noble}]' --profile 4shark-mfa > /tmp/snap_<client>_<nnn>.json 2>&1
```

**0.3 — (daily-shutdown environments only) start the old trio.** The set does not exist while the nodes are off, so there is nothing to `rs.add` to. **The script takes instance ids POSITIONALLY** — there is no `--instance-id` flag — and it accepts several, then waits for `running`:

```bash
bash ~/.claude/scripts/start-instance.sh --profile 4shark-mfa <old-001-id> <old-002-id> <old-003-id>
```

**0.4 — Confirm the set reconstituted and is healthy before touching it.**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.status().members.map(m => m.name + \" \" + m.stateStr + \" health=\" + m.health)"' > /tmp/<client>_set_status.log 2>&1
```

**0.5 — Read the set name from the primary. Do not assume it.**

**Run it as its own command.** `mongosh --quiet --eval A --eval B` prints only the LAST expression — chaining this onto the health check silently drops the set name (hit 2026-07-15).

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.status().set"' > /tmp/<client>_setname.log 2>&1
```

---

## Phase A — bring the new nodes up and join them

**A.1 — Terraform: three new nodes + three DNS records.** Additive; `3 to add, 0 to change, 0 to destroy` is the expected plan. The integrator stack applies first (the instances must exist), then the `dns` stack (its records resolve the instances by Name tag). Pattern: terraform #703.

**A.2 — Confirm SSH reaches each new node, and that the image is what it claims.** First contact needs `-o StrictHostKeyChecking=accept-new` (a brand-new host key).

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new ubuntu@<new-004> 'hostname && lsb_release -cs && mongod --version | head -1 && systemctl is-active mongod'
```

Expect `noble`, `db version v8.0.26`, `active`. **The patch must match what the old set already runs** — this hop moves the OS and nothing else. A mismatch here means the image is wrong; stop.

**A.3 — Append the set name to the two new DATA nodes.** The golden image ships `mongod.conf` with **no** `replication` block — `ansible-role-mongodb/defaults/main.yml:46` sets `mongodb_conf_replSetName: ""` and the template (`templates/mongod.conf.j2:17`) omits the block when it is empty. This is deliberate: one image serves the whole fleet and each client has a different set name. So every re-provisioned node needs this.

**A.3a — read the file before writing to it.** The append is blind otherwise: if a `replication` block were already present (a re-run, a changed image), appending a second one produces a duplicate YAML key and `mongod` refuses to start. Confirm the block is absent.

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'cat /etc/mongod.conf'
```

Expect `net:` / `storage:` / `processManagement:` / `systemLog:` / `operationProfiling:` and **no `replication:`**.

**A.3b — append:**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'printf "\nreplication:\n  replSetName: <set-name>\n" | sudo tee -a /etc/mongod.conf'
```

**A.4 — Restart mongod, then prove the config actually took.**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'sudo systemctl restart mongod && sleep 4 && systemctl is-active mongod'
```

**`systemctl is-active` is not enough, and `db.hello().setName` is a TRAP.** On a node that carries `replSetName` but has not yet been added to a set, `setName` is **empty** — which is indistinguishable from the config not having been read at all. Both look like success. The probe that actually discriminates is the error code from `rs.status()`:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "try { rs.status() } catch (e) { print(e.codeName + \": \" + e.message) }"'
```

- `NotYetInitialized: no replset config has been received` → **correct**. The node is running as a member of the named set and is waiting to be added.
- Anything mentioning replication not being enabled → the append or the restart did not take. Fix before `rs.add`.

(Found 2026-07-15: the first draft verified with `db.hello().setName`, which returns empty in the healthy pre-`rs.add` state and would have passed a node whose config never loaded.)

**A.5 — Add both new DATA nodes to the set, as non-voting followers.** Run from the **primary**. `votes: 0, priority: 0` is what keeps the election safe while they sync.

**One at a time** — MongoDB accepts at most one voting-member change per reconfig, and `rs.add` of a `votes: 0` member is still a config change to serialize. Confirm `ok: 1` on each before the next.

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.add({ host: \"integrator-<client>-mongo004.4shark.internal:27017\", votes: 0, priority: 0 })"'
```

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.add({ host: \"integrator-<client>-mongo005.4shark.internal:27017\", votes: 0, priority: 0 })"'
```

`votes: 0` **and** `priority: 0` together are mandatory, not belt-and-braces: a non-voting member is required to be priority 0 (§ Rule 2 constraints).

The set is now **5 members**. The new arbiter (006) is **not** added — it is swapped in at B.4.

**A.6 — Wait for both to reach `SECONDARY`.** The initial sync is the slow part; both run in parallel, which is the whole reason all three nodes are stood up at once.

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.status().members.map(m => m.name + \" \" + m.stateStr + \" health=\" + m.health)"' > /tmp/<client>_sync_check.log 2>&1
```

Do not proceed until **both** new data nodes read `SECONDARY health=1`. Poll — do not guess a duration; the sync scales with the data volume.

---

## Phase B — cut the set over

**This is the destructive half.** The old nodes keep their data and stay running, so an abort is still a step back rather than a restore — but from B.3 onward the old *set* no longer exists as a set. Everything before this point is additive; nothing after it is.

**Three rules govern the whole phase.**

**Rule 1 — the reconfig helper depends on the DIRECTION of the vote change.** These are different commands and they are not interchangeable:

| Change | Command | Why |
|---|---|---|
| `votes: 0 → 1` (promote) | `rs.reconfigForPSASet(idx, cfg)` | The helper performs the two safe internal reconfigs itself. It **requires the member to be at `votes: 0` in the current config**. |
| `votes: 1 → 0` (demote) | `rs.reconfig(cfg)` | `reconfigForPSASet` would **fail** here — the member is already voting, which is exactly the precondition it rejects. |
| priority only, votes unchanged | `rs.reconfig(cfg)` | The helper exists for the vote transition; a priority move does not need it. |

(The first draft of this file used `reconfigForPSASet` for the demote at B.4. It would have failed on contact. Corrected 2026-07-15 against `~/.claude/docs/runbooks/databases/MONGODB-VERSION-UPGRADE.md` § The PSA reconfig guard, before it ran.)

**Rule 2 — compute the member index inline; never hand-substitute it.** `rs.reconfigForPSASet` takes the member's **index in the config array**, not its host. The index shifts as members are removed, so a value read three commands ago is a live grenade. `findIndex` on the host is the only safe form.

**Two MongoDB constraints bound every reconfig below.** Both are the vendor's, not ours:

- **A member with `votes: 0` must have `priority: 0`** ([docs](https://www.mongodb.com/docs/manual/tutorial/configure-a-non-voting-replica-set-member/)). Vote and priority move together on the way up (`0/0 → 1/0.5`) and on the way down (`1/0.5 → 0/0`). A config that gives a non-voting member a non-zero priority is rejected whole.

  **The constraint is one-directional only.** `votes: 1` with `priority: 0` is perfectly legal — that is what an arbiter is, and what a "voting but never primary" member is. Observed directly: `reconfigForPSASet` passes *through* `{ votes: 1, priority: 0 }` as its own first internal step. (A secondary source claimed the reverse — "voting members cannot have priority 0" — and it is wrong; the helper's own output disproves it.)
- **A reconfig may add or remove at most ONE voting member at a time.** This is why B.3 removes the old data nodes one at a time and why the arbiter swap is six discrete steps rather than one clever config. The step-by-step shape is a requirement, not caution.

**Rule 3 — the priority pattern is `others → 0.5`, `target → 1`. Always. Never a number above 1.**

This is MongoDB's own documented procedure for forcing a specific member to become primary ([Force a Self-Managed Replica Set Member to Become Primary](https://www.mongodb.com/docs/manual/tutorial/force-member-to-be-primary/)), quoted literally:

```
cfg = rs.conf()
cfg.members[0].priority = 0.5
cfg.members[1].priority = 0.5
cfg.members[2].priority = 1
rs.reconfig(cfg)
```

An election only fires when a member's priority is **strictly higher** than the current primary's — so the move is always relative: push the others down, pull the target up. The doc also states: *"You also can force a member never to become primary by setting its `members[n].priority` value to `0`"*.

**Why this pattern and not "primary-candidate = 2".** The fleet's old habit was to promote with `priority: 2` and leave it there. That is what broke on almaviva today: the node being retired was itself promoted to `2` by Step 2, so promoting the new node to `2` produced a **tie** and no election — the reconfig returned `ok: 1` and the old primary stayed. Escalating (3, then 4…) turns the priority into a generation counter and defers the same failure. Ending every promotion at `1` makes the recipe **idempotent across generations**: the next OS migration runs the identical `others → 0.5, target → 1` and works, forever.

**Consequence — the steady state changes.** After this migration a set reads `primary = 1`, `secondary = 0.5`, `arbiter = 0`. The old `2 / 1 / 0` shape is retired. Both express the same intent (a designated primary-candidate); only this one composes with itself.

**Track the voting count.** It is what the order exists to protect:

| After step | Voting members | Count | Priorities |
|---|---|---|---|
| *(start)* | 001, 002, 003 | 3 | 001=2, 002=1 |
| B.1a | 001, 002, 003, **004** | 4 | 004=0.5 (eligible, not yet a candidate) |
| B.1b | 001, 002, 003, 004 | 4 | 001=0.5, 002=0.5, **004=1** → 004 elects |
| B.2 | 001, 002, 003, 004, **005** | 5 | 005=0.5 |
| B.3a | 002, 003, 004, 005 | 4 | |
| B.3b | 003, 004, 005 | 3 | |
| B.4c | 003, 004 | 2 | 005 → votes 0 |
| B.4d | 004 | 1 | |
| B.4e | 004, **006** | 2 | |
| B.4f | 004, 005, 006 | **3** ✓ | 004=1, 005=0.5, 006=0 |

The even counts are transient reconfig moments (seconds), not states the set sits in. The long window — the initial sync — was deliberately held at 3 by adding the new data nodes non-voting (A.5). That is the property that matters.

**B.0 — Re-confirm the integration window is still clear.** Phase A's sync may have taken a while; the check from 0.1 goes stale.

```bash
aws ecs list-tasks --region sa-east-1 --cluster integrator-<client>-cluster --desired-status RUNNING --output json > /tmp/<client>_running_tasks_preB.json 2>&1
```

**B.1 — Promote 004 to primary-candidate.**

> **TRAP — `priority: 2` is a TIE, not a win. The promote recipe is NOT idempotent across generations.** Measured on almaviva, 2026-07-15: the reconfig returned `ok: 1`, and **001 stayed PRIMARY**. Cause: **001 is itself at `priority: 2`**, because Step 2 promoted it with this very recipe (`PLAN.md`: *"promoted a new data node via reconfigForPSASet priority:2"*). MongoDB only triggers an election when a member's priority is **strictly higher** than the current primary's — equal priority leaves the incumbent in place. Step 2 worked because the nodes it replaced were `4client-*` at the default `priority: 1`; every node this migration replaces is a former migration's promoted primary-candidate and carries `priority: 2` already.
>
> **This will fire on maqnelson, atento and commcenter too** — all three were promoted the same way.
>
> **Read the config before promoting. Never assume the old primary is at the default priority:**
>
> ```bash
> ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "rs.conf().members.map(m => m.host + \" votes=\" + m.votes + \" priority=\" + m.priority + \" arbiter=\" + m.arbiterOnly)"'
> ```

It takes **two commands**, because two different things change and each needs its own tool (Rule 1). Run both from the current primary (001).

**B.1a — give 004 a vote** (`votes: 0 → 1`, so `reconfigForPSASet`). Priority goes to `0.5`, not straight to the target value: this step only makes 004 *eligible*, it does not yet ask for the election.

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "cfg = rs.conf(); idx = cfg.members.findIndex(m => m.host == \"integrator-<client>-mongo004.4shark.internal:27017\"); cfg.members[idx].votes = 1; cfg.members[idx].priority = 0.5; rs.reconfigForPSASet(idx, cfg)"'
```

**B.1b — force the election** (priority only, so plain `rs.reconfig`). This is Rule 3 verbatim: every other data member down to `0.5`, the target up to `1`. **This is the write blip** — the old primary sees it no longer holds the highest priority and steps down, closing client connections for ~10-20s ([MongoDB docs](https://www.mongodb.com/docs/manual/tutorial/force-member-to-be-primary/)).

**The filter is `!m.arbiterOnly && m.votes > 0`, and both halves are load-bearing:**

- **Skip the arbiter** — an arbiter is always `priority: 0`.
- **Skip non-voting members** — [MongoDB requires a member with `votes: 0` to have `priority: 0`](https://www.mongodb.com/docs/manual/tutorial/configure-a-non-voting-replica-set-member/). At this point 005 is still `votes: 0`, so a blanket `forEach` that gives it `0.5` produces an **invalid config and the whole reconfig is rejected**. (Caught before running, 2026-07-15 — the first draft of this command had the blanket form.)

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<old-001> 'mongosh --quiet --eval "cfg = rs.conf(); cfg.members.forEach(m => { if (!m.arbiterOnly && m.votes > 0) m.priority = 0.5 }); cfg.members[cfg.members.findIndex(m => m.host == \"integrator-<client>-mongo004.4shark.internal:27017\")].priority = 1; rs.reconfig(cfg)"'
```

**B.1c — confirm 004 actually took the primary role. Do not assume the election went the way the priority asked** — that assumption is exactly what failed on almaviva, and `ok: 1` came back both times.

**The `sleep` is not padding.** `rs.reconfig` returns as soon as the config is accepted; the election happens after. Reading `rs.status()` immediately shows the *pre-election* state and reports the OLD primary — which looks identical to a genuine failure to elect. ~12s covers it (the fleet's measured election is ~10-20s).

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'sleep 12; mongosh --quiet --eval "rs.status().members.find(m => m.stateStr == \"PRIMARY\").name"'
```

**B.1d — confirm the priorities landed as intended**, including that the non-voting member was left alone:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.conf().members.map(m => m.host + \" votes=\" + m.votes + \" priority=\" + m.priority + \" arbiter=\" + m.arbiterOnly)"'
```

Expect: old data nodes at `votes=1 priority=0.5`, arbiter at `votes=1 priority=0`, **004 at `votes=1 priority=1`**, and 005 still at `votes=0 priority=0` (untouched — proof the `m.votes > 0` filter held).

**Every command from here runs against 004** — it is the primary now.

**B.2 — Promote 005 to electable, at `0.5`.** It becomes the surviving secondary; without a vote it could not sustain the final PSA. It stays at `0.5` so 004 remains the designated primary-candidate — that is the steady state Rule 3 leaves behind (`primary = 1`, `secondary = 0.5`).

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "cfg = rs.conf(); idx = cfg.members.findIndex(m => m.host == \"integrator-<client>-mongo005.4shark.internal:27017\"); cfg.members[idx].votes = 1; cfg.members[idx].priority = 0.5; rs.reconfigForPSASet(idx, cfg)"'
```

**B.3 — Remove the two old DATA nodes, ONE AT A TIME. THIS IS THE POINT OF NO RETURN.**

Up to here the old data nodes are still voting members holding live data — if the new primary died, the set would elect a focal node by itself and keep serving. **After B.3 that safety net is gone**: the old nodes become idle machines holding a frozen copy, and recovery changes from "it heals itself" to "re-add a member and re-sync". The Phase 0.2 snapshots and the still-running old instances are the rollback from here on.

Both are plain secondaries now (004 took the primary role at B.1), so neither removal moves the primary. One at a time because MongoDB accepts at most one voting-member change per reconfig (§ Rule 2 constraints) — this is a requirement, not caution.

**B.3a — remove the old primary-candidate:**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.remove(\"integrator-<client>-mongo001.4shark.internal:27017\")"'
```

**Verify before the next removal** — 4 members, 004 still PRIMARY, everything `health=1`:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.status().members.map(m => m.name + \" \" + m.stateStr + \" health=\" + m.health)"'
```

**B.3b — remove the old secondary:**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.remove(\"integrator-<client>-mongo002.4shark.internal:27017\")"'
```

**Verify** — 3 members (004 PRIMARY, 005 SECONDARY, 003 old ARBITER), all `health=1`. The set is now entirely noble except the arbiter, which B.4 swaps:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.status().members.map(m => m.name + \" \" + m.stateStr + \" health=\" + m.health)"'
```

**B.4 — Swap the arbiter. Six steps, and the order is the whole point.**

The set is now P(004) + S(005) + A(003-old). To retire the old arbiter and install the new one, MongoDB will **reject** a reconfig that produces a PSA topology with an *electable* secondary — so 005 must be lowered out of the way and restored afterwards. That is the entire reason for steps (c) and (f).

**B.4a — give 006 the set name** (identical to A.3; the arbiter runs the same golden image and is missing the same block).

Preflight first — same reason as A.3a (never append blind), plus it confirms the image on the arbiter, which A.2 only checked on the data nodes:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new ubuntu@<new-006> 'hostname && lsb_release -cs && systemctl is-active mongod && grep -c replication /etc/mongod.conf'
```

Expect `noble`, `active`, and `0`. **This command exits 1 on success — read the output, not the exit code.** `grep -c` returns exit 1 when the count is zero, so the chain "fails" exactly when it confirms what it was asked to confirm (`0` = no `replication` block = ready to append). Do not let an automation abort on this.

Then append:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-006> 'printf "\nreplication:\n  replSetName: <set-name>\n" | sudo tee -a /etc/mongod.conf'
```

**B.4b — restart it and prove the config took** (the `NotYetInitialized` probe from A.4, same trap):

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-006> 'sudo systemctl restart mongod && sleep 4 && systemctl is-active mongod && mongosh --quiet --eval "try { rs.status() } catch (e) { print(e.codeName) }"'
```

**B.4c — lower 005 out of the way.** `rs.reconfig`, **not** `reconfigForPSASet` (Rule 1 — this is a demote):

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "cfg = rs.conf(); idx = cfg.members.findIndex(m => m.host == \"integrator-<client>-mongo005.4shark.internal:27017\"); cfg.members[idx].votes = 0; cfg.members[idx].priority = 0; rs.reconfig(cfg)"'
```

**B.4d — remove the old arbiter:**

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.remove(\"integrator-<client>-mongo003.4shark.internal:27017\")"'
```

**B.4e — add the new arbiter.** The topology is PSA with a non-electable secondary, which the guard accepts:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.addArb(\"integrator-<client>-mongo006.4shark.internal:27017\")"'
```

> **⚠ Between B.4c and B.4f the set is at its most fragile.** With 005 non-voting, the only voters are the primary and the arbiter — **two votes, majority two**. Lose the primary in this window and nothing can be elected: the arbiter alone is 1 of 2, and the secondary cannot vote. The set would go read-only until 005 is restored.
>
> This transient is unavoidable (the PSA guard demands the secondary be non-electable while the arbiter is swapped), but it must be **passed through, never parked in**. Run B.4c → B.4d → B.4e → B.4f back to back. Do not stop for anything between them, and do not leave this window open across a break.

**B.4f — restore 005** to `votes: 1, priority: 0.5`. `reconfigForPSASet` is correct here — 005 is at `votes: 0`, which is precisely its precondition:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "cfg = rs.conf(); idx = cfg.members.findIndex(m => m.host == \"integrator-<client>-mongo005.4shark.internal:27017\"); cfg.members[idx].votes = 1; cfg.members[idx].priority = 0.5; rs.reconfigForPSASet(idx, cfg)"'
```

**B.5 — Verify the final all-new PSA.** 004 PRIMARY, 005 SECONDARY, 006 ARBITER, all `health: 1`, exactly three members:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.status().members.map(m => m.name + \" \" + m.stateStr + \" health=\" + m.health)"'
```

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "rs.conf().members.map(m => m.host + \" votes=\" + m.votes + \" priority=\" + m.priority)"'
```

Expect exactly three members, in the Rule 3 steady state: 004 at `votes=1 priority=1`, 005 at `votes=1 priority=0.5`, 006 arbiter at `votes=1 priority=0`. **If any member reads `priority=2`, the old non-idempotent shape survived — fix it before closing the environment**, or the next OS migration inherits the same tie.

Then the version, which must **not** have moved:

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "db.version()"'
```

```bash
ssh -i ~/.ssh/kp-4shark.pem -o ConnectTimeout=25 ubuntu@<new-004> 'mongosh --quiet --eval "db.adminCommand({getParameter:1, featureCompatibilityVersion:1}).featureCompatibilityVersion.version"'
```

Expect `8.0.26` and `8.0` — the OS moved, the version did not. **Separate calls: `mongosh --eval A --eval B` prints only the last.**

---

## Phase C — cut the app over

**Order (engineer, 2026-07-15): stop the old nodes FIRST, then SSM, then the repoint PR, then deploy, then the gate.** Stopping first makes the deploy prove itself against a fleet where the old nodes are already gone, rather than proving it later.

> **The MONGODB URL is NOT in Terraform. There is no URL to change in a PR.**
>
> `integrator-<client>/ssm.tf` creates the parameter with `value = "PLACEHOLDER"` and `lifecycle { ignore_changes = [value] }` — Terraform creates the parameter and then never looks at its value again. The file's own header documents the only path: `aws ssm put-parameter --overwrite`. A Terraform PR "changing the URL" would have an empty diff.
>
> **What Terraform DOES own is the instance-id repoint (C.5)** — four references to the old nodes that must move to the new ones. Those are a real PR, and they are what "point at the new instances" actually means.

**C.1 — Stop the old trio.** They are already out of the set (B.3/B.4), so this is non-disruptive; they stay as a cold fallback with their data. **Instance ids are POSITIONAL** (same as `start-instance.sh` — there is no `--instance-id` flag on either):

```bash
bash ~/.claude/scripts/stop-instance.sh --profile 4shark-mfa <old-001-id> <old-002-id> <old-003-id>
```

**C.2 — Repoint the SSM `MONGODB` value** to the `mongo004/005/006` hostnames, preserving the rest of the connection string. **This is `put-parameter`, not Terraform.** atento has **7** params; commcenter has **2**.

**Swap by ROLE, not by arithmetic:** `001→004` (data, primary-candidate), `002→005` (data, secondary), `003→006` (arbiter). The numbers happen to line up here; the roles are what must line up.

**Never let the value through the session.** It is a SecureString, and § Layer 0 lists connection strings as credentials. `PLAN.md` records an earlier assessment that this particular string carries no password — do not lean on that. The file round-trip costs nothing and removes the question:

```bash
aws ssm get-parameter --region sa-east-1 --name /integrator-<client>/MONGODB --with-decryption --query Parameter.Value --output text > /tmp/<client>_mongodb_url.txt 2>&1
```

Inspect **only the hostnames**, never the whole string, and take the byte count as a baseline:

```bash
grep -o 'integrator-<client>-mongo00[0-9]' /tmp/<client>_mongodb_url.txt
```

```bash
wc -c < /tmp/<client>_mongodb_url.txt
```

Transform locally. **`tr -d '\n'` is mandatory** — `--output text` appends a newline, and `file://` would store it as part of the connection string:

```bash
sed 's/integrator-<client>-mongo001/integrator-<client>-mongo004/g; s/integrator-<client>-mongo002/integrator-<client>-mongo005/g; s/integrator-<client>-mongo003/integrator-<client>-mongo006/g' /tmp/<client>_mongodb_url.txt | tr -d '\n' > /tmp/<client>_mongodb_url_new.txt
```

Verify the swap **and the length**: the byte count must drop by exactly 1 (the newline). The hostnames are the same length, so any other delta means `sed` touched something it should not have.

```bash
grep -o 'integrator-<client>-mongo00[0-9]' /tmp/<client>_mongodb_url_new.txt
```

```bash
wc -c < /tmp/<client>_mongodb_url_new.txt
```

Write it with `file://`, so the value never appears in a command line either:

```bash
aws ssm put-parameter --region sa-east-1 --name /integrator-<client>/MONGODB --value file:///tmp/<client>_mongodb_url_new.txt --type SecureString --overwrite --profile 4shark-mfa
```

Re-read and confirm. A stored length one byte over the written length means `file://` kept a trailing newline — fix it before deploying, or the driver gets a malformed host.

**C.3 — Repoint the four Terraform references to the new instances. This is the real PR.**

`compute.tf` names the old instances in four places, and **every one of them must move to `integrator_mongo004/005/006` or the daily-shutdown cycle is broken**:

```bash
grep -rn "integrator_mongo00[123]" /Users/plribeiro3000/Projects/4Shark/terraform/integrator-<client>/
```

| Reference | What breaks if it is left pointing at the old nodes |
|---|---|
| `AWS_INSTANCE_IDS` env var | the app's ShutDownWorker stops the OLD (retired) nodes and never stops the new ones — they run forever |
| `ec2:StartInstances` Resource in `aws_iam_role_policy.ecs_scheduler` | the scheduler is not permitted to start the nodes that actually serve |
| `InstanceIds` in `aws_scheduler_schedule.start_mongodb` | the pre-window start fires at the wrong machines; the real set is never brought up |
| `ec2_instance_arns` in `module.iam_deploy` | the deploy user cannot act on the serving nodes |

**Do not grep only `compute.tf`** — atento's `ec2_instance_arns` lives in **`alb.tf`** instead (PLAN.md, atento teardown lesson). Grep the whole stack.

**This is urgent for a daily-shutdown environment and cannot wait for the teardown PR.** The scheduler fires before the next integration window; until this lands it starts and stops machines that are no longer in the replica set. The repoint is safe on its own — the old blocks still exist, they are simply no longer referenced. Only their *removal* (Phase D) has to be coupled.

**C.4 — Deploy. Mandatory, not optional.** The app does not re-resolve SSM on its own — this was assumed once, was never verified, and is treated as false. The deploy is also what picks up the new `AWS_INSTANCE_IDS` from C.3.

```bash
gh workflow run deploy.yaml -R 4shark/integrator -f integrator=<slug>
```

**C.5 — Engineer validates via `bin/ecs run`, with the old cluster OFF. This is the gate.** It must show `ApplicationConfiguration.mongodb` on the new hostnames and `User.count` intact. Old-cluster-off is the point: it proves the app has no hidden dependency on the old nodes. Here the old nodes were stopped back at C.1, so the gate is already being run under the right conditions.

Reference counts from the 8.0 validation (2026-07-14): almaviva 17026, maqnelson 193, atento-mx 10063, commcenter 1992.

---

## Phase D — teardown (separate PR, only after C.4 passes)

**Do not start before the gate passes.** This is the irreversible half.

**D.1 — DNS FIRST.** A `data "aws_instance"` matches `running`/`stopped` but **not** `terminated`. Terminate first and every later `plan`/`apply` of the whole `dns` stack errors. Remove the 3 `data` blocks + 3 records for 001/002/003 and apply the `dns` stack **before** touching the instances.

**D.2 — Capture the root volume ids BEFORE terminating.** `delete_on_termination = false` orphans them; they survive as `available` and keep costing.

```bash
aws ec2 describe-instances --region sa-east-1 --instance-ids <old-001-id> --query "Reservations[].Instances[].BlockDeviceMappings[0].Ebs.VolumeId" --output text
```

**D.3 — Clear termination protection on each old node.** The AWS provider does **not** auto-disable it on destroy; `TerminateInstances` fails with `OperationNotPermitted`.

```bash
aws ec2 modify-instance-attribute --region sa-east-1 --instance-id <old-001-id> --no-disable-api-termination --profile 4shark-mfa
```

**D.4 — Remove the `aws_instance` blocks.** `prevent_destroy` is cleared by **removing the block**, not by editing it — no intermediate apply needed.

**Grep the whole stack first** — the old-node references are not always in `compute.tf`:

```bash
grep -rn "aws_instance.integrator_mongo00[123]" /Users/plribeiro3000/Projects/4Shark/terraform/integrator-<client>/
```

For **almaviva and maqnelson** (daily-shutdown) repoint all four references to `integrator_mongo004/005/006` in the same PR, or `plan` fails with "Reference to undeclared resource": `AWS_INSTANCE_IDS`, the `ec2:StartInstances` Resource list in `aws_iam_role_policy.ecs_scheduler`, the `InstanceIds` in the `aws_scheduler_schedule.start_mongodb` target, and `ec2_instance_arns` in `module.iam_deploy`. For **atento** the single reference lives in `alb.tf`. **commcenter** has none.

**D.5 — Delete the orphaned volumes.**

```bash
aws ec2 delete-volume --region sa-east-1 --volume-id <root-volume-id> --profile 4shark-mfa
```

**D.6 — (daily-shutdown only) START → deploy → STOP.** The teardown changed `AWS_INSTANCE_IDS`, and the app only picks it up on a deploy — otherwise the ShutDownWorker still targets terminated instance ids and the daily cycle is broken. The deploy's preflight requires mongo running, hence the order.

---

## Progress

| Environment | Phase 0 | Phase A | Phase B | Phase C | Phase D |
|---|---|---|---|---|---|
| almaviva | **DONE** | **DONE** | **DONE** — all-noble PSA, 8.0.26/FCV 8.0 | C.1–C.4 done; **resume at C.5 — engineer's `bin/ecs run` gate** | blocked on C.5 |
| maqnelson | — | — | — | — | — |
| atento | — | — | — | — | — |
| commcenter | — | — | — | — | — |

### almaviva — exact state (2026-07-15)

**Set name: `almaviva`** — read from the primary, confirmed not assumed.

| Role | Node | Instance | IP | State after Phase B |
|---|---|---|---|---|
| old data | mongo001 | `i-0cd07e231c9329506` | 10.1.0.51 | **running, OUT of the set** — frozen copy, cold fallback |
| old data | mongo002 | `i-002507fbd26dcda2d` | 10.1.0.81 | **running, OUT of the set** — frozen copy, cold fallback |
| old arbiter | mongo003 | `i-0011d11c35213667a` | 10.1.0.95 | **running, OUT of the set** — holds no data |
| new data | mongo004 | `i-010dc808ccd1c512f` | 10.1.0.9 | **PRIMARY** — noble, `votes:1 priority:1` |
| new data | mongo005 | `i-037447a0c68422b51` | 10.1.0.70 | **SECONDARY** — noble, `votes:1 priority:0.5` |
| new arbiter | mongo006 | `i-0b62a5d5d92083bf4` | 10.1.0.104 | **ARBITER** — noble, `votes:1 priority:0` |

**Do not stop or terminate 001/002/003 until Phase C's `bin/ecs run` gate passes** — they are the rollback.

**Restore points (Phase 0.2, taken while the nodes were stopped → consistent by construction):**

| Node | Root volume | Snapshot |
|---|---|---|
| mongo001 | `vol-03a3a7519b7e45fb6` | `snap-07105ca280b9b9a21` |
| mongo002 | `vol-032352ce4532f44f1` | `snap-0f74f27ecd90e0ccc` |

**Done:** 0.1 window clear (`taskArns: []`) → 0.2 snapshots → 0.3 old trio started (set reconstituted clean: 001 PRIMARY / 002 SECONDARY / 003 ARBITER, all `health=1`) → 0.4/0.5 health + set name → A.2 SSH + image verified (`noble`, `v8.0.26`, `active` — patch matches the old set exactly) → A.3 `replSetName: almaviva` appended to 004 and 005 → A.4 both restarted, both probe `NotYetInitialized` → A.5 both `rs.add`'d as `votes:0/priority:0`, both `ok: 1` → A.6 both reached `SECONDARY health=1` (sync was quick — 17k users) → B.0 window re-checked, still clear → **B.1a/B.1b: 004 is PRIMARY.**

**Config after B.2 — verified, not assumed:**

```
mongo001  votes=1 priority=0.5   demoted, focal, still holds its data
mongo002  votes=1 priority=0.5   demoted, focal, still holds its data
mongo003  votes=1 priority=0     arbiter, focal
mongo004  votes=1 priority=1     PRIMARY  ← noble, serving
mongo005  votes=1 priority=0.5   SECONDARY  ← noble, electable
```

This is already the Rule 3 steady state among the new nodes (`1` / `0.5`); the three old members are still in the set at `0.5` / `0.5` / arbiter and come out at B.3–B.4.

**almaviva is now being served by a MongoDB 8.0.26 primary on Ubuntu 24.04.** The two `ok: 1` responses on the way here proved nothing on their own — the first promote returned `ok: 1` and elected nobody. Only `rs.status()` settles it.

→ **B.2: 005 promoted** to `votes: 1, priority: 0.5` (`ok: 1`; the helper stepped through `{votes:1, priority:0}` then `{priority:0.5}`).

→ **B.3: the point of no return was crossed.** 001 removed (`ok: 1`, verified 4 members / 004 still PRIMARY), then 002 removed (`ok: 1`). The set went to 3 members — `mongo003` ARBITER (focal) / `mongo004` PRIMARY (noble) / `mongo005` SECONDARY (noble), all `health=1`.

**Every byte of almaviva's data now lives on Ubuntu 24.04.** Both data members are noble; only the arbiter (which holds no data) was still focal.

**Rollback from here** is no longer automatic. 001 (`i-0cd07e231c9329506`) and 002 (`i-002507fbd26dcda2d`) are running, hold a frozen copy, and are out of the set — recovering to them means re-adding a member and re-syncing, or restoring `snap-07105ca280b9b9a21` / `snap-0f74f27ecd90e0ccc`. Do not stop or terminate them until Phase C's validation gate passes.

→ **B.4a–B.4e done. B.4f NOT run.**

- **B.4a preflight** — `hostname && lsb_release -cs && systemctl is-active mongod && grep -c replication /etc/mongod.conf` on 006 → `ip-10-1-0-104` / `noble` / `active` / `0`. **The command exited 1 and that was a false alarm**: `grep -c` exits 1 when the count is 0, so the chain "fails" precisely by confirming what it was asked to confirm. Read the output, not the exit code.
- **B.4a append** — `replSetName: almaviva` appended to `/etc/mongod.conf` on 006.
- **B.4b restart** — `active` + probe `NotYetInitialized` (the config took).
- **B.4c** — 005 lowered to `votes: 0, priority: 0` via **`rs.reconfig`** → `ok: 1`.
- **B.4d** — old arbiter `mongo003` removed → `ok: 1`.
- **B.4e** — `rs.addArb("integrator-almaviva-mongo006...")` → `ok: 1`.

→ **B.4f done — the fragile window is CLOSED.** 005 restored to `votes: 1, priority: 0.5` via `reconfigForPSASet` → `ok: 1`. All three members vote again.

> **Rule 2 proved itself here.** The helper reported `member at index 1` — 005 had been index **4** when Phase A added it, and became index **1** once 001/002/003 were removed. A hand-substituted index (which the first draft of this file used) would have reconfigured the wrong member. `findIndex` absorbed the shift silently.

→ **B.5 — PHASE B COMPLETE. Verified, not assumed:**

```
integrator-almaviva-mongo004  PRIMARY    health=1   votes=1 priority=1
integrator-almaviva-mongo005  SECONDARY  health=1   votes=1 priority=0.5
integrator-almaviva-mongo006  ARBITER    health=1   votes=1 priority=0
```

`db.version()` = **`8.0.26`**, FCV = **`8.0`** — byte-identical to what the fleet ran before this started. **The OS moved; the version did not.** That is the whole thesis of Step 6, confirmed on the first environment.

**No focal member remains in the set.** No member carries `priority=2` — the non-idempotent shape is gone from almaviva, so its next OS migration will elect on the first try.

→ **C.1 done — old trio stopped** (`i-0cd07e231c9329506` / `i-002507fbd26dcda2d` / `i-0011d11c35213667a`). The set was verified **unaffected** immediately after: `004 PRIMARY / 005 SECONDARY / 006 ARBITER`, all `health=1`. almaviva kept serving with every focal machine powered off — which is the real proof Phase B was complete.

→ **C.2 done — SSM `/integrator-almaviva/MONGODB` is now Version 4**, carrying `mongo004/005/006`. The value never entered the session: read to file → hostnames inspected via `grep -o` → `sed` + `tr -d '\n'` → written back with `file://`. Byte accounting confirmed integrity end to end (172 read → 171 written → 172 re-read; the only delta is the newline `--output text` adds).

→ **C.3 — repoint PR open: [terraform#705](https://github.com/4shark/terraform/pull/705).** All four `compute.tf` references moved to `integrator_mongo004/005/006`, verified by grep: the only surviving `integrator_mongo00[123]` matches are the three `resource` blocks in `mongodb.tf` — the definitions themselves, which is exactly what should remain. They are now unreferenced, so Phase D can delete them without a "Reference to undeclared resource" failure.

Plan: **4 to add, 4 to change, 4 to destroy** — the 4 add/destroy are task-definition revisions (runner / scheduled_task / web / worker, all carrying `AWS_INSTANCE_IDS`), the 4 changes are the scheduler policy, the `start_mongodb` schedule, the `iam_deploy` policy, and the scheduled_task schedule. Services are not recreated. This matches the documented cascade exactly.

**The urgency is measured, not guessed:** `aws_scheduler_schedule.start_mongodb` is `cron(50 0 * * ? *)` — **00:50 UTC**, five minutes before the window. Until this applies, it fires at three stopped, retired machines and the serving nodes are never started or stopped by anything.

→ **C.3 applied — `4 added, 3 changed, 4 destroyed`.**

**The plan said 4 changes and the apply made 3 — investigated, benign.** The fourth (`module.scheduled_task.aws_scheduler_schedule.this[0]`) planned as a change only because its `task_definition_arn` went `(known after apply)` while the task-def was replaced. At apply time the new value resolved to the **same string**, so nothing needed writing. The reason is a property worth knowing:

> **The scheduled task targets the task-definition FAMILY, not a pinned revision** — `arn:aws:ecs:…:task-definition/integrator-<client>-cron-integration-cron`, with no `:N` suffix. ECS resolves the family to the latest ACTIVE revision at run time, so a new revision is picked up with no repoint. Verified live via `aws scheduler get-schedule`.

**Verified live, not inferred:**

| Check | Result |
|---|---|
| `aws scheduler get-schedule … start-mongodb` | `cron(50 0 * * ? *)`, `ENABLED`, `InstanceIds` = `i-010dc808ccd1c512f` / `i-037447a0c68422b51` / `i-0b62a5d5d92083bf4` — **the noble nodes** |
| latest `…-cron-integration-cron` task-def | **revision 55**, `AWS_INSTANCE_IDS` = the same three noble ids |
| schedule's `TaskDefinitionArn` | family-level (no revision) → resolves to 55 |

**The daily-shutdown cycle is fixed.** Tonight's 00:50 UTC start fires at the machines that actually serve.

→ **C.4 — deploy `29418707622` SUCCESS.** Every job green: `Preflight` / `Quiet worker` / `Migrate` / `Register cron tasks` / `Deploy web` / `Deploy worker`.

**Two of those jobs are independent proof, not just green ticks:**

- **`Preflight`** reads the `MONGODB` URL from SSM and checks connectivity — it validated the C.2 `put-parameter` without being told about it.
- **`Migrate`** *connected to MongoDB over the new URL and ran migrations* — **with every old node stopped since C.1**. The application reached the all-noble set and wrote to it. That is the hidden-dependency question answered by behaviour rather than by inspection.

→ **[terraform#705](https://github.com/4shark/terraform/pull/705) merged** and cleaned up (worktree removed, `develop` at `d3a88eb`, branch deleted with `-d`).

**Resume at C.5 — the engineer's `bin/ecs run almaviva` gate.** It must show `ApplicationConfiguration.mongodb` on `mongo004/005/006` and `User.count` = **17026** (the 2026-07-14 reference). The old nodes have been stopped since C.1, so the gate is already running under the required old-cluster-off condition.

**Phase D is blocked on that gate and must not start before it passes.**

---

## Harvest — this file IS the binary's specification

**Sequence decided by the engineer, 2026-07-15:**

1. **almaviva by hand** — every command, executed and written here as it ran. ← *done through C.4; C.5 is the engineer's gate, D follows*
2. **PAUSE. Build the automation** from this file, plus the spike that decides its shape.
3. **maqnelson, atento, commcenter run THROUGH the automation** — in a new session, end to end, with the agent resolving what comes up rather than asking. Each gap the run exposes is fixed **in the binary**, never worked around by hand.

**Why this order.** The version-hop skill slipped twice because it was to be reconstructed from a session transcript afterwards. This file is the opposite: written before the commands ran, corrected the moment each one taught something. The binary is a transcription of a procedure proven once in production — and then hardened by three more real runs. **Three environments is the test suite.**

### What the next session must be able to do unattended

The engineer's bar (2026-07-15): *run one environment end to end without asking permission, resolving whatever comes up, with backup taken and rollback available.* Concretely that means the binary must own:

- **The backup gate** — Phase 0.2 snapshots are not optional and not skippable. No mutation before a restore point exists at the current state.
- **The rollback story at each phase** — it changes as it goes, and the binary must know where it is: additive (abort is free) → B.1/B.2 (old nodes still voting, set self-heals) → **B.3 onward** (old nodes are a frozen copy; recovery is re-add + re-sync) → post-teardown (snapshots only).
- **Verification that discriminates** — every `ok: 1` in this file that proved nothing is a lesson. `rs.status()`, not the return code.
- **Abort, not improvise** — if a node does not come back healthy, stop and surface. Judgment lives in `SKILL.md`; the script stays mechanical.

**One boundary the binary cannot cross, by design:** `gh pr merge` is blocked by a PreToolUse hook, unconditionally. The automation can go all the way to *PR opened and applied*; the merge stays the engineer's. Design for that stop rather than around it.

### The known gap in this specification

**Phase D has not been executed.** The teardown carries traps documented from Step 2 (DNS removed before terminating, `disable_api_termination` cleared out of band, root volumes orphaned by `delete_on_termination = false`) — but **none of them has been seen in THIS shape**, and every phase so far taught something the plan did not predict. Do not treat Phase D's write-up as battle-tested the way Phases 0–C now are. Either execute almaviva's teardown before building the binary, or build the binary knowing its D is the weakest section.

**What almaviva has already contributed — each one is a bug the automation must not reproduce:**

| Finding | Where it would have bitten |
|---|---|
| `reconfigForPSASet` for a `votes: 1 → 0` demote **fails** — the demote is `rs.reconfig` | B.4c, on every environment |
| `priority: 2` is a **tie**, not a win — the old promote recipe is not idempotent across generations | B.1, on all four environments |
| The doc's `others → 0.5, target → 1` is the fix, and it composes with itself | the permanent shape |
| `db.hello().setName` is empty on an un-added node — it cannot verify the config took; `rs.status()` → `NotYetInitialized` can | A.4, every node |
| `mongosh --eval A --eval B` prints only the last | any chained verification |
| Snapshot **before** starting a daily-shutdown node — a stopped volume is consistent by construction | Phase 0, almaviva + maqnelson |
| `start-instance.sh` **and** `stop-instance.sh` take ids positionally, not `--instance-id` | Phase 0 and C.3 |
| The member index shifts as members are removed — compute it inline with `findIndex` | every reconfig |
| A non-voting member **must** be `priority: 0` — a blanket `forEach` over priorities rejects the whole config | B.1b |
| Only ONE voting member may change per reconfig — the six-step arbiter swap is a requirement, not caution | B.3, B.4 |
| `rs.reconfig` returns before the election resolves — reading `rs.status()` immediately reports the OLD primary, which is indistinguishable from a real failure | B.1c |
| Read `mongod.conf` before appending — a second `replication` block is a duplicate key and mongod refuses to start | A.3a |
| `grep -c` **exits 1 when the count is 0** — the preflight "fails" precisely when it confirms the block is absent. An automation that gates on exit code aborts here | B.4a |
| B.4c→B.4f is a **window where only the primary and arbiter vote** (majority 2). Losing the primary inside it leaves the set read-only with no election possible. The four steps must run back to back — an automation must never checkpoint, prompt, or retry-with-backoff inside them | B.4 |
| **The MONGODB URL is not in Terraform** — `ssm.tf` writes `PLACEHOLDER` + `ignore_changes = [value]`. A PR "changing the URL" has an empty diff; the only path is `put-parameter` | C.2 |
| Rotate the SSM value **through a file** — read to disk, `grep -o` only the hostnames, `sed`, write back with `file://`. The value never enters the session or a command line | C.2 |
| `--output text` appends a newline — **`tr -d '\n'` before `file://`** or the newline is stored inside the connection string. Byte-count the before/after: the delta must be exactly 1 | C.2 |
| The repoint of `AWS_INSTANCE_IDS` + scheduler + IAM is **urgent and separable** from the teardown. Left undone, the scheduler starts retired machines and never starts the serving ones — the daily-shutdown cycle silently breaks | C.3 |
| The repoint plan is `4 add / 4 change / 4 destroy` but applies as **`4 / 3 / 4`** — the scheduled-task schedule plans a change only because the task-def ARN is `(known after apply)`, and resolves to the same value. **Not a failure; do not chase it.** The schedule targets the task-def *family*, so revisions are picked up with no repoint | C.3 |

What the shape shows so far:

- Every node-touching command is `ssh -i ~/.ssh/kp-4shark.pem ubuntu@<node> '<cmd>'` — one access pattern, no exceptions.
- The commands are already parameterized by exactly four things: `<client>`, `<set-name>`, `<node>`, and the member index.
- The judgment — window check, snapshot gate, the `bin/ecs run` gate, abort-if-a-node-does-not-return-healthy — never appears in a command. It belongs in `SKILL.md`, per the settled design (PLAN.md § Upgrade-automation design): the script executes, the skill decides.
- **The re-provision is a different job from the version hop.** `mongodb-upgrade.sh hop --to <X.0>` is the in-place path. This procedure is a candidate second binary, not a fifth subcommand — the decision is open and belongs to the engineer once the shape is proven across four environments.
