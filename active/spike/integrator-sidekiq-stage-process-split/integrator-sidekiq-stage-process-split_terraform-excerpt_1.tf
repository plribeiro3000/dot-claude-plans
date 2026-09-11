# Auxiliary — Terraform reference material for the Sidekiq stage-split spike
#
# Three excerpts, each labeled with its real source path. None of this is
# proposed code — it is what exists today, kept here for side-by-side
# comparison while the options in SPIKE.md are read. Referenced from
# SPIKE.md Finding 4, Finding 5, and the "Terraform delta" section.

# =============================================================================
# 1) Current worker service definition for one client
#    Source: ~/Projects/4Shark/terraform/integrator-almaviva/main.tf:73-109
#    (byte-identical shape repeats in integrator-atento, integrator-commcenter,
#    integrator-maqnelson — every stack runs exactly one `worker` role)
# =============================================================================

# deployments.main.services (inside module "this" { ... }) —
#
#   services = {
#     web = {
#       command                           = ["bundle", "exec", "puma", "-C", "config/puma.rb"]
#       cpu                               = 512
#       memory                            = 1024
#       container_port                    = 3000
#       desired_count                     = 1
#       attach_to_alb                     = true
#       health_check_grace_period_seconds = 60
#     }
#     worker = {
#       command       = ["bundle", "exec", "sidekiq"]   # <- no -q flags: reads config/sidekiq.yml, ALL queues
#       cpu           = 512
#       memory        = 2048
#       desired_count = 2
#     }
#     runner = {
#       cpu           = 512
#       memory        = 2048
#       desired_count = 0                                # <- idle, used only via bin/ecs run
#     }
#   }
#
#   scale_up_schedules = {
#     web = {
#       cron          = "cron(55 0 * * ? *)"
#       timezone      = "UTC"
#       desired_count = 1
#       description   = "Scale up web service before processing starts"
#     }
#     worker = {
#       cron          = "cron(55 0 * * ? *)"
#       timezone      = "UTC"
#       desired_count = 2
#       description   = "Scale up worker service before processing starts"
#     }
#   }

# =============================================================================
# 2) The module's `services` and `scale_up_schedules` variable schema
#    Source: ~/Projects/4Shark/terraform/modules/integrator/variables.tf:66-81
#    This is what makes a new named service (e.g. a Load-only worker) a
#    stack-level tfvars addition, not a module change — the map already
#    accepts an arbitrary set of role keys, each with its own `command`.
# =============================================================================

#     services = map(object({
#       command                           = optional(list(string), [])
#       cpu                               = number
#       memory                            = number
#       desired_count                     = number
#       container_port                    = optional(number)
#       attach_to_alb                     = optional(bool, false)
#       health_check_grace_period_seconds = optional(number)
#     }))
#     scale_up_schedules = optional(map(object({
#       cron          = string
#       timezone      = string
#       desired_count = number
#       description   = string
#       state         = optional(string, "ENABLED")
#     })), {})

# =============================================================================
# 3) The ONLY existing IAM grant for ecs:UpdateService in this module today —
#    held by the EventBridge Scheduler's role, NOT by the ECS task role.
#    Source: ~/Projects/4Shark/terraform/modules/integrator/deployments_alb.tf:218-248
#    A worker calling ecs:UpdateService from INSIDE the task needs an
#    equivalent statement attached to aws_iam_role.ecs_task_execution instead
#    (modules/integrator/iam_task_role.tf) — that role currently grants only
#    ECR/logs (AmazonECSTaskExecutionRolePolicy), a scoped ssm:GetParameters +
#    kms:Decrypt, and the ECS Exec ssmmessages:* actions. No ecs:UpdateService
#    or ecs:DescribeServices statement exists on it.
# =============================================================================

# resource "aws_iam_role" "deployments_scheduler" {
#   assume_role_policy = jsonencode({
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "scheduler.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }
#
# resource "aws_iam_role_policy" "deployments_scheduler" {
#   role = aws_iam_role.deployments_scheduler[0].id
#   policy = jsonencode({
#     Statement = concat([
#       {
#         Effect   = "Allow"
#         Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
#         Resource = "arn:aws:ecs:sa-east-1:405749097490:service/${local.name_prefix}${local.scheduler_cluster_wildcard}-cluster/*"
#       },
#       # ... (a second statement follows, not read in this session)
#     ])
#   })
# }
