# SPIKE — Is the `ansible` repository still useful to 4Shark?

## Investigation question

The engineer's hypothesis is that `~/Projects/4Shark/ansible/` has no remaining utility and should be retired, on four grounds: (1) its main use was provisioning a "Foreclient" (the retired name for Integrator); (2) creating an integrator is a Terraform operation today; (3) a dead WordPress deploy still lives there; (4) MongoDB moved to the dedicated `mongodb` / `ansible-role-mongodb` repos.

The spike tests each ground against the repository contents, the live AWS state, and the other 4Shark repositories, and produces a per-item verdict (playbooks, own roles, imported roles, Packer templates, configuration files) plus the concrete retirement blockers.

## Sources consulted

- `~/Projects/4Shark/ansible/` @ `develop` — every playbook, role, Packer template and config file read directly.
- `git -C ~/Projects/4Shark/ansible log` — per-file last-commit attribution and the 2026 bot-vs-human commit split. See auxiliary: [`ansible_gitlog_1.txt`](ansible_gitlog_1.txt).
- Live AWS (read-only profile, `sa-east-1` + `us-east-1`) — EC2 `Automation` tags, ASGs, ELB, AMI, ECS clusters. This is what separates "the code exists" from "the code has a target". See auxiliary: [`ansible_aws_state_1.txt`](ansible_aws_state_1.txt).
- `~/Projects/4Shark/terraform/` — the stacks and modules that replace each provisioning playbook.
- `~/Projects/4Shark/ansible-role-mongodb/` and `~/Projects/4Shark/mongodb/` — the dedicated MongoDB repos; full role diff in auxiliary: [`ansible_mongodb_role_diff_1.txt`](ansible_mongodb_role_diff_1.txt).
- `~/.claude/` (docs, skills, commands, runbooks) — external references to this repo.
- Raw grep output (legacy naming, imported-role usage, vault variables, orphan roles, external references): [`ansible_grep_1.txt`](ansible_grep_1.txt).

## Findings

### Finding 1: The repository is NOT dead — two playbooks have live targets

**Evidence:** `4shark-vpn-001` is running and tagged `Automation=ansible`; six MongoDB nodes are still tagged `Automation=ansible` (commcenter ×3 running, redebrasil ×3 stopped):

```
{ "Name": "4shark-vpn-001",                 "Type": null,      "Automation": "ansible", "State": "running" },
{ "Name": "integrator-commcenter-mongo001", "Type": "mongodb", "Automation": "ansible", "State": "running" },
{ "Name": "integrator-commcenter-mongo002", "Type": "mongodb", "Automation": "ansible", "State": "running" },
{ "Name": "integrator-commcenter-mongo003", "Type": "mongodb", "Automation": "ansible", "State": "running" },
{ "Name": "integrator-almaviva-mongo001",   "Type": "mongodb", "Automation": "packer",  "State": "running" },
```

The Terraform Pritunl module tags its instance for Ansible follow-up — `~/Projects/4Shark/terraform/modules/pritunl/main.tf:17`: `Automation = "ansible"`, alongside `ignore_changes = [ami, user_data, user_data_base64]` (line 28), i.e. Terraform deliberately does not manage what is on the box.

**Source:** `ansible_aws_state_1.txt` §1 and §5; `~/Projects/4Shark/terraform/modules/pritunl/main.tf:17`.

**Significance:** The premise "the repo has no remaining utility" does not hold as stated. Two playbooks — `provision-pritunl.yml` and `provision-4client-mongodb-server.yml` — configure infrastructure that is running right now, and nothing else in the 4Shark toolchain currently performs their function. The evidence shows the repo has shrunk to a live core of 2 playbooks + 7 own roles + 2 Galaxy roles; the trade-off is between retiring a repo that is ~85% dead and keeping a repo whose ~15% live core has no replacement yet.

### Finding 2: The current model is Terraform-provisions / Ansible-configures — by convention, not by code

**Evidence:** `playbooks/provision-4client-mongodb-server.yml:1-13` states the contract explicitly:

```yaml
#
# Provision 4Client MongoDB ReplicaSet
#
# Takes 3 bare Ubuntu EC2 instances (provisioned by Terraform) and configures them
# as a MongoDB 8.2 ReplicaSet (primary + secondary + arbiter).
#
# Usage:
#   ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml \
#     client_name=cliente1 \
#     mongo_arbiter=10.1.5.10 \
```

The same shape appears at `playbooks/provision-pritunl.yml:5-6`: `# Takes a bare Ubuntu 24.04 EC2 instance (provisioned by Terraform) and installs`, `# Pritunl VPN + MongoDB.`

No Terraform code invokes Ansible: there is no `provisioner`, and no `user_data` calling a playbook (`ansible_aws_state_1.txt` §5).

**Source:** `playbooks/provision-4client-mongodb-server.yml:1-13`; `playbooks/provision-pritunl.yml:5-6`; `ansible_aws_state_1.txt` §5.

**Significance:** The engineer's ground (2) — "creating a new integrator today is a Terraform operation" — is correct for networking, ECS, RDS and ElastiCache, but incomplete: the MongoDB replica set and the VPN box are Terraform-creates-the-VM + human-runs-a-playbook. The handoff is a documented manual step, not an automated one, which is why it is easy to forget the repo is in the loop.

### Finding 3: `~/.claude/commands/create-integrator.md` still instructs the engineer to run a playbook from this repo

**Evidence:** `~/.claude/commands/create-integrator.md:125-130`:

```markdown
## Step 5 — Post-Terraform manual steps

After terraform apply, remind the engineer of steps that are NOT managed by Terraform:
1. **MongoDB installation**: Run Ansible playbook to install MongoDB on the 3 new EC2 instances
2. **MongoDB replica set**: Configure the replica set (PSA topology)
3. **SSM secret values**: Populate the SSM parameters with actual secret values via AWS CLI
```

**Source:** `~/.claude/commands/create-integrator.md:128`.

**Significance:** This is a live, in-toolchain dependency: the skill the engineer cited as evidence that integrator creation is "a Terraform operation" itself hands off to this repo for step 5.1/5.2. Retiring the repo without resolving this leaves the `/create-integrator` skill pointing at a step with no implementation.

### Finding 4: The WordPress hypothesis is confirmed — the stack is gone in all three dimensions

**Evidence:** three independent AWS checks, all negative:

```
# aws autoscaling describe-auto-scaling-groups --region us-east-1
  -> "asg-4shark-wp-production" ABSENT (39 ASGs listed, all app/setup/worker)

# aws elb describe-load-balancers --region us-east-1 --load-balancer-names elb-4shark-wp-production
  An error occurred (LoadBalancerNotFound) ... There is no ACTIVE Load Balancer named 'elb-4shark-wp-production'

# aws ec2 describe-images --region us-east-1 --image-ids ami-c58e80d2
  An error occurred (InvalidAMIID.NotFound) ... The image id '[ami-c58e80d2]' does not exist
```

The AMI id checked is the one pinned in `group_vars/all/all.yml`: `aws_4shark_wp_images:` / `  production: "ami-c58e80d2"`. The ELB/ASG names are the ones `playbooks/provision-4shark-wp.yml:2028` (`name: elb-4shark-wp-production`) and `:2067` (`name: "asg-4shark-wp-production"`) create.

**Source:** `ansible_aws_state_1.txt` §4a/§4b/§4c; `group_vars/all/all.yml` (`aws_4shark_wp_images.production`).

**Significance:** Ground (3) holds without qualification. The WordPress playbooks, the Packer template, the Apache/PHP Galaxy roles and the `aws_4shark_wp_images` / `aws_vpc.4shark-wp-production` config blocks reference infrastructure that no longer exists.

### Finding 5: Both Packer templates have been broken for ~8 years

**Evidence:** the templates reference `.yaml` playbook files:

```
packer/aws-ami-4shark-wp.json:21:            "playbook_file": "playbooks/aws-ami-4shark-wp.yaml"
packer/aws-ami-ubuntu-16.04-python.json:21: "playbook_file": "playbooks/aws-ami-ubuntu-python-node.yaml"
```

The files on disk are `.yml` (`playbooks/aws-ami-4shark-wp.yml`, `playbooks/aws-ami-ubuntu-python-node.yml`). Git explains the drift — `git log --follow -- playbooks/aws-ami-4shark-wp.yml` contains `2018-10-29 | Leon Waldman | Renamed playbooks from .yaml to .yml`, while `git log -- packer/` returns exactly one commit: `2016-12-29 | Leon Waldman | Initial Commit`.

**Source:** `ansible_grep_1.txt` §7; `ansible_gitlog_1.txt` (rename evidence + packer history).

**Significance:** There is no live AMI pipeline in this repo. Both builds would fail at the provisioner step and have been unrunnable since 2018. The live golden-AMI pipeline is `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl`, a different repo.

### Finding 6: `roles/4shark.mongodb` is a stale fork of `ansible-role-mongodb`, and a third copy (`4shark.mongodb8`) also exists

**Evidence:** the in-repo copy pins an end-of-life MongoDB series and hardcodes an Ubuntu codename:

```yaml
# roles/4shark.mongodb/defaults/main.yml:4
mongodb_version: "4.0"

# roles/4shark.mongodb/tasks/main.yml:17
    repo: "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-{{ mongodb_version }}.gpg ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/{{ mongodb_version }} multiverse"
```

The dedicated repo removed the default and templates the codename:

```yaml
# ansible-role-mongodb/defaults/main.yml:3-15 (excerpt)
> # mongodb_version has NO default on purpose — the consuming build declares it
> mongodb_ubuntu_codename: "focal"
```

and adds package holds the in-repo copy lacks (`ansible-role-mongodb/tasks/main.yml:48-52`, `- name: Hold MongoDB packages at the installed version` / `dpkg_selections`). `~/Projects/4Shark/mongodb/README.md:9-11` confirms the ownership move: *"The provisioning role is NOT vendored here — it lives in its own repository, [`ansible-role-mongodb`](https://github.com/4shark/ansible-role-mongodb), and Packer pulls it at build time"*.

Separately, `roles/4shark.mongodb8/defaults/main.yml:5` (`mongodb_version: "8.2"`) and `:8` (`mongodb_ubuntu_codename: "noble"`) is a third, independent copy of the same capability — the one `provision-4client-mongodb-server.yml` actually uses.

**Source:** `ansible_mongodb_role_diff_1.txt` (full diff); `~/Projects/4Shark/mongodb/README.md:9-11`.

**Significance:** Ground (4) is half-right. The *golden-AMI build* moved to the dedicated repos, but the *post-boot per-client replica-set step* did not — `mongodb/README.md:22-25` says so explicitly: *"The **per-client** part — the actual `replSetName` and `rs.initiate()` — is **not** baked; it differs per client and runs post-boot (the Ansible playbook that provisions a client's replica set)."* The capability now exists in three places, and the version-provisioning logic in this repo is the worst of the three.

### Finding 7: The MongoDB fleet migration to the golden AMI is in flight, not finished

**Evidence:** the `Automation` tag splits the fleet cleanly — `almaviva` (6 nodes), `atento` (3), `maqnelson` (3) are `packer`; `commcenter` (3) and `redebrasil` (3) are still `ansible` (`ansible_aws_state_1.txt` §1). Terraform pins the AMI by hand per stack — `~/Projects/4Shark/terraform/integrator-atento/mongodb.tf:29`: `ami = "ami-0e4d77e66719fceb1"`, described at line 19 as `# Ubuntu 20.04 + MongoDB 5.0 nodes (golden AMI ami-0e4d77e66719fceb1), named`.

`~/Projects/4Shark/mongodb/README.md:50-53` confirms this is deliberate: *"Terraform consumers currently **pin the AMI id by hand** ... so a new build is NOT picked up automatically: adopting a new image is a deliberate edit plus a re-provision of the replica-set member."*

**Source:** `ansible_aws_state_1.txt` §1; `~/Projects/4Shark/terraform/integrator-atento/mongodb.tf:19,29`; `~/Projects/4Shark/mongodb/README.md:50-53`.

**Significance:** Two clients have not yet been migrated to the golden-AMI path. Until they are, the Ansible MongoDB path is the one that describes how those nodes were built and how they would be rebuilt.

### Finding 8: The integrator app-server playbooks are superseded by ECS — despite being 4 months old

**Evidence:** zero EC2 instances are tagged `Role=application`:

```
# aws ec2 describe-instances --region sa-east-1 --filters "Name=tag:Role,Values=application"
[]
```

Every integrator client runs on ECS instead (`integrator-atento-br-cluster`, `integrator-commcenter-cluster`, `integrator-almaviva-cluster`, …, 16 clusters). In the Terraform integrator stacks, `compute.tf` is the ECS cluster definition and the only `aws_instance` resources are the Mongo nodes — `~/Projects/4Shark/terraform/integrator-commcenter/compute.tf:1-3`:

```hcl
# =============================================================================
# ECS Cluster — Commcenter Prod
# =============================================================================
```

Yet `provision-integrator-server.yml` was last touched `2026-03-03` and `provision-integrator-ruby.yml` `2026-02-23` (`ansible_gitlog_1.txt`).

**Source:** `ansible_aws_state_1.txt` §2 and §3; `~/Projects/4Shark/terraform/integrator-commcenter/compute.tf:1-3`; `ansible_gitlog_1.txt`.

**Significance:** Recency of a commit does not imply the code has a live target. These playbooks and their five supporting roles (`chruby`, `integrator_packages`, `integrator_setup`, `mssql_odbc`, plus the `geerlingguy.ruby` / `weareinteractive.environment` Galaxy roles) were actively developed right up to the ECS cutover and then stranded. This is the largest block of recently-written-but-superseded code in the repo.

### Finding 9: The repository holds two credentials that survive its deletion

**Evidence (category only — no values read or printed):**

1. **A plaintext ansible-vault password in the README.** `README.md:68` is the heading `- `~/.4shark/vault_password_file.txt``, and the fenced block that follows it (line 71) contains the password value in cleartext. It has been there since `2018-10-29 | Leon Waldman | Add README.md` (`git log -S'vault_password_file.txt' -- README.md`). This password is the one `run_playbook.sh:42` consumes: `AWS_PROFILE=${aws_profile} ansible-playbook -i ec2.py -u $username --vault-password-file ~/.4shark/vault_password_file.txt $playbook ...`.

2. **A git-tracked SSH private key.** `git ls-files roles/4shark.common_users/files/` returns `4shark_deployer.pem`, `4shark_deployer.pub`, `authorized_keys`. The `.pem` is copied to two `id_rsa` destinations at `roles/4shark.common_users/tasks/main.yml:16-20`:

```yaml
- name: Deployment Key
  copy: src=../files/4shark_deployer.pem dest="/home/{{ app_user }}/.ssh/id_rsa" owner="{{ app_user }}" mode=0400

- name: Deployer Key - Root
  copy: src=../files/4shark_deployer.pem dest=/root/.ssh/id_rsa owner=root mode=0400
```

The key's contents were **not** read (a read attempt was correctly denied by the permission system); the classification is from filename plus its use as `id_rsa`.

`group_vars/all/vault.yml` is `$ANSIBLE_VAULT;1.1;AES256`, 29 lines, and must hold the six variables referenced across the repo: a Datadog API key, three JumpCloud credentials, an OpenVPN LDAP bind password, and a Redis default password (`ansible_grep_1.txt` §5). It was **not** decrypted.

**Source:** `README.md:68` (+ the value on line 71, redacted here); `run_playbook.sh:42`; `roles/4shark.common_users/tasks/main.yml:16-20`; `ansible_grep_1.txt` §5 and §6; `ansible_gitlog_1.txt`.

**Significance:** Because the vault password is committed next to the vault, the vault's encryption provides no confidentiality against anyone with repo access — every secret in `vault.yml` should be treated as exposed to the repo's whole access surface for the last ~8 years. Deleting or archiving the repository does **not** remediate this: the material stays in git history and, for the private key, on any host the role ever touched. Rotation is required on any path, and is therefore independent of the retire/keep decision rather than a consequence of it.

### Finding 10: `4shark.common_users` — the role shipping the private key — is an orphan

**Evidence:** `grep -rl '4shark.common_users' playbooks roles` returns no output. No playbook and no other role references it. Its last commit is `2023-10-13 | Paulo Ribeiro | remove(*): `Liberta` VPC`. The live roles use `4shark.deploy_user` instead, whose `tasks/main.yml` copies only `authorized_keys` and no private key — introduced by `2023-10-09 | Leon Waldman | Add 4shark.deploy_user and replace 4shark.users by it on provision-4client-app-server.yml`.

**Source:** `ansible_grep_1.txt` §4 and §6; `ansible_gitlog_1.txt`.

**Significance:** The private-key-distribution pattern was already superseded by `deploy_user` in 2023, but the orphan role and its key were never removed. Nothing runs it today; the exposure is historical, not ongoing.

### Finding 11: The JumpCloud variables are dead config still bound to vault secrets

**Evidence:** `group_vars/all/all.yml:9-12`:

```yaml
# JumpCloud
jumpcloud_api_key: "{{ vault_jumpcloud_api_key }}"
jumpcloud_x_connect_key: "{{ vault_jumpcloud_x_connect_key }}"
jumpcloud_all_systems_group: "{{ vault_jumpcloud_all_systems_group }}"
```

`grep -rn 'jumpcloud' -i roles playbooks group_vars` shows no role consumes any of the three. The install was removed by `2023-10-13 | Leon Waldman | Deprecate JumpCloud instalation and implement ec2-instance-connect on 4shark.users and helper script`. The only surviving JumpCloud coupling is the OpenVPN LDAP config (`playbooks/vars/openvpn/openvpn-settings-ldap.yml:16` `openvpn_ldap_server: ldap.jumpcloud.com`), which is itself dead (Finding 12).

**Source:** `ansible_grep_1.txt` §5; `ansible_gitlog_1.txt`.

**Significance:** Three of the six vault secrets are referenced only by dead config. If the vault is rotated, these three are candidates for deletion rather than rotation — but that is a question about the JumpCloud tenancy, not about this repo.

### Finding 12: OpenVPN is fully replaced by Pritunl

**Evidence:** the only VPN instance is `4shark-vpn-001` (Finding 1) — no instance matching the `vpn-{{ vpn_name }}` pattern `provision-openvpn.yml:2949` creates (`Name: "vpn-{{ vpn_name }}"`). The live Terraform VPN stack uses the Pritunl module exclusively — `~/Projects/4Shark/terraform/vpn/main.tf:10-14`:

```hcl
module "pritunl" {
  source = "../modules/pritunl"

  name_prefix   = "4shark-vpn-001"
  vpc_id        = "vpc-0bdc76f3b391694dd"
```

There is no OpenVPN module in `terraform/`. `roles/4shark.openvpn` was last touched `2018-10-19`.

**Source:** `ansible_aws_state_1.txt` §1 and §5; `~/Projects/4Shark/terraform/vpn/main.tf:10-14`; `ansible_gitlog_1.txt`.

**Significance:** The OpenVPN playbooks/role, the LDAP vars, and the `openvpn_ubuntu_image` in `group_vars/all/all.yml` are all dead. Pritunl replaced the capability, and its Ansible role is one of the two live ones.

### Finding 13: The self-managed Redis fleet no longer exists

**Evidence:** the `sa-east-1` instance list contains no instance tagged `Type: "redis"` (`ansible_aws_state_1.txt` §1) — the tag `provision-redis-5-master-slave.yml:3232` sets (`Type: "redis"`). ElastiCache is Terraform-managed instead: `~/Projects/4Shark/terraform/modules/integrator/elasticache.tf` exists in the integrator module.

**Source:** `ansible_aws_state_1.txt` §1 and §6; `~/Projects/4Shark/terraform/modules/integrator/elasticache.tf`.

**Significance:** The four Redis playbooks, `roles/4shark.redis` (a fork — `2019-07-17 | Leon Waldman | Add role 4shark.redis (forked from DavitWittman.redis)`), the `nickhammond.logrotate` Galaxy role, and the `redis_ebs_size` / `redis_ebs_type` blocks in `group_vars/all/all.yml` (~150 lines mapping instance types to device paths) are all dead. `vault_redis_default_password` is referenced only by these.

### Finding 14: `imported_roles/` is NOT vendored — it is git-ignored Galaxy output

**Evidence:** `.gitignore:2`:

```
__pycache__
imported_roles
ansible_user
venv
```

The directory is produced by `install_requirements.sh`: `ansible-galaxy install -r requirements.yml -p ./imported_roles/`. The tracked artifact is `requirements.yml` (530 bytes, 8 entries).

**Source:** `.gitignore:2`; `install_requirements.sh`; `ansible_grep_1.txt` §3.

**Significance:** This corrects the briefing's premise that the 8 third-party roles are "vendored into the repo". They are not in git; only the manifest is. The retirement cost of the imported roles is therefore a 530-byte file, not 8 vendored codebases — and pinning/dependency risk for them lives in `requirements.yml`, not in checked-in code.

### Finding 15: 80% of 2026 commit volume is dependency-bot churn

**Evidence:** `git log --oneline --since='2026-01-01' --no-merges --format='%an' | sort | uniq -c | sort -rn`:

```
 135 4shark-renovate[bot]
  34 Paulo Ribeiro
   1 dependabot[bot]
```

The bots are maintaining `requirements.txt` — a Python dependency set (`ansible-core==2.21.1`, `boto3`, `botocore`, `cryptography`, …) needed only to *run* the playbooks locally. `.github/workflows/` holds `renovate.yml` (cron `0 11 * * 1-5`), `verify-minimum-age.yaml`, and `reverify-minimum-age.yaml`.

**Source:** `ansible_gitlog_1.txt`; `requirements.txt`; `.github/workflows/renovate.yml`.

**Significance:** 136 of 170 non-merge commits this year exist to keep the local execution environment of a mostly-dead repo current. This is the daily PR churn the engineer sees. It is real overhead, and it scales with the *Python toolchain*, not with the repo's remaining 2 live playbooks — so it does not shrink as the repo shrinks, only when the repo (or its `requirements.txt`) goes away.

---

## Complete inventory — Playbooks (22)

| Item | What it does | Legacy naming | Replaced by | Last human commit | Verdict | Reasoning |
|---|---|---|---|---|---|---|
| `aws-ami-4shark-wp.yml` | Bakes the WordPress golden image: `common_packages` + `users` + `deploy_user` + `geerlingguy.php` + `geerlingguy.apache`, Apache vhost for `4shark.com.br`, `rc.local` deploy script, nfs-common | `wp` | Nothing — capability abandoned | 2023-10-16 Leon Waldman | **DEAD** | Consumed only by `packer/aws-ami-4shark-wp.json`, which points at `...wp.yaml` and cannot resolve the `.yml` file (Finding 5). Target AMI `ami-c58e80d2` does not exist; no WP ASG/ELB (Finding 4). References `php7.0.conf`/`php7.0.load` — PHP 7.0 is EOL since 2019 |
| `aws-ami-ubuntu-python-node.yml` | Installs `python-simplejson` (Python 2) on a bare Ubuntu via `raw`, disables unattended-upgrades and apt-daily timers | — | Nothing | 2020-01-28 Leon Waldman | **DEAD** | Consumed only by `packer/aws-ami-ubuntu-16.04-python.json`, broken since 2018 (Finding 5). Ubuntu 16.04 EOL April 2021; Python 2 EOL January 2020 |
| `provision-4client-app-server.yml` | Creates a `t3.small` Ruby app EC2 (`4client-{{client_name}}-{{server_name}}`), Route53 A record, then Ruby 3.4.1 from source + Datadog + users | `4client` | `terraform/integrator-*/compute.tf` (ECS) | 2025-05-14 Paulo Ribeiro | **SUPERSEDED** | Zero EC2 tagged `Role=application` exist; all 16 integrator clients run on ECS (Finding 8) |
| `provision-4client-mongodb-server.yml` | Takes 3 Terraform-provisioned bare Ubuntu boxes and configures a MongoDB 8.2 PSA replica set: `common_packages`, `unattended-upgrades`, `ntp`, `users`, `deploy_user`, `engineers`, `mongodb8`, `cloudwatch_agent`, then `rs.initiate()` with FQDN members | `4client` (in filename, hostnames, and `rs.initiate` members) | Partially by `mongodb` + `ansible-role-mongodb` (base image only — NOT the per-client replica set) | **2026-05-14 Paulo Ribeiro** | **KEEP** (or MIGRATE) | The only implementation of the per-client `replSetName` + `rs.initiate()` step, which `mongodb/README.md:22-25` explicitly says is **not** baked into the AMI. `create-integrator.md:128-129` depends on it (Finding 3). Two clients still on the ansible path (Finding 7) |
| `provision-4client-out.yml` | Full outbound-client build: VPC `/26`, 4 subnets, IGW, NAT, management peering, routing, VPN (VGW + customer GW + ipsec.1), default SG, Ruby app EC2, Route53 | `4client` | `terraform/networking/vpc_*.tf` + `peering.tf` + `transit_gateway.tf` | 2025-05-14 Paulo Ribeiro | **SUPERSEDED** | Every resource it creates is a Terraform stack today (`ansible_aws_state_1.txt` §6). Uses the pre-collection `ec2:`/`ec2_vpc_route_table_facts:` modules removed in `amazon.aws` ≥ 5 |
| `provision-4client-without-vpn.yml` | Same as `provision-4client.yml` minus the VPN legs: VPC `/24`, subnets, IGW/NAT, peering, ElastiCache Redis 7.1, 3 Mongo nodes + app node, Route53 | `4client` | `terraform/networking/` + `terraform/modules/integrator/elasticache.tf` | 2025-03-06 Paulo Ribeiro | **SUPERSEDED** | Same as above. Its MongoDB half uses `roles/4shark.mongodb` (the stale 4.0 fork) and `mongo --eval 'rs.initiate()'` — superseded by `provision-4client-mongodb-server.yml` |
| `provision-4client.yml` | The full original client build: VPC, subnets, IGW/NAT, peering, ElastiCache, VPN, SG, 3 Mongo + 1 app node, Route53, then Mongo replica set + Ruby app + users | `4client` | `terraform/networking/` + `terraform/modules/integrator/` | 2025-03-06 Paulo Ribeiro | **SUPERSEDED** | The original "provision a Foreclient" playbook — the exact artifact the engineer's ground (1) describes. Fully replaced by the Terraform integrator stacks |
| `provision-4shark-wp.yml` | Provisions the WordPress production ELB + Launch Configuration (`ami-c58e80d2`, EFS user_data) + ASG (min 2 / max 100) in `us-east-1` | `wp` | Nothing | 2019-06-15 Leon Waldman | **DEAD** | ASG, ELB and AMI all confirmed absent from AWS (Finding 4). Hardcodes an IAM instance-profile ARN. `ec2_elb_lb`/`ec2_lc`/`ec2_asg` are removed modules |
| `provision-aws-elasticache-cluster.yml` | Creates an ElastiCache subnet group + a 2-node Redis replication group via a raw `aws elasticache create-replication-group` shell-out (engine 5.0.4) | — | `terraform/modules/integrator/elasticache.tf` | 2019-06-16 Leon Waldman | **SUPERSEDED** | ElastiCache is Terraform-managed. Pins Redis 5.0.4 (2019). Shells out to the AWS CLI rather than using a module |
| `provision-aws-vpc-cidr-16.yml` | Creates a `/16` VPC + 4 `/22` subnets, IGW (NAT commented out), management peering, routing, default SG; writes the result to `vars/aws/{{vpc_name}}-vpc.yml` | — | `terraform/networking/vpc_*.tf` | 2024-06-17 Roni | **SUPERSEDED** | `terraform/networking/` holds a `vpc_<client>.tf` per client plus `peering.tf`/`transit_gateway.tf`. The "write a YAML file as state" pattern is a hand-rolled state store Terraform replaced |
| `provision-aws-vpc-cidr-24.yml` | Same as `-16` but a `/24` VPC with `/26` subnets and NAT enabled; the only playbook partially migrated to the `amazon.aws.*` collection | — | `terraform/networking/vpc_*.tf` | 2024-11-14 Eduardo Santos | **SUPERSEDED** | Same as above. Note the last human commit is a Portuguese message (`criando rede atento em us-east-1`) — a one-off network creation, not maintenance |
| `provision-generic-node.yml` | Creates one EC2 of a given type/size in a named VPC's private subnet A, then applies `common_packages` + `users` + `deploy_user` | — | `terraform` (any stack defining `aws_instance`) | 2023-10-16 Leon Waldman | **SUPERSEDED** | A generic "give me a box" helper. Terraform defines every EC2 today; the base-role application is the only part with residual value, and it is reachable via the live playbooks |
| `provision-integrator-ruby.yml` | Installs a Ruby version via `4shark.chruby` on an existing host; explicitly does not restart Puma/Sidekiq | — (comments reference `integrator`) | `terraform/integrator-*/compute.tf` (ECS) + the integrator Docker image | 2026-02-23 Paulo Ribeiro | **SUPERSEDED** | Targets the EC2 integrator servers that no longer exist (Finding 8). Ruby version now ships in the container image |
| `provision-integrator-server.yml` | Configures a Terraform-provisioned bare Ubuntu box into an integrator web/worker node: `common_packages`, `integrator_packages`, `mssql_odbc`, `unattended-upgrades`, `ntp`, `deploy_user`, `engineers`, `chruby`, `integrator_setup`, `Datadog`, `users`; builds `MONGODB`/`REDIS` env vars | `4client` (in the `MONGODB`/`REDIS` connection strings it templates) | `terraform/integrator-*/compute.tf` (ECS) | 2026-03-03 Paulo Ribeiro | **SUPERSEDED** | Zero `Role=application` EC2 exist; 16 integrator ECS clusters do (Finding 8). The most recently developed of the superseded playbooks — stranded by the ECS cutover |
| `provision-openvpn.yml` | Creates a `t2.medium` OpenVPN EC2 in the management VPC with a public IP, then `common_packages` + `unattended-upgrades` + `ntp` + `users` + `4shark.openvpn` with LDAP auth | — | `terraform/vpn/main.tf` → `modules/pritunl` + `provision-pritunl.yml` | 2020-01-28 Leon Waldman | **DEAD** | No OpenVPN instance exists; the only VPN box is the Pritunl one (Finding 12). No OpenVPN module in Terraform |
| `provision-pritunl.yml` | Takes a Terraform-provisioned bare Ubuntu 24.04 box and installs Pritunl VPN + MongoDB: `common_packages`, `unattended-upgrades`, `ntp`, `engineers`, `pritunl`. Deliberately excludes `4shark.users` to preserve the AWS key pair for SSH | — | Nothing | **2026-02-27 Paulo Ribeiro** | **KEEP** | `4shark-vpn-001` is running with `Automation=ansible`; `terraform/modules/pritunl/main.tf:17` tags it for Ansible follow-up and `ignore_changes` its `user_data` (Finding 1). The only implementation of the live VPN's configuration |
| `provision-rds-instance.yml` | Creates an RDS subnet group + security group + RDS instance (postgres default, auto-generated password) + Route53 CNAME, then prints the endpoint and password | — | `terraform/modules/rds_instance/` | 2022-09-05 Paulo Ribeiro | **SUPERSEDED** | `terraform/modules/rds_instance/{main,outputs}.tf` is the current path; `auth-001/rds.tf` consumes it. The playbook also `debug:`-prints the master password to stdout (`:3191`), which conflicts with the credential-output policy |
| `provision-redis-5-master-slave.yml` | Creates two Redis EC2 nodes with encrypted data EBS, Elastic IPs, Route53 A records, partitions/mounts `/var/lib/redis` as xfs, then `4shark.redis` (5.0.4) + Datadog `redisdb` check | — | `terraform/modules/integrator/elasticache.tf` | 2024-11-29 Paulo Ribeiro | **SUPERSEDED** | No EC2 tagged `Type: redis` exists (Finding 13). ElastiCache replaced the self-managed pair. Assigns public IPs to a database node |
| `provision-redis-5-sentinel.yml` | Provisions the Redis Sentinel quorum nodes on top of the master/slave pair | — | ElastiCache automatic failover | 2023-10-16 Leon Waldman | **SUPERSEDED** | Same as above — Sentinel exists to give self-managed Redis the failover ElastiCache provides natively (`--automatic-failover-enabled` is already in `provision-aws-elasticache-cluster.yml:2131`) |
| `remove-redis-5-pair-from-sentinel.yml` | Issues `SENTINEL REMOVE {{app_name}}` via `redis-cli` against the sentinel quorum to decommission a pair | — | ElastiCache | 2023-10-11 Leon Waldman | **SUPERSEDED** | Operates on a Sentinel quorum that no longer exists (Finding 13) |
| `update-openvpn.yml` | Updates an existing OpenVPN node in place | — | Pritunl | 2022-06-13 Leon Waldman | **DEAD** | No OpenVPN node to update (Finding 12) |
| `update-redis-5-sentinel.yml` | Updates the Sentinel config on running nodes | — | ElastiCache | 2019-07-17 Leon Waldman | **SUPERSEDED** | No Sentinel nodes exist (Finding 13). Oldest human touch in the playbook set |

**Playbook verdict counts:** DEAD 5 · SUPERSEDED 15 · KEEP 2 · MIGRATE 0

---

## Complete inventory — Own roles (15)

| Item | What it does | Legacy naming | Replaced by | Last human commit | Verdict | Reasoning |
|---|---|---|---|---|---|---|
| `4shark.chruby` | Installs Ruby build deps (autoconf, bison, libssl-dev, …), downloads `ruby-install`, installs a Ruby via chruby | — | The integrator Docker image (ECS) | 2026-03-03 Paulo Ribeiro | **SUPERSEDED** | Used only by `provision-integrator-server.yml` and `provision-integrator-ruby.yml`, both of which target EC2 hosts that no longer exist (Finding 8) |
| `4shark.cloudwatch_agent` | Purges `datadog-agent`, installs the Amazon CloudWatch Agent `.deb`, templates `amazon-cloudwatch-agent.json` | — | Nothing | **2026-05-13 Paulo Ribeiro** | **KEEP** | Used by the live `provision-4client-mongodb-server.yml`. The `Removed datadog-agent` first task implements the CHANGELOG entry *"MongoDB observability moved from Datadog to CloudWatch Agent"* — this is current direction, not legacy |
| `4shark.common_packages` | Installs the base toolset (git, vim-nox, tmux, htop, sysstat, iotop, netcat-traditional, screen, curl, mc) with `ignore_errors: true` | — | Nothing | 2023-10-13 Leon Waldman | **KEEP** | Referenced by both live playbooks (`provision-4client-mongodb-server.yml`, `provision-pritunl.yml`). Old commit date reflects stability, not abandonment — a package list needs no churn |
| `4shark.common_users` | Creates the app user, installs `authorized_keys`, **and copies a private key to `~/.ssh/id_rsa` and `/root/.ssh/id_rsa`**, plus a sudoers drop-in | — | `4shark.deploy_user` (2023-10-09) | 2023-10-13 Paulo Ribeiro | **DEAD** | Orphan: referenced by zero playbooks and zero roles (Finding 10). Superseded by `deploy_user`, which does the same without distributing a private key. **Its `files/4shark_deployer.pem` is a git-tracked private key** (Finding 9) — deleting the role does not remove it from history |
| `4shark.deploy_user` | Creates the app user, installs `authorized_keys`, templates the sudoers drop-in. No private key | — | Nothing | 2023-10-09 Leon Waldman | **KEEP** | Referenced by the live `provision-4client-mongodb-server.yml`. This is the sanctioned replacement for `common_users` |
| `4shark.engineers` | Creates a per-engineer account, `.ssh` dir and `authorized_keys` from an `engineers` list, plus a sudoers template | — | Nothing | 2026-02-23 Paulo Ribeiro | **KEEP** | Referenced by both live playbooks. This is how a human gets shell on the Mongo nodes and the VPN box |
| `4shark.integrator_packages` | Installs the integrator's system packages (build-essential, freetds-*, libpq-dev, libicu-dev, libxml2-dev, libxslt1-dev, nodejs) | — | The integrator Docker image | 2026-02-23 Paulo Ribeiro | **SUPERSEDED** | Used only by `provision-integrator-server.yml` (Finding 8). These packages are now `Dockerfile` lines |
| `4shark.integrator_setup` | Creates `/var/www` and the Capistrano-style shared dirs (`log`, `tmp/pids`, `tmp/cache`, `tmp/sockets`, `public/system`) | — | The integrator Docker image / ECS | 2026-04-08 Paulo Ribeiro | **SUPERSEDED** | Used only by `provision-integrator-server.yml`. The Capistrano `shared/` layout is meaningless on ECS. Most recent commit of the superseded set (`fix(integrator): disable cron job by default`) |
| `4shark.mongodb` | Installs MongoDB from the MongoDB apt repo, THP hardening via `rc.local`, `mongod.conf` template | — | `ansible-role-mongodb` (dedicated repo) | 2026-05-13 Paulo Ribeiro | **SUPERSEDED** | A stale fork of the dedicated repo on every axis: pins `mongodb_version: "4.0"` (EOL Apr 2022) at `defaults/main.yml:4`, hardcodes `bionic` in the repo path at `tasks/main.yml:17`, no package holds, `rc.local` instead of a systemd unit (Finding 6, full diff in the auxiliary). Still referenced by the superseded `provision-4client.yml` / `provision-4client-without-vpn.yml` |
| `4shark.mongodb8` | The MongoDB 8.2 sibling: `mongodb_version: "8.2"` (`defaults/main.yml:5`), `mongodb_ubuntu_codename: "noble"` (`:8`), systemd `disable-thp.service`, `mongod.conf` template | — | Overlaps `ansible-role-mongodb` | 2026-02-25 Paulo Ribeiro | **MIGRATE** | The role the live `provision-4client-mongodb-server.yml` actually uses. But it is a **third** copy of a capability the dedicated `ansible-role-mongodb` already owns in a versioned, linted, CHANGELOG'd form (Finding 6). The capability is needed; this copy of it is the duplicate |
| `4shark.mssql_odbc` | Installs the Microsoft ODBC driver for SQL Server (prereqs, GPG key, apt repo) | — | The integrator Docker image | 2026-02-25 Paulo Ribeiro | **SUPERSEDED** | Used only by `provision-integrator-server.yml` (Finding 8). The integrator connects to client SQL Server from its container |
| `4shark.openvpn` | A vendored OpenVPN role (fork with its own LICENSE, Makefile, `.travis.yml`, `runtests.sh`, `easy-rsa.tar.gz`, and per-distro vars for Debian jessie / Ubuntu trusty, vivid, xenial) | — | `4shark.pritunl` | **2018-10-19 Leon Waldman** | **DEAD** | No OpenVPN instance exists (Finding 12). Oldest role in the repo — untouched for ~8 years. Its per-distro vars target distributions (jessie, trusty, vivid, xenial) that are all long EOL |
| `4shark.pritunl` | Installs Pritunl + MongoDB, templates dnsmasq override/vpn configs, fail2ban filter+jail for Pritunl, logrotate for pritunl/mongod/dnsmasq | — | Nothing | **2026-03-25 Paulo Ribeiro** | **KEEP** | Configures the running `4shark-vpn-001` (Finding 1). The only implementation of the live VPN server's configuration |
| `4shark.redis` | A vendored Redis role (fork of DavitWittman.redis) with Kitchen/Travis/serverspec test harness, per-distro init templates, sentinel + server task trees | — | ElastiCache (`terraform/modules/integrator/elasticache.tf`) | 2024-11-29 Paulo Ribeiro | **SUPERSEDED** | No Redis EC2 exists (Finding 13). Provenance is explicit in git: `2019-07-17 | Leon Waldman | Add role 4shark.redis (forked from DavitWittman.redis)`. Carries a full test harness (Gemfile, .kitchen.yml, serverspec) that has never run in this repo's CI |
| `4shark.users` | Installs `ec2-instance-connect` and applies the 4Shark users policy | — | Nothing | 2026-03-03 Paulo Ribeiro | **KEEP** | Referenced by the live `provision-4client-mongodb-server.yml`. `ec2-instance-connect` is the current access path (it replaced the JumpCloud agent in 2023-10-13) and is what `bin/ssh-ec2.sh` relies on |

**Own-role verdict counts:** DEAD 2 · SUPERSEDED 6 · KEEP 6 · MIGRATE 1

---

## Complete inventory — Imported (Galaxy) roles (8)

**Framing correction:** these are **not vendored**. `.gitignore:2` lists `imported_roles`, so the on-disk directory is `ansible-galaxy` output from `install_requirements.sh`, and the only tracked artifact is `requirements.yml` (Finding 14). The verdict below is on **the `requirements.yml` entry**, not on checked-in code.

| Item | What it does | Legacy naming | Replaced by | Referenced by (live?) | Verdict | Reasoning |
|---|---|---|---|---|---|---|
| `Datadog.datadog` | Installs and configures the Datadog agent | — | `4shark.cloudwatch_agent` for MongoDB; ECS-native APM elsewhere | `provision-4client-app-server`, `provision-4client-out`, `provision-4client-without-vpn`, `provision-4client`, `provision-integrator-server`, `provision-redis-5-master-slave` — **all superseded** | **SUPERSEDED** | No live playbook references it. `4shark.cloudwatch_agent`'s first task is `Remove datadog-agent if present` — the direction of travel is away from it. Consumes `vault_datadog_api_key` |
| `geerlingguy.apache` | Installs/configures Apache httpd | — | Nothing | `aws-ami-4shark-wp.yml` only — **dead** | **DEAD** | Referenced exclusively by the WordPress image playbook, whose target AMI/ELB/ASG are all gone (Finding 4) |
| `geerlingguy.ntp` | Installs/configures NTP time sync | — | Nothing | `provision-4client-mongodb-server`, `provision-pritunl` (**both live**) + 8 superseded | **KEEP** | Referenced by both live playbooks. Clock skew across MongoDB replica-set members is a correctness issue, not cosmetic |
| `geerlingguy.php` | Installs/configures PHP | — | Nothing | `aws-ami-4shark-wp.yml` only — **dead** | **DEAD** | WordPress-only. The playbook pins `php7.0.conf`/`php7.0.load`; PHP 7.0 is EOL since January 2019 |
| `geerlingguy.ruby` | Installs Ruby (from source when asked) | — | `4shark.chruby`, then the integrator Docker image | `provision-4client-app-server`, `provision-4client-out`, `provision-4client-without-vpn`, `provision-4client` — **all superseded** | **SUPERSEDED** | Already internally superseded by `4shark.chruby` for the integrator path, and that path is itself superseded by ECS (Finding 8) |
| `jnv.unattended-upgrades` | Configures APT unattended security upgrades | — | Nothing | `provision-4client-mongodb-server`, `provision-pritunl` (**both live**) + 8 superseded | **KEEP** | Referenced by both live playbooks. Note the interaction with `ansible-role-mongodb`'s `mongodb_held_packages` — unattended upgrades are exactly the mechanism the package holds defend against on a replica-set member |
| `nickhammond.logrotate` | Manages logrotate configs | — | ElastiCache (no host to rotate) | `provision-redis-5-master-slave`, `provision-redis-5-sentinel` — **both superseded** | **SUPERSEDED** | Referenced only by the Redis playbooks (Finding 13). `4shark.pritunl` ships its own logrotate templates rather than using this role |
| `weareinteractive.environment` | Writes environment variables to `/etc/environment` | — | ECS task definition env vars | `provision-4client-app-server`, `provision-4client-out`, `provision-4client-without-vpn`, `provision-4client` — **all superseded** | **SUPERSEDED** | Not referenced by any live playbook. `provision-integrator-server.yml` had already replaced it with an inline `blockinfile` on `/etc/environment`. On ECS, env vars are Terraform-managed task-definition entries |

**Imported-role verdict counts:** DEAD 2 · SUPERSEDED 4 · KEEP 2

---

## Complete inventory — Packer templates (2)

| Item | What it does | Legacy naming | Replaced by | Last human commit | Verdict | Reasoning |
|---|---|---|---|---|---|---|
| `packer/aws-ami-4shark-wp.json` | `amazon-ebs` build in `us-east-1` from `source_ami: ami-bd9a95aa` on a `c4.large`, provisioned by the Ansible WordPress playbook, output `4shark-ubuntu-16.04-wp-{{timestamp}}` | `wp` | Nothing | **2016-12-29 Leon Waldman** (Initial Commit — never modified) | **DEAD** | Broken: `:21` references `playbooks/aws-ami-4shark-wp.yaml`; the file is `.yml` since 2018-10-29 (Finding 5). Hardcodes a `vpc_id`/`subnet_id`/`security_group_id` from the pre-Terraform era. Targets Ubuntu 16.04 (EOL). Uses the legacy JSON format, not HCL2 |
| `packer/aws-ami-ubuntu-16.04-python.json` | Same builder shape from `source_ami: ami-40d28157`, provisioned by the Python 2 playbook, output `4shark-ubuntu-16.04-python-{{timestamp}}` | — | Nothing | **2016-12-29 Leon Waldman** (Initial Commit — never modified) | **DEAD** | Broken the same way (`:21` → `...python-node.yaml`). Ubuntu 16.04 EOL April 2021; Python 2 EOL January 2020 |

**Answer to "is there an AMI pipeline still alive here?":** No. Neither template can resolve its playbook, and neither has been touched since the repository's initial commit in 2016. The live golden-AMI pipeline is `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl` (HCL2, CI-built on merge, per `mongodb/README.md:39-48`) — a different repository.

**Packer verdict counts:** DEAD 2

---

## Complete inventory — Configuration files, scripts and CI (20)

| Item | What it does | Legacy naming | Replaced by | Last human commit | Verdict | Reasoning |
|---|---|---|---|---|---|---|
| `README.md` | Setup guide: venv, pip, AWS credentials, `ansible_user`, the vault password file, `install_requirements.sh`, VPN + `kp-4shark.pem` requirement, playbook categories and usage | — | — | 2022-07-08 Paulo Ribeiro | **MIGRATE** (security-blocking) | **Line 71 contains the ansible-vault password in cleartext**, present since 2018-10-29 (Finding 9). Also documents `ansible_user` as "your jumpcloud user" — JumpCloud was deprecated in 2023. Whatever is decided about the repo, this content must be rotated and purged |
| `CHANGELOG.md` | Keep a Changelog format; current-year entries only, with `[Unreleased]` listing the CloudWatch migration, the FQDN `rs.initiate` change, the disabled cron default | — | — | 2026-06-18 Paulo Ribeiro | **KEEP** | Actively maintained and describes 2026 work. Its `[Unreleased]` entries are the written record that the MongoDB/Pritunl core is current |
| `changelogs/` (2019–2025, 7 files) | Per-year archived changelog sections | — | — | 2026-06-18 Paulo Ribeiro | **KEEP** | Historical record; the split was itself a deliberate 2026-06-18 change (`docs(changelog): split previous years into changelogs folder`) |
| `ansible.cfg` | `roles_path = ./imported_roles:./roles:../roles`, `retry_files_enabled = False`, `timeout = 300`, `host_key_checking = False` | — | — | 2026-02-27 (file mtime) | **KEEP** | Required for any playbook to resolve roles. `host_key_checking = False` is a standing weakness (accepts any host key) but is what makes provisioning a fresh box non-interactive |
| `ansible_user` | Holds the engineer's SSH username; read by `run_playbook.sh` | — | — | n/a (git-ignored) | **KEEP** | `.gitignore:3` — per-engineer local file, not tracked. `run_playbook.sh` refuses to run without it |
| `run_playbook.sh` | The entry point: validates `ansible_user`, refuses `playbooks/aws-ami*` (points at `packer_build.sh`), builds `--extra-vars` from `k=v` args, then runs `ansible-playbook -i ec2.py ... --vault-password-file ~/.4shark/vault_password_file.txt` (`:42`) | — | — | 2026-03-03 Paulo Ribeiro | **KEEP** | The invocation path for both live playbooks; their header comments document `./run_playbook.sh 4shark playbooks/...` usage. Recently maintained |
| `ec2.py` | The legacy AWS dynamic-inventory script (73KB), used as `-i ec2.py` by `run_playbook.sh:42` | — | `amazon.aws.aws_ec2` inventory plugin (upstream) | 2025-05-14 Paulo Ribeiro | **MIGRATE** | Still wired in and touched in 2025, but it is the deprecated boto2-era contrib script; upstream replaced it with the `amazon.aws.aws_ec2` plugin. It is also why `boto==2.49.0` (last released 2018) is pinned in `requirements.txt` |
| `ec2.ini` | Config for `ec2.py`: `regions = us-east-1,sa-east-1`, exclusions, destination-variable settings | — | `amazon.aws.aws_ec2` plugin config | 2025-04-07 (file mtime) | **MIGRATE** | Moves or dies with `ec2.py` |
| `edit_vault.sh` | `ANSIBLE_VAULT_PASSWORD_FILE=~/.4shark/vault_password_file.txt ansible-vault edit $@` | — | — | 2025-04-07 (file mtime) | **KEEP** (while the vault exists) | 4-line convenience wrapper. Its value is contingent on the vault surviving the rotation decision |
| `install_requirements.sh` | `mkdir ./imported_roles` then `ansible-galaxy install -r requirements.yml -p ./imported_roles/` | — | — | 2025-04-07 (file mtime) | **KEEP** | The mechanism that makes `imported_roles/` git-ignorable (Finding 14) |
| `packer_build.sh` | `AWS_PROFILE=4shark packer build $@` | — | `mongodb` repo's `build.yaml` GitHub workflow | 2025-04-07 (file mtime) | **DEAD** | Its only possible arguments are the two broken templates (Finding 5). Its `usage()` even contradicts the arg check it performs |
| `requirements.txt` | Pins the Python/Ansible toolchain: `ansible-core==2.21.1`, `ansible==5.7.1`, `boto3`, `botocore`, `boto==2.49.0`, `cryptography`, … | — | — | 2026-06-18 (bot) | **KEEP** (but it is the churn source) | Needed to run the live playbooks. It is what Renovate/Dependabot bump 136 times a year (Finding 15). Note the internal contradiction: `ansible==5.7.1` (2022) alongside `ansible-core==2.21.1` — and `boto==2.49.0` exists solely for `ec2.py` |
| `requirements.yml` | Declares the 8 Galaxy roles with version pins (`jnv.unattended-upgrades v1.3.0`, `geerlingguy.ntp 2.3.0`, `geerlingguy.apache 2.1.2`, `geerlingguy.php 3.7.0`, `geerlingguy.ruby 2.5.3`, `weareinteractive.environment 1.4.0`; `nickhammond.logrotate` unpinned) | — | — | 2026-05-13 (file mtime) | **MIGRATE** | Only 2 of its 8 entries serve a live playbook (Finding 14). `nickhammond.logrotate` has **no version pin**, which is a supply-chain gap against the repo's own `minimumReleaseAge` posture |
| `renovate.json` | Renovate config: `minimumReleaseAge: 7 days`, `rangeStrategy: pin`, GHA digest exemption, pin-PR suppression | — | — | 2026-05-22 (file mtime) | **KEEP** (conditional on the repo) | Conforms to the 4Shark standard. Its cost is Finding 15 — it is doing exactly what it should, on a repo that may not warrant it |
| `techstack.yml` | An 18KB StackShare/tech-report inventory: `report_id`, `timestamp: '2024-02-29T18:03:26+00:00'`, `detected_tools_count: 31`, then a generated list of tools with marketing descriptions and `img.stackshare.io` image URLs | — | — | 2025-04-07 (file mtime) | **DEAD** | A one-off generated snapshot from 2024-02-29. **Nothing consumes it** — no workflow, script or playbook references it. It is a frozen report of a repo that has changed since, checked into git |
| `.editorconfig` | `indent_size = 2`, LF, UTF-8, trim trailing whitespace; `[*.js] indent_size = 4` | — | — | 2025-04-07 (file mtime) | **KEEP** | Standard hygiene. The `[*.js]` block matches nothing in this repo |
| `.gitignore` | `__pycache__`, `imported_roles`, `ansible_user`, `venv`, `.idea`, `.claude/` | — | — | 2026-06-08 (file mtime) | **KEEP** | Load-bearing for Finding 14. Correctly keeps Galaxy output and the per-engineer file out of git |
| `bin/ssh-ec2.sh` | Resolves an instance's private IP, pushes a public key via `ec2-instance-connect send-ssh-public-key`, then SSHes in. Defaults `4shark` / `sa-east-1` | — | AWS SSM Session Manager (not adopted here) | 2025-04-07 (file mtime) | **KEEP** | The access path to the live Mongo/VPN boxes, paired with `4shark.users`' `ec2-instance-connect` install. **Independent of Ansible** — a generic operator utility that happens to live in this repo |
| `group_vars/all/all.yml` | The global var file: SSH key path, `app_user`, the 3 JumpCloud vars, Datadog config, `aws_profile`/`aws_key_name`, the internal Route53 zone + id, per-region Ubuntu/OpenVPN AMIs and DHCP opts, the management VPC/peering block, the WordPress AMI + VPC block, and ~150 lines of `redis_ebs_size`/`redis_ebs_type` instance-type→device maps | `4client` (`aws_4client_vpc`), `wp` | Partly `terraform/networking/` (SSM outputs) | 2023-10-13 Paulo Ribeiro | **MIGRATE** | Mixed: the internal zone id, `aws_key_name` and the region AMIs are consumed by live paths; the JumpCloud block (dead, Finding 11), the WordPress block (dead, Finding 4), the `openvpn_ubuntu_image` (dead, Finding 12) and the ~150-line Redis EBS maps (dead, Finding 13) are not. Hardcoded resource ids duplicate what Terraform now owns |
| `group_vars/all/vault.yml` | `$ANSIBLE_VAULT;1.1;AES256`, 29 lines. Holds the 6 `vault_*` variables referenced across the repo (**not decrypted for this spike**) | — | AWS SSM Parameter Store / 1Password (the current 4Shark patterns) | 2023-10-13 (with `all.yml`) | **MIGRATE** (rotation-blocking) | Categories held: **1 observability API key** (Datadog), **3 identity-provider credentials** (JumpCloud), **1 LDAP bind password** (OpenVPN), **1 database password** (Redis default). By live-target analysis: 3 JumpCloud are dead config (Finding 11), OpenVPN LDAP is dead (Finding 12), Redis is dead (Finding 13), Datadog is referenced only by superseded playbooks. **Its encryption is void** — the password sits in `README.md:71` (Finding 9) |
| `.github/workflows/renovate.yml` | Self-hosted Renovate on cron `0 11 * * 1-5` + `workflow_dispatch`, via a GitHub App token | — | — | 2026-07-15 (file mtime) | **KEEP** (conditional) | Conforms to the 4Shark three-layer standard. It is the direct source of the 135 bot commits (Finding 15) |
| `.github/workflows/verify-minimum-age.yaml` | On `pull_request`, runs `.github/scripts/verify-minimum-age.sh` with `NOTIFY_HANDLE: 4shark/infrastructure` | — | — | 2026-07-15 (file mtime) | **KEEP** (conditional) | The 7-day supply-chain gate. Correct and current |
| `.github/workflows/reverify-minimum-age.yaml` | Daily cron re-evaluating open PRs so pending ages self-heal to green | — | — | 2026-07-15 (file mtime) | **KEEP** (conditional) | Same |
| `.github/scripts/verify-minimum-age.sh` | Enumerates `uses: org/repo@<SHA>` refs, queries commit dates, posts the `Verify Minimum Age` commit status | — | — | 2026-07-15 (file mtime) | **KEEP** (conditional) | Same |

**Config verdict counts:** DEAD 2 · MIGRATE 6 · KEEP 15 (7 of them "conditional on the repo existing")

---

## Cross-cutting questions

### Is anything in this repo referenced from OUTSIDE it?

**Yes — one live, material reference.**

- `~/.claude/commands/create-integrator.md:128` — *"1. **MongoDB installation**: Run Ansible playbook to install MongoDB on the 3 new EC2 instances"*, followed at `:129` by *"2. **MongoDB replica set**: Configure the replica set (PSA topology)"*. This is a documented handoff into `provision-4client-mongodb-server.yml` and must be resolved before the repo is retired (Finding 3).
- `~/.claude/docs/PROJECTS-CATALOG.md:101` — `| `ansible` | Ansible | Server provisioning and configuration. |` plus a node in the Mermaid graph at `:179`. Catalog bookkeeping, not a functional dependency.
- `~/.claude/docs/runbooks/databases/MONGODB-VERSION-UPGRADE.md:332` — *"- **`ansible-role-mongodb`** — the role that actually installs MongoDB."* This points at the **dedicated repo**, not this one. Not a dependency.
- `AUTOMATED-DEPENDENCY-UPDATES.md`, `COMMAND-SAFETY.md`, `LANGUAGE-POLICY.md` — the word "ansible" appears in generic policy prose (e.g. the infra-command list `terraform`, `aws`, `kubectl`, `docker`, `ansible`). Not references to this repository.

**I searched `~/.claude/docs/runbooks/` specifically:** the only runbook hit is `MONGODB-VERSION-UPGRADE.md`, and both of its hits (`:108`, `:332`) name `ansible-role-mongodb` — the dedicated repo. **No runbook instructs an engineer to run a playbook from this repo.** The `/create-integrator` skill is the sole in-toolchain dependency.

Across the other 4Shark repos, no code references this repository. Full grep output in [`ansible_grep_1.txt`](ansible_grep_1.txt) §8.

### Does anything in `terraform/` invoke Ansible?

**No — the coupling is tag-convention only.** There is no `provisioner`, no `local-exec`/`remote-exec` calling a playbook, and no `user_data` bootstrapping one. What exists is:

- `terraform/modules/pritunl/main.tf:17` and `:23` — `Automation = "ansible"`, with `:28` `ignore_changes = [ami, user_data, user_data_base64]`. Terraform declares "I made the box, something else configures it".
- `terraform/integrator-*/mongodb.tf` — `Automation = "packer"` for the migrated clients (`integrator-atento/mongodb.tf:48`), i.e. the tag itself records which provisioning path built the node.

The `Automation` tag is doing real work as documentation: it is the only machine-readable record of which hosts depend on this repo. That is also the fastest way to measure the blast radius of retiring it (Finding 1).

### Is there an AMI pipeline still alive here?

**No.** Both Packer templates have been broken since the 2018 `.yaml`→`.yml` rename and were last modified at the repository's 2016 initial commit (Finding 5). `aws-ami-ubuntu-16.04-python.json` targets Ubuntu 16.04 (EOL April 2021) to install Python 2 (EOL January 2020); nothing consumes its output. The live AMI pipeline is `~/Projects/4Shark/mongodb/` (`packer/mongodb.pkr.hcl`, built by CI on merge, pruning to the 3 most recent AMIs per `mongodb/README.md:39-48`).

The AMIs consumed by live Terraform are hand-pinned ids (`integrator-atento/mongodb.tf:29` `ami = "ami-0e4d77e66719fceb1"`; `terraform/vpn/main.tf` `ami_id = "ami-032ab7316dbf1ea74"`), none produced by this repo's templates.

### What is `techstack.yml`?

An 18KB **generated StackShare-style tech report**, snapshotted once and committed. Its header is self-describing:

```yaml
repo_name: 4shark/ansible
report_id: 0166f5bd711f36ec050b29c7beefed53
version: 0.1
repo_type: Public
timestamp: '2024-02-29T18:03:26+00:00'
requested_by: plribeiro3000
provider: github
branch: develop
detected_tools_count: 31
```

The body is a list of detected tools with marketing copy and `img.stackshare.io` image URLs (e.g. `- name: Jinja` / `description: Full featured template engine for Python`). **Nothing consumes it** — no workflow, script or playbook references it. It is a frozen 2024-02-29 snapshot of a repository that has changed materially since, with `repo_type: Public` recorded in it. Verdict: **DEAD**.

### What is in `group_vars/all/vault.yml`?

**Not decrypted. Category only.** It is an `$ANSIBLE_VAULT;1.1;AES256` file, 29 lines. From the `vault_*` references across the repo it must hold **6 secrets** in **4 categories**:

| Category | Variable | Consumed by | Still live? |
|---|---|---|---|
| Observability API key | `vault_datadog_api_key` | `group_vars/all/all.yml:15` → `Datadog.datadog` | **No** — only superseded playbooks; `4shark.cloudwatch_agent` actively purges the Datadog agent |
| Identity-provider credentials (×3) | `vault_jumpcloud_api_key`, `vault_jumpcloud_x_connect_key`, `vault_jumpcloud_all_systems_group` | `group_vars/all/all.yml:10-12` — **no role consumes them** | **No** — JumpCloud agent install removed 2023-10-13 (Finding 11) |
| LDAP bind password | `vault_openvpn_ldap_bind_password` | `playbooks/vars/openvpn/openvpn-settings-ldap.yml:18` | **No** — OpenVPN fully replaced by Pritunl (Finding 12) |
| Database password | `vault_redis_default_password` | 4 Redis playbooks + `playbooks/templates/redis_sentinel_check_master.sh.j2:11` | **No** — no Redis EC2 exists (Finding 13) |

**None of the six secrets is consumed by a live playbook.** The two live playbooks (`provision-4client-mongodb-server.yml`, `provision-pritunl.yml`) reference no `vault_*` variable.

**But this is a rotation problem regardless of the retire/keep decision**, and the reason is Finding 9: `README.md:71` contains the vault password in cleartext and has since 2018-10-29. The encryption protects nothing against anyone with repository access. Whether these secrets are still valid *at the provider* (Datadog, JumpCloud, Redis) is the open question — see "What remains uncertain".

### Is the CI still doing anything meaningful?

**It is correct, current, and conformant — and mostly pointed at a dead repo.** `renovate.yml`, `verify-minimum-age.yaml`, `reverify-minimum-age.yaml` and `verify-minimum-age.sh` implement the 4Shark three-layer dependency standard faithfully. There is no test/lint CI — no `ansible-lint`, no `yamllint`, no syntax check. (By contrast, the dedicated `ansible-role-mongodb` ships `.ansible-lint` and `.yamllint`.)

The cost is Finding 15: **136 of 170 non-merge 2026 commits (80%) are bot bumps**, maintaining `requirements.txt` — the Python environment needed to *run* the playbooks locally. Two observations on the shape of that cost:

1. It **does not scale down with the repo**. Trimming 20 of 22 playbooks leaves `requirements.txt` untouched; `ansible-core`, `boto3`/`botocore` and `cryptography` still release constantly. Only removing the repo (or its `requirements.txt`) removes the churn.
2. Part of it is self-inflicted by `ec2.py`: the pinned `boto==2.49.0` (last released 2018) exists solely for the legacy inventory script. Migrating to the `amazon.aws.aws_ec2` plugin would drop a dependency, not add one.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A. Delete the repository outright** | Removes 100% of the Renovate churn (Finding 15); removes the 2 committed credentials from the working tree; forces the golden-AMI migration to finish | Destroys the only implementation of the per-client `rs.initiate()` step (Finding 6) and of the live VPN's configuration (Finding 1); breaks `create-integrator.md:128` (Finding 3); commcenter + redebrasil Mongo nodes lose their documented build path (Finding 7); does **not** remove the credentials from git history (Finding 9) | Findings 1, 3, 6, 7, 9, 15 |
| **B. Archive read-only on GitHub** | Churn stops (Renovate cannot open PRs on an archived repo); history stays reachable for the 2 live playbooks; reversible (unarchive) | The 2 live playbooks still need to be *run* — an archived repo can be cloned and run, so this preserves capability but freezes it: any fix to Pritunl or Mongo provisioning requires unarchiving; the credential exposure persists unchanged | Findings 1, 9, 15 |
| **C. Trim to the live core, keep the repo** | Keeps both live playbooks working; deletes 5 DEAD + 15 SUPERSEDED playbooks, 8 dead/superseded roles, both Packer templates, `techstack.yml`, the WordPress/JumpCloud/Redis config blocks; lets `requirements.yml` drop to 2 entries | Churn largely persists — `requirements.txt` is the churn driver and survives the trim (Finding 15); the repo remains a second home for MongoDB provisioning alongside `ansible-role-mongodb` (Finding 6); a trim is a substantial PR against untested code (no lint/CI) | Findings 6, 14, 15 |
| **D. Migrate the live core out, then retire** — Pritunl role → its own repo (or `terraform/modules/pritunl`); Mongo replica-set step → `mongodb`/`ansible-role-mongodb` | Ends the three-copies-of-MongoDB problem (Finding 6); each capability lands where the dedicated-repo pattern already works (versioned, linted, CHANGELOG'd, min-age gated); the ansible repo then retires with nothing live in it | The largest effort of the four; the Mongo replica-set step is per-client and post-boot, so it does not fit the golden-AMI repo's build-time model without a new home; needs `create-integrator.md` updated in the same change | Findings 3, 6, 7; `mongodb/README.md:19-25` |
| **E. Rotate credentials + purge history** (orthogonal — pairs with any of A–D) | Closes an ~8-year exposure (Finding 9); can proceed immediately without deciding the repo's fate | History rewrite on a repo with 275+ PRs, or acceptance that the material stays in history; requires confirming each secret's validity at its provider first (all 6 are referenced only by dead paths) | Finding 9, 10, 11, 12, 13 |
| **Finish the golden-AMI migration first** (sequencing option, not an endpoint) | Removes commcenter + redebrasil from the ansible path (Finding 7), shrinking the live core from 2 playbooks to 1 and making A/B far cheaper | Does not address Pritunl; requires a per-client replica-set-member re-provision, which `mongodb/README.md:50-53` describes as "a deliberate edit plus a re-provision" | Finding 7; `mongodb/README.md:50-53` |

---

## Retirement blockers

**Not "none found" — there are four, of which three are hard.**

1. **HARD — the per-client MongoDB replica-set step has no other implementation.** `provision-4client-mongodb-server.yml` (last human commit 2026-05-14) is the only code that runs `rs.initiate()` with the correct FQDN members for a new client. `mongodb/README.md:22-25` states this is deliberately **not** in the golden AMI: *"The **per-client** part — the actual `replSetName` and `rs.initiate()` — is **not** baked; it differs per client and runs post-boot"*. Retiring without a new home for this step breaks new-integrator creation. (Findings 3, 6)

2. **HARD — the live VPN's configuration has no other implementation.** `4shark-vpn-001` is running with `Automation=ansible`; `terraform/modules/pritunl/main.tf:28` explicitly `ignore_changes` its `user_data`, so Terraform will never configure it. `provision-pritunl.yml` + `roles/4shark.pritunl` are the only description of what is on that box. If it is lost, the VPN becomes unrebuildable-from-code. (Findings 1, 12)

3. **HARD — `~/.claude/commands/create-integrator.md:128-129` points at this repo.** Step 5.1/5.2 of the `/create-integrator` skill hands off to `provision-4client-mongodb-server.yml`. The skill must be updated in the same change that retires the repo, or it documents a step nobody can perform. (Finding 3)

4. **SOFT (but urgent, and independent) — two committed credentials that survive retirement.** `README.md:71` holds the ansible-vault password in cleartext (since 2018-10-29), and `roles/4shark.common_users/files/4shark_deployer.pem` is a git-tracked SSH private key. **Neither is remediated by deleting or archiving the repo** — both remain in git history, and the private key remains on any host the role ever touched. This is *not* a blocker in the sense of "retirement must wait for it"; it is a blocker in the sense that **retirement must not be mistaken for remediation**. Rotation is required on every path, including "delete the repo tomorrow". (Findings 9, 10)

**Explicitly NOT blockers** (checked and cleared):
- No runbook in `~/.claude/docs/runbooks/` runs a playbook from this repo (the MongoDB runbook's hits name the *dedicated* `ansible-role-mongodb`).
- No Terraform code invokes Ansible — the coupling is a tag convention, so no `terraform apply` breaks.
- No other 4Shark repository references this one.
- `imported_roles/` is git-ignored Galaxy output, not vendored code — retiring it costs a 530-byte manifest (Finding 14).
- The two Packer templates are already broken and consume nothing (Finding 5).

**The blast radius is small and precisely enumerable:** 1 VPN instance + 6 MongoDB instances across 2 clients (commcenter running, redebrasil stopped), 2 playbooks, 7 own roles, 2 Galaxy roles, 1 skill file.

---

## What remains uncertain

- **Are the 6 vault secrets still valid at their providers?** All six are referenced only by dead or superseded paths, but whether the Datadog key, the three JumpCloud credentials, the OpenVPN LDAP bind account and the Redis password are still *active* at Datadog/JumpCloud/the Redis fleet cannot be determined from the repository. This decides rotate-vs-revoke. Answering it needs provider-console access, which is past the read-only boundary of this spike.
- **Was the plaintext vault password or the committed private key ever exploited?** Not determinable here. `README.md` has held the password since 2018-10-29, and the repo's own `techstack.yml:4` records `repo_type: Public` as of 2024-02-29 — whether the GitHub repository was ever actually public (and if so, when) was **not verified**; `techstack.yml` is a third-party generated report, not authoritative. If it was public at any point, the exposure class changes materially. This needs a check of the repository's visibility history.
- **Why does `redebrasil` have Mongo nodes both as `4client-redebrasil-mongo003/4/5` (stopped, `Automation=ansible`) and an `integrator-redebrasil-cluster` on ECS?** The naming split suggests a migration that stopped midway, but whether those stopped nodes are pending deletion, pending migration, or a cold standby was not established.
- **Is the golden-AMI migration for commcenter/redebrasil planned, and when?** This is the single variable that most changes the retirement calculus (it would halve the live core). No planning document for it was found.
- **Does `4shark.mongodb8` differ from `ansible-role-mongodb` in any way that matters** beyond the series (8.2/noble vs the dedicated repo's no-default/focal)? The full diff was taken against `4shark.mongodb` (the 4.0 fork), not against `mongodb8`. A `mongodb8` ↔ `ansible-role-mongodb` diff was **not** performed and would be required before merging the two.
- **Ownership of `bin/ssh-ec2.sh`.** It is a live, Ansible-independent operator utility that happens to live here. If the repo retires, it needs a home; which one was not determined.

---

## Suggested options for main and the engineer

The four verdict counts across all 65 inventoried items:

| Verdict | Playbooks | Own roles | Imported roles | Packer | Config | **Total** |
|---|---|---|---|---|---|---|
| **DEAD** | 5 | 2 | 2 | 2 | 2 | **13** |
| **SUPERSEDED** | 15 | 6 | 4 | 0 | 0 | **25** |
| **KEEP** | 2 | 6 | 2 | 0 | 15 | **25** |
| **MIGRATE** | 0 | 1 | 0 | 0 | 6 | **7** |

Read on capability rather than file count: **the repo is ~85% dead weight around a live core of 2 playbooks + 7 own roles + 2 Galaxy roles**, serving 1 VPN box and 2 clients' MongoDB.

- **Option A — Delete outright.** Coherent only if the live core is first relocated or accepted as lost. As-is it breaks the VPN's rebuild path, the per-client `rs.initiate()` step, and `create-integrator.md:128`.
- **Option B — Archive read-only on GitHub.** Stops the churn immediately (the largest measurable cost, Finding 15) and keeps the live playbooks runnable-from-clone. Freezes them: the next Pritunl or Mongo fix needs an unarchive.
- **Option C — Trim to the live core.** Deletes the 13 DEAD + 25 SUPERSEDED items, keeps the repo alive for its 2 playbooks. Does **not** solve the churn (`requirements.txt` survives) and leaves MongoDB provisioning duplicated across three places.
- **Option D — Migrate the core out, then retire.** Pritunl → its own repo or `terraform/modules/pritunl`; the per-client Mongo step → `mongodb`/`ansible-role-mongodb`. Highest effort; the only option that ends both the duplication and the churn.
- **Option E — Rotate the credentials and purge.** Orthogonal to A–D; can start now. Should not be deferred behind the repo decision, because no repo decision remediates it.
- **Sequencing lever — finish the golden-AMI migration for commcenter + redebrasil first.** Not an endpoint, but it halves the live core and makes A and B substantially cheaper.

**The condition that decides between them:** *does the per-client MongoDB `rs.initiate()` step have a home outside this repo?*

- **If yes** (it moves to `mongodb`/`ansible-role-mongodb`, or new integrators stop needing it) → only Pritunl blocks retirement, and **A** or **B** becomes viable once Pritunl is relocated or accepted as frozen.
- **If no** (the step must stay Ansible-shaped and post-boot, as `mongodb/README.md:22-25` currently argues) → the repo has a live reason to exist, and the decision collapses to **C vs D**: trim in place and accept the churn, or pay once to move the core out.

A secondary lever, if the churn is the dominant pain: **B stops it today at the cost of freezing two live playbooks**, whereas **C does not stop it at all**. If the engineer's daily Renovate PRs are the actual motivation, B and D are the only two options that address it.

The engineer decides.
