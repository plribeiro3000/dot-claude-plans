# Phase 2 Decisions — Resolved (2026-07-10)

> Originally a list of "blocking decisions the engineer must make". Re-examined against 4Shark's own documentation, the existing terraform precedent, and community best-practice — **none of these is a genuine engineer design decision**; each resolves from a documented rule, an existing precedent, or a grounded external fact. Resolutions + grounding below. The only item that is not doc-resolvable is SPIKE-8, and that is an empirical Phase-3 test, not a Phase-2 decision.

## SPIKE-2: MongoDB VM provisioning ✅ RESOLVED — superseded by the golden-AMI pipeline

**Question:** How to provision the dedicated Mongo VM (new role 2A vs conditional in `4shark.pritunl` 2B)?

**Resolution:** **Neither.** The MongoDB golden-AMI pipeline (repo `mongodb` + `ansible-role-mongodb` + Packer, built/merged/validated 2026-07-10) bakes MongoDB into a versioned AMI. PR 2.3's Mongo VM launches from that AMI via a `data "aws_ami"` tag lookup — **no Ansible role runs on the VM at all**, so the 2A/2B question is moot.

**Corrected 2026-07-16:** the AMI is **MongoDB 8.0 on Ubuntu 24.04**, not 8.2 — `mongodb_version` tracks the X.0 LTS line only (`mongodb/packer/mongodb.pkr.hcl:45-54`), and 24.04 is a ceiling because MongoDB's apt repo 404s for 26.04 (`:71-75`). This resolution originally claimed the image "closes the 8.0→8.2 drift"; **there is no drift and no version change** — the combined VM runs 8.0 today (`ansible/roles/4shark.pritunl/defaults/main.yml:6`) and the AMI installs 8.0. What the image closes is the *provisioning*, not a version gap.

**Grounding:** `~/Projects/4Shark/dot-claude-plans/active/mongodb-golden-ami/PLAN.md` (its Phase 2 IS this Pritunl Mongo VM adoption; its Phase 3 — the 12-node integrator fleet cutover — is **complete** as of 2026-07-14/15, so this AMI now backs four production replica sets); the golden-AMI build/role/IAM are all merged.

---

## SPIKE-3: MongoDB security group scoping ✅ RESOLVED — SG-based (3A), per the Network Access Model

> **REVERSED 2026-07-16.** This item previously resolved to "3B — CIDR-scoped", on three claims that are all false. The governing document is `terraform/docs/NETWORK-ACCESS-MODEL.md` — the repo's own canonical standard for exactly this decision — and it mandates the opposite. The original reasoning is preserved below the correction so the error is legible, not silently rewritten.

**Question:** SG reference (3A) vs narrowed CIDR (3B) for Mongo-VM ingress?

**Resolution:** **3A — SG-based.** The Mongo VM's security group allows MongoDB's port from the **Pritunl instance's security group**, by reference. Not a CIDR.

**Grounding:** `terraform/docs/NETWORK-ACCESS-MODEL.md` is the canonical standard and states the rule in its decision table (`:45`): a source that is *"An AWS resource in the **same region + reachable VPC**"* → **"SG-based (default)"**. The Pritunl ECS instance and the Mongo VM are both in the management VPC in `sa-east-1` — precisely that row. CIDR is explicitly the fallback, used *"only where a security group cannot express the source"* (`:26`), which does not apply here. The doc also settles that this is not an open judgement call: *"This was once decided case by case; it is now a fixed standard"* (`:3`).

**Why the original three claims were wrong:**
1. **"Zero SG-to-SG precedent in the repo"** — false, and the cause was a bad grep. The search looked for `source_security_group_id` / `referenced_security_group_id`; the codebase expresses SG references as an inline `ingress { security_groups = [...] }` block, which that pattern never matches. Real precedents: RDS ingress 5432 from the pooler SG + app cluster SG (`app-shared-001/rds.tf:18-24`), OpenSearch 443 from the app cluster SG, the pooler 6432 from the app cluster SG (`modules/connection_pooler/main.tf`), the app ECS instances from the ALB SG (`modules/ecs_cluster/main.tf`). SG-based is the fleet's normal shape, not a novelty.
2. **`VPC-CROSS-VPC-CONNECTIVITY.md:40` mandates CIDR** — misapplied. That runbook governs **cross-VPC** connections, and gives the reason in the next line (`:51`): *"not just an EC2 SG reference, which doesn't cross VPC boundaries"*. It is a constraint about crossing a boundary this case does not cross.
3. **`VPC-DEPOSED-SG-DEPENDENCY.md` documents SG-to-SG `DependencyViolation` fragility** — that runbook never mentions SG-to-SG references. Its `DependencyViolation` comes from ENIs on instances stuck in `Terminating:Wait` holding a deposed SG during an ASG replacement. Unrelated mechanism.

**The `auth-001` observation was real but is not the standard.** `auth-001/security_groups.tf:41-47` does scope RDS by VPC CIDR — but `NETWORK-ACCESS-MODEL.md` is what the fleet was brought onto ("Every data and compute store in the fleet has been brought onto this model", `:3`), and one stack's older shape does not override it. Copying the loosest existing example is not "applying the convention".

**The real trade-off SG-based carries** (`NETWORK-ACCESS-MODEL.md:69`): SG allows are identity-pinned, so if the Pritunl instance is ever rebuilt with a **new** SG, this allow stops covering it — the failure that caused the `app-atento-001` outage. That is a known operational gotcha to respect at cutover (re-check this allow whenever the Pritunl SG changes), not a reason to fall back to CIDR.

---

## SPIKE-4: Staging Mongo database ✅ RESOLVED — separate DB on the prod Mongo VM (4B)

**Question:** Separate staging Mongo VM (4A) vs separate DB on prod host (4B) vs ephemeral (4C)?

**Resolution:** **4B — a separate database on the production Mongo VM.**

**Grounding:** the documented 4Shark staging precedent — `terraform/auth-001/auth_001_staging.tf` — reuses the production data host and is "isolated only by its own database" (own DB, hostname, log group; shared cluster/VPC/RDS). The `-staging` Pritunl instance follows the same shape: its own database on the shared Mongo VM, not a second VM to provision/patch (4A) and not a seed-data strategy to invent (4C).

---

## SPIKE-5: Staging public entry ✅ RESOLVED — default public IP on stop/start (5B)

**Question:** Dedicated EIP (5A) vs default public IP (5B) vs private-only (5C)?

**Resolution:** **5B — the instance's default (non-elastic) public IP**, assigned fresh on each stop/start bring-up.

**Grounding:** the staging instance is normally at zero to carry no idle cost (decision 7) — an always-allocated EIP (5A) contradicts that. Validation requires an actually-reachable VPN endpoint (an engineer connects a real OpenVPN/WireGuard client), which a private-only path (5C) complicates. Community practice for a transient, brought-up-for-a-window test instance is the ephemeral default public IP. The changing IP is acceptable because the tester is the one bringing the instance up and reads the new IP at that moment.

---

## SPIKE-6: Staging EC2 host bring-up ✅ RESOLVED — direct stop/start (confirmed)

**Question:** Confirm direct stop/start of the EC2 host (not ASG managed-scaling-from-zero)?

**Resolution:** **Confirmed — direct stop/start** via `~/.claude/scripts/stop-instance.sh` / `start-instance.sh`, paired with `ecs-scale.sh` for the ECS service's desired_count. Bring up: start host → scale service to 1. Bring down: scale service to 0 → stop host.

**Grounding:** ASG managed-scaling-from-zero is ruled out by AWS's own documented behavior — *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances"* (`docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html`) — which would launch two hosts for a single host-networked Pritunl task. The stop/start wrappers are the existing 4Shark tooling. This was already a researched finding, not an open decision.

---

## SPIKE-7: Privileged/host-network task definition ✅ RESOLVED — bespoke (7B)

**Question:** Extend `modules/ecs_service` with a `privileged`/host-network branch (7A) vs a bespoke `aws_ecs_task_definition` (7B)?

**Resolution:** **7B — a bespoke `aws_ecs_task_definition`** for Pritunl, not a change to the shared module.

**Grounding:** `modules/ecs_service` is consumed by **~19 stacks** (every `app-*`, `integrator-*`, `setup`, `onboarding` — confirmed by grep) — extending it for a one-off privileged/host-network special case puts the whole ECS fleet at risk of regression. The existing precedent already points bespoke: `terraform/modules/pritunl` is itself a bespoke `aws_instance`, not a reuse of a generic module. Isolate the special case; do not modify shared infra for it.

---

## SPIKE-8: Pritunl SIGTERM session-drain ⏳ EMPIRICAL — Phase-3 test, not a Phase-2 decision

**Question:** Does Pritunl drain or drop in-flight OpenVPN/WireGuard sessions on `SIGTERM`?

**Status:** the **one item not resolvable from docs/community** — no source documents the in-flight-session behavior (confirmed in the PLAN's residual items). But it is a **test to run**, not a decision to make, and it blocks **Phase 3** validation, not Phase 2. Phase 2 proceeds with `STOPSIGNAL SIGTERM` + ECS `stopTimeout: 20s` (grounded in Pritunl's own systemd unit: default SIGTERM, `TimeoutStopSec=20`). The empirical drain-vs-drop test runs during Phase 3 pre-flip validation with a live client connection.

---

## PR sequencing — no decision blockers remain

All Phase-2 PRs are now execution-only (each in its own focused session with Pattern Priming + PR-first + gated plan/apply):

1. **PR 2.1 (ECR repositories)** — no blocker, start anytime
2. **PR 2.2 (identity governance)** — no blocker, start anytime
3. **PR 2.3 (Mongo VM + SG)** — SPIKE-2 (golden-AMI) + SPIKE-3 (CIDR) resolved → ready
4. **PR 2.4 (production Pritunl ECS)** — SPIKE-7 (bespoke) resolved → ready
5. **PR 2.5 (staging Pritunl ECS)** — SPIKE-4 (shared-host DB) + SPIKE-5 (default public IP) + SPIKE-6 (stop/start) resolved → ready

SPIKE-8's empirical test is scheduled into Phase 3, independent of all Phase-2 work.

## Decomposition (unchanged)

Option A (component-based, 5 PRs): 2.1 ECR · 2.2 governance · 2.3 Mongo VM · 2.4 prod ECS · 2.5 staging ECS.
