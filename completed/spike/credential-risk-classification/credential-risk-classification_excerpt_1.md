<!-- Auxiliary file for SPIKE.md — credential-risk-classification -->
<!-- Raw evidence: the two distinct EC2 SSH key pairs found in the terraform repository -->

# Excerpt 1 — EC2 key pairs: `kp-4shark` vs `4Shark-key`

## Grep: every `key_pair`/`key_name` reference in the terraform repo (filtered to the literal-value hits)

```
integrator-almaviva/mongodb.tf:28:  key_name      = "kp-4shark"
integrator-almaviva/mongodb.tf:73:  key_name      = "kp-4shark"
integrator-almaviva/mongodb.tf:118: key_name      = "kp-4shark"
integrator-atento/mongodb.tf:28,73,118:   key_name = "kp-4shark"
integrator-redebrasil/mongodb.tf:28,73,118: key_name = "kp-4shark"
integrator-maqnelson/mongodb.tf:28,73,118:  key_name = "kp-4shark"
integrator-commcenter/mongodb.tf:28,73,118: key_name = "kp-4shark"
integrator-atento/windows_machine.tf:17:  key_name = "kp-4shark"
integrator-atento/windows_machine.tf:66:  description = "Encrypted Administrator password — decrypt with: aws ec2 get-password-data --instance-id <id> --priv-launch-key kp-4shark.pem"
vpn/main.tf:19:  key_name      = "kp-4shark"
modules/pritunl/variables.tf:27-30:
  variable "key_name" {
  ...
  default     = "kp-4shark"
```

## `integrator-almaviva/mongodb.tf` (representative of all 5 integrator mongo stacks — almaviva, atento, redebrasil, maqnelson, commcenter each provision 3 EC2 instances: primary/secondary/arbiter, all three pinned to `key_name = "kp-4shark"`)

```hcl
resource "aws_instance" "mongo003" {
  ami           = "ami-0bd91caaa9bc42cf3"
  instance_type = "t3.small"
  key_name      = "kp-4shark"
  subnet_id     = nonsensitive(data.aws_ssm_parameter.prv_a_subnet_id.value)
  iam_instance_profile = "mongo-cwagent"
  ...
  tags = {
    Name       = "4client-almaviva-mongo003"
    Client     = "almaviva"
    Project    = "integrator"
    Role       = "database"
    Type       = "mongodb"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data, user_data_base64]
  }
}
```
(mongo004 secondary, mongo005 arbiter follow the identical shape, same `key_name`.)

## `vpn/main.tf` — the Pritunl VPN EC2 host

```hcl
module "pritunl" {
  source = "../modules/pritunl"

  name_prefix   = "4shark-vpn-001"
  vpc_id        = "vpc-0bdc76f3b391694dd"
  subnet_id     = data.aws_subnet.management_pub_a.id
  vpc_cidr      = "10.255.0.0/16"
  instance_type = "t3a.micro"
  ami_id        = "ami-032ab7316dbf1ea74"
  key_name      = "kp-4shark"
  volume_size   = 20
  vpn_port      = 14720
  wg_port       = 14721
}
```

## `integrator-atento/windows_machine.tf` (lines 55–69) — Windows RDP box, Administrator password decrypted with the same key

```hcl
output "windows_machine_private_ip" {
  description = "Private IP of the Windows machine (RDP target via management VPN)"
  value       = aws_instance.windows_machine.private_ip
}

output "windows_machine_password_data" {
  description = "Encrypted Administrator password — decrypt with: aws ec2 get-password-data --instance-id <id> --priv-launch-key kp-4shark.pem"
  value       = aws_instance.windows_machine.password_data
  sensitive   = true
}
```

## `terraform.tfvars` — a SECOND, distinct key pair name used by every app/setup ECS-host stack

```
app-shared-001/terraform.tfvars:5:  key_name                    = "4Shark-key"
app-atento-001/terraform.tfvars:4:  key_name                    = "4Shark-key"
app-beta-001/terraform.tfvars:5:    key_name                    = "4Shark-key"
app-demo-001/terraform.tfvars:5:    key_name                    = "4Shark-key"
setup/terraform.tfvars:5:           key_name                    = "4Shark-key"
```

No other file in `~/Projects/4Shark` (searched `.md`/`.tf`/`.yml`/`.sh`) references the literal string `4Shark-key` — no ansible playbook, no runbook, no README documents how or whether anyone actually uses this key pair's private half interactively. Contrast with `kp-4shark`, which IS documented for interactive/automation use (see Excerpt 3).

## `modules/ecs_cluster/main.tf` (lines 72–114) — how `create_key_pair` and `key_name` interact for the ECS-host capacity fleet

```hcl
resource "aws_key_pair" "this" {
  count = var.create_key_pair ? 1 : 0
  key_name   = var.key_name
  ...
}
# app-shared-001/main.tf:73-74, app-atento-001/compute.tf:405-406, setup/main.tf:135-136 etc.
# all pass create_key_pair = false and key_name = var.key_name (resolved to "4Shark-key"
# via terraform.tfvars) — meaning these stacks reference an already-existing AWS key
# pair rather than creating a new one each time.
```
