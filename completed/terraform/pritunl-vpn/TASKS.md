# NEXT TASKS — Standardize VPN: Migrate to Single Pritunl Instance — Terraform + Ansible

> **Objective of this iteration:** Discovery of existing Pritunl config, then build Terraform infra module + Ansible role to deploy a single managed Pritunl instance in the Management VPC.
> **Reference:** PLAN.md — Phases 0–6 (discovery + infrastructure + ansible + operational)

---

## 0) Pre-conditions

- [x] **PLAN.md approved** (Terraform + Ansible approach — selected)
- [x] **Base branch:** `develop` • **Working branch:** `feature/standardize-vpn-001-phase1`
- [x] Project files exist: `modules/integrator/security.tf`, `modules/app/security.tf` for reference
- [x] SSH key pair `4Shark-prd` exists in AWS (confirmed — used by both existing Pritunl instances)
- [x] Ubuntu 24.04 LTS AMI available (confirmed — both existing instances run Ubuntu 24.04)
- [x] Management VPC exists: `vpc-0bdc76f3b391694dd` with public subnet `10.255.0.0/24`
- [x] Engineer has SSH access to existing Pritunl instances (temporary SSH opened and closed)

---

## 1) Step by Step (atomic tasks)

### Phase 0: Discovery — COMPLETE

> All discovery was performed via temporary SSH access + Pritunl Web UI on both production and beta instances.
> Full findings documented in SPIKE.md "Discovery" section and PLAN.md "Current Situation" section.

### Task 1 — Connect to existing Pritunl server and extract system info — DONE

- **Status:** COMPLETE
- **Findings:** Both instances run Ubuntu 24.04 LTS, Pritunl v1.32.x, MongoDB 6.0.25, key pair `4Shark-prd`, user `ubuntu`

### Task 2 — Extract Pritunl application configuration — DONE

- **Status:** COMPLETE
- **Findings:** Pritunl config via Web UI — server settings, ports, virtual networks, cipher/hash/DH, DNS (8.8.8.8), mongod.conf (default, bind localhost, no auth)

### Task 3 — Extract network and security configuration — DONE

- **Status:** COMPLETE
- **Findings:** NAT/MASQUERADE confirmed via iptables. SourceDestCheck=true works with NAT. Routes limited to own VPC CIDR only. No VPC peering on beta.

### Task 4 — Extract SSL, disk, and resource info — DONE

- **Status:** COMPLETE
- **Findings:** t3a.micro (918MB RAM), production disk 6.8GB at 83%, SSM Agent installed (snap) but no IAM Profile

### Task 5 — Extract Pritunl application state from Web UI — DONE

- **Status:** COMPLETE
- **Findings:** Server configs, routes, users captured via Web UI screenshots (avoided MongoDB queries that would expose private keys). Users will be recreated from scratch — no migration needed.
- **Decisions made:**
  - MongoDB: local (same instance) — DocumentDB/Atlas too expensive for 5MB
  - Disk: 20GB gp3
  - Log rotation: via Ansible
  - Users: 3 (paulo.ribeiro@4shark.com.br, elisio.filho@4shark.com.br, emerson.silva@4shark.com.br)

---

### Phase 1: Terraform Module — Infrastructure Only

### Task 6 — Create `modules/pritunl/variables.tf`

- **Objective:** Define all input variables for the Pritunl infrastructure module.
- **Actions (checklist):**
  - [ ] Create file `modules/pritunl/variables.tf`
  - [ ] Define variables:
    - `name_prefix` (string, required) — e.g., `4shark-vpn-001`
    - `vpc_id` (string, required)
    - `subnet_id` (string, required) — public subnet
    - `instance_type` (string, default: `t3a.micro`)
    - `key_name` (string, required) — EC2 key pair (existing: `4Shark-prd`)
    - `ami_id` (string) — Ubuntu 24.04 LTS AMI
    - `volume_size` (number, default: `20`)
    - `volume_type` (string, default: `gp3`)
    - `vpn_port` (number, required) — UDP port for VPN client connections
    - `vpc_cidr` (string, required) — VPC CIDR for internal SG rule (e.g., `10.255.0.0/16`)
    - `tags` (map(string), optional)
  - [ ] Add descriptions for each variable
- **Affected files:** `modules/pritunl/variables.tf` (new)
- **Completion criteria:** All variables defined with type, description, and appropriate defaults.

### Task 7 — Create `modules/pritunl/security.tf`

- **Objective:** Define security group for VPN traffic.
- **Actions (checklist):**
  - [ ] Create file `modules/pritunl/security.tf`
  - [ ] Define `aws_security_group` with:
    - Name: `${var.name_prefix}-sg`
    - VPC: `var.vpc_id`
  - [ ] Inbound rules:
    - `var.vpn_port`/UDP from `0.0.0.0/0` (VPN client connections)
    - ALL traffic from `var.vpc_cidr` (internal access — matches existing pattern)
  - [ ] Outbound: all traffic to `0.0.0.0/0`
  - [ ] NO inbound port 22 (SSH via SSM only)
  - [ ] NO inbound 443/TCP from internet (web console via SSM port-forward only)
  - [ ] Tags
- **Affected files:** `modules/pritunl/security.tf` (new)
- **Completion criteria:** Security group with correct VPN port rules, no SSH access.
- **Observations:** Reference `modules/integrator/security.tf` for style patterns.

### Task 8 — Create `modules/pritunl/iam.tf`

- **Objective:** Create IAM role, instance profile, and policies for VPC route advertisement, Secrets Manager, and SSM.
- **Actions (checklist):**
  - [ ] Create file `modules/pritunl/iam.tf`
  - [ ] Define `aws_iam_role` with EC2 trust policy
  - [ ] Define `aws_iam_instance_profile`
  - [ ] Define inline policy with:
    - `ec2:DescribeRouteTables`, `ec2:CreateRoute`, `ec2:ReplaceRoute`, `ec2:DeleteRoute`
    - `secretsmanager:PutSecretValue`, `secretsmanager:CreateSecret`
  - [ ] Attach managed policy: `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`
  - [ ] Tags
- **Affected files:** `modules/pritunl/iam.tf` (new)
- **Completion criteria:** IAM role with VPC route, Secrets Manager, and SSM permissions.

### Task 9 — Create `modules/pritunl/main.tf`

- **Objective:** Define the EC2 instance with EIP and source/dest check disabled.
- **Actions (checklist):**
  - [ ] Create file `modules/pritunl/main.tf`
  - [ ] Define `aws_instance`:
    - AMI from `var.ami_id`
    - Instance type from `var.instance_type`
    - Key name from `var.key_name`
    - Subnet from `var.subnet_id`
    - Security group from `aws_security_group`
    - IAM instance profile
    - Root block device: `var.volume_size`, `var.volume_type`
    - Note: SourceDestCheck remains default (true) — NAT/MASQUERADE handles routing
    - Tags: `Name = var.name_prefix`, `Automation = "ansible"`, `Role = "vpn"`, plus `var.tags`
    - `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` (Ansible-friendly)
  - [ ] Define `aws_eip` with tags
  - [ ] Define `aws_eip_association`
- **Affected files:** `modules/pritunl/main.tf` (new)
- **Completion criteria:** EC2 instance with EIP, source/dest check disabled, Ansible-compatible lifecycle.

### Task 10 — Create `modules/pritunl/outputs.tf`

- **Objective:** Export key outputs for downstream consumption.
- **Actions (checklist):**
  - [ ] Create file `modules/pritunl/outputs.tf`
  - [ ] Define outputs:
    - `instance_id`
    - `security_group_id`
    - `public_ip` (EIP)
    - `private_ip`
    - `eip_allocation_id`
    - `iam_role_arn`
    - `iam_instance_profile_name`
- **Affected files:** `modules/pritunl/outputs.tf` (new)
- **Completion criteria:** All outputs correctly referencing module resources.

### Task 11 — Create `vpn/` root module

- **Objective:** Create the root module that instantiates the Pritunl module in the Management VPC.
- **Actions (checklist):**
  - [ ] Create directory `vpn/`
  - [ ] Create `vpn/providers.tf`:
    - Terraform required version
    - AWS provider with region `sa-east-1`
  - [ ] Create `vpn/main.tf`:
    - Module block referencing `../modules/pritunl`
    - Data source to find Management VPC public subnet by CIDR or tag
    - Route53 A record `vpn.4shark.internal` pointing to EIP
  - [ ] Create `vpn/outputs.tf`:
    - `pritunl_security_group_id`
    - `pritunl_instance_id`
    - `pritunl_public_ip`
    - `pritunl_private_ip`
- **Affected files:** `vpn/providers.tf` (new), `vpn/main.tf` (new), `vpn/outputs.tf` (new)
- **Completion criteria:** Root module instantiates Pritunl module correctly. Route53 record configured.

### Task 12 — Validate Terraform module (`terraform validate` + `terraform plan`)

- **Objective:** Ensure all Terraform files compile and the plan looks correct before applying.
- **Actions (checklist):**
  - [ ] Run `terraform init` in `vpn/`
  - [ ] Run `terraform validate`
  - [ ] Run `terraform plan` and review output
  - [ ] Verify: EC2, EIP, SG, IAM role, Route53 record all present
  - [ ] Save plan output to `/tmp/terraform_plan_management_YYYYMMDD_HHMMSS`
- **Affected files:** None (validation)
- **Completion criteria:** `terraform validate` passes. Plan shows expected resources.
- **[HOLD POINT]** Review plan before applying. Confirm subnet ID is correct.

---

### Phase 2: Deploy Terraform Infrastructure

### Task 13 — Apply Terraform (`terraform apply`)

- **Objective:** Deploy EC2 instance, EIP, SG, IAM role to AWS.
- **Type:** Requires AWS access
- **Actions (checklist):**
  - [ ] Run `terraform apply` in `vpn/`
  - [ ] Capture outputs to `/tmp/terraform_apply_management_YYYYMMDD_HHMMSS`
  - [ ] Note `pritunl_instance_id` (for Ansible inventory and SSM)
  - [ ] Note `pritunl_security_group_id` (for Phase 4)
  - [ ] Note `pritunl_public_ip` (for VPN endpoint)
- **Affected files:** AWS infrastructure
- **Completion criteria:** Apply succeeds. Instance running. EIP associated.

---

### Phase 3: Ansible Role — Install Pritunl

> **Note:** This phase happens in the `ansible` project (`~/Projects/4Shark/ansible/`).

### Task 14 — Create Ansible role `pritunl`

- **Objective:** Create an Ansible role that installs and configures Pritunl + MongoDB based on Phase 0 discovery data.
- **Type:** Code task (in ansible project)
- **Actions (checklist):**
  - [ ] Create role structure: `roles/pritunl/{tasks,handlers,templates,defaults,vars}/`
  - [ ] `defaults/main.yml`: default variables (Pritunl version, MongoDB version, secret name, etc.)
  - [ ] `tasks/main.yml`:
    - Add Pritunl GPG key and repository
    - Add MongoDB GPG key and repository
    - Install packages: `pritunl`, `mongodb-org`, `wireguard`, `wireguard-tools`, `awscli`
    - Configure MongoDB (`/etc/mongod.conf` from template)
    - Disable `DNSStubListener` in systemd-resolved
    - Enable and start `mongod` service
    - Enable and start `pritunl` service
    - Run `pritunl setup-key` and store in Secrets Manager (idempotent — check if already stored)
    - Run `pritunl default-password` and store in Secrets Manager (idempotent)
  - [ ] `handlers/main.yml`: restart handlers for `pritunl` and `mongod`
  - [ ] `templates/mongod.conf.j2`: MongoDB config from discovery data
- **Affected files:** `~/Projects/4Shark/ansible/roles/pritunl/` (new)
- **Completion criteria:** Role is idempotent. All tasks use proper Ansible modules (apt, systemd, template, etc.).
- **Observations:** Exact configuration (versions, repo URLs, mongod.conf settings) will come from Phase 0 discovery output.

### Task 15 — Add Pritunl host to Ansible inventory and create playbook

- **Objective:** Add the new instance to Ansible inventory and create a playbook to run the role.
- **Type:** Code task (in ansible project)
- **Actions (checklist):**
  - [ ] Add `4shark-vpn-001` to inventory (use private IP or instance ID for SSM connection)
  - [ ] Create `playbooks/pritunl.yml` applying the `pritunl` role
  - [ ] Configure connection method (SSH via SSM or direct SSH via VPN)
- **Affected files:** Ansible inventory, `playbooks/pritunl.yml` (new)
- **Completion criteria:** Playbook runs successfully against the new instance.

### Task 16 — Run Ansible playbook against new Pritunl instance

- **Objective:** Execute the Ansible role to install and configure Pritunl on the new EC2 instance.
- **Type:** Manual / Operational
- **Actions (checklist):**
  - [ ] Run `ansible-playbook -i inventory playbooks/pritunl.yml --limit 4shark-vpn-001`
  - [ ] Verify: Pritunl service running (`systemctl status pritunl`)
  - [ ] Verify: MongoDB service running (`systemctl status mongod`)
  - [ ] Verify: Setup key stored in Secrets Manager
  - [ ] Save playbook output to `/tmp/ansible_pritunl_YYYYMMDD_HHMMSS`
- **Affected files:** None (Ansible execution)
- **Completion criteria:** Ansible completes successfully. Pritunl and MongoDB services are running.
- **[HOLD POINT]** If Ansible fails: debug, fix role, re-run (idempotent).

---

### Phase 4: Update Environment Modules with New SG ID

> **Dependency:** Task 13 complete — SG ID must be known.

### Task 17 — Retrieve new security group ID

- **Objective:** Get the SG ID from Terraform output.
- **Actions (checklist):**
  - [ ] Run `terraform output pritunl_security_group_id` in `vpn/`
  - [ ] Verify format: `sg-...`
- **Completion criteria:** SG ID confirmed.

### Task 18 — Update `management_vpn_sg_id` in all 7 environment files

- **Objective:** Replace hardcoded old SG ID with new SG ID in all environments.
- **Actions (checklist):**
  - [ ] Update `integrator-almaviva/main.tf`
  - [ ] Update `integrator-redebrasil/main.tf`
  - [ ] Update `integrator-maqnelson/main.tf`
  - [ ] Update `integrator-commcenter/main.tf`
  - [ ] Update `integrator-aster-maquinas/main.tf`
  - [ ] Update `integrator-atento-br/main.tf`
  - [ ] Update `app-atento-br/main.tf`
- **Affected files:** 7 `main.tf` files listed above
- **Completion criteria:** All 7 files updated with new SG ID.

### Task 19 — Verify all SG ID updates

- **Objective:** Confirm consistency — no old SG IDs remain.
- **Actions (checklist):**
  - [ ] Search: `grep -r "management_vpn_sg_id" . --include="*.tf"`
  - [ ] Verify all 7 matches show new SG ID
  - [ ] Save output to `/tmp/vpn_sg_id_verification_YYYYMMDD_HHMMSS`
- **Completion criteria:** All references updated. No old SG ID remains.

---

### Phase 5: Configure Pritunl via Web UI

> **Dependency:** Task 16 complete — Pritunl is installed and running.

### Task 20 — Access Pritunl web console via SSM port-forward

- **Objective:** Establish tunnel to Pritunl management console.
- **Type:** Manual / Operational
- **Actions (checklist):**
  - [ ] Run SSM port-forward:
    ```bash
    aws ssm start-session \
      --target <instance-id> \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["443"],"localPortNumber":["4430"]}'
    ```
  - [ ] Open `https://localhost:4430` in browser
  - [ ] Accept self-signed certificate warning
- **Completion criteria:** Pritunl setup wizard visible in browser.

### Task 21 — Complete setup wizard and configure VPN server

- **Objective:** Initialize Pritunl and create VPN server with all routes and DNS.
- **Type:** Manual / Operational
- **Actions (checklist):**
  - [ ] Retrieve setup-key: `aws secretsmanager get-secret-value --secret-id pritunl/setup-key`
  - [ ] Enter setup-key + MongoDB URI (`mongodb://localhost:27017/pritunl`)
  - [ ] Log in with default admin credentials (from Secrets Manager)
  - [ ] Create organization: "4Shark"
  - [ ] Create VPN server:
    - Port: `1194` UDP, WireGuard: `1195` UDP
    - Remove `0.0.0.0/0` default route
    - Add routes with VPC Route Advertisement:
      - `10.255.0.0/16` (Management VPC)
      - `10.1.0.0/24` (integrator-almaviva)
      - `10.1.1.0/24` (integrator-redebrasil)
      - `10.1.2.0/24` (integrator-maqnelson)
      - `10.1.3.0/24` (integrator-commcenter)
      - `10.1.4.0/24` (integrator-aster-maquinas)
      - `10.12.0.0/26` (app-atento-br)
      - `10.12.255.0/24` (integrator-atento-br)
  - [ ] Enable "VPN Client DNS Mapping"
  - [ ] Push DNS server: `10.255.0.2`
  - [ ] Push search domain: `4shark.internal`
  - [ ] Attach organization to server
  - [ ] Start server
- **Completion criteria:** VPN server running with all routes and DNS configured.

### Task 22 — Create users and test connectivity

- **Objective:** Create all 3 users, connect via VPN, and verify access to all networks.
- **Type:** Manual / Operational
- **Actions (checklist):**
  - [ ] Create users in "4Shark" organization:
    - paulo.ribeiro@4shark.com.br
    - elisio.filho@4shark.com.br
    - emerson.silva@4shark.com.br
  - [ ] Download `.ovpn` profiles
  - [ ] Connect via VPN client
  - [ ] Test connectivity:
    - [ ] Ping integrator machine (e.g., `10.1.0.x`)
    - [ ] Ping management VPC machine (e.g., `10.255.x.x`)
    - [ ] Resolve DNS: `nslookup <hostname>.4shark.internal`
    - [ ] SSH to an internal machine
  - [ ] Document results
- **Completion criteria:** VPN connected. All networks reachable. DNS resolves.
- **[HOLD POINT]** If connectivity fails: check VPC Route Advertisement, security groups, DNS proxy. Do not proceed to Phase 6 until all tests pass.

---

### Phase 6: Migration and Decommission — PARTIAL

> **Dependency:** Task 22 complete — all connectivity verified.

### Task 23 — Transition users to new VPN — DONE

- **Status:** COMPLETE
- **Result:** Profiles distributed to all engineers. VPN profiles for OpenVPN and WireGuard available.

### Task 24 — Remove OpenVPN routes from `auth-001/vpc.tf` — DONE

- **Status:** COMPLETE (2026-03-03)
- **Objective:** Delete OpenVPN connector routes from Terraform.
- **Actions (checklist):**
  - [x] Remove `aws_route.pub_openvpn_80` (route to `100.80.0.0/12` via dead ENI)
  - [x] Remove `aws_route.pub_openvpn_96` (route to `100.96.0.0/11` via dead ENI)
  - [x] Run `terraform validate` in `auth-001/` — passed
  - [x] Run `terraform plan` — confirmed 2 route deletions (both already in `blackhole` state)
- **Affected files:** `auth-001/vpc.tf`
- **Note:** Code change included in PR `feature/vpc-app-beta-001`. Apply blocked until `networking/` is applied first (creates missing SSM parameter `nat_gateway_eips` for management).

### Task 25 — Decommission old VPN instances — DONE

- **Status:** COMPLETE (2026-03-03)
- **Objective:** Decommission old VPN instances that are no longer needed.

**Final inventory:**

| # | Instance | ID | Region | Action | Date |
|---|----------|----|--------|--------|------|
| 1 | `4shark-vpn-001` | i-081c9edd7aa737bfd | sa-east-1 | **KEEP** (Terraform-managed) | — |
| 2 | `VPN-Pritunl-management` | i-046935b488a2fa3ed | sa-east-1 | **Terminated** | 2026-03-03 |
| 3 | `ovpn-connector-1-OLD` | i-0426b9931c3763436 | sa-east-1 | **Terminated** | 2026-03-03 |
| 4 | `production-vpn` | i-0d024e262cf53e00d | us-east-1 | **Terminated** | 2026-03-03 |
| 5 | `pritunl-beta-app0001` | i-03f3a7be5c6de8a69 | us-east-1 | **Terminated** | 2026-03-03 |
| 6 | `staging-vpn` | i-0c15fc4817cb0a667 | us-east-1 | **Terminated** | 2026-03-03 |

**Additional cleanup (Beta VPC, done with instance #5):**
- SG `VPN-Client-Beta` (sg-01689947e4f5c6e53) — deleted
- SG `4Shark-Beta-db` (sg-067dc36d901a5b1d0) — deleted (orphaned, 0 ENIs, 0 RDS)

### Task 26 — Update CHANGELOG.md — DONE

- **Status:** COMPLETE
- **Result:** Updated in both Terraform (PR #192) and Ansible (PR #141) before merge.

---

### Pending work (separate from this feature)

- [ ] **VPC Peering Management ↔ Beta into Terraform** — peering `pcx-0ac1851979c0a8730` was created manually via AWS CLI, needs to be imported or codified when networking layer is restructured.
- ~~**Add `10.255.0.0/16` to Production/Beta SGs**~~ — DROPPED. Networking layer in Terraform is being restructured separately; not worth adding to current mess.

---

## 2) Items Requiring User Confirmation

- [x] **Phase 0 access:** SSH access confirmed and used (temporary rules opened/closed)
- [ ] **Subnet ID:** Confirm public subnet ID in Management VPC for `10.255.0.0/24`
- [ ] **Ansible project location:** Confirm `~/Projects/4Shark/ansible/` is the correct path
- [ ] **Naming:** Is `4shark-vpn-001` and organization `4Shark` appropriate?
- [ ] **VPN port:** Choose UDP port for new instance (existing: 18428 prod, 19517 beta)
- [ ] **Decommission timeline:** When to terminate old instances? (after transition period)

---

## 3) Pending Items After This Iteration

- [ ] **Terraform provider `disc/pritunl`:** Future phase to manage users/orgs/servers as code
- ~~**DNS troubleshooting**~~ — RESOLVED (dnsmasq + Little Snitch exception)
- ~~**Route table monitoring**~~ — Not using VPC Route Advertisement (routes configured manually in Pritunl UI)
- ~~**Apply SG changes in environments**~~ — Already applied via PR #191

---

## Summary

| Phase | Tasks | Type | Project | Status |
|-------|-------|------|---------|--------|
| **Phase 0** (Tasks 1–5) | Discovery from existing Pritunl | Manual — SSH + Web UI | Existing servers | **COMPLETE** |
| **Phase 1** (Tasks 6–12) | Create Terraform module + root module | Code — `/execute` | terraform | **COMPLETE** |
| **Phase 2** (Task 13) | Deploy infrastructure | `terraform apply` | terraform | **COMPLETE** |
| **Phase 3** (Tasks 14–16) | Create Ansible role + run playbook | Code + execution | ansible | **COMPLETE** |
| **Phase 4** (Tasks 17–19) | Update SG ID in 7 environments | Code — `/execute` | terraform | **COMPLETE** (PR #191) |
| **Phase 5** (Tasks 20–22) | Configure Pritunl via Web UI | Manual / Operational | — | **COMPLETE** |
| **Phase 6** (Tasks 23–26) | Migration + decommission + changelog | Manual + code | terraform | **COMPLETE** |

**Total code tasks:** 12 (Phases 1 + 3 + 4)
**Total operational tasks:** 14 (Phases 0 + 2 + 5 + 6)

### Key Values (from Discovery)

| Parameter | Value |
|-----------|-------|
| OS | Ubuntu 24.04 LTS |
| Key Pair | `4Shark-prd` |
| Instance Type | `t3a.micro` |
| Disk | 20GB gp3 |
| MongoDB | Local, v6.0.25 |
| VPN Users | paulo.ribeiro@, elisio.filho@, emerson.silva@ (@4shark.com.br) |
| DNS | VPC resolver (e.g., `10.255.0.2`) + search domain `4shark.internal` |
| NAT | MASQUERADE (SourceDestCheck=true is fine) |
