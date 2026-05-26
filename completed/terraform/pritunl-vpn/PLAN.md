# PLAN — Standardize VPN: Migrate to Single Pritunl Instance

> Reference: SPIKE.md at `~/.claude/plans/active/spike/pritunl-vpn-terraform/SPIKE.md`

## Current Situation

### VPN Instances (confirmed via AWS CLI — 2026-03-02)

6 running instances found across 2 regions:

**sa-east-1 — Management VPC (`vpc-0bdc76f3b391694dd`, 10.255.0.0/16):**

| Instance | Instance ID | Public IP | Type | Provisioning | Status |
|----------|-------------|-----------|------|--------------|--------|
| `4shark-vpn-001` | i-081c9edd7aa737bfd | 18.228.109.20 | t3a.micro | Terraform (`vpn/`) + Ansible | **KEEP — new, permanent** |
| `VPN-Pritunl-management` | i-046935b488a2fa3ed | 54.94.130.156 | t3a.micro | Manual (third party) | **TBD — awaiting engineer decision** |
| `ovpn-connector-1-OLD` | i-0426b9931c3763436 | 18.230.152.167 | t3.small | Ansible (`provision-openvpn.yml`) | **TBD — awaiting engineer decision** |

**us-east-1 — Production VPC (`vpc-0204a1f8b5de51941`, 10.254.0.0/16):**

| Instance | Instance ID | Public IP | Type | Provisioning | Status |
|----------|-------------|-----------|------|--------------|--------|
| `production-vpn` | i-0d024e262cf53e00d | 52.71.109.191 | t3a.micro | Manual (third party) | **TBD — awaiting engineer decision** |

**us-east-1 — Beta VPC (`vpc-0968cc73edd5596b0`, 10.154.0.0/16):**

| Instance | Instance ID | Public IP | Type | Provisioning | Status |
|----------|-------------|-----------|------|--------------|--------|
| `pritunl-beta-app0001` | i-03f3a7be5c6de8a69 | 54.205.27.81 | t3a.micro | Manual (third party) | **TBD — awaiting engineer decision** |
| `staging-vpn` | i-0c15fc4817cb0a667 | 44.214.209.13 | t2.micro | Unknown | **NEW FINDING — not in original SPIKE, unknown purpose** |

**Note (2026-03-02):** Original SPIKE found 5 instances. AWS CLI confirms 6 — `staging-vpn` (us-east-1, Beta VPC, t2.micro) was not previously known. It shares the same VPC as `pritunl-beta-app0001`.

### Existing Pritunl Configuration (from SSH + Web UI inspection)

Both instances share identical config except where noted:

| Param | Production | Beta |
|-------|-----------|------|
| **Pritunl version** | v1.32.4278.46 | v1.32.4400.99 |
| **OS** | Ubuntu 24.04.2 LTS | Ubuntu 24.04 LTS |
| **MongoDB** | 6.0.25 local (5MB data) | 6.0.25 local |
| **Port** | 18428/udp | 19517/udp |
| **Virtual Network** | 192.168.220.0/24 | 192.168.248.0/24 |
| **VPC Route** | 10.254.0.0/16 | 10.154.0.0/16 |
| **DNS** | 8.8.8.8 (no search domain) | 8.8.8.8 (no search domain) |
| **Cipher** | AES 128bit GCM | AES 128bit GCM |
| **Hash** | SHA-1 | SHA-1 |
| **Block Outside DNS** | On | Off |
| **Restrict Routing** | On | On |
| **Inter-Client** | On | On |
| **NAT mode** | MASQUERADE (iptables) | MASQUERADE (iptables) |
| **SourceDestCheck** | true (works due to NAT) | true (works due to NAT) |
| **IAM Profile** | None (SSM broken) | None (SSM broken) |
| **Disk** | 6.8GB (83% full) | 8GB |
| **RAM** | 918MB (t3a.micro) | 918MB (t3a.micro) |
| **Key Pair** | `4Shark-prd` | `4Shark-prd` |

### Infrastructure References

- **OpenVPN routes**: `auth-001/vpc.tf` lines 144–155 (`100.80.0.0/12` and `100.96.0.0/11` via ENI `eni-02bdd29d01b46838d`)
- **Management VPN SG**: `sg-001068a60ca68d4ba` — hardcoded in 7 environment `main.tf` files
- **Internal DNS zone**: `4shark.internal` (Route53 Zone ID: `Z3PBW9DU61QULB`)

### Network Topology

- **sa-east-1**: Management VPC `10.255.0.0/16` (hub) + 6 integrator VPCs + 1 app VPC — all via VPC Peering
- **us-east-1**: Production VPC `10.254.0.0/16` + Beta VPC `10.154.0.0/16` + 4app-atento `10.2.1.0/24`
- **Cross-region peering**:
  - Production VPC → Management VPC (`pcx-0d8b42289e7030f61`) — routes OK both sides
  - Beta VPC → Management VPC (`pcx-0ac1851979c0a8730`) — created manually via AWS CLI
  - 4app-atento → Management VPC
- **No Transit Gateway** — all connectivity via VPC Peering (no transitive routing)
- **SG access note**: Production and Beta SGs only allow their own VPC CIDR. VPN traffic arrives with source `10.255.x.x` (Management VPC) due to NAT. Network-level access is confirmed working, but individual service SGs block it. Not worth fixing now — networking layer is being restructured later.

### Problems Found

1. **DNS = 8.8.8.8** — does not resolve `*.4shark.internal`. Must use VPC DNS resolver
2. **No DNS Search Domain** — clients can't use short hostnames
3. **No IAM Instance Profile** — SSM Agent installed but can't register
4. **Disk at 83%** — 1.2GB free on production, logs will fill it
5. **MongoDB local with no backup** — instance death = config loss
6. **Routes limited to own VPC** — each VPN only reaches its own network
7. **Beta VPC completely isolated** — no VPC peering connections at all

## Objective / Target State

Replace three separate VPN solutions (1 paid OpenVPN + 2 unmanaged Pritunl instances) with a single Pritunl instance where **Terraform manages infrastructure** and **Ansible manages application installation/configuration**.

**Success criteria:**
- [x] Single Pritunl instance deployed in Management VPC via Terraform module
- [x] Pritunl installed and configured via Ansible role (idempotent, re-runnable)
- [x] All engineers can connect via VPN and reach all internal resources (management VPC, all integrator VPCs, app VPC)
- [x] Internal DNS (`*.4shark.internal`) resolves correctly for VPN clients (via dnsmasq)
- [x] All `management_vpn_sg_id` references updated to the new Pritunl security group ID
- [x] CHANGELOG.md updated
- [ ] OpenVPN routes removed from `auth-001/vpc.tf` — DEFERRED (keeping old VPN as safety net)
- [ ] Old Pritunl instances decommissioned — DEFERRED (keeping old VPN as safety net)
- [~] ~~Production/Beta SGs updated to allow `10.255.0.0/16` for VPN access~~ — DROPPED (networking layer will be restructured separately)

## Problem / New Feature

**Objective**: Consolidate three VPN solutions into one Terraform-managed Pritunl instance that provides full-mesh access to the entire internal network.

**Current pain points**:
- OpenVPN is a paid product — cost without benefit over Pritunl
- Two unmanaged Pritunl instances (prod + beta) create inconsistent access and operational overhead
- Integrator machines are not reachable through current VPN — engineers cannot debug integrator services
- Internal DNS does not resolve through VPN — hostnames like `db.4shark.internal` fail for connected clients

## Challenges, Difficulties and Risks

**Technical**:
- The new Pritunl instance must coexist with existing VPN during migration (parallel deployment)
- NAT/MASQUERADE handles routing — SourceDestCheck can remain true (confirmed on existing instances)
- VPC Route Advertisement requires IAM permissions to modify route tables
- MongoDB runs locally on the same instance — no external dependency but also no HA
- Disk must be 20GB+ to avoid the 83% usage problem found on production (6.8GB)

**Security**:
- VPN port (UDP) must be open from internet for client connections
- Management console (443/TCP) must be restricted to SSM port-forward only — no direct internet access
- Setup key stored in Secrets Manager — access must be restricted to the instance role and authorized engineers

**Migration**:
- Existing Pritunl users must be recreated manually (no import tool)
- `.ovpn` profiles from old instances are not compatible — users need new profiles
- Transition period requires both old and new VPN to be operational simultaneously
- Decommissioning old OpenVPN must be coordinated with auth-001 Terraform changes

**Operational**:
- `management_vpn_sg_id` is a hardcoded string in 7 files — all must be updated after the new SG is created
- The new SG ID is only known after `terraform apply` on the new module

## Solution Options

**Option 1 — Terraform (infra) + Ansible (application) — SELECTED**
- **How it works**: Terraform creates the EC2 instance, EIP, security group, and IAM role. Ansible role installs Pritunl + MongoDB, configures services, and stores setup-key in Secrets Manager. This matches the existing project pattern where integrator instances use `Automation = "ansible"`.
- **Pros**: Idempotent installation (re-runnable), consistent with existing project patterns, separation of concerns (infra vs app), easy to update Pritunl/MongoDB versions later
- **Cons**: Requires Ansible playbook run after Terraform apply (two-step deploy)
- **When NOT to use**: If the team wants a single-tool deployment

**Option 2 — Terraform with user_data (rejected)**
- **How it works**: Terraform creates everything including a user_data script that installs Pritunl on first boot
- **Pros**: Single-tool deployment
- **Cons**: Not idempotent (runs once on boot), if it fails you destroy and recreate, can't update Pritunl without recreating instance, inconsistent with project patterns
- **When NOT to use**: When ongoing maintenance and consistency matter

**Selected approach**: Option 1 (Terraform + Ansible)

## Proposed Steps

### Phase 0: Discovery — Extract configuration from existing Pritunl server — COMPLETE

**Purpose**: Connect to the existing production Pritunl server via SSH/SSM and extract all current configuration. This data will inform the Ansible role to replicate the exact same setup.

**Status**: COMPLETE — Both production and beta instances inspected via temporary SSH + Web UI. All findings documented in SPIKE.md "Discovery" section and in this plan's "Current Situation" section above.

The engineer connected to both Pritunl instances and extracted the following (preserved for reference):

**System-level information:**
```bash
# OS and version
cat /etc/os-release

# Pritunl version
pritunl version

# MongoDB version
mongod --version

# Installed packages related to Pritunl
dpkg -l | grep -E "pritunl|mongod|wireguard" 2>/dev/null || rpm -qa | grep -E "pritunl|mongod|wireguard"

# Repository sources for Pritunl and MongoDB
cat /etc/apt/sources.list.d/pritunl*.list 2>/dev/null; cat /etc/apt/sources.list.d/mongodb*.list 2>/dev/null
# Or for RPM-based:
cat /etc/yum.repos.d/pritunl*.repo 2>/dev/null; cat /etc/yum.repos.d/mongodb*.repo 2>/dev/null
```

**Pritunl configuration:**
```bash
# Full Pritunl settings dump
sudo pritunl get

# Setup key (for reference, not reuse)
sudo pritunl setup-key

# Default password (if still default)
sudo pritunl default-password
```

**Service configuration:**
```bash
# Pritunl service status and configuration
systemctl status pritunl
systemctl cat pritunl

# MongoDB service status and configuration
systemctl status mongod
systemctl cat mongod

# MongoDB data directory and config
cat /etc/mongod.conf
```

**Network configuration:**
```bash
# Network interfaces
ip addr show

# Current routing table
ip route show

# iptables/nftables rules
sudo iptables -L -n -v 2>/dev/null || sudo nft list ruleset 2>/dev/null

# Source/dest check status (from instance metadata)
curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -1 | xargs -I{} curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/{}source-dest-check

# DNS configuration
cat /etc/resolv.conf
systemctl status systemd-resolved 2>/dev/null
resolvectl status 2>/dev/null
```

**SSL/TLS:**
```bash
# SSL certificate info
sudo ls -la /var/lib/pritunl/*.pem 2>/dev/null
sudo ls -la /etc/pritunl/ 2>/dev/null

# Check if Let's Encrypt is used
sudo ls -la /etc/letsencrypt/ 2>/dev/null
```

**Disk and resources:**
```bash
# Disk usage
df -h

# Memory
free -h

# Instance type (from metadata)
curl -s http://169.254.169.254/latest/meta-data/instance-type
```

**MongoDB data (Pritunl application state):**
```bash
# List Pritunl organizations
mongo pritunl --eval "db.organizations.find().pretty()"

# List Pritunl servers (VPN servers)
mongo pritunl --eval "db.servers.find({}, {name:1, port:1, protocol:1, network:1, routes:1, dns_servers:1, search_domain:1}).pretty()"

# List Pritunl users
mongo pritunl --eval "db.users.find({}, {name:1, email:1, type:1, disabled:1, org_id:1}).pretty()"

# List server routes
mongo pritunl --eval "db.servers.find({}, {routes:1}).pretty()"
```

The engineer will provide all output. This data will be used to create the Ansible role with matching configuration.

### Phase 1: Create the `modules/pritunl` Terraform module

Build the reusable module. **Terraform handles infrastructure only — no user_data for application installation.**

Files to create:
```
modules/pritunl/
├── main.tf          # EC2 instance, EIP, source/dest check disabled
├── variables.tf     # All inputs: vpc_id, subnet_id, instance_type, ami_id, key_name, etc.
├── outputs.tf       # security_group_id, instance_id, public_ip, private_ip, eip_allocation_id
├── iam.tf           # IAM role + instance profile + SSM policy + VPC route advertisement policy
└── security.tf      # aws_security_group for VPN traffic
```

Key differences from previous plan:
- **No user_data.tf / user_data.sh.tpl** — Ansible handles installation
- **IAM role includes SSM managed policy** (`AmazonSSMManagedInstanceCore`) for Ansible/SSM access
- **IAM role includes VPC route advertisement permissions** + Secrets Manager write
- **Tag `Automation = "ansible"`** (not "terraform") on the EC2 instance, matching integrator pattern
- **Tag `Automation = "terraform"`** on infrastructure resources (SG, EIP, IAM)

IAM policy permissions:
```json
{
  "ec2:DescribeRouteTables",
  "ec2:CreateRoute",
  "ec2:ReplaceRoute",
  "ec2:DeleteRoute",
  "secretsmanager:PutSecretValue",
  "secretsmanager:CreateSecret"
}
```

Plus AWS managed policy: `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`

Security group rules:
- Inbound: `<vpn_port>`/UDP from `0.0.0.0/0` (VPN client connections — existing instances use 18428 and 19517)
- Inbound: ALL traffic from Management VPC CIDR `10.255.0.0/16` (internal access)
- Outbound: all traffic to `0.0.0.0/0`
- No inbound port 22 (SSH managed via SSM only)
- No inbound 443/TCP from internet (web console via SSM port-forward only)

### Phase 2: Create the `vpn/` root module and deploy

Create a new Terraform root module directory `vpn/` to manage the Management VPC resources. It will:
1. Reference the existing Management VPC and subnets by ID (not re-create them)
2. Instantiate `modules/pritunl` into the Management VPC public subnet (`10.255.0.0/24`)
3. Create the Route53 A record `vpn.4shark.internal` pointing to the EIP
4. Output the new `management_vpn_sg_id` for use in other modules

```hcl
module "pritunl" {
  source = "../modules/pritunl"

  name_prefix    = "4shark-vpn-001"
  vpc_id         = "vpc-0bdc76f3b391694dd"
  subnet_id      = "<pub_a_subnet_id>"   # 10.255.0.0/24
  instance_type  = "t3a.micro"
  key_name       = "4Shark-prd"
  volume_size    = 20

  tags = {
    Environment = "management"
    Role        = "vpn"
  }
}
```

### Phase 3: Ansible role — Install and configure Pritunl

**This phase happens in the `ansible` project**, not in this Terraform project. The Ansible role will be created based on the discovery data from Phase 0.

Role structure:
```
roles/pritunl/
├── tasks/
│   └── main.yml       # Installation and configuration tasks
├── handlers/
│   └── main.yml       # Service restart handlers
├── templates/
│   ├── mongod.conf.j2 # MongoDB configuration
│   └── pritunl.conf.j2 # Pritunl configuration (if applicable)
├── defaults/
│   └── main.yml       # Default variables
└── vars/
    └── main.yml       # Role variables
```

Role responsibilities:
1. Add Pritunl and MongoDB official repositories
2. Install packages: `pritunl`, `mongodb-org`, `wireguard`, `wireguard-tools`
3. Configure MongoDB (`/etc/mongod.conf`)
4. Disable `systemd-resolved` DNS stub listener (prevent port 53 conflict)
5. Enable and start `mongod` and `pritunl` services
6. Run `pritunl setup-key` and store output in AWS Secrets Manager
7. Store default admin password in Secrets Manager
8. All tasks must be idempotent (safe to re-run)

Playbook execution:
```bash
ansible-playbook -i inventory playbooks/pritunl.yml --limit 4shark-vpn-001
```

### Phase 4: Update all environment modules with new SG ID

After `terraform apply` on `vpn/`, retrieve the output `module.pritunl.security_group_id` and update `management_vpn_sg_id` in:

- `integrator-almaviva/main.tf`
- `integrator-redebrasil/main.tf`
- `integrator-maqnelson/main.tf`
- `integrator-commcenter/main.tf`
- `integrator-aster-maquinas/main.tf`
- `integrator-atento-br/main.tf`
- `app-atento-br/main.tf`

This is a plain string substitution. No `terraform apply` needed for these environments unless other changes are being made — the security group membership in each VPC's default SG will update on next apply.

### Phase 5: Configure Pritunl via web UI (post-Ansible)

After Ansible completes, access via SSM Session Manager port-forward:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["443"],"localPortNumber":["4430"]}'
```

Then open `https://localhost:4430` in a browser.

Configuration steps (manual, not Terraform-managed in this phase):
1. Retrieve setup key from Secrets Manager
2. Complete web wizard (setup key + MongoDB URI = `mongodb://localhost:27017/pritunl`)
3. Create organization (e.g., "4Shark")
4. Create VPN server with:
   - Port: `1194` UDP (primary), `1195` UDP (WireGuard)
   - Remove default `0.0.0.0/0` route
   - Add routes for all internal CIDRs (see list below)
   - Enable VPC Route Advertisement on each route
   - Enable "VPN Client DNS Mapping"
   - Push DNS server: `10.255.0.2` (Management VPC resolver)
   - Push search domain: `4shark.internal`
5. Create users and assign to organization
6. Start the server

Routes to configure in Pritunl server:
```
10.255.0.0/16   # Management VPC
10.1.0.0/24     # integrator-almaviva
10.1.1.0/24     # integrator-redebrasil
10.1.2.0/24     # integrator-maqnelson
10.1.3.0/24     # integrator-commcenter
10.1.4.0/24     # integrator-aster-maquinas
10.12.0.0/26    # app-atento-br
10.12.255.0/24  # integrator-atento-br
```

### Phase 6: Migration and decommission — COMPLETE

1. ~~Test all network paths from a connected VPN client~~ — DONE
   - OpenVPN: connected, DNS resolving, all networks reachable
   - WireGuard: connected, DNS resolving (14ms), all networks reachable
   - Management VPC: direct access OK
   - Production VPC: peering OK, network reachable (SGs need `10.255.0.0/16`)
   - Beta VPC: peering created, network reachable (SGs need `10.255.0.0/16`)
2. ~~Migrate users~~ — DONE (profiles distributed to all engineers)
3. ~~Decommission~~ — DONE (2026-03-03)

   All 5 legacy VPN instances terminated. Only `4shark-vpn-001` (Terraform-managed) remains.

   | # | Instance | ID | Action | Date |
   |---|----------|----|--------|------|
   | 1 | `VPN-Pritunl-management` | i-046935b488a2fa3ed | Terminated | 2026-03-03 |
   | 2 | `ovpn-connector-1-OLD` | i-0426b9931c3763436 | Terminated | 2026-03-03 |
   | 3 | `production-vpn` | i-0d024e262cf53e00d | Terminated | 2026-03-03 |
   | 4 | `staging-vpn` | i-0c15fc4817cb0a667 | Terminated | 2026-03-03 |
   | 5 | `pritunl-beta-app0001` | i-03f3a7be5c6de8a69 | Terminated | 2026-03-03 |

   Additional cleanup (Beta VPC):
   - SG `VPN-Client-Beta` (sg-01689947e4f5c6e53) — deleted
   - SG `4Shark-Beta-db` (sg-067dc36d901a5b1d0) — deleted (orphaned, 0 ENIs, 0 RDS)

## Internal References

- OpenVPN routes: `auth-001/vpc.tf` lines 144–155
- Management VPN SG references: `integrator-almaviva/main.tf`, `integrator-redebrasil/main.tf`, `integrator-maqnelson/main.tf`, `integrator-commcenter/main.tf`, `integrator-aster-maquinas/main.tf`, `integrator-atento-br/main.tf`, `app-atento-br/main.tf`
- Module security patterns: `modules/integrator/security.tf`, `modules/app/security.tf`
- Module variable patterns: `modules/integrator/variables.tf`, `modules/app/variables.tf`
- Spike research: `~/.claude/plans/active/spike/pritunl-vpn-terraform/SPIKE.md`
- Ansible project: `~/Projects/4Shark/ansible/`

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Infrastructure approach | Custom `modules/pritunl` | Follows project patterns, no external module dependency |
| Application installation | Ansible role | Idempotent, re-runnable, consistent with integrator pattern (`Automation = "ansible"`) |
| Configuration management | Web UI (Phase 1) | Terraform provider (`disc/pritunl`) deferred — simplifies initial deployment |
| OS | Ubuntu 24.04 LTS | Same OS as both existing Pritunl instances (discovered). Pritunl officially supports it |
| Instance placement | Public subnet of Management VPC | VPN requires internet-accessible IP; SSM handles management access |
| Bootstrap access | SSM Session Manager + Secrets Manager | Secure, no SSH port exposure required |
| Instance type | `t3a.micro` | Same as existing instances. 918MB RAM is sufficient for 3 users + MongoDB (5MB data) |
| Key pair | `4Shark-prd` | Same key pair used by both existing Pritunl instances (discovered) |
| Disk | 20GB gp3 | Existing instances had 6.8–8GB (83% full on prod). 20GB provides room for growth without waste |
| MongoDB backend | Local (same instance) | DocumentDB minimum $56/mo, Atlas M10 $57/mo — overkill for 5MB database. Local with log rotation via Ansible |
| NAT mode | MASQUERADE (iptables) | Same as existing instances. SourceDestCheck=true works fine with NAT |
| High availability | Single instance (no ASG) | Scope: single instance replacing existing single instances |
| DNS record | `vpn.4shark.internal` via Route53 | Internal resolution for tooling and documentation |
| Log rotation | Ansible-managed logrotate | Prevent disk fill (production was at 83% due to logs) |
| Discovery before build | Phase 0 extracts config from existing Pritunl | Ensure new instance matches production configuration — **COMPLETE** |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Discovery reveals unexpected config | ~~Medium~~ Resolved | Phase 0 complete — no surprises. NAT/MASQUERADE confirmed, MongoDB 6.0.25, 5MB data |
| Ansible role fails on first run | Low | Idempotent tasks, can re-run safely after fixing |
| New SG ID update requires manual propagation | Medium | All 7 files identified; update immediately after Phase 2 apply |
| Pritunl VPC Route Advertisement modifies live route tables | High | Test in non-critical VPC first; backup current route table state |
| Users lose VPN access during migration | High | Run old and new instances in parallel; migrate users in batches |
| DNS port 53 conflict with systemd-resolved | Medium | Ansible disables `DNSStubListener` before Pritunl starts |
| Old Pritunl instances not in Terraform state | Low | Decommission is manual (terminate EC2 via console) |
| `disc/pritunl` provider not used in Phase 1 | Low | Configuration not reproducible from code; accepted trade-off for Phase 1 |

## Assumptions

- The Management VPC, subnets, and peering connections already exist and are functional
- Ubuntu 24.04 LTS AMI supports Pritunl installation (confirmed — both existing instances run Ubuntu 24.04)
- SSM Agent is available in the Ubuntu AMI (confirmed installed on existing instances via snap, just needs IAM Profile)
- AWS Secrets Manager is available and accessible from the Management VPC
- The key pair `4Shark-prd` exists and is available (confirmed — used by both existing Pritunl instances)
- Public subnet `10.255.0.0/24` (pub_a) is the correct subnet for the Pritunl instance
- All VPC peering routes are already in place — this plan does not add new peering connections
- The `ansible` project exists at `~/Projects/4Shark/ansible/` and follows standard role structure
- 3 VPN users: paulo.ribeiro@4shark.com.br, elisio.filho@4shark.com.br, emerson.silva@4shark.com.br

---

## Additional Work (not in original plan)

- **WireGuard port** (14721/UDP) added to SG permanently — required for WireGuard client connections
- **HTTPS 443/TCP** added to SG permanently — required for Pritunl client sync (without it, WireGuard "Failed to sync")
- **dnsmasq** installed via Ansible instead of Pritunl DNS Mapping (Enterprise-only feature) — forwards `4shark.internal` queries to VPC DNS resolver `10.255.0.2`
- **VPC Peering Management ↔ Beta** (`pcx-0ac1851979c0a8730`) created manually via AWS CLI — did not exist before
- **Little Snitch DNS Encryption** — Mac users need to add exception for `4shark.internal` domain pointing to `10.149.176.1` (VPN DNS)
- **/etc/hosts hostname fix** — added to Ansible playbook to prevent `sudo: unable to resolve host` warnings

---

**Status:** ALL PHASES COMPLETE (0–6) — Feature finished 2026-03-03
