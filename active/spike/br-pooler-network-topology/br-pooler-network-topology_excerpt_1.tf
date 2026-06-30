# Auxiliary file: key Terraform excerpts supporting the BR pooler network topology spike.
# Each section is labeled with the source file:line range.
# Credential values are never reproduced here; structure only.

# ============================================================
# SOURCE: terraform/networking/transit_gateway.tf:23-66
# Finding: spoke_rt has ONLY 0.0.0.0/0 → egress VPC; no intra-spoke routes exist.
# ============================================================

resource "aws_ec2_transit_gateway_route_table" "spoke_rt" {
  transit_gateway_id = aws_ec2_transit_gateway.sa_east_1.id
  tags = { Name = "spoke-rt" }
}

# Only route in spoke_rt: all traffic → egress VPC (NAT GW).
# There are NO routes between spoke VPCs; spoke-to-spoke communication is impossible via TGW.
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress_sa_east_1.id
}

# ============================================================
# SOURCE: terraform/networking/vpc_app_outbound_atento_br.tf:5-137
# Finding: app-outbound-atento-br VPC = 10.12.0.0/26; both route tables have
#          lifecycle { ignore_changes = [route] } (VPN/Pritunl routes exist out-of-band).
#          Private route default: 0.0.0.0/0 → TGW (→ egress NAT, internet only).
# ============================================================

resource "aws_vpc" "app_outbound_atento_br" {
  cidr_block = "10.12.0.0/26"
  # ...
}

resource "aws_route_table" "app_outbound_atento_br_pub" {
  vpc_id = aws_vpc.app_outbound_atento_br.id
  # ...
  lifecycle {
    ignore_changes = [route]  # VGW + Pritunl out-of-band routes managed outside Terraform
  }
}

resource "aws_route_table" "app_outbound_atento_br_prv" {
  vpc_id = aws_vpc.app_outbound_atento_br.id
  # ...
  lifecycle {
    ignore_changes = [route]  # same
  }
}

resource "aws_route" "app_outbound_atento_br_pub_default" {
  route_table_id         = aws_route_table.app_outbound_atento_br_pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_outbound_atento_br.id
}

resource "aws_route" "app_outbound_atento_br_prv_default" {
  route_table_id         = aws_route_table.app_outbound_atento_br_prv.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.sa_east_1.id  # → egress VPC NAT (internet only)
}

# ============================================================
# SOURCE: terraform/networking/peering.tf:507-532
# Finding: app-outbound-atento-br ↔ Management is peered, BUT the return route from
#          Management is added only to management_PUB (not management_prv).
#          All other peeringsadd routes to both pub AND prv in Management.
#          There is NO direct peering between app-outbound-atento-br and app-atento-001.
# ============================================================

# Same-region peering: app-outbound-atento-br (sa-east-1) <-> Management (sa-east-1)
resource "aws_vpc_peering_connection" "app_outbound_atento_br_management" {
  vpc_id      = aws_vpc.app_outbound_atento_br.id
  peer_vpc_id = aws_vpc.management.id
  auto_accept = true
  tags = { Name = "4client-app-outbound-atento-br-management", Client = "atento-br" }
}

# Route in app-outbound-atento-br PRIVATE route table → Management (10.255.0.0/16)
resource "aws_route" "app_outbound_atento_br_prv_to_management" {
  route_table_id            = aws_route_table.app_outbound_atento_br_prv.id
  destination_cidr_block    = "10.255.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.app_outbound_atento_br_management.id
}

# Return route in Management PUBLIC route table only (not management_prv)
resource "aws_route" "management_to_app_outbound_atento_br" {
  route_table_id            = aws_route_table.management_pub.id   # <-- PUBLIC only
  destination_cidr_block    = "10.12.0.0/26"
  vpc_peering_connection_id = aws_vpc_peering_connection.app_outbound_atento_br_management.id
}

# ============================================================
# SOURCE: terraform/networking/peering.tf:140-160 (approximate)
# Finding: Management <-> app-atento-001 (us-east-1) is a cross-region peering;
#          routes to 10.100.12.0/22 exist in Management pub + prv tables.
#          This is the ONLY existing private path from Management to the atento-001 RDS.
# ============================================================

resource "aws_vpc_peering_connection" "app_atento_001_management" {
  vpc_id      = aws_vpc.management.id
  peer_vpc_id = aws_vpc.app_atento_001.id
  peer_region = "us-east-1"
  # ...
}
# Routes: Management pub + prv → 10.100.12.0/22 via peering (cross-region)

# ============================================================
# SOURCE: terraform/app-atento-001/rds.tf:23-53
# Finding: RDS SG allows port 5432 ONLY from:
#   (a) module.vpc_data.vpc_cidr = 10.100.12.0/22 (atento-001 VPC itself)
#   (b) 10.255.0.0/16 (Management VPC, for VPN/admin access)
#   No rule exists for 10.12.0.0/26 (app-outbound-atento-br) or any sa-east-1 CIDR.
# ============================================================

resource "aws_security_group" "rds_app_atento_001" {
  name_prefix = "app-atento-001-rds-"
  vpc_id      = module.vpc_data.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc_data.vpc_cidr]  # = 10.100.12.0/22
  }

  ingress {
    description = "PostgreSQL from VPN (Management VPC)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.255.0.0/16"]
  }
  # No ingress for 10.12.0.0/26 (app-outbound-atento-br)
}

# ============================================================
# SOURCE: terraform/modules/atento_001_task_config/main.tf:85-88
# Finding: Both the us-east-1 (app-atento-001) stack AND the sa-east-1
#          (app-outbound-atento-br) stack fetch secrets from the SAME SSM
#          parameter ARNs in us-east-1. A naive pooler SSM swap propagates
#          to the sa-east-1 worker, which may not have a path to the pooler host.
# ============================================================

secrets = [for name in local.secret_names : {
  name      = name
  valueFrom = "arn:aws:ssm:us-east-1:405749097490:parameter/atento-001/${name}"
}]

# ============================================================
# SOURCE: terraform/app-outbound-atento-br/main.tf (key vars)
# Finding: VPN to Atento corporate = static routes to 10.155.0.152/32 and
#          10.189.0.162/32 ONLY. No routes to us-east-1 RDS address space.
# ============================================================

# customer_gateway_ip      = "177.22.252.45"
# customer_network_cidrs   = ["10.155.0.152/32", "10.189.0.162/32"]

# ============================================================
# SOURCE: terraform/networking/vpc_egress_sa_east_1.tf:9 and :111-115
# Finding: Egress VPC CIDR = 10.254.0.0/27; TGW subnet default route is
#          0.0.0.0/0 → NAT GW. Return routes per spoke in the pub route table.
# ============================================================

resource "aws_vpc" "egress_sa_east_1" {
  cidr_block = "10.254.0.0/27"
  # ...
}

resource "aws_route" "egress_sa_east_1_tgw_default" {
  route_table_id         = aws_route_table.egress_sa_east_1_tgw.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.egress_sa_east_1.id
}
