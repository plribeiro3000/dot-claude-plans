# SPIKE: New EC2 Instances for Integrator Atento BR via Terraform

## Question

Is it possible to spin up new EC2 instances for the integrator atento-br environment using Terraform for infrastructure + Ansible for provisioning, following the same patterns already established?

## Context

- The integrator atento-br VPN will serve multiple countries (BR, Mexico, Colombia, Chile)
- Need to add 2 new app servers immediately (test with 1 first)
- DNS must be configured via the centralized dns/ stack
- Ansible playbook `provision-integrator-server.yml` handles software installation
- The VPN name stays "atento-br" for now, but it's shared across countries

## Answer: YES — Fully Viable

Everything needed is already in place. Adding new EC2 instances requires changes in **3 stacks** (2 mandatory, 1 recommended):

## Evidence

### 1. Terraform — Integrator Stack (MANDATORY)

**File**: `integrator-atento-br/main.tf`

The module uses `app_servers` as a map with `for_each`. Adding a new server is just adding an entry:

```hcl
# Current state (1 server):
app_servers = {
  "app002" = { instance_type = "t3.medium", subnet_key = "prv-a" }
}

# Target state (3 servers):
app_servers = {
  "app002" = { instance_type = "t3.medium", subnet_key = "prv-a" }
  "app003" = { instance_type = "t3.medium", subnet_key = "prv-b" }
  "app004" = { instance_type = "t3.medium", subnet_key = "prv-a" }
}
```

This creates EC2 instances named `4client-atento-br-app003` and `4client-atento-br-app004` with:
- Tags: `Automation=ansible`, `Role=application`, `Type=ruby`
- Key pair: `kp-4shark`
- Security group: default SG (allows VPC internal + management VPN)
- AMI: `ami-0bd91caaa9bc42cf3` (Ubuntu)
- 40GB gp2 root volume
- Termination protection enabled

**No changes needed** in the integrator module itself — the `for_each` pattern handles N servers.

### 2. DNS Stack (MANDATORY)

**File**: `dns/internal_dns_integrator.tf`

DNS records are NOT created by the integrator module — they live in the centralized dns/ stack. Each new server needs:

1. A `data "aws_instance"` to look up the EC2 by tag Name
2. An `aws_route53_record` (A record) pointing to the private IP

```hcl
# Data source
data "aws_instance" "atento_app003" {
  filter {
    name   = "tag:Name"
    values = ["4client-atento-br-app003"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

# DNS record
resource "aws_route53_record" "atento_app003" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "4client-atento-br-app003.${local.internal_zone_name}"
  type    = "A"
  ttl     = 60
  records = [data.aws_instance.atento_app003.private_ip]
}
```

**Important**: The DNS stack must be applied AFTER the integrator stack (EC2 must exist for the data source to find it).

### 3. Networking (NO CHANGES NEEDED)

**File**: `networking/vpc_atento_br.tf`

The VPC `10.12.255.0/24` has plenty of IP space:
- `prv-a`: `10.12.255.128/26` — 62 usable IPs (currently ~5 used: 3 MongoDB + 1 app + overhead)
- `prv-b`: `10.12.255.192/26` — 62 usable IPs (currently ~1 used: 1 MongoDB)

Adding 2 more servers is trivially within capacity.

Peering to management VPC is already configured. Security groups already allow all traffic within VPC + from management VPN SGs.

### 4. Ansible Provisioning (READY)

**File**: `ansible/playbooks/provision-integrator-server.yml`

After Terraform creates the EC2, run:

```bash
cd /path/to/ansible

# Provision the new server (use the private IP from terraform output)
./run_playbook.sh 4shark playbooks/provision-integrator-server.yml \
  target_host=<PRIVATE_IP> \
  client_name=atento-br \
  server_role=web \
  ruby_version=3.4.1
```

Note: The `vars/integrator/atento-br.yml` file needs to exist with client-specific vars (Datadog API key, `aws_internal_zone`, etc.). Currently the directory only has `.gitkeep` — the file is likely gitignored or needs to be created.

## Deployment Order

```
1. terraform apply (integrator-atento-br)  → Creates EC2 instances
2. terraform apply (dns)                   → Creates DNS A records
3. ansible provision-integrator-server     → Installs Ruby, packages, users
4. deploy application                      → Standard deploy pipeline
```

## Naming Convention for Multi-Country

Current: `4client-atento-br-app002` (Brazil)

For future countries within the same VPN, two options:

**Option A — Suffix per country** (recommended):
- `4client-atento-br-app002` (existing BR)
- `4client-atento-mx-app001` (Mexico)
- `4client-atento-co-app001` (Colombia)
- `4client-atento-cl-app001` (Chile)

This would mean separate integrator stacks (e.g., `integrator-atento-mx/`) sharing the same VPN/VPC, or new VPCs per country.

**Option B — Sequential numbering in same stack**:
- `4client-atento-br-app002` (BR)
- `4client-atento-br-app003` (MX)
- `4client-atento-br-app004` (CO)

Simpler, but the naming doesn't reflect which country each server serves.

**Decision needed from engineer** before scaling to multiple countries.

## Risks and Considerations

1. **Apply order matters**: DNS data sources fail if EC2 doesn't exist yet. Apply integrator stack first, then dns stack.
2. **Ansible vars file**: `playbooks/vars/integrator/atento-br.yml` appears to be gitignored or missing. Need to verify it exists or create it before running the playbook.
3. **Termination protection**: Enabled by default — intentional, prevents accidental deletion.
4. **VPN routing**: New app servers will automatically be accessible via the site-to-site VPN (same VPC/SG as existing app002).
5. **Route53 zone association**: Already done by the integrator module (`dns.tf`) — no additional config needed.

## Conclusion

The infrastructure is fully ready. For the first test machine:
- **1 line added** to `integrator-atento-br/main.tf` (new entry in `app_servers`)
- **~15 lines added** to `dns/internal_dns_integrator.tf` (data source + record)
- **1 Ansible command** to provision the server
- **Zero networking changes**
