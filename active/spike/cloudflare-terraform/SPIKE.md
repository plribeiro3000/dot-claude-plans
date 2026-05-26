# SPIKE — Cloudflare Terraform Automation and Import

> **Question:** How to bring all Cloudflare configuration under Terraform management and set up Cloudflare protection for the new Pritunl VPN?

## Status: COMPLETE

---

## Findings

### 1. API Token

Use **API Token** (not Global API Key — legacy). Required permissions:

| Permission Group | Level |
|-----------------|-------|
| Zone: DNS | Edit |
| Zone: Zone | Read |
| Zone: Zone Settings | Edit |
| Zone: WAF | Edit |
| Zone: SSL and Certificates | Edit |

Created via: Cloudflare Dashboard → Profile → API Tokens → Create Custom Token. Store in 1Password and as environment variable `CLOUDFLARE_API_TOKEN`.

### 2. Discovery — List All Zones

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
  jq '.result[] | {id: .id, name: .name}'
```

### 3. cf-terraforming — Import Tool

Official Cloudflare tool. Install: `brew tap cloudflare/cloudflare && brew install cloudflare/cloudflare/cf-terraforming`.

Workflow:
```bash
# 1. Generate HCL
cf-terraforming generate --resource-type "cloudflare_record" --zone $ZONE_ID > dns.tf

# 2. Generate import blocks (Terraform >= 1.5)
cf-terraforming import --resource-type "cloudflare_record" --zone $ZONE_ID --modern-import-block > import_dns.tf

# 3. Review and rename resources (UUID names by default)
# 4. terraform plan && terraform apply
# 5. terraform plan → should return "No changes"
```

**Limitations:** One-time migration tool, not for CI/CD. Some generated resources may fail `terraform validate` due to schema inconsistencies in provider v5.

### 4. Provider Setup

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "4shark-terraform-state"
    key    = "cloudflare/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "cloudflare" {
  # Reads CLOUDFLARE_API_TOKEN from environment
}
```

### 5. Available Resources

**Critical for the use case:**
- `cloudflare_record` — DNS records (proxied or not)
- `cloudflare_zone_setting` — SSL, TLS, HTTPS rewrites (v5, individual per setting)
- `cloudflare_ruleset` — WAF managed rules, WAF custom rules, rate limiting
- `data.cloudflare_ip_ranges` — Cloudflare IPs for AWS security groups

**WARNING:** `cloudflare_rate_limit` and `cloudflare_firewall_rule` were **removed on 2025-06-15**. Use `cloudflare_ruleset` exclusively.

### 6. Recommended Architecture

```
terraform/
├── cloudflare/          # NEW root module — all zones
│   ├── providers.tf
│   ├── variables.tf
│   ├── dns.tf
│   ├── zone_settings.tf
│   ├── waf.tf
│   └── rate_limiting.tf
└── vpn/
    ├── cloudflare.tf    # NEW — VPN-specific config
    └── ...              # existing
```

Cloudflare recommends **not using modules** for Cloudflare resources — use flat `.tf` files organized by product.

### 7. Pritunl-Specific Configuration

**Critical note:** VPN UDP traffic (port 14720) **does NOT go through Cloudflare proxy** — Cloudflare only proxies TCP 80/443. The web panel HTTPS can be protected, but VPN clients connect directly to the origin IP via UDP.

**Requirement before enabling SSL strict:** The Pritunl server needs a valid TLS certificate. Use Cloudflare Origin CA.

Example configuration:
```hcl
# DNS proxied
resource "cloudflare_record" "vpn_web" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn"
  type    = "A"
  content = module.pritunl.public_ip
  proxied = true
  ttl     = 1
}

# SSL Full Strict
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

# Rate limiting on VPN web panel
resource "cloudflare_ruleset" "vpn_rate_limit" {
  zone_id = var.cloudflare_zone_id
  name    = "VPN web panel rate limiting"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules {
    ref         = "rate_limit_vpn_login"
    description = "Rate limit VPN admin panel by IP"
    expression  = "(http.host eq \"vpn.4shark.com\")"
    action      = "block"
    ratelimit {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 60
      requests_per_period = 30
      mitigation_timeout  = 600
    }
  }
}

# AWS SG: restrict HTTPS to Cloudflare IPs only
data "cloudflare_ip_ranges" "cloudflare" {}

resource "aws_security_group_rule" "cloudflare_https" {
  count             = length(data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks)
  type              = "ingress"
  security_group_id = module.pritunl.security_group_id
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks[count.index]]
  description       = "HTTPS from Cloudflare"
}
```

---

## Decisions Required Before Implementation

1. **Zone IDs and real domains** — discover via API or dashboard
2. **Pritunl TLS certificate** — required for `ssl = "strict"`. Use Cloudflare Origin CA
3. **Cloudflare account plan** (Free/Pro/Business/Enterprise) — affects which WAF features are available
4. **VPN public domain** — current record is `vpn.4shark.internal` (Route53 private). Cloudflare needs a public domain
5. **Existing WAF/rate limit rules** — any rules created via deprecated resources that need migration?

---

## Sources

- [Cloudflare Terraform provider documentation](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Import Cloudflare resources guide](https://developers.cloudflare.com/terraform/advanced-topics/import-cloudflare-resources/)
- [cf-terraforming GitHub repository](https://github.com/cloudflare/cf-terraforming)
- [Cloudflare Terraform best practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)
- [API token permissions reference](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)
- [Rate limiting Terraform configuration](https://developers.cloudflare.com/terraform/additional-configurations/rate-limiting-rules/)
- [WAF Managed Rules Terraform configuration](https://developers.cloudflare.com/terraform/additional-configurations/waf-managed-rulesets/)
- [WAF Custom Rules Terraform configuration](https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/)
- [cloudflare_ip_ranges data source](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/ip_ranges)
