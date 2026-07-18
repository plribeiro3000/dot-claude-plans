# Auxiliary — internal Terraform excerpts cited in SPIKE.md
# Preserved verbatim from ~/Projects/4Shark/terraform, each tagged with source
# path and the SPIKE.md Finding it backs. Not meant to be applied/run.

# =============================================================================
# modules/redis_cloud/README.md:92-98 — network path (no VPC peering)
# =============================================================================
# ## Known Limitations
#
# - `plan_id` and `payment_method_id` are Redis Cloud-specific identifiers that must be
#   obtained from the Redis Cloud console — they are not discoverable via the Terraform
#   provider data sources.
# - Redis Cloud Essentials does not support VPC peering — connectivity is over the public
#   internet with TLS encryption enforced.

# =============================================================================
# source_ips across all four stacks — re-confirmed this revision by direct grep
# =============================================================================
# app-shared-001/redis.tf:14   source_ips = ["0.0.0.0/0"]   (cache module)
# app-shared-001/redis.tf:40   source_ips = ["0.0.0.0/0"]   (sidekiq module)
# app-atento-001/redis.tf:14   source_ips = ["0.0.0.0/0"]   (cache module)
# app-atento-001/redis.tf:40   source_ips = ["0.0.0.0/0"]   (sidekiq module)
# app-beta-001/redis.tf:14     source_ips = ["0.0.0.0/0"]   (single combined module)
# app-demo-001/redis.tf:14     source_ips = ["0.0.0.0/0"]   (single combined module, structurally
#                                                             identical to beta-001, subscription/
#                                                             database name "Demo001")

# =============================================================================
# app-shared-001/ssm.tf (full) — dedicated REDIS_SIDEKIQ_URL parameter
# =============================================================================
# locals {
#   ssm_secret_names = toset([
#     ... , "REDIS_SIDEKIQ_URL", ...   # line 17
#   ])
# }
#
# resource "aws_ssm_parameter" "secrets" {
#   for_each = local.ssm_secret_names
#   name  = "/shared-001/${each.key}"     # line 28
#   type  = "SecureString"
#   value = "PLACEHOLDER"
#   lifecycle {
#     ignore_changes = [value]
#   }
# }

# =============================================================================
# app-atento-001/ssm.tf (full) — also a dedicated REDIS_SIDEKIQ_URL parameter
# =============================================================================
# locals {
#   ssm_secret_names = toset([
#     "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "CURRENCY_API_KEY",
#     "DATA_DOG_API_KEY", "DATA_DOG_APPLICATION_KEY", "DATABASE_REPLICA_URL",
#     "DATABASE_URL", "HIREFIRE_TOKEN", "NEW_RELIC_LICENSE_KEY",
#     "OPENSEARCH_PASSWORD", "OPENSEARCH_USER", "RAILS_MASTER_KEY",
#     "REDIS_CACHE_URL", "REDIS_LOCK_URL", "REDIS_SIDEKIQ_URL", "REDIS_URL",
#     "ROLLBAR_CLIENT_ACCESS_TOKEN", "ROLLBAR_SERVER_ACCESS_TOKEN", "SECRET_KEY_BASE",
#   ])
# }
# resource "aws_ssm_parameter" "secrets" {
#   for_each = local.ssm_secret_names
#   name  = "/atento-001/${each.key}"
#   type  = "SecureString"
#   value = "PLACEHOLDER"
#   lifecycle { ignore_changes = [value] }
# }

# =============================================================================
# app-beta-001/ssm.tf and app-demo-001/ssm.tf (full, structurally identical
# except the name prefix) — NO "REDIS_SIDEKIQ_URL" entry in the secret list;
# only "REDIS_URL" exists, because beta-001/demo-001 provision ONE combined
# Redis Cloud database for both cache and Sidekiq (see redis.tf excerpt above)
# =============================================================================
# locals {
#   ssm_secret_names = toset([
#     "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "CURRENCY_API_KEY",
#     "DATA_DOG_API_KEY", "DATA_DOG_APPLICATION_KEY", "DATABASE_URL",
#     "GRAPHQL_INTROSPECTION_TOKEN", "HIREFIRE_TOKEN", "NEW_RELIC_LICENSE_KEY",
#     "RAILS_MASTER_KEY", "REDIS_LOCK_URL", "REDIS_URL",
#     "ROLLBAR_CLIENT_ACCESS_TOKEN", "ROLLBAR_SERVER_ACCESS_TOKEN", "SECRET_KEY_BASE",
#   ])
# }
# resource "aws_ssm_parameter" "secrets" {
#   for_each = local.ssm_secret_names
#   name  = "/beta-001/${each.key}"    # (or /demo-001/ in the sibling file)
#   type  = "SecureString"
#   value = "PLACEHOLDER"
#   lifecycle { ignore_changes = [value] }
# }
#
# Both ssm.tf files carry the same header comment (verbatim, beta-001 shown):
#   # Sensitive environment variables are stored as SecureString parameters.
#   # Values are NOT managed by Terraform after initial creation (ignore_changes).
#   # To set or rotate a value:
#   #   aws ssm put-parameter \
#   #     --name "/beta-001/<NAME>" \
#   #     --value "<VALUE>" \
#   #     --type SecureString \
#   #     --overwrite \
#   #     --region us-east-1

# =============================================================================
# ecs_ssm_read IAM policy (all four stacks, shape identical) — NOTE: this
# grants ssm:GetParameters + kms:Decrypt to `ecsTaskExecutionRole`, a
# DIFFERENT principal than the default read-only AWS profile Claude Code
# uses. The live test in SPIKE.md's Finding did NOT go through this policy —
# it went through whatever grant the default profile's own IAM identity
# (arn:aws:iam::405749097490:user/paulo@4shark.com.br, confirmed via
# `aws sts get-caller-identity`) carries. This policy is included for
# completeness on how the ECS task itself gets the value at runtime, not as
# an explanation of why the live test succeeded.
# =============================================================================
# resource "aws_iam_role_policy" "ecs_ssm_read" {
#   name = "<stack>-ssm-read"
#   role = "ecsTaskExecutionRole"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       { Effect = "Allow", Action = ["ssm:GetParameters"],
#         Resource = ["arn:aws:ssm:us-east-1:405749097490:parameter/<stack>/*"] },
#       { Effect = "Allow", Action = ["kms:Decrypt"],
#         Resource = ["arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03"] }
#     ]
#   })
# }

# =============================================================================
# app-shared-001/.envrc:16-17, app-atento-001/.envrc:16-17,
# app-beta-001/.envrc:16-17, app-demo-001/.envrc:16-17 (identical shape) —
# a DIFFERENT Redis credential entirely: the Redis Cloud PROVIDER's own API
# key, used by Terraform to manage the rediscloud_essentials_* resources
# themselves (create/modify the subscription and database). This is NOT the
# database connection credential the app's Sidekiq client uses, and NOT
# usable to connect to the Sidekiq Redis as a client.
# =============================================================================
# export REDISCLOUD_ACCESS_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_ACCESS_KEY").value')"
# export REDISCLOUD_SECRET_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_SECRET_KEY").value')"
