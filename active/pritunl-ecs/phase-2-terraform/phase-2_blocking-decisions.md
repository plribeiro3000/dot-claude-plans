# Phase 2 Blocking Decisions — Quick Reference

> Before Phase 2 Terraform PRs begin, engineer must decide on these items. Each decision unblocks one or more PRs.

## SPIKE-2: MongoDB VM Ansible role placement ⚠️ BLOCKS PR 2.3

**Question:** How to provision the dedicated Mongo VM?

**Option 2A (Recommended):** Create new independent role `ansible/roles/4shark.mongodb-pritunl/`
- Pros: Reusable, clean separation, independent lifecycle
- Cons: New files, new playbook structure

**Option 2B:** Conditional in existing `ansible/roles/4shark.pritunl/` (wrap Mongo tasks with `when: inventory_hostname in groups['pritunl_mongodb']`)
- Pros: Single playbook, existing role structure
- Cons: Multi-purpose role, harder to deprecate Mongo later

**Engineer decision needed:** 2A or 2B?

---

## SPIKE-3: MongoDB security group scoping mechanism ⚠️ BLOCKS PR 2.3

**Question:** How to restrict Mongo VM ingress to ONLY the Pritunl instance?

**Option 3A (New pattern):** Security-group-to-security-group reference via `referenced_security_group_id`
- Pros: Dynamic, survives instance replacement, clearest intent
- Cons: New pattern (no existing 4Shark precedent), requires AWS provider verification

**Option 3B (Existing pattern):** Narrowed CIDR to Pritunl instance's private IP
- Pros: Matches existing convention, no new patterns
- Cons: Fragile across instance replacement, requires IP tracking strategy

**Engineer decision needed:** 3A (SG-to-SG) or 3B (CIDR)?

---

## SPIKE-4: Staging Mongo database strategy ⚠️ BLOCKS PR 2.5 (possibly extends PR 2.3)

**Question:** Where does the `-staging` Pritunl instance get its MongoDB?

**Option 4A:** Separate staging Mongo VM (full isolation)
- Pros: Complete isolation, staging VM can be torn down after test window
- Cons: Doubles Mongo VM footprint, adds second host to manage

**Option 4B:** Separate database on production Mongo VM (shared host)
- Pros: Single Mongo VM, simpler infra
- Cons: Staging/prod data on same host, requires database-level isolation discipline

**Option 4C:** Ephemeral Mongo (brought up only during staging test window)
- Pros: Zero persistent cost for staging Mongo
- Cons: Requires seed-data strategy, re-provisioning time on each bring-up

**Engineer decision needed:** 4A (separate VM), 4B (shared host), or 4C (ephemeral)?

---

## SPIKE-5: Staging public entry mechanism ⚠️ BLOCKS PR 2.5

**Question:** How does `-staging` Pritunl reach the public during a test window?

**Option 5A:** Dedicated Elastic IP for staging (possibly ephemeral)
- Pros: Stable IP for test window, familiar pattern
- Cons: EIP carries idle cost when staging is at zero

**Option 5B:** Default public IP on instance ENI (transient, changes on stop/start)
- Pros: Zero cost during idle
- Cons: Changing IP requires manual notification to testers

**Option 5C:** Private-only validation (Systems Manager / VPN tunnel)
- Pros: Zero public exposure, zero cost
- Cons: Non-standard validation workflow

**Engineer decision needed:** 5A (dedicated EIP), 5B (default public IP), or 5C (private-only)?

---

## SPIKE-6: EC2 host bring-up mechanism for `-staging` ⚠️ BLOCKS PR 2.5

**Question:** Confirm that direct stop/start of EC2 instance (not ASG managed scaling) is acceptable?

**Finding:** ASG-backed capacity provider with `min_size=0` is ruled out because AWS automatically launches 2 instances on scale-from-zero (violates single-instance framing).

**Chosen approach:** Direct stop/start via `~/.claude/scripts/stop-instance.sh` / `start-instance.sh`, separate from ECS service `desired_count=0`.

**Procedure:**
- To bring up: start EC2 host → scale ECS service to desired_count=1
- To bring down: scale ECS service to desired_count=0 → stop EC2 host

**Engineer decision needed:** Confirm this is acceptable, or propose alternative?

---

## SPIKE-7: ecs_service module extension vs bespoke task definition ⚠️ BLOCKS PR 2.4, PR 2.5

**Question:** How to provide privileged + host-networking task definition for Pritunl?

**Option 7A:** Extend `terraform/modules/ecs_service/` with `privileged` variable + host network-mode branch
- Pros: Reusable for future privileged workloads, module-based
- Cons: Module change carries risk to downstream consumers, requires backward-compatibility testing

**Option 7B:** Bespoke `aws_ecs_task_definition` resource for Pritunl (mirroring current `terraform/modules/pritunl`)
- Pros: Simple, isolated, no risk to other ECS workloads
- Cons: Task definition logic not reused

**Engineer decision needed:** 7A (extend module) or 7B (bespoke)?

**If 7A:** Must verify no downstream consumers are impacted (search terraform repo for `ecs_service` calls).

---

## SPIKE-8: Pritunl SIGTERM graceful-shutdown behavior ⚠️ BLOCKS PHASE 3 (not Phase 2)

**Question:** What does Pritunl do with in-flight OpenVPN/WireGuard sessions when receiving SIGTERM?

**Two possibilities:**
- Drains gracefully within 20-second window (safe to proceed with STOPSIGNAL SIGTERM + ECS stopTimeout: 20s)
- Drops immediately (risk to in-flight connections during container restarts)

**Note:** This blocks Phase 3 (cutover) validation, NOT Phase 2 Terraform. Phase 2 can proceed; Dockerfile can set STOPSIGNAL as-is and document open question.

**Validation approach:** Establish live OpenVPN/WireGuard connection → send SIGTERM → observe behavior (drain vs drop).

**Engineer decision needed:** Schedule empirical test with a real Pritunl instance + live client connection.

---

## PR Sequencing (after spikes resolve)

**Fast path (assumes all spikes resolve cleanly):**

1. SPIKE-2, SPIKE-3 resolve → PR 2.3 (Mongo VM)
2. PR 2.1 (ECR) — can be parallel with everything
3. PR 2.2 (Governance) — can be parallel with everything
4. SPIKE-7 resolves → PR 2.4 (Prod ECS)
5. SPIKE-4, SPIKE-5, SPIKE-6 resolve → PR 2.5 (Staging ECS)

**SPIKE-8 is independent and can be resolved anytime; it blocks Phase 3 validation, not Phase 2 work.**

---

## Decomposition option preference

**Engineer choice (from TASKS.md):** Option A (component-based, 5-6 smaller PRs) — each PR is a coherent unit, easier review, explicit external sequencing.

**Summary:**
- PR 2.1: ECR repositories
- PR 2.2: Identity governance
- PR 2.3: MongoDB VM + security group
- PR 2.4: Production Pritunl ECS
- PR 2.5: Staging Pritunl ECS

**Total:** 5 PRs, all dependent on spike resolutions above.
