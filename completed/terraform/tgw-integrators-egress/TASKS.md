# TASKS — Centralized Egress for Integrator VPCs via Transit Gateway

**Branch:** `feature/tgw-integrators-egress`
**Plan:** `PLAN.md`

---

## Phase 0 — CIDR Safety Check

- [ ] **T01** — Verify 10.254.0.0/27 does not conflict with any client on-premise CIDR
  - Check static routes in each integrator VGW (almaviva, redebrasil, maqnelson, commcenter, aster-maquinas, atento-br, out-atento-br)
  - If conflict found: use 10.253.0.0/27 instead and update PLAN.md

---

## Phase 1 — egress-sa-east-1 VPC

- [ ] **T02** — Create `networking/vpc_egress_sa_east_1.tf`
  - VPC `egress-sa-east-1`, CIDR 10.254.0.0/27
  - Subnet `egress-sa-east-1-tgw-a`: 10.254.0.0/28, sa-east-1a (private)
  - Subnet `egress-sa-east-1-pub-a`: 10.254.0.16/28, sa-east-1a (public)
  - Internet Gateway
  - EIP + NAT Gateway in pub-a
  - Route table for tgw-a subnet: `0.0.0.0/0` → NAT Gateway
  - Route table for pub-a subnet: `0.0.0.0/0` → Internet Gateway

- [ ] **T03** — Add VPC peering egress-sa-east-1 ↔ management in `networking/peering.tf`
  - Peering connection resource
  - Route in management private RT: 10.254.0.0/27 → peering
  - Route in egress tgw-a RT: 10.255.0.0/16 → peering
  - Accept peering (same account, same region — auto-accepted or explicit accepter resource)

- [ ] **T04** — Add SSM parameters for egress VPC in `networking/ssm.tf`
  - `/networking/egress-sa-east-1/vpc_id`
  - `/networking/egress-sa-east-1/subnet_tgw_a_id`
  - `/networking/egress-sa-east-1/subnet_pub_a_id`
  - `/networking/egress-sa-east-1/nat_gateway_id`
  - `/networking/egress-sa-east-1/eip_nat`

- [ ] **T05** — `terraform plan` + apply Phase 1, validate:
  - VPC created and visible in AWS console
  - NAT Gateway in service
  - Peering active, routes present in both route tables
  - Can reach egress VPC subnets via VPN (ping 10.254.0.x from VPN client)

---

## Phase 2 — Transit Gateway

- [ ] **T06** — Create `networking/transit_gateway.tf`
  - `aws_ec2_transit_gateway` named `4shark-main`, default RT association/propagation disabled
  - TGW route table `spoke-rt` with default route `0.0.0.0/0` → egress attachment
  - TGW route table `egress-rt` (return routes added per integrator in subsequent tasks)
  - TGW attachment to egress-sa-east-1 (tgw-a subnet), associated to `egress-rt`

- [ ] **T07** — `terraform plan` + apply Phase 2, validate:
  - TGW in available state
  - egress attachment active
  - Route tables created with correct routes
  - No integrator traffic affected (all integrators still use their own NAT GWs)

---

## Phase 3 — Pilot: almaviva

- [ ] **T08** — Add almaviva TGW attachment and routes
  - TGW attachment to integrator-almaviva VPC, associated to `spoke-rt`
  - Add 10.1.0.0/24 → almaviva attachment in TGW `egress-rt`
  - Add route in egress tgw-a RT: 10.1.0.0/24 → TGW

- [ ] **T09** — Flip almaviva default route to TGW
  - Change almaviva private RT: `0.0.0.0/0` from `nat-0c73faca7e745930d` → TGW attachment
  - **Do not delete the NAT Gateway yet**

- [ ] **T10** — Validate almaviva (24h observation window)
  - From almaviva server: `curl https://ifconfig.me` → should return management NAT EIP
  - From almaviva server: `apt-get update` succeeds
  - Datadog metrics arriving from almaviva
  - S2S VPN to client still working (ping client internal IP)

- [ ] **T11** — Delete almaviva NAT Gateway and EIP (after 24h validation)
  - Remove `aws_nat_gateway.almaviva` and `aws_eip.almaviva_nat` from Terraform
  - `terraform apply`

---

## Phase 4 — Migrate Remaining Integrators

> Repeat T08→T11 pattern for each integrator. Each is a separate PR or commit.

- [ ] **T12** — Migrate maqnelson (CIDR 10.1.2.0/24, NAT nat-0f4523b88ae80f008)
- [ ] **T13** — Migrate commcenter (CIDR 10.1.3.0/24, NAT nat-0ca37d7634939afa3)
- [ ] **T14** — Migrate aster-maquinas (CIDR 10.1.4.0/24, NAT nat-01f4651d50c20d462)
- [ ] **T15** — Migrate redebrasil (CIDR 10.1.1.0/24, NAT nat-05abe4fcc9b9f0d55)
- [ ] **T16** — Migrate out-atento-br (CIDR 10.12.0.0/26, NAT nat-03b45836d0effc138)
- [ ] **T17** — Migrate atento-br (CIDR 10.12.255.0/24, NAT nat-0d943e24969e7bf4f)
  - Extra validation: confirm Redis/ElastiCache connectivity after flip

---

## Phase 5 — Cleanup

- [ ] **T18** — Update CHANGELOG.md
- [ ] **T19** — Verify AWS Cost Explorer shows reduction in NAT Gateway charges
