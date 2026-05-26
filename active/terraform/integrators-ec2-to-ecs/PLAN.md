# PLAN — Integrators EC2 to ECS Fargate Migration

> Reference: SPIKE.md (research complete, all questions answered)

## Status (2026-04-13)

**almaviva — DONE** (validated in production 2026-03-19, cleanup PR #298 merged, EC2 terminated, old subnets decommissioned)
**maqnelson — DONE** (deployed 2026-04-06, validated running daily on ECS, EC2 terminated, old subnets decommissioned)
**redebrasil — DONE** (deployed 2026-04-09, validated running daily on ECS)
**aster-maquinas — CANCELLED** (contract cancelled, decommission only)
**atento — DONE** (2026-04-12 deployed, 2026-04-13 first automated BR cycle validated — scale-up → cron → self-shutdown successful)
**commcenter — DONE** (2026-04-13 deployed, prod + staging validated with Database.connect!, EC2 terminated, old subnets decommissioned, first automated cycle pending tonight)

**Execution order:** almaviva (done) → maqnelson (done) → redebrasil (done) → atento (done) → commcenter
**aster-maquinas:** contract cancelled — skip migration, decommission entire stack at the end

**Grandfather rule:** almaviva, maqnelson, and redebrasil are grandfathered under the single-environment pattern. ECS services in production cannot be renamed in-place (requires recreation). Retrofitting is not worth the operational risk for purely cosmetic consistency. The multi-cluster pattern applies to atento and commcenter going forward.


**Terraform repo:** PRs #244, #248, #324 merged to `develop`.
**Integrator repo:** PRs #2139, #2140, #2141 merged to `develop`.
**Integrator repo:** PRs #2038–#2047, #2057 merged to `develop`.

---

## Objective

Migrate all 6 integrator application servers from standalone EC2 instances to ECS Fargate,
eliminating manual OS and Ruby version management, replacing fragile Capistrano deploys with
a container-based pipeline, and aligning integrators with the proven deployment model of the
app stacks. The migration is cost-neutral (~+$1.80/month) while eliminating all EC2 compute
operational toil.

## Scope

### In Scope

- Containerize the integrator Rails application (Dockerfile + entrypoint + health check)
- Build GitHub Actions CI/CD pipeline: one build workflow (all integrators), one deploy workflow (parameterized by integrator name)
- Update `modules/ecs_service` to support Fargate launch type (`launch_type = FARGATE`, `network_mode = awsvpc`)
- Update `modules/integrator/app.tf`: replace `aws_instance` resources with ECS Fargate services
- Add `compute.tf` to each integrator stack with ECS cluster + services
- Migrate 6 integrator stacks in order: redebrasil → almaviva → maqnelson → aster-maquinas → commcenter → atento
- Env var catalogue per integrator (SSH into EC2, collect all vars before each cutover)
- Internal ALB per integrator for the web service (using existing `modules/internal_alb`)
- IAM deploy user per integrator for GitHub Actions (using existing `modules/iam_deploy`)
- Runner task definition per integrator (on-demand, for migrations and rake tasks)
- **VPC redesign + MongoDB migration per integrator** — all integrator VPCs have the same structural problem: both private subnets are in the same AZ (`sa-east-1a`). ALB requires subnets in at least 2 different AZs. Each phase must include the standard VPC redesign and MongoDB migration procedure (see "Standard VPC Redesign + MongoDB Migration Procedure" section below)
- **Two-component scheduling architecture** — current EC2 flow has two separate triggers that must both be migrated:
  1. **EventBridge Schedule 1 → `ecs:UpdateService` direct (Task 1.9):** starts EC2 before processing time → becomes an EventBridge Scheduler that calls `ecs:UpdateService` directly (no Lambda), scaling `desired_count` 0 → N with gorjeta so tasks are RUNNING by processing time. **No scale-down scheduler** — the application itself detects when processing is complete and calls `ecs:UpdateService` (desired_count → 0) to scale itself down. The ECS task role must have `ecs:UpdateService` permission on its own cluster for this to work.
  2. **Application cron job → EventBridge Schedule 2 (Task 1.8):** fires at processing time on the EC2 to trigger the processing initialization rake task → becomes a second EventBridge schedule that calls `ecs:RunTask` on the runner task definition with the same initialization command
- The runner task definition in each `compute.tf` is the ECS vehicle for the processing initialization trigger
- Decommission EC2 app servers in Phase 8 (after all integrators are on ECS, cron jobs migrated, Lambda updated)
- Remove Capistrano deploy infrastructure from integrator repo in Phase 9 (dead code after ECS migration — `Capfile`, `config/deploy.rb`, Capistrano gems, custom deploy hooks)
- Update Claude Code `/integrator-instances` skill in Phase 10 (EC2-based skill no longer relevant — evaluate replacement with ECS-based management)

### Out of Scope

- ElastiCache Redis (unchanged)
- App stacks (app-atento-001, app-shared-001 — they stay on ECS EC2 launch type)
- Staging task sizing optimization (can be done post-migration as a cost reduction task)
- MongoDB migration for atento — mongo000/001/002 stay on existing EC2 instances in `-old` subnets (see atento section)
- Retrofitting almaviva, maqnelson, redebrasil to multi-environment naming (see grandfather rule above)

## EC2 Termination Policy

EC2 app servers are terminated **per-integrator** as part of the migration cleanup (Step 13). Once the MongoDB RS migration is complete and the connection string is updated, the old EC2 app server cannot function anymore — there is no MongoDB in the old subnets to connect to. Keeping it alive provides no fallback value.

**Per-integrator termination conditions** (all must be met before terminating that integrator's EC2):
1. MongoDB RS migrated to new subnets and old nodes terminated
2. Connection string updated on app server (confirms no dependency on old MongoDB)
3. ECS services deployed and ALB health check passing
4. EventBridge old rule disabled, new schedules enabled

After termination, decommission old subnets immediately — do not defer to a global Phase 8.

## Multi-Environment Pattern (new standard)

> Source: SPIKE-multi-env.md (Decisions 1–5)

This pattern applies to clients that host **N countries** (atento: BR, MX, CO, CL) or **N environments** (commcenter: prod + homologation) on shared infrastructure. The single-environment pattern (one `web-service`, one `worker-service` per client) is NOT used for these clients.

### When to apply

- **Apply** to: atento, commcenter, and any future client with multiple countries or environments.
- **Do NOT apply** to: almaviva, maqnelson, redebrasil — these are grandfathered under the single-environment pattern and will not be retrofitted.

### Key differences from the single-environment checklist

| Dimension | Single-env (almaviva/maqnelson/redebrasil) | Multi-env (atento/commcenter) |
|---|---|---|
| ECS cluster | One per client | **One per environment** (e.g., `integrator-atento-br-cluster`, `integrator-atento-mx-cluster`) |
| ECR repo | One per client | One per client (unchanged — same image, different env vars) |
| ECS services | `web-service`, `worker-service` | `web-service`, `worker-service` (standard names — cluster provides the isolation) |
| Runner | `runner-service` (one) | `runner-service` (one per cluster — standard name) |
| ALB | One per client, one target group | **One per client, shared** — host-based routing, one target group per environment |
| DNS | `integrator-{client}.4shark.internal` | `integrator-{client}-{env}.4shark.internal` (one record per env, all pointing to the same ALB) |
| SSM namespace | `/integrator-{client}/{SECRET}` | `/integrator-{client}/{env}/{SECRET}` |
| GitHub Environment | One per client | One per client (unchanged — IAM credentials are per-client, not per-env) |
| EventBridge schedules | One set per client | One set per environment (countries have different timezones and processing windows) |
| Deploy workflow invocation | One dispatch per client | One dispatch per environment (workflow resolves cluster from `integrator + suffix`) |

### Why one cluster per environment (Decision 7 — 2026-04-12)

The original design used one cluster with 12 services (3 services × 4 countries). After analysis:

- **Cost: identical.** ECS has no per-cluster fee (unlike EKS at $73/month/cluster). Cost is purely task vCPU/memory.
- **ALB: shared.** One ALB with host-based routing serves all clusters. No extra ALB cost.
- **Isolation: better.** Each country is independently deployable, scalable, and debuggable. A bad deploy to BR does not affect MX.
- **Simplicity: better.** Service names are standard (`web-service`, `worker-service`) instead of suffixed (`web-br-service`). Deploy scripts resolve the cluster name from `integrator + suffix`, no suffix arithmetic in service names.
- **Consistency: better.** Single-env clients have one cluster with `web-service`/`worker-service`. Multi-env clients have one cluster per env with the same service names. The pattern is uniform.

This also applies to commcenter (`integrator-commcenter-cluster` for prod, `integrator-commcenter-staging-cluster` for homologation) and any future multi-env client.

### ALB design (host-based routing, shared across clusters)

Resources declared **directly in `compute.tf`** — the `internal_alb` module is NOT used for multi-env clients. See SPIKE-multi-env.md (Decision 1).

```
aws_lb "this"                          # one internal ALB, named integrator-{client}
aws_lb_listener "http"                 # port 80
aws_lb_listener_rule "{env}"           # one per environment — host_header: integrator-{client}-{env}.4shark.internal
aws_lb_target_group "{env}"            # one per environment — target_type = "ip"
```

Each cluster's `web-service` registers to its corresponding target group. The ALB routes by `Host` header — it does not know or care which cluster the task belongs to.

### ECS cluster naming

```
integrator-{client}-{env}-cluster      # e.g., integrator-atento-br-cluster
```

Service names inside each cluster are standard (no suffix):
```
integrator-{client}-{env}-web-service     # e.g., integrator-atento-br-web-service
integrator-{client}-{env}-worker-service
integrator-{client}-{env}-runner-service
```

### Deploy workflow: `deploy-ecs.yaml` evolution

The workflow receives an optional `suffix` input (empty by default). See SPIKE-multi-env.md (Decision 2).

- **Single-env clients** (empty `suffix`): cluster = `integrator-almaviva-cluster`, services = `integrator-almaviva-web-service`.
- **Multi-env clients** (`suffix = "br"`): cluster = `integrator-atento-br-cluster`, services = `integrator-atento-br-web-service`.

The `deploy-ecs` composite action does **not** change. The workflow resolves cluster and service names from `integrator + suffix`. The engineer triggers the workflow once per country because each country has its own deploy window and upgrade cadence.

### Runner: one per cluster

Each cluster has a `runner-service` with `desired_count = 0`. The runner task definition holds the environment-specific MongoDB connection string. Zero runtime cost. `bin/ecs run {client} {env} <cmd>` resolves to the correct cluster and runner service. See SPIKE-multi-env.md (Decision 5).

### EventBridge schedules: one set per environment

Each environment gets its own Schedule 1 (scale-up via `ecs:UpdateService` on the environment's cluster) and Schedule 2 (RunTask cron on the environment's cluster). Schedule 0 (start MongoDB) is only created if MongoDB is being migrated for that client — not all clients need it. See SPIKE-multi-env.md (Decision 3).

---

## Standard VPC Redesign + MongoDB Migration Procedure

> This procedure covers single-environment clients (almaviva, maqnelson, redebrasil) and the networking preparation phase for multi-environment clients (atento, commcenter). For multi-environment clients, the VPC and MongoDB steps are identical; only the `compute.tf` structure differs (see Multi-Environment Pattern section above).

**Problem**: All integrator VPCs were originally created with both private subnets in the same AZ (`sa-east-1a`). Additionally, each VPC has an unused public subnet, IGW, and public route table. ALB requires subnets in at least 2 different AZs for HA. This procedure was first executed on almaviva (Phase 3) and must be replicated on every remaining integrator.

**Reference implementation**: almaviva — `networking/vpc_almaviva.tf` (final state), `integrator-almaviva/mongodb.tf`

### Step-by-step procedure (per integrator)

**Step 1 — Drop public infrastructure via AWS CLI**

Before touching Terraform code, manually delete public resources using the AWS CLI. This avoids CIDR conflicts when Terraform tries to create new subnets in the freed space.

Delete in this order:
1. Verify the public subnet is empty: `aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=<subnet-id>"` — must return no results
2. Delete the public subnet (`aws ec2 delete-subnet`)
3. Delete routes from public route table first (`aws ec2 delete-route`), then the route table (`aws ec2 delete-route-table`)
4. Delete SSM parameters for public subnet IDs and public route table ID (`aws ssm delete-parameter`)
5. Delete the IGW (`aws ec2 detach-internet-gateway` + `aws ec2 delete-internet-gateway`) — all integrator VPCs use TGW for egress; IGW is orphaned from the TGW migration and should be removed

**Step 2 — Rename existing private subnets via `terraform state mv`**

- `prv-a` → `prv-a-old`
- `prv-b` → `prv-b-old`
- Also rename the route table associations: `prv_a` → `prv_a_old`, `prv_b` → `prv_b_old`

This preserves MongoDB and EC2 instances in the old subnets without Terraform trying to destroy/recreate them.

**Step 3 — Update Terraform code and remove state for dropped resources**

In `networking/vpc_{client}.tf`:
- Remove: `pub-b` subnet, IGW, public route table, public route table association, public default route
- Rename `prv-a` → `prv-a-old`, `prv-b` → `prv-b-old` (matching state mv)
- Add new `prv-a` (sa-east-1a) and `prv-b` (sa-east-1b) with final names
- Add route table associations for new subnets

In `networking/transit_gateway.tf`:
- Update TGW attachment `subnet_ids` to include **both** new subnets (`prv-a` + `prv-b`). Without this, the AZ of `prv-b` has no egress via TGW.

In `networking/ssm.tf`:
- Remove SSM parameters for public subnet IDs and public route table ID
- Add new SSM parameters: `/prv_a_subnet_id` and `/prv_b_subnet_id`
- Update `/private_subnet_ids` to point to old subnets (legacy EC2 module compatibility)

Run `terraform state rm` for the resources dropped via CLI (subnet, route table, route table association, route, SSM params).

**Step 4 — Apply networking stack**

`terraform plan` and `terraform apply`. Expected result:
- Create: new prv-a, new prv-b, route table associations, SSM params
- Change: old subnet tags (→ `-old` suffix), TGW attachment (→ new subnet)
- Destroy: nothing (already dropped via CLI)

**Step 5 — Provision new MongoDB instances (integrator stack)**

In `integrator-{client}/mongodb.tf`:
- Create `mongo003` (Primary) in `prv-a` (`sa-east-1a`) — t3.small, 60 GB
- Create `mongo004` (Secondary) in `prv-b` (`sa-east-1b`) — t3.small, 60 GB
- Create `mongo005` (Arbiter) in `prv-b` (`sa-east-1b`) — t3.micro, 20 GB
- All with `prevent_destroy = true`
- Arbiter co-located with secondary: if `sa-east-1a` fails, secondary + arbiter still have quorum

**Step 6 — Update integrator stack for new subnets**

In `integrator-{client}/main.tf`:
- Set `app_servers = {}` and `terraform state rm` the app server instances — EC2 app servers are NOT migrated to new subnets; they stay as-is outside Terraform until terminated after ECS is validated. Changing subnets with app servers in the module forces replacement, which destroys running instances.
- Add `has_public_subnets = false`, `has_nat_gateway = false`
- Keep `enable_mongo` as default (true) — old MongoDB stays managed by the module until RS migration is complete
- Point `subnet_prv_a_id` and `subnet_prv_b_id` to old subnets (`private_ids[0]`/`private_ids[1]`) initially — the integrator module manages old MongoDB; changing subnets forces replacement with `prevent_destroy` error
- Point `subnet_pub_b_id` to `private_ids[0]` (legacy field, no public subnet exists)

Apply integrator stack. MongoDB EC2 instances created in new subnets.

> After MongoDB RS migration is complete (Step 10): set `enable_mongo = false`, `terraform state rm` old MongoDB instances, then update `subnet_prv_a_id`/`subnet_prv_b_id` to point to new subnets (via SSM params). This migrates the ElastiCache subnet group to the new subnets (update in-place).

**Step 6c — Required env vars for all integrators**

The following env vars must be defined in `compute.tf` `locals.env_vars` for every integrator:

- `AWS_ECS_ENVIRONMENT` — the ECS environment identifier used by the application to resolve cluster and service names for self-shutdown (`ecs:UpdateService desired_count=0`). Value = the integrator environment name (e.g., `almaviva`, `atento-br`, `commcenter-prod`). Without this, the application cannot find its own ECS services and self-shutdown silently fails.

**Step 6d — Required SSM secrets for all integrators**

The following secrets must exist in SSM for every integrator, even if they were not present on the original EC2 instance. The build pipeline (`assets:precompile`) fails without them:
- `SYMMETRIC_ENCRYPTION_IV` — unique per integrator (16 bytes hex = 32 chars)
- `SYMMETRIC_ENCRYPTION_KEY` — unique per integrator (32 bytes hex = 64 chars)

Generate new values for each integrator (do NOT copy from another integrator — each environment must have its own keys for isolation):
```
openssl rand -hex 16  # IV
openssl rand -hex 32  # KEY
```

**Step 7 — Register DNS for new MongoDB nodes (dns stack)**

In `dns/internal_dns_integrator.tf`:
- Add A records for `4client-{client}-mongo003`, `4client-{client}-mongo004`, `4client-{client}-mongo005` pointing to their private IPs in the `4shark.internal` zone
- Apply dns stack

**This must be done BEFORE the RS migration.** Without DNS, `rs.add()` succeeds but the node stays `not reachable/healthy` because the primary can't resolve the new hostname.

**Step 8 — Pre-migration checks**

Before starting the RS migration, validate:

1. **Database size**: `du -sh /data/db/` on the primary — determines if new instances need temporary upsizing for initial sync
   - Dataset < 4 GB: t3.small (2 GB RAM) is sufficient
   - Dataset 4–16 GB: t3.medium (4 GB RAM) recommended during sync — upsize **before** running Ansible
   - Dataset > 16 GB: t3.large (8 GB RAM) recommended during sync — upsize **before** running Ansible
   - Upsize via CLI: stop instance → `aws ec2 modify-instance-attribute --instance-type` → start instance
   - After sync completes, downsize back to t3.small via same procedure
2. **DNS resolution**: from old primary, `ping 4client-{client}-mongo003` must resolve. If systemd-resolved has stale cache: `sudo systemctl restart systemd-resolved`
3. **Network connectivity**: from old primary, `nc -zv 4client-{client}-mongo003 27017` must succeed. From new nodes, `nc -zv 4client-{client}-mongo002 27017` (or whichever is primary) must also succeed. Both directions required.
4. **Security groups**: old and new nodes must share the same security group, or the SGs must allow bidirectional traffic on port 27017
5. **SSH access**: connect directly via VPN as `deploy@<private-ip>` — no bastion/jump host needed

**Step 9 — Migrate MongoDB replica set (manual / Ansible)**

1. Install MongoDB (same version as existing cluster) on mongo003/004/005 via Ansible:
   `cd ~/Projects/4Shark/ansible && ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-new-nodes.yml client_name={client} primary=<mongo003-ip> secondary=<mongo004-ip> arbiter=<mongo005-ip>`
2. Check who is PRIMARY: `rs.status().members.forEach(function(m) { print(m.name + " — " + m.stateStr) })` — connect to the PRIMARY for the next steps
3. Add mongo003 and mongo004 as new secondaries — can be done in parallel: `rs.add("4client-{client}-mongo003:27017")` then `rs.add("4client-{client}-mongo004:27017")`
4. Wait for STARTUP2 → SECONDARY on both nodes — monitor with `rs.status()` and `du -sh /data/db/` on new nodes. This takes time proportional to dataset size. **Do not Ctrl+C in mongo shell on new nodes** — SIGINT kills mongod, not just the shell
5. Remove old arbiter: `rs.remove("4client-{client}-mongo000:27017")`
6. Remove old secondary: `rs.remove("4client-{client}-mongo001:27017")` — quorum is now old primary + mongo003 + mongo004
7. Add new arbiter: `rs.addArb("4client-{client}-mongo005:27017")`
8. Step down old primary: `rs.stepDown()` — only mongo003 and mongo004 are candidates, guaranteeing a new node becomes PRIMARY. The shell will disconnect and reconnect as SECONDARY.
9. **Reconnect to the new PRIMARY** (mongo003 or mongo004): `ssh deploy@4client-{client}-mongo003.4shark.internal` then `mongo`. `rs.remove` can only be executed on the PRIMARY — the old primary is now a SECONDARY and cannot remove itself.
10. Remove old primary: `rs.remove("4client-{client}-mongo002:27017")`
11. Verify: `rs.status()` — expected: mongo003=PRIMARY, mongo004=SECONDARY, mongo005=ARBITER
12. Stop old MongoDB instances via CLI and test application with new connection string
13. Update application connection strings (`/etc/environment` on app servers) to point to new nodes and validate
14. If instances were temporarily upsized for sync, downsize back to t3.small via CLI (stop → modify-instance-attribute → start)

**Step 10 — Terminate old MongoDB and clean up**

1. Disable termination protection on old instances: `aws ec2 modify-instance-attribute --instance-id <id> --no-disable-api-termination`
2. Terminate old MongoDB instances: `aws ec2 terminate-instances --instance-ids <mongo000> <mongo001> <mongo002>`
3. Remove old instances from Terraform state: `terraform state rm 'module.this.aws_instance.mongo_arbiter[0]' 'module.this.aws_instance.mongo_primary[0]' 'module.this.aws_instance.mongo_secondary[0]'`
4. Set `enable_mongo = false` in `integrator-{client}/main.tf`
5. Remove old DNS records (mongo000/001/002) from `dns/internal_dns_integrator.tf`

**Step 11 — Migrate ElastiCache to new subnets**

ElastiCache subnet group cannot be updated in-place to remove a subnet with an active node (`SubnetInUse` error). The solution is to delete and recreate the cluster — Redis is only cache with no persistent data (data only exists during integration runs).

1. Delete the cluster via CLI: `aws elasticache delete-cache-cluster --cache-cluster-id ec-{client}`
2. Wait for deletion: `aws elasticache wait cache-cluster-deleted --cache-cluster-id ec-{client}`
3. Delete the subnet group: `aws elasticache delete-cache-subnet-group --cache-subnet-group-name ecsg-{client}`
4. Remove both from Terraform state: `terraform state rm 'module.this.aws_elasticache_cluster.redis' 'module.this.aws_elasticache_subnet_group.this'`
5. Update `main.tf` to point `subnet_prv_a_id`/`subnet_prv_b_id` to new subnets (via SSM params) — this also requires `app_servers = {}` and `terraform state rm` of app server instances first, otherwise changing subnets forces EC2 replacement
6. `terraform plan` + `terraform apply` — recreates subnet group and cluster in new subnets
7. Verify DNS CNAME for Redis still resolves (same cluster ID = same endpoint pattern, but verify)

**Step 12 — Configure ECS for access and deploy**

1. Populate SSM secrets with values from `/etc/environment` on the EC2 app server
2. Ensure `SYMMETRIC_ENCRYPTION_IV` and `SYMMETRIC_ENCRYPTION_KEY` are in SSM (required for all integrators — copy from almaviva if not present on EC2)
3. Clean GitHub Environment: keep only `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_INSTANCE_IDS` (pointing to mongo003/004/005). Remove all application env vars and secrets.
4. Trigger build workflow to push image to ECR
5. Trigger "Deploy ECS" workflow with the integrator name
6. Verify ALB health check: `curl http://integrator-{client}.4shark.internal/health`
7. Access is via **HTTP** (port 80), not HTTPS — ALB does not have SSL configured for internal integrators
8. Verify `alb_ingress_cidrs` includes Pritunl client range (`10.149.176.0/27`) in addition to customer VPN CIDR and management VPN (`10.255.0.0/16`)

**Step 13 — Decommission old subnets**

Old subnets (`prv-a-old`, `prv-b-old`) can only be decommissioned after ALL resources in them are gone:
- Old MongoDB instances terminated (Step 10)
- ElastiCache recreated in new subnets (Step 11)
- EC2 app servers terminated (via CLI, not managed by Terraform after Step 6)

### Known issues and lessons learned

Issues encountered during the almaviva and maqnelson migrations. The procedure must account for all of these.

#### Networking

1. **IGW removal**: all integrator VPCs had orphaned IGWs from the TGW migration. Drop via CLI during Step 1. Confirmed safe — all egress is via TGW.
2. **TGW attachment must include both new subnets**: without the prv-b subnet in the TGW attachment, instances in that AZ have no egress. Always update `transit_gateway.tf` with both subnets. Reference: almaviva already has both.
3. **`private_subnet_ids` SSM param must be kept**: the `networking_data` module depends on it. After old subnets are removed, update it to point to new subnets. Do NOT delete it.
4. **`vpn_client_cidrs` must NOT be set**: this causes permanent SG drift because the `aws_default_security_group` merges CIDR and SG rules. Almaviva does not use it and works fine. VPN access is already handled via `management_vpn_sg_ids`.

#### Security Group drift (`aws_default_security_group`)

5. **Permanent SG drift is a known Terraform issue**: the `aws_default_security_group` resource has a known behavior where AWS combines multiple ingress rules with the same protocol/port into a single rule. Terraform always sees a diff because the code defines separate rules but AWS stores them combined. This affects ALL integrators (almaviva included). It is cosmetic — the actual rules in AWS are correct. The fix is to replace `aws_default_security_group` with `aws_security_group` in the module, which is a post-migration cleanup task.

#### DNS

6. **DNS must be registered BEFORE MongoDB RS migration**: `rs.add()` succeeds but the node stays `not reachable/healthy` if the primary can't resolve the new hostname.
7. **systemd-resolved DNS cache**: after creating DNS records in Route53, existing EC2 instances may not resolve new hostnames. Fix: `sudo systemctl restart systemd-resolved`.
7b. **macOS DNS cache (NXDOMAIN)**: if a `.4shark.internal` hostname is queried before the Route53 record exists, macOS caches the NXDOMAIN result in `mDNSResponder`. `nslookup` and `dig` bypass this cache and resolve correctly, but browsers, `curl`, and all apps use `mDNSResponder` and continue to fail. Fix: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`. **Prevention**: always create the DNS record BEFORE anyone tries to access the hostname.
8. **Remove DNS records for terminated instances**: app servers and old MongoDB DNS records must be removed from `dns/internal_dns_integrator.tf` after termination, otherwise `terraform plan` fails on data source lookups.

#### MongoDB

9. **Check database size before migration**: `du -sh /data/db/` on the primary. If > 4 GB, upsize new instances to t3.medium BEFORE running Ansible. Downsize after sync completes.
10. **OOM during initial sync**: t3.small (2 GB RAM) is insufficient for syncing datasets > 4 GB. The WiredTiger cache + initial sync memory pressure causes OOM killer to terminate mongod.
11. **Ctrl+C in mongo shell kills mongod**: on a node in STARTUP2 state, Ctrl+C sends SIGINT which terminates the mongod process, not just the shell. This causes the sync to fail and requires cleaning `/data/db/` and re-adding the node.
12. **Both sync nodes can run in parallel**: `rs.add()` mongo003 and mongo004 at the same time — the primary handles both syncs concurrently.
13. **RS migration order matters**: remove old arbiter and old secondary BEFORE `rs.stepDown()`. This guarantees the new primary is one of the new nodes. Then add new arbiter, then remove old primary.
14. **Check who is PRIMARY before starting**: `rs.status()` — connect to the actual PRIMARY, which may not be the expected node.
15. **SSH access**: `deploy@<private-ip>` directly via VPN. No bastion.

#### ElastiCache

16. **ElastiCache cannot be migrated in-place**: `ModifyCacheSubnetGroup` cannot remove a subnet with an active node. Delete the cluster and subnet group via CLI, remove from state, let Terraform recreate in new subnets. Redis is cache-only — no persistent data loss.

#### Terraform state

17. **EC2 app servers must be removed from Terraform before changing subnets**: `subnet_id` change forces replacement with `prevent_destroy`. Remove from state and set `app_servers = {}` FIRST.
18. **`enable_mongo = false` requires `terraform state rm` first**: old MongoDB instances have `prevent_destroy = true`. Must remove from state, then terminate via CLI, then set the flag.
19. **`github_token` SSM param**: exists in almaviva, not used by the app (expired GitHub App token). Removed in PR #298. Do NOT add to new integrators.

#### ECS / Deploy

20. **ALB ingress must include Pritunl client CIDR**: `10.149.176.0/27` in `alb_ingress_cidrs`. Without this, engineers can't access the ALB via VPN.
21. **ALB is HTTP only**: access via `http://`, not `https://`. No SSL on internal ALBs.
22. **Docker build requires dummy symmetric encryption vars**: `assets:precompile` boots Rails which loads symmetric-encryption gem. Fixed in PR #2103 — dummy values in Dockerfile.
23. **`SYMMETRIC_ENCRYPTION_IV` and `SYMMETRIC_ENCRYPTION_KEY` must be in SSM for all integrators**: even if not present on the original EC2. Generate unique values per integrator (`openssl rand -hex 16` for IV, `openssl rand -hex 32` for KEY). Do NOT copy from another integrator — each environment must have its own keys for isolation.
24. **`AWS_INSTANCE_IDS` should use dynamic references**: `${aws_instance.mongo003.id}` instead of hardcoded IDs. Fixed for almaviva in PR #298.
25. **GitHub Environment cleanup**: after migration, keep only `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_INSTANCE_IDS`. Remove all application env vars and secrets — they are managed by Terraform via SSM.
26. **Disable old EventBridge rule**: `aws events disable-rule --name EC2-start-integrator-{client}` after ECS is validated.
27. **GitHub Environment API paginates**: when cleaning variables via `gh api`, use `--paginate` flag. Without it, only the first page (~10 items) is returned and remaining variables are not deleted.
28. **Deploy preflight check fails on terminated instances**: the `deploy-ecs.yaml` workflow checks `4client-{client}-mongo*` instances — terminated instances remain visible in EC2 API for up to 1 hour. Fixed in integrator PR #2121: filter excludes `terminated` and `shutting-down` states.
29. **Env vars from EC2 may contain unused variables**: `THROUGHPUT_CEILING`, `FETCH_DAYS`, `INITIAL_FETCH_DATE`, `TABLE_PREFIX` (when empty) were present on redebrasil EC2 but not read by the application. Always cross-check env vars against the codebase before adding to `compute.tf` — do not blindly copy everything from `/etc/environment`.
30. **EC2 app servers should be terminated per-integrator**: after MongoDB RS migration, the old EC2 has no MongoDB to connect to and provides no fallback. Terminate during Step 13 cleanup, not in a deferred Phase 8.
31. **`[4shark]` AWS profile in `~/.aws/credentials`**: the Ansible `run_playbook.sh` uses `AWS_PROFILE=$1` — the first argument. If the `[4shark]` profile has stale credentials, Ansible fails with `AuthFailure`. Verify the profile credentials are valid before running Ansible.

### CIDR planning per integrator

Each VPC is a /24. The public subnet occupies a small range that will be freed. New subnets are created in available CIDR space.

| Integrator | VPC CIDR | Current pub-b | Current prv-a | Current prv-b | New prv-a (sa-east-1a) | New prv-b (sa-east-1b) |
|---|---|---|---|---|---|---|
| almaviva | 10.1.0.0/24 | (removed) | 10.1.0.128/26 → old | 10.1.0.192/26 → old | 10.1.0.0/26 ✅ | 10.1.0.64/26 ✅ |
| maqnelson | 10.1.2.0/24 | (removed) | 10.1.2.128/26 → old | 10.1.2.192/26 → old | 10.1.2.0/26 ✅ | 10.1.2.64/26 ✅ |
| redebrasil | 10.1.1.0/24 | (removed) | (removed) | (removed) | 10.1.1.0/26 ✅ | 10.1.1.64/26 ✅ |
| aster-maquinas | — | — | — | — | — (decommission only) | — |
| commcenter | TBD | TBD | TBD | TBD | TBD | TBD |
| atento | 10.12.255.0/24 | 10.12.255.0/28 (destroy) | 10.12.255.128/26 (sa-east-1a) → old | 10.12.255.192/26 (**sa-east-1c** — non-standard) → old | 10.12.255.0/26 (sa-east-1a) | 10.12.255.64/26 (**sa-east-1b** — normalized) |

> Note: atento prv-b was originally in sa-east-1c, not sa-east-1b. The new prv-b normalizes to sa-east-1b to match the standard pattern. CIDRs for commcenter will be filled when that phase begins.

## Execution Phases

---

### Phase 1: Prerequisites

**Objective**: Establish all shared infrastructure before migrating any integrator.
This phase touches the integrator application repo, the shared Terraform modules, and GitHub Actions.
Nothing is deployed to production — this phase creates the foundation.

**Components**:

- **Dockerfile (integrator app repo)**: Multi-stage build. Entrypoint script differentiates between `web` (Puma) and `worker` (Sidekiq) based on a `PROCESS_TYPE` env var. Health check at `/health` or `/up` (Rails 7.1 default). Graceful SIGTERM handling for ECS task draining.
- **GitHub Actions — build workflow**: Triggered on every merge to `master` of the integrator repo. Builds one Docker image and pushes to ECR with two tags: `latest` and the git SHA. One image shared by all integrators (env vars differ per integrator, not the image).
- **GitHub Actions — deploy workflow**: Triggered manually or by release. Receives `integrator_name` as input parameter (e.g., `redebrasil`). Reads secrets from the GitHub Environment for that integrator (e.g., `integrator-redebrasil`). Registers a new ECS task definition revision with full env vars injected. Updates the ECS service to use the new revision.
- **`modules/ecs_service` — Fargate mode**: Add `launch_type` variable (default `"EC2"` for backward compatibility). When `launch_type = "FARGATE"`: set `requires_compatibilities = ["FARGATE"]`, `network_mode = "awsvpc"`, remove `capacity_provider_strategy` block, add `network_configuration` block (`subnets`, `security_groups`, `assign_public_ip`). The existing `subnets`, `security_groups`, `assign_public_ip` variables are already declared in `variables.tf` — only the `main.tf` logic needs updating. The `capacity_provider` variable becomes optional (nullable) when Fargate mode is active.
- **ECR repositories**: One per integrator. The `ecr` module already exists. Verify each integrator stack has an ECR repo; create missing ones.
- **Env var inventory template**: A checklist/script to SSH into each EC2 app server and extract the full env var set before cutover. Output format: GitHub Actions secret names ready to configure.

**Dependencies**: None — this is the foundation phase.

**Success Criteria**:
- [ ] Dockerfile builds successfully and image runs locally with `PROCESS_TYPE=web` and `PROCESS_TYPE=worker`
- [ ] GitHub Actions build workflow pushes image to ECR on merge to `master`
- [ ] GitHub Actions deploy workflow updates ECS service when triggered with an integrator name
- [ ] `modules/ecs_service` passes `terraform validate` with Fargate mode enabled; existing app stacks are unaffected (backward compatible)
- [ ] All 6 integrator ECR repositories exist in AWS

---

### Phase 2: redebrasil

**Objective**: First integrator cutover. Simplest topology (1 web + 1 worker, no staging, no multi-tenant).
Validates the full migration process end-to-end before scaling to more complex integrators.

**Services**: `integrator-redebrasil-web-service` (desired_count=1), `integrator-redebrasil-worker-service` (desired_count=1)
**Runner**: `integrator-redebrasil-runner` task definition (on-demand)
**Cost**: $22.49 + $11.25 = $33.74/month (vs $38.54/month for 1x t3.medium — savings of $4.80)

**Components**:

- **Env var inventory**: SSH into `redebrasil/app002`, collect all env vars. Sensitive vars → `integrator-redebrasil/ssm.tf`. Non-sensitive vars → `locals.env_vars` in `compute.tf`. **No GitHub Environment created.**
- **`integrator-redebrasil/ssm.tf`** (new file): SSM SecureString parameters at `/integrator-redebrasil/*` + IAM policy for `ecsTaskExecutionRole`. Follow `integrator-almaviva/ssm.tf` pattern.
- **`integrator-redebrasil/compute.tf`** (new file): ECS cluster (`integrator-redebrasil-cluster`), internal ALB, web service, worker service, runner task definition, IAM deploy user, security group for tasks. Include `locals.env_vars` and `locals.secrets` wired into services.
- **`integrator-redebrasil/main.tf`**: Set `app_servers = {}` to remove EC2 instances (actual pattern used — no changes to shared module).

**Dependencies**: Phase 1 complete.

**Success Criteria**:
- [ ] `terraform plan` on `integrator-redebrasil` shows correct resource additions and EC2 instance removal
- [ ] ECS cluster `integrator-redebrasil-cluster` created
- [ ] Web and worker Fargate tasks running and healthy in ECS
- [ ] Internal ALB health check passing for web service
- [ ] Sidekiq processing jobs (verify via logs in CloudWatch)
- [ ] Deploy workflow successfully deploys a new image to redebrasil
- [ ] EC2 instance `redebrasil/app002` terminated (Phase 8 — after all integrators validated)

---

### Phase 3: almaviva

**Objective**: Migrate almaviva. Two app servers, both running same queue with 2 threads each — maps to one `worker` service with `desired_count = 2`.

**Services**: `integrator-almaviva-web-service` (desired_count=1), `integrator-almaviva-worker-service` (desired_count=2)
**Runner**: `integrator-almaviva-runner-service` (desired_count=0 — exists for network config), `integrator-almaviva-runner` task definition (on-demand)
**Cost**: $22.49 + 2×$11.25 = $44.99/month (vs $77.08/month for 2x t3.medium — savings of $32.09)

#### VPC Redesign (discovered during Phase 3 — 2026-03-16)

**Blocker found**: ALB requires at least 2 subnets in 2 different Availability Zones. The almaviva VPC originally had only one private subnet (`prv-a`, `sa-east-1a`) — the second subnet was in the same AZ. ECS/ALB could not be deployed in a HA configuration.

**Solution**: Redesigned the almaviva VPC to have proper multi-AZ private subnets.

**VPC: `4client-almaviva` (10.1.0.0/24)**

| Subnet | CIDR | AZ | Status | Purpose |
|--------|------|----|--------|---------|
| `4client-almaviva-prv-a` | 10.1.0.0/26 | sa-east-1a | **Active (new)** | ECS Fargate, MongoDB primary |
| `4client-almaviva-prv-b` | 10.1.0.64/26 | sa-east-1b | **Active (new)** | ECS Fargate, MongoDB secondary + arbiter |
| `4client-almaviva-prv-a-old` | 10.1.0.128/26 | sa-east-1a | **Pending decommission** | Empty (MongoDB terminated) |
| `4client-almaviva-prv-b-old` | 10.1.0.192/26 | sa-east-1a | **Pending decommission** | app002 + app003 stopped — decommission blocked until ECS validated |

Old subnets renamed via `terraform state mv` (not destroy/recreate). New subnets created with final names from day one — no `-new` suffix.

**SSM parameters** (`/networking/integrator-almaviva/`):
- `/prv_a_subnet_id` → `prv-a` (10.1.0.0/26, sa-east-1a)
- `/prv_b_subnet_id` → `prv-b` (10.1.0.64/26, sa-east-1b)
- `/private_subnet_ids` → `prv-a-old,prv-b-old` (legacy; still used by EC2 module)

#### MongoDB Migration (in progress — 2026-03-16)

New MongoDB EC2 instances provisioned in `integrator-almaviva/mongodb.tf` in the new subnets (PSA topology):

| Instance | Terraform | Role | Subnet | AZ | Size | Disk |
|----------|-----------|------|--------|----|------|------|
| `4client-almaviva-mongo003` | `aws_instance.mongo003` | Primary | prv-a | sa-east-1a | t3.small | 60 GB |
| `4client-almaviva-mongo004` | `aws_instance.mongo004` | Secondary | prv-b | sa-east-1b | t3.small | 60 GB |
| `4client-almaviva-mongo005` | `aws_instance.mongo005` | Arbiter | prv-b | sa-east-1b | t3.micro | 20 GB |

Arbiter co-located with secondary so if sa-east-1a (primary AZ) fails, secondary + arbiter still have quorum.

**MongoDB migration sequence** ✅ Complete (2026-03-16):
1. ✅ Install MongoDB 4.0.28 on mongo003/004/005 via Ansible
2. ✅ mongo003 and mongo004 added as new secondaries
3. ✅ mongo003 elected PRIMARY; mongo004 SECONDARY; mongo005 ARBITER
4. ✅ Old nodes (mongo000/001/002) removed from replica set
5. ✅ app002/app003 updated with new connection string and validated
6. ✅ mongo000/001/002 terminated (Task 3.7 — 2026-03-16)
7. ⏳ Decommission old subnets (prv-a-old, prv-b-old) — blocked until app002/app003 terminated

**Components**:

- **Env var inventory**: SSH into `almaviva/app002` and `almaviva/app003`. Diff env vars across instances to confirm they are identical (expected). Create GitHub Environment `almaviva`.
- **`integrator-almaviva/compute.tf`** ✅ Created: ECS cluster, ALB (both AZs), web service (1 task), worker service (2 tasks), runner service (desired_count=0), runner task definition, Schedule 1 (UpdateService scale-up at 00:55 UTC), Schedule 2 (RunTask `bin/rails integration:cron` at 01:00 UTC), IAM deploy module.
- **`integrator-almaviva/mongodb.tf`** ✅ Created: mongo003, mongo004, mongo005 with `prevent_destroy = true`.
- **`integrator-almaviva/main.tf`**: `app_servers = { app002, app003 }` — EC2 servers kept intentionally until ECS is validated (Task 3.5). Will be set to `{}` after validation.
- **Ansible**: Playbook to install MongoDB 4.0.28 on mongo003/004/005 (separate step, not Terraform).

**Dependencies**: Phase 2 complete and validated. VPC redesign and MongoDB provisioning complete (applied).

**Success Criteria**:
- [x] VPC redesigned with 2 private subnets in 2 AZs
- [x] MongoDB EC2 instances (mongo003/004/005) provisioned in new subnets
- [x] ECS cluster and ALB deployed across both AZs
- [x] ALB health check passing for web service
- [x] GitHub Environment `almaviva` configured with env vars and AWS credentials
- [x] First deploy triggered via GitHub Actions; ECS services running with image from ECR (Task 3.5) ✅
- [x] MongoDB 4.0.28 installed on mongo003/004/005 via Ansible
- [x] mongo003 and mongo004 added to replica set as new secondaries
- [x] Replica set migrated fully to new nodes (mongo000/001/002 removed and terminated)
- [ ] Old subnets (prv-a-old, prv-b-old) decommissioned — blocked until app002/app003 terminated (Task 3.7b)
- [x] Worker service running with `desired_count = 2` (2 Fargate tasks visible in ECS) ✅
- [x] Both worker tasks processing jobs from the same queue (validated 2026-03-19) ✅
- [ ] EC2 instances `almaviva/app002` and `almaviva/app003` terminated (Phase 8)

---

### Phases 4–7: Remaining Integrators

Each integrator follows the standard VPC redesign + MongoDB migration + ECS migration procedure documented above. Execution order: maqnelson → aster-maquinas → commcenter → redebrasil → atento. Multi-environment clients (atento, commcenter) follow the variant documented in the Multi-Environment Pattern section above.

#### Per-integrator specifics

| Integrator | VPC CIDR | New prv-a (sa-east-1a) | New prv-b (sa-east-1b) | Services | Worker d= | Cost/mo |
|---|---|---|---|---|---|---|
| maqnelson | 10.1.2.0/24 | 10.1.2.0/26 | 10.1.2.64/26 | web, worker, runner | 2 | $44.99 |
| aster-maquinas | TBD | TBD | TBD | web-prod, worker-prod, web-staging, worker-staging, runner | 1 each | $67.48 |
| commcenter | TBD | TBD | TBD | multi-env pattern — see commcenter section | TBD | TBD |
| atento | 10.12.255.0/24 | 10.12.255.0/26 | 10.12.255.64/26 | web-{br,mx,co,cl}, worker-{br,mx,co,cl}, runner-{br,mx,co,cl} | 1 each (CL d=0) | ~$101.22 |

#### maqnelson — notes

- pub-b (10.1.2.0/28) is inside the 10.1.2.0/26 range — must be destroyed before new prv-a can be created
- Schedules: MongoDB start TBD, scale-up `cron(25 1 * * ? *)`, cron `cron(30 1 * * ? *)`

#### aster-maquinas / commcenter — notes

- SSM prefixes split by environment: `/integrator-{client}/prod/*` and `/integrator-{client}/staging/*`
- Staging clients are actively developing integrations — cannot be decommissioned

#### atento — detailed notes

See the dedicated atento section below for full specifics.

#### commcenter — notes

- Multi-environment pattern: prod + staging (homologation)
- Clusters: `integrator-commcenter-cluster` (prod), `integrator-commcenter-staging-cluster` (homologation)
- SSM prefixes: `/integrator-commcenter/*` (prod) and `/integrator-commcenter-staging/*` (homologation)
- GitHub Environment: `commcenter` (prod), `commcenter-staging` (homologation)
- ALB: host-based routing, one target group per environment (same design as atento)
- DNS: `integrator-commcenter.4shark.internal` (prod), `integrator-commcenter-staging.4shark.internal` (homologation)
- VPC CIDR: 10.1.3.0/24; new prv-a: 10.1.3.0/26 (sa-east-1a), new prv-b: 10.1.3.64/26 (sa-east-1b)
- MongoDB: migrate to new subnets (standard procedure)
- Topology: 2 clusters × 3 services (web d=1, worker d=1, runner d=0) = 6 services total; staging desired_count=0
- Schedules (prod only): MongoDB start `cron(50 3 * * ? *)`, scale-up `cron(55 3 * * ? *)`, cron `cron(0 4 * * ? *)`; staging has no schedules
- Deploy workflow: one dispatch per environment (same as atento)

#### atento — full specification

> This client uses the multi-environment pattern. See SPIKE-multi-env.md for all design decisions.

**Rename: `integrator-atento-br` → `integrator-atento`** (Decision 4)

Everything renameable must change before any ECS resource is created:

1. Terraform stack folder: `integrator-atento-br/` → `integrator-atento/`
2. Networking file: `vpc_atento_br.tf` → `vpc_atento.tf`
3. All AWS resource tags: `4client-atento-br-*` → `4client-atento-*`
4. All AWS security group names, route table names containing `atento-br`
5. SSM paths: `/integrator-atento-br/*` → `/integrator-atento/*` (will be per-env: `/integrator-atento/{br,mx,co,cl}/*`)
6. GitHub Environment: `atento-br` → `atento`
7. ECR repo: `integrator-atento-br` → `integrator-atento` (exists — rename via `terraform state mv` + `aws ecr` CLI)
8. DNS record: `integrator-atento-br.4shark.internal` → per-env records (see DNS below)

**CRITICAL ordering: MongoDB EC2 tags must be renamed BEFORE the first ECS deploy.** The `deploy-ecs.yaml` preflight check uses tag pattern `4client-{integrator}-mongo*`. After rename, the pattern becomes `4client-atento-mongo*`. If MongoDB tags still say `4client-atento-br-mongo*` when the first deploy runs, the preflight check fails. See Decision 4 in SPIKE-multi-env.md.

**VPC state (discovered 2026-04-10)**

| Subnet | CIDR | AZ | Status | Action |
|---|---|---|---|---|
| `pub-b` | 10.12.255.0/28 | sa-east-1a | Empty | Destroy via CLI (Step 1) |
| `prv-a` | 10.12.255.128/26 | sa-east-1a | MongoDBs (010.12.255.162, .159) | Rename → `prv-a-old` |
| `prv-b` | 10.12.255.192/26 | **sa-east-1c** | MongoDB (10.12.255.210) | Rename → `prv-b-old` |
| `prv-a` (new) | 10.12.255.0/26 | sa-east-1a | ECS Fargate | Create |
| `prv-b` (new) | 10.12.255.64/26 | **sa-east-1b** | ECS Fargate | Create (normalized from sa-east-1c) |

**MongoDB (Decision 6 — NOT migrating)**

- mongo000 (10.12.255.162, prv-a-old), mongo001 (10.12.255.210, prv-b-old), mongo002 (10.12.255.159, prv-a-old) stay on existing EC2 instances.
- `mongodb.tf` is **NOT created** for atento.
- `enable_mongo = true` in `main.tf` — existing MongoDB stays managed by the integrator module.
- `AWS_INSTANCE_IDS = []` in `compute.tf` — no Schedule 0, no MongoDB start automation.
- ECS tasks connect to existing MongoDBs over the VPC (MongoDBs are in `-old` subnets, ECS tasks in new subnets — same VPC, same security group, reachable).

**ECS services per country**

| Service | Task family | Country | `desired_count` |
|---|---|---|---|
| `integrator-atento-web-br-service` | `integrator-atento-web-br` | BR | 1 |
| `integrator-atento-worker-br-service` | `integrator-atento-worker-br` | BR | 1 |
| `integrator-atento-runner-br-service` | `integrator-atento-runner-br` | BR | 0 |
| `integrator-atento-web-mx-service` | `integrator-atento-web-mx` | MX | 1 |
| `integrator-atento-worker-mx-service` | `integrator-atento-worker-mx` | MX | 1 |
| `integrator-atento-runner-mx-service` | `integrator-atento-runner-mx` | MX | 0 |
| `integrator-atento-web-co-service` | `integrator-atento-web-co` | CO | 1 |
| `integrator-atento-worker-co-service` | `integrator-atento-worker-co` | CO | 1 |
| `integrator-atento-runner-co-service` | `integrator-atento-runner-co` | CO | 0 |
| `integrator-atento-web-cl-service` | `integrator-atento-web-cl` | CL | 0 |
| `integrator-atento-worker-cl-service` | `integrator-atento-worker-cl` | CL | 0 |
| `integrator-atento-runner-cl-service` | `integrator-atento-runner-cl` | CL | 0 |

**ALB (Decision 1 — host-based routing)**

One internal ALB `integrator-atento`. Resources declared directly in `compute.tf` (not using `internal_alb` module).

DNS records (all pointing to the same ALB IP):
- `integrator-atento-br.4shark.internal`
- `integrator-atento-mx.4shark.internal`
- `integrator-atento-co.4shark.internal`
- `integrator-atento-cl.4shark.internal`

**SSM namespace**

`/integrator-atento/{br,mx,co,cl}/{SECRET_NAME}` — one parameter per (env × secret). IAM policy wildcard: `arn:aws:ssm:...:parameter/integrator-atento/*`.

**EventBridge schedules (Decision 3 — per-country)**

Each country has its own Schedule 1 (scale-up) and Schedule 2 (cron RunTask). Countries are in different timezones. Schedule values to be filled by engineer based on current EventBridge rules per country (existing rule `EC2-start-integrator-atento-br` → `cron(55 1 ? * * *)` ENABLED is the BR reference). Schedule 0 (start MongoDB) is NOT created.

**EC2 app servers**

- `app002` (BR), `mx-app002` (MX), `co-app002` (CO), `cl-app002` (CL): terminate after ECS validation for each country.

**Deploy workflow**

One dispatch per country: `integrator=atento, environment=br` / `environment=mx` / `environment=co`. The optional `environment` input must be added to `deploy-ecs.yaml` before the first atento deploy (prerequisite).

**Existing EventBridge rule**

`EC2-start-integrator-atento-br` (ENABLED) — disable after BR ECS is validated.

---

#### Success criteria (applies to each integrator)

- [ ] VPC redesigned with 2 private subnets in 2 AZs
- [ ] MongoDB migrated to new subnets (mongo003/004/005) — OR existing MongoDBs confirmed reachable from new subnets (atento)
- [ ] ECS services running and healthy
- [ ] ALB health check passing
- [ ] First full automated cycle validated (scale-up → cron → processing → self-shutdown)
- [ ] EC2 instances kept running in parallel until ECS is validated per-country

---

### Phase 9: Capistrano Removal (integrator repo)

**Objective**: Remove all Capistrano deploy infrastructure from the integrator application repository. With all integrators on ECS Fargate, Capistrano is dead code — no integrator deploys via `cap` anymore. All deploys go through the GitHub Actions ECS pipeline.

**Scope**:

- `Capfile`
- `config/deploy.rb` and `config/deploy/` directory (per-environment configs)
- Capistrano-related gems in `Gemfile` (`capistrano`, `capistrano-rails`, `capistrano-bundler`, `capistrano-rbenv`, etc.)
- Any `lib/capistrano/` tasks or custom deploy hooks
- References to Capistrano in documentation, scripts, or CI/CD configs

**Dependencies**: All integrators migrated to ECS (Phase 8 complete — commcenter done, aster-maquinas decommissioned).

**Success Criteria**:
- [ ] All Capistrano files and gems removed from the integrator repo
- [ ] `bundle install` succeeds without Capistrano gems
- [ ] Build workflow still succeeds (Docker image builds correctly)
- [ ] Deploy workflow still succeeds (ECS deploy unaffected)

---

### Phase 10: Claude Code Skill Update (`.claude` repo)

**Objective**: The `/integrator-instances` skill in the Claude Code configuration manages EC2 instances for integrator clients (start, stop, check status). With all integrators on ECS Fargate, there are no EC2 app servers to manage — the skill no longer serves its original purpose. Evaluate what changes are needed to align the skill with the ECS-based infrastructure.

**Scope**:

- `~/.claude/commands/integrator-instances.md` — the skill definition
- `~/.claude/scripts/integrator-instances.sh` — the underlying script
- `~/.claude/scripts/start-instance.sh` and `~/.claude/scripts/stop-instance.sh` — instance management scripts
- Related references in `~/.claude/CLAUDE.md` and `~/.claude/settings.json`
- Evaluate whether `/integrator-services` (ECS service management) already covers the use cases, or if a unified skill is needed

**Dependencies**: All integrators migrated to ECS (Phase 8 complete).

**Success Criteria**:
- [ ] Skill updated or replaced to reflect ECS-based infrastructure
- [ ] Engineers can manage integrator services (scale up/down, check status) through the updated skill
- [ ] Old EC2-specific scripts removed or archived
- [ ] CLAUDE.md references updated

---

### Phase 11: New Integrator Onboarding Documentation (integrator repo)

**Objective**: Create a complete guide for provisioning a new integrator client from scratch. With all integrators on ECS Fargate, the onboarding process is fully codified across Terraform, Ansible, and GitHub Actions. This documentation replaces the old README production setup instructions.

**Scope**:

- End-to-end guide covering all steps to onboard a new client
- Terraform: VPC, VPN (conditional — not all clients need VPN), MongoDB, ElastiCache, ECS cluster, ALB, SSM parameters, IAM deploy user, EventBridge schedules
- Ansible: MongoDB installation on EC2 instances
- GitHub: Environment creation (AWS credentials only), `INTEGRATORS` repository variable update, ECR repository, build matrix
- Single-environment vs multi-environment pattern (when to use each)
- Conditional VPN setup (clients with on-premises databases vs cloud-hosted databases)

**Dependencies**: Phase 9 complete (Capistrano removed, README updated).

**Success Criteria**:
- [ ] Step-by-step guide exists in the integrator repo (e.g., `.github/ONBOARDING.md`)
- [ ] Covers both single-env and multi-env patterns with clear decision criteria
- [ ] VPN setup documented as conditional (with and without)
- [ ] References the correct Terraform modules and file patterns
- [ ] An engineer unfamiliar with the project can follow it to onboard a new client

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Launch type | ECS Fargate | Eliminates all EC2 compute management; cost-neutral vs current ($348.66 vs $346.86); zero AMI/ASG/Launch Template overhead |
| ECS EC2 launch type | Ruled out | Same cost as current ($346.86), adds 18 EC2 instances to manage, zero savings |
| Module strategy for Fargate | Extend `modules/ecs_service` with `launch_type` variable | Avoids duplication; backward compatible with existing app stacks (default stays `EC2`) |
| Env var management | SSM Parameter Store (SecureString) + Terraform `env_vars` | Pattern settled by Tier 1 migration (all 6 app stacks). Sensitive vars in `ssm.tf` (SecureString, `ignore_changes = [value]`), non-sensitive vars in `locals.env_vars` in `compute.tf`. Reference: `github-envs-to-terraform-ssm/PLAN.md`. GitHub Environments are **not** created for integrators. |
| Build pipeline | One image, all integrators | Integrators share the same Rails application code; env vars differentiate behavior, not the image |
| Deploy pipeline | One script, `integrator_name` parameter | Avoids N nearly-identical workflows; each run creates a new task definition revision with that integrator's secrets |
| Cluster per integrator (not per environment) | One cluster per integrator, all environments inside | Staging and production share the same VPC, VPN, MongoDB, and Redis — there is no isolation benefit to separate clusters. Naming: `integrator-{name}-cluster` (e.g., `integrator-almaviva-cluster`, `integrator-commcenter-cluster`). Staging and prod services coexist as separate ECS services within the same cluster. |
| Staging environments | Separate ECS services within the same cluster | aster-maquinas and commcenter clients are actively using staging; decommissioning is not an option. Services named with `-prod-` and `-staging-` suffixes. |
| Runner tasks | On-demand task definition (not a long-running service) | Migrations and rake tasks run via `aws ecs run-task`; no idle cost; ~$0.02 per execution on Fargate |
| Scale-down | Application self-shutdown (no scheduler) | The integrator application already has a process that detects processing completion and stops the server. On ECS this becomes `ecs:UpdateService` (desired_count → 0). No scale-down scheduler needed. |
| Scale-up scheduler | EventBridge Scheduler → `ecs:UpdateService` direct (no Lambda) | Fewer moving parts; EventBridge Scheduler supports direct AWS API calls as universal targets; simpler to maintain and debug |
| Migration order | redebrasil → almaviva → maqnelson → aster-maquinas → commcenter → atento | Ordered by complexity: simplest first to validate the pattern, most complex (atento) last |
| ALB for web services | Internal ALB (not public) | Web traffic comes from client network via VPN; `modules/internal_alb` already exists |
| ALB for multi-env clients (atento, commcenter) | One ALB, host-based routing, resources in `compute.tf` directly | ~$48/month savings vs 4 separate ALBs; `internal_alb` module not used for these clients; see SPIKE-multi-env.md Decision 1 |
| Multi-env deploy workflow | Optional `environment` input in `deploy-ecs.yaml`, one dispatch per env | Countries have independent deploy windows and upgrade cadence; single-env clients unaffected (empty input = current behavior); see SPIKE-multi-env.md Decision 2 |
| Multi-env schedules | Per-environment EventBridge rules | Countries are in different timezones; independent processing windows; see SPIKE-multi-env.md Decision 3 |
| atento rename scope | `atento-br` → `atento` everywhere | Removes country suffix from shared infrastructure (cluster, VPC, ECR serve all countries); MongoDB tags renamed before first deploy; see SPIKE-multi-env.md Decision 4 |
| atento runner | One runner-service per country | Each country has its own MongoDB connection string; symmetric with web/worker; zero idle cost; see SPIKE-multi-env.md Decision 5 |
| atento MongoDB | Not migrated — stays on existing EC2 in -old subnets | Engineer decision: migration risk not justified at this time; ECS tasks connect to existing MongoDBs over VPC; `mongodb.tf` not created; see SPIKE-multi-env.md Decision 6 |
| Retrofit existing integrators | Not done — grandfathered | ECS services cannot be renamed in-place (recreation required); operational risk on active production clients not justified for cosmetic consistency; see SPIKE-multi-env.md Q3 |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Incomplete env var inventory | High | SSH and collect before each cutover; run smoke tests on ECS before terminating EC2 |
| Atento BR country-specific queue mapping | Medium | Run both EC2 and ECS in parallel during cutover; validate queue names via CloudWatch logs before decommissioning EC2 |
| `ecs_service` module changes break app stacks | Medium | Default value of `launch_type` stays `"EC2"`; run `terraform plan` on app-atento-001 and app-shared-001 after any module change |
| Capistrano deploy hooks not reimplemented | Medium | Audit `Capfile` and `config/deploy.rb` before Phase 1; document all hooks; ensure DB migrations run via runner task post-deploy |
| Cron jobs not migrated before EC2 termination | High | Task 1.8 investigates and migrates all cron jobs; EC2 is not terminated until cron migration is confirmed complete |
| EventBridge Scheduler scale-up not configured | High | Task 1.9 creates EventBridge Scheduler (direct `ecs:UpdateService`, no Lambda); must be tested before EC2 is terminated |
| Application self-shutdown not migrated | High | Task 8.0 updates the integrator shutdown process from EC2 stop to ECS UpdateService; must be deployed and tested before EC2 is terminated |
| Staging size increase (aster-maquinas, commcenter) | Low | Cost increase is known ($28.94/month per integrator); optional staging task downsizing can reduce this post-migration |
| ECS Exec for debugging (replaces SSH) | Low | `enable_execute_command = true` on all services; engineers must have IAM permissions for `ssm:StartSession` |

## Assumptions

- The integrator Rails application has no local filesystem state that needs to persist across container restarts
- All 6 integrators run the same application codebase (one Docker image is valid for all)
- MongoDB and Redis are reachable from private subnets (confirmed: they are in the same VPC)
- The `ecsTaskExecutionRole` IAM role already exists (used by app stacks)
- GitHub Actions has network access to push to ECR and call ECS APIs
- Each integrator's VPC has internet egress via a centralized NAT Gateway through Transit Gateway (PR #243, 2026-03-16) — no per-integrator NAT Gateway; `has_public_subnets = false`, `has_nat_gateway = false` applies to all integrator stacks
- The `modules/internal_alb` module is used for single-environment clients; multi-environment clients (atento, commcenter) declare ALB resources directly in `compute.tf`
- Cutover timing: each integrator cutover happens during low-traffic hours, with EC2 termination only after ECS validation
