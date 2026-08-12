# Excerpt copied for line-by-line reference during the spike.
# Source: modules/cloudflare_zone_security/main.tf:152-177 (terraform repository)

# =============================================================================
# Rate Limiting (http_ratelimit phase)
# =============================================================================

resource "cloudflare_ruleset" "rate_limiting" {
  zone_id     = var.zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "limit_api"
      description = "Limit API"
      action      = "block"
      expression  = "(starts_with(http.request.uri.path, \"/api\"))"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = var.rate_limit_period
        requests_per_period = var.rate_limit_requests
        mitigation_timeout  = var.rate_limit_period
      }
    },
  ]
}

# -----------------------------------------------------------------------------
# Source: modules/cloudflare_zone_security/variables.tf:24-34
# -----------------------------------------------------------------------------

variable "rate_limit_period" {
  description = "Rate limit evaluation period in seconds."
  type        = number
  default     = 10
}

variable "rate_limit_requests" {
  description = "Maximum requests allowed per period before blocking."
  type        = number
  default     = 1500
}

# -----------------------------------------------------------------------------
# The line that couples the two knobs:
#
#   mitigation_timeout  = var.rate_limit_period
#
# There is no `rate_limit_mitigation_timeout` variable. The block duration is
# not merely SET to the same value as the counting period — it is structurally
# bound to it, so the two cannot be given different values without changing the
# module. Neither variable is overridden by any of the five callers, so every
# zone runs on the defaults: period 10s, threshold 1500, mitigation 10s.
# -----------------------------------------------------------------------------
