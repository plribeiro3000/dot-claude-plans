# Phase 2 Decisions — Resolved (2026-07-10)

> Originally a list of "blocking decisions the engineer must make". Re-examined against 4Shark's own documentation, the existing terraform precedent, and community best-practice — **none of these is a genuine engineer design decision**; each resolves from a documented rule, an existing precedent, or a grounded external fact. Resolutions + grounding below. The only item that is not doc-resolvable is SPIKE-8, and that is an empirical Phase-3 test, not a Phase-2 decision.

## SPIKE-2: MongoDB VM provisioning ✅ RESOLVED — superseded by the golden-AMI pipeline

**Question:** How to provision the dedicated Mongo VM (new role 2A vs conditional in `4shark.pritunl` 2B)?

**Resolution:** **Neither.** The MongoDB golden-AMI pipeline (repo `mongodb` + `ansible-role-mongodb` + Packer, built/merged/validated 2026-07-10) bakes MongoDB 8.2 into a versioned AMI. PR 2.3's Mongo VM launches from that AMI via a `data "aws_ami"` tag lookup — **no Ansible role runs on the VM at all**, so the 2A/2B question is moot and the 8.0→8.2 drift is closed at the image.

**Grounding:** `~/Projects/4Shark/dot-claude-plans/active/mongodb-golden-ami/PLAN.md` (its Phase 2 IS this Pritunl Mongo VM adoption); the golden-AMI build/role/IAM are all merged.

---

## SPIKE-3: MongoDB security group scoping ✅ RESOLVED — CIDR (3B), per 4Shark convention

**Question:** SG-to-SG reference (3A) vs narrowed CIDR (3B) for Mongo-VM ingress?

**Resolution:** **3B — CIDR-scoped** ingress from the management VPC's private subnet where the Pritunl instance runs.

**Grounding:** 4Shark's documented convention is CIDR ingress, not SG-to-SG: `~/.claude/docs/runbooks/migrations/VPC-CROSS-VPC-CONNECTIVITY.md:40` ("Security group on destination — ingress from source VPC CIDR"); `terraform/auth-001/security_groups.tf:11-23,41-47` scopes even RDS by VPC CIDR (`10.255.0.0/16`). There is **zero SG-to-SG precedent** in the repo, and `~/.claude/docs/runbooks/migrations/VPC-DEPOSED-SG-DEPENDENCY.md` documents how SG-to-SG references add a `DependencyViolation` fragility during migrations. Community generally favors SG-to-SG for precision, but 4Shark's consistent, documented practice is CIDR — apply the convention. (Scoping to the subnet CIDR rather than a `/32` also survives instance replacement, addressing the fragility the PLAN flagged for CIDR.)

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
