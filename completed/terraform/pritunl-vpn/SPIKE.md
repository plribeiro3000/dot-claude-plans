# SPIKE — Pritunl VPN: Terraform Deployment, Architecture, and Migration

**Conducted by:** Engineering
**Date:** 2026-02-26
**Status:** COMPLETE — Decisions made, PLAN.md and TASKS.md created at `~/.claude/plans/active/terraform/standardize-vpn/`

---

## Goal

Answer the following questions before planning a Pritunl VPN deployment (or migration from OpenVPN):

1. Is there an official or reliable community Terraform module for Pritunl on AWS?
2. Is there an official AMI? What is the recommended installation method?
3. How does Pritunl handle multi-subnet/multi-VPC routing?
4. Should the management interface be public or internal? How to solve the bootstrap problem?
5. How does Pritunl handle DNS resolution for internal resources?
6. What are the networking requirements (ports, protocols, security groups)?
7. How does Pritunl compare to OpenVPN for routing and subnet access?
8. How to migrate from OpenVPN and/or consolidate multiple Pritunl instances?

---

## Method

- Web search for current Pritunl documentation, community experience, and Terraform modules (2024–2026)
- Review of official Pritunl documentation at docs.pritunl.com
- Review of community Terraform modules on GitHub and Terraform Registry
- Review of Mattermost's public case study on OpenVPN-to-Pritunl migration
- Review of CloudFormation template from the official Pritunl GitHub repository

---

## Evidence

### 1. Terraform Modules

#### No Official Module Exists

Pritunl does not publish an official Terraform module. All available modules are community-maintained. There is also a **Terraform provider** (`disc/pritunl`) that manages Pritunl *configuration* (users, organizations, servers) post-deployment — separate from the infrastructure provisioning modules.

#### Community Infrastructure Modules (EC2 provisioning)

| Module | Source | Approach | Status |
|--------|--------|----------|--------|
| `oozou/terraform-aws-pritunl-vpn` | [GitHub](https://github.com/oozou/terraform-aws-pritunl-vpn) | ASG + EFS + NLB + Route53 + user_data | Active (v0.0.0, Apache 2.0) |
| `iops-team/ec2-pritunl/aws` | [Terraform Registry](https://registry.terraform.io/modules/iops-team/ec2-pritunl/aws/latest) | EC2 + user_data | Unknown maintenance |
| `opsgang/terraform-aws-pritunl-vpn-server` | [GitHub](https://github.com/opsgang/terraform-aws-pritunl-vpn-server) | EC2 + user_data | Unknown maintenance |
| `poush/terraform-aws-pritunl` | [GitHub](https://github.com/poush/terraform-aws-pritunl) | EC2 + Elastic IP + user_data | Last commit 2019 — abandoned |
| `wirediq/terraform-aws-ec2-pritunl-vpn` | [GitHub](https://github.com/wirediq/terraform-aws-ec2-pritunl-vpn) | EC2 + user_data | Unknown maintenance |

**Most complete module:** `oozou/terraform-aws-pritunl-vpn` — includes Auto Scaling Group, EFS for persistent config, Network Load Balancer (public and private), Route53, IAM roles, launch templates, and security groups. This is the most production-oriented approach found.

**Develeap (2025 blog post):** Documents a complete reusable Terraform module that:
- Places Pritunl + MongoDB in a **private subnet**
- Bootstraps Pritunl via user_data
- Stores the setup key and default admin credentials in **AWS Secrets Manager**
- Source: [Replacing AWS Client VPN with Pritunl](https://www.develeap.com/replacing-aws-client-vpn-with-pritunl-a-terraform-first-approach/nico-aroyo)

#### Terraform Provider (Pritunl configuration management)

The `disc/pritunl` provider (v0.3.1) manages Pritunl **after** it is deployed. It supports:

- `pritunl_organization` — create organizations
- `pritunl_user` — create users (name, email, groups, organization)
- `pritunl_server` — create VPN servers (port, protocol, network, groups, org associations)

Provider requires: `url`, `token`, `secret`, and optionally `insecure` (for self-signed certs).
Sources: [Terraform Registry](https://registry.terraform.io/providers/disc/pritunl/latest/docs), [GitHub](https://github.com/disc/terraform-provider-pritunl)

A fork also exists: [next-gen-infrastructure/terraform-provider-pritunl](https://pkg.go.dev/github.com/next-gen-infrastructure/terraform-provider-pritunl)

---

### 2. AMI and Installation Method

#### No Official AMI

Pritunl explicitly does **not** publish AMIs. From the official documentation:
> "Only the Amazon provided images in the Quick Start section and the official Oracle Linux images from the Oracle owner ID should be used."

Third-party AMIs exist on the AWS Marketplace but are not endorsed by Pritunl.

#### Recommended OS

From official docs, priority order:
1. **Oracle Linux 9** — all Pritunl development and testing is done on this
2. **AlmaLinux 9** — good compatibility, full SELinux profile support
3. **Amazon Linux 2023** — dedicated builds available
4. **Ubuntu 24.04** — supported but noted as having "outdated OpenVPN builds"

#### Installation Method: user_data Script

The standard approach is launching a plain EC2 from an official OS AMI and installing via `user_data`. Example script (Ubuntu 22.04, from community tutorials):

```bash
echo 'deb http://repo.pritunl.com/stable/apt jammy main' > /etc/apt/sources.list.d/pritunl.list
echo 'deb https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse' > /etc/apt/sources.list.d/mongodb-org-6.0.list
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
apt update && apt --assume-yes upgrade
apt -y install wireguard wireguard-tools
ufw disable
apt -y install pritunl mongodb-org
systemctl enable mongod pritunl && systemctl start mongod pritunl
```

The official Pritunl CloudFormation template (RHEL/Amazon Linux based) installs via YUM from Pritunl's RPM repository. Source: [pritunl.template on GitHub](https://github.com/pritunl/pritunl/blob/master/tools/aws/pritunl.template)

**Important:** Installation can take 3–5 minutes after Terraform applies. The instance must be given enough time before attempting to access the management console.

**Alternative:** Ansible post-provisioning is viable and used by some teams, but user_data is more common in Terraform-first setups.

---

### 3. Multi-Subnet / Multi-VPC Routing

#### How Pritunl Handles Routes

Pritunl server configuration defines which networks VPN clients can reach. The default route is `0.0.0.0/0` (all traffic through VPN). For private network access:

1. **Remove** the default `0.0.0.0/0` route
2. **Add** specific routes per subnet/VPC CIDR (e.g., `10.0.0.0/8`, `172.16.0.0/16`)
3. Each route can be configured with or without NAT

Source: [Accessing a Private Network — Pritunl Docs](https://docs.pritunl.com/docs/accessing-a-private-network)

#### AWS VPC Route Advertisement

When "VPC Route Advertisement" is enabled on a route, Pritunl:
- Uses the IAM role to call the AWS API
- Automatically adds/updates entries in the **VPC route table** pointing to the Pritunl EC2 instance
- Handles failover automatically: if the instance fails, the route table is updated to point to a backup host

**IAM permissions required** (minimum):
```json
{
  "ec2:DescribeRouteTables",
  "ec2:CreateRoute",
  "ec2:ReplaceRoute",
  "ec2:DeleteRoute"
}
```

Or `AmazonVPCFullAccess` for simplicity (less restrictive).

**Source/Destination Check** must be **disabled** on the EC2 network interface to allow routing traffic from other networks.

Source: [AWS Route Advertisement — Pritunl Docs](https://docs.pritunl.com/docs/aws-route-advertisement)

#### Network Mapping (Subnet Overlap)

Pritunl supports remapping overlapping subnets via NAT Network Mapping. Example: if VPC uses `192.168.0.0/16` and a client's local network uses the same range, Pritunl can expose VPC resources as `10.168.0.0/16` to that client. This requires NAT and does not support non-NAT configurations.

Source: [Network Mapping — Pritunl Docs](https://docs.pritunl.com/docs/network-mapping)

---

### 4. Management Interface: Public vs Internal (Bootstrap Problem)

#### Official Security Stance

From the Pritunl security documentation:
> "All ports for SSH, internal tools, and any other internal services on your network should be blocked at the firewall, and these services should always be accessed using the VPN connection."

This implies the management interface should ideally be **internal-only** — but this creates a chicken-and-egg problem: you need the VPN to access the interface, but you need the interface to configure the VPN.

#### Bootstrap Solutions Used in Practice

**Option A — Temporary public access (most common approach):**
- Deploy Pritunl with port 443 temporarily accessible from a restricted IP (e.g., engineer's office IP via security group)
- Complete initial setup (setup-key, admin password, org/user/server configuration)
- After first user is configured and connected via VPN, restrict 443 to internal-only
- Commands to run on first boot via SSH:
  - `sudo pritunl setup-key` — generates the setup key for the web wizard
  - `sudo pritunl default-password` — retrieves the initial admin credentials

**Option B — AWS SSM Session Manager (recommended for fully private setups):**
- Place Pritunl in a private subnet
- Use AWS SSM Session Manager to SSH into the instance without opening port 22
- Run the setup commands via SSM
- Port-forward 443 through SSM to access the web console locally
- This is the approach favored by Develeap's 2025 module (credentials in Secrets Manager)

**Option C — Secrets Manager automation:**
- user_data script runs `pritunl setup-key` and stores output in AWS Secrets Manager
- Operator retrieves setup key from Secrets Manager, accesses console via SSM port-forward
- Fully automates bootstrap without any public exposure

#### Architecture Recommendation

Pritunl uses an internal/external web server separation for security:
- `pritunl-web` (Go) handles SSL and validates incoming requests externally
- The internal Python process only binds to `127.0.0.1`
- SELinux policies are applied to the internal process

Source: [Securing Pritunl — Pritunl Docs](https://docs.pritunl.com/docs/securing-pritunl)

---

### 5. DNS Resolution for Internal Resources

#### How DNS Push Works

Pritunl pushes DNS nameserver settings to VPN clients. Options:

1. **Push custom DNS servers**: Configure the server's DNS settings to push internal resolvers (e.g., AWS Route53 Resolver at `169.254.169.253` or a custom DNS server)
2. **Search domains**: Configure search domains pushed to clients (e.g., `internal.example.com`)
3. **VPN Client DNS Mapping**: When enabled, starts `pritunl-dns` process on the server — proxies all DNS requests, always available to connected clients

#### AWS-Specific DNS

For internal AWS DNS resolution (`.internal`, `.compute.internal`):
- Enable "VPN Client DNS Mapping" in advanced server settings
- Push the VPC DNS resolver (typically `VPC_CIDR + 2`, e.g., `10.0.0.2` for `10.0.0.0/16`)
- May need to add the DNS server IP as a route in the Pritunl server routes

#### Common DNS Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Port 53 conflict | systemd-resolved binds to port 53 | Set `DNSStubListener=no` in `/etc/systemd/resolved.conf` |
| macOS DNS priority issues | All DNS pushed, not just Pritunl's | Run `pritunl set vpn.dns_mapping_push_all false` |
| iOS DNS failures | Platform-specific behavior | Add `8.8.8.8/32` as route, or enable DNS Mapping |
| WPAD interference | ISP proxy auto-discovery | Disable WPAD in network preferences |

Sources: [Internal DNS Docs](https://docs.pritunl.com/docs/internal-dns), [DNS Issues Docs](https://docs.pritunl.com/kb/vpn/client/dns-issues)

---

### 6. Networking Requirements (Ports and Security Groups)

#### Client-Facing Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 443 | TCP | Web console (HTTPS) + WireGuard reverse-proxy mode |
| 80 | TCP | Let's Encrypt certificate validation (optional) |
| 1194 | UDP/TCP | OpenVPN client connections (default, configurable) |
| 1195 | UDP | WireGuard client connections (default, configurable) |
| 10000–19999 | UDP | Legacy range used by some Pritunl versions |

**WireGuard requirement:** Pritunl web service must be running on port 443 with SSL (self-signed or Let's Encrypt). Without this, WireGuard clients fail to connect or time out after 15 seconds.

#### Inter-Host / Cluster Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 9790 | TCP | Host-to-host latency checks (optional) |
| 500 | UDP | IPsec (site-to-site / pritunl-link) |
| 4500 | UDP | IPsec NAT traversal (site-to-site) |
| 4789 | UDP | VXLan (required for multi-host replication) |

#### IAM Permissions for EC2 Instance Role

Minimum required for VPC route advertisement:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeRouteTables",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute"
    ],
    "Resource": "*"
  }]
}
```

---

### 7. Pritunl vs OpenVPN Comparison

| Dimension | OpenVPN (standalone) | Pritunl |
|-----------|---------------------|---------|
| **Architecture** | Single server per VPN | Distributed cluster, no master node |
| **Protocol** | OpenVPN | OpenVPN + WireGuard + IPsec (site-to-site) |
| **Multi-VPC routing** | Manual static routes | Automated via AWS API (VPC route advertisement) |
| **Subnet access** | Configured per server | Multiple routes per server, with NAT options |
| **Access control** | Rule-based per user/group | Group-based (less granular than OpenVPN AS) |
| **High availability** | Manual failover | Automatic failover via replication count |
| **Management UI** | Basic | Full web UI for users, servers, organizations |
| **SSO support** | Plugin-based | Built-in (Okta, OneLogin, etc.) |
| **Device auth** | No | TPM + Apple Secure Enclave |
| **MongoDB dependency** | No | Yes (local or hosted Atlas/DocumentDB) |
| **Terraform provider** | No official provider | `disc/pritunl` provider available |
| **Cost** | Open source | Open source (Enterprise features paid) |

**Key routing difference:** Pritunl can automatically manage VPC route tables so that all instances in the VPC route traffic to Pritunl without requiring each client to know the VPC CIDR. OpenVPN requires manual route configuration and does not integrate with the AWS VPC API.

**Access control trade-off:** Pritunl's group-based access control is less granular than OpenVPN AS's rule-based system. Complex per-user routing rules are harder to implement in Pritunl.

Source: [Mattermost migration case study](https://developers.mattermost.com/blog/pritunl/), [Twingate comparison](https://www.twingate.com/blog/comparisons/openvpn-vs-pritunl)

---

### 8. Migration and Consolidation

#### OpenVPN → Pritunl Migration

Mattermost's documented migration approach:
- Pritunl is built on the OpenVPN protocol — existing OpenVPN clients continue to work
- Users need new `.ovpn` configuration files generated by Pritunl (not compatible with OpenVPN AS format directly)
- No automated import of OpenVPN AS user configurations — users must be recreated in Pritunl
- Forum thread confirms no official import of 3rd-party `.ovpn` profiles: [Importing 3rd party ovpn profiles](https://forum.pritunl.com/t/importing-3rd-party-ovpn-profiles/745)
- Migration is parallel: run both systems, migrate users in batches, then decommission OpenVPN

#### Consolidating Multiple Pritunl Instances

Pritunl's cluster architecture enables consolidation:
- All Pritunl instances connect to a **shared MongoDB** to obtain configuration
- Multiple hosts in a cluster are equals — any host can run any server
- **Replication Count** setting determines how many hosts run each VPN server simultaneously
- Migration between instances: use a shared/remote MongoDB — point new instance at same DB, old instance is removed

Source: [Multi-Host Servers Docs](https://docs.pritunl.com/docs/multi-host-servers), [Scaling Docs](https://docs.pritunl.com/docs/scaling), [move pritunl between servers (gist)](https://gist.github.com/makenova/33fd38b6dbe0ec37d254)

#### User Management Best Practices

- Organize users into **Organizations** (logical groupings, e.g., by team or access level)
- Use **Groups** for access control — assign servers to groups and users to groups
- Integrate SSO (Okta, OneLogin) to avoid managing passwords in Pritunl
- Never email `.ovpn` profiles — use Pritunl's temporary download links or SSO-based key delivery
- The `disc/pritunl` Terraform provider can manage users/orgs as code post-deployment

---

## Conclusions

### What Is Clear

1. **No official Terraform module or AMI exists.** Deployment is always: official OS AMI + user_data script installing from Pritunl's package repository. The `oozou` module is the most complete community option for production use.

2. **Two Terraform layers are needed:** infrastructure provisioning (EC2, security groups, IAM — any community module) + configuration management (`disc/pritunl` Terraform provider for users/orgs/servers).

3. **Multi-subnet access works well.** Add specific subnet CIDRs as routes on the Pritunl server. Enable "VPC Route Advertisement" to have Pritunl automatically manage the VPC route table — no manual static routes needed.

4. **The management interface bootstrap problem has a clean solution:** store `setup-key` output in AWS Secrets Manager via user_data; use SSM Session Manager for initial access instead of opening port 443 publicly. This is the current best practice (2025).

5. **DNS for internal resources requires explicit configuration.** Enable "VPN Client DNS Mapping" and push the VPC DNS resolver IP. The `pritunl-dns` proxy handles resolution transparently for all clients.

6. **OpenVPN to Pritunl migration is parallel, not in-place.** Users must be recreated; no profile import tool exists. Both systems run simultaneously during transition.

7. **Consolidating multiple Pritunl instances** is the primary architectural advantage of Pritunl — shared MongoDB enables a single logical cluster managing multiple physical nodes and multiple VPN servers with replication/failover.

### What Remains Uncertain

- Whether the `oozou` module is actively maintained (v0.0.0 tag is a concern — could indicate pre-release versioning or stalled development)
- The exact production-readiness of the `disc/pritunl` Terraform provider for managing a full user base via Terraform state
- Performance and cost comparison between local MongoDB vs MongoDB Atlas vs AWS DocumentDB for Pritunl's backend

---

## Discovery — Existing Pritunl Instances (2026-02-26)

Phase 0 discovery completed. Both Pritunl instances were accessed via temporary SSH/HTTPS rules on security groups.

### Instances Found

4 VPN instances total across 2 regions:

| Instance | Region | VPC | Public IP | Type | Purpose |
|----------|--------|-----|-----------|------|---------|
| `ovpn-connector-1-OLD` | sa-east-1 | Management (10.255.0.0/16) | 18.230.152.167 | t3.small | OpenVPN (paid) |
| `VPN-Pritunl-management` | sa-east-1 | Management (10.255.0.0/16) | 54.94.130.156 | t3a.micro | Pritunl (management) |
| `production-vpn` | us-east-1 | Production (10.254.0.0/16) | 52.71.109.191 | t3a.micro | Pritunl (production) |
| `pritunl-beta-app0001` | us-east-1 | Beta (10.154.0.0/16) | 54.205.27.81 | t3a.micro | Pritunl (beta) |

### Production VPN Config (`production-vpn`)

| Param | Value |
|-------|-------|
| **Pritunl version** | v1.32.4278.46 |
| **OS** | Ubuntu 24.04.2 LTS |
| **MongoDB** | 6.0.25 (local, localhost:27017) |
| **Key Pair** | `4Shark-prd` |
| **Server name** | 4Shark-prd |
| **Organization** | 4Shark-prd |
| **Port** | 18428/udp |
| **Virtual Network** | 192.168.220.0/24 (253 users) |
| **Routes** | 192.168.220.0/24 (virtual), 10.254.0.0/16 (VPC) |
| **DNS Server** | 8.8.8.8 |
| **DNS Search Domain** | (empty) |
| **Cipher** | AES 128bit GCM |
| **Hash** | SHA-1 |
| **DH Param** | 2048 |
| **Ping Interval/Timeout** | 10 / 60 |
| **Max Clients** | 2000 |
| **Restrict Routing** | On |
| **Inter-Client Routing** | On |
| **Block Outside DNS** | On |
| **WireGuard** | Off |
| **Google Auth** | Off |
| **Multiple Devices** | Off |
| **Uptime** | 168 days |
| **Users** | 2/7 online |

**Instance resources:**
- RAM: 918MB total (t3a.micro)
- Disk: 6.8GB total, 5.5GB used (83% — critical)
- CPU: 2 vCPU (AMD EPYC 7571)
- MongoDB data: 5MB total (42 collections, ~16k objects)
- IP forwarding: enabled
- SSM Agent: installed and running (snap) but **no IAM Instance Profile** — cannot register

**NAT/Routing:**
- SourceDestCheck: true
- iptables MASQUERADE rules: VPN clients (192.168.220.0/24) NATed to instance IP for both 8.8.8.8 and 10.254.0.0/16
- VPN works because of NAT — SourceDestCheck doesn't block

### Beta VPN Config (`pritunl-beta-app0001`)

| Param | Value |
|-------|-------|
| **Pritunl version** | v1.32.4400.99 |
| **OS** | Ubuntu 24.04 LTS |
| **MongoDB** | local (localhost:27017) |
| **Key Pair** | `4Shark-prd` |
| **Server name** | server-beta |
| **Organization** | betaapp |
| **Port** | 19517/udp |
| **Virtual Network** | 192.168.248.0/24 |
| **Routes** | 192.168.248.0/24 (virtual), 10.154.0.0/16 (VPC) |
| **DNS Server** | 8.8.8.8 |
| **Block Outside DNS** | Off |
| All other settings | Same as production |

**Key difference from production:** Block Outside DNS = Off.

### Common Problems Found

1. **DNS = 8.8.8.8** — does not resolve `*.4shark.internal`. Should use VPC DNS resolver (e.g., `10.255.0.2`)
2. **No DNS Search Domain** — clients can't resolve short hostnames
3. **No IAM Instance Profile** — SSM Agent installed but can't register. No maintenance access without opening SSH
4. **Disk at 83%** — only 1.2GB free on 6.8GB disk. Logs will fill it
5. **MongoDB local with no backup** — if instance dies, config is lost
6. **Beta VPC completely isolated** — no VPC peering at all
7. **Routes limited to own VPC** — each VPN only reaches its own VPC network

### Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| MongoDB backend | Local (same instance) | DB is only 5MB; DocumentDB minimum is ~$56/mo; Atlas M2 ($9/mo) has no VPC peering |
| Disk size | 20GB gp3 | Current 6.8GB is at 83%; 20GB gives room for logs and growth |
| Log rotation | Ansible role | Prevent disk from filling up |
| Users to create | 3 | paulo.ribeiro@4shark.com.br, elisio.filho@4shark.com.br, emerson.silva@4shark.com.br |
| User migration | Recreate from scratch | No import needed, only 3 users |

## Next Steps

Decisions already made:

**Decision 1 — Infrastructure approach:** B) Custom Terraform module (Terraform for infra + Ansible for app)

**Decision 2 — Configuration management:** B) Web UI for now, Terraform provider later

PLAN.md and TASKS.md created at `~/.claude/plans/active/terraform/standardize-vpn/`.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
