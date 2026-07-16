// RAW CODE EXCERPTS — the resources this SPIKE reasons about.
// Copied verbatim from ~/Projects/4Shark/terraform on 2026-07-15 for line-by-line reference.
// Each block is labelled with its source file and line range. NOT a runnable configuration.

// =============================================================================
// [1] modules/ecs_service/main.tf:12-65 — the task definition resource.
// Terraform OWNS the content (the lifecycle block at :64 is EMPTY).
// Note :33 `secrets = var.secrets` — this is where the SSM ARNs land.
// Note :45-52 logConfiguration — `awslogs-create-group` is absent, so the
// log group must pre-exist for a task to start.
// =============================================================================

resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  requires_compatibilities = [var.launch_type]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name              = var.container_name
      image             = var.image
      cpu               = var.container_cpu
      memoryReservation = var.launch_type == "FARGATE" ? null : var.container_memory_reservation
      memory            = var.container_memory
      essential         = true

      command     = length(var.command) > 0 ? var.command : null
      entryPoint  = length(var.entrypoint) > 0 ? var.entrypoint : null
      environment = local.environment_list
      secrets     = var.secrets

      # EC2 bridge: hostPort = 0 para port mapping dinâmico (múltiplas tasks por EC2).
      # Fargate awsvpc: hostPort = containerPort (cada task tem IP próprio).
      portMappings = var.container_port == null ? [] : [{
        containerPort = var.container_port
        hostPort      = var.launch_type == "FARGATE" ? var.container_port : 0
        protocol      = "tcp"
      }]

      healthCheck = var.health_check

      logConfiguration = var.enable_cloudwatch_logging ? {
        logDriver = "awslogs"
        options = {
          awslogs-group         = try(aws_cloudwatch_log_group.this[0].name, local.log_group_name)
          awslogs-region        = data.aws_region.current.id
          awslogs-stream-prefix = "ecs"
        }
      } : null
    }
  ])

  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value.name
      host_path = try(volume.value.host_path, null)
    }
  }

  lifecycle {}   // <-- line 64. EMPTY. See taskdef-drift_git_1.txt (commit 13d32a0).
}

// =============================================================================
// [2] modules/ecs_service/main.tf:152-163 — the SERVICE lifecycle.
// THIS is the trap: task_definition (the POINTER) is ignored, so the service
// is never moved onto the revision Terraform just registered in [1].
// =============================================================================

  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition, # CodeDeploy gerencia a task definition durante deployments
      load_balancer,   # CodeDeploy gerencia os target groups durante blue/green deployments
    ]

    # Force service replacement when target group is replaced (e.g., VPC migration).
    # TG has vpc_id as ForceNew, so VPC change → TG replaced → TG ARN changes →
    # terraform_data changes → service replaced with correct TG reference.
    replace_triggered_by = [terraform_data.lb_config]
  }

// =============================================================================
// [3] modules/ecs_service/main.tf:81 — force_new_deployment is DISABLED for
// CodeDeploy services and left to a variable (default true) otherwise.
// It only takes effect if Terraform actually updates the service resource —
// and with task_definition ignored, a revision-only change produces no update.
// =============================================================================

  force_new_deployment = var.deployment_controller_type == "CODE_DEPLOY" ? false : var.force_new_deployment

// =============================================================================
// [4] modules/ecs_service/main.tf:1-10 — the log group IS terraform-managed,
// with NO ignore_changes. Terraform can destroy it. A live revision that names
// a destroyed group fails to launch (see taskdef-drift_sources_1.md S6).
// =============================================================================

resource "aws_cloudwatch_log_group" "this" {
  count = var.enable_cloudwatch_logging && var.create_cloudwatch_log_group ? 1 : 0

  name              = var.cloudwatch_log_group_use_name_prefix ? null : local.log_group_name
  name_prefix       = var.cloudwatch_log_group_use_name_prefix ? "${local.log_group_name}-" : null
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = var.tags
}

// =============================================================================
// [5] modules/connection_pooler/main.tf:361-363 — the SECOND module with the
// same trap shape. Same ignore, no CodeDeploy here (deployment_controller is
// "ECS", :352-354).
// =============================================================================

  deployment_controller {
    type = "ECS"
  }

  // ... :361-363:
  lifecycle {
    ignore_changes = [task_definition]
  }

// =============================================================================
// [6] modules/ecs_scheduled_task/main.tf:83 — THE CONTRAST CASE.
// No ignore_changes anywhere in this module. The EventBridge target strips the
// revision suffix so it tracks the FAMILY, i.e. always resolves to the newest
// ACTIVE revision at invocation time. Terraform registers a new revision and the
// next scheduled run picks it up — no pinned-old-revision window exists.
// =============================================================================

    ecs_parameters {
      task_definition_arn = replace(aws_ecs_task_definition.this.arn, "/:\\d+$/", "")
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = var.subnets
        security_groups  = var.security_groups
        assign_public_ip = false
      }
    }

// =============================================================================
// [7] app-demo-001/ssm.tf:35-72 — the two Q4 resource classes, in one file.
// (a) The 15 SSM parameters ARE terraform-managed. `ignore_changes = [value]`
//     means Terraform owns EXISTENCE but not the value — destroying the resource
//     destroys the parameter, which is exactly what terraform #711 did.
// (b) The IAM role POLICY is terraform-managed and attached to a role that is
//     NOT. Destroying this policy removes ssm:GetParameters + kms:Decrypt for
//     EVERY secret at once — a wider blast radius than any single parameter.
// =============================================================================

resource "aws_ssm_parameter" "secrets" {
  for_each = local.ssm_secret_names

  name  = "/demo-001/${each.key}"
  type  = "SecureString"
  value = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role_policy" "ecs_ssm_read" {
  name = "demo-001-ssm-read"
  role = "ecsTaskExecutionRole"    // <-- referenced by NAME; the role itself is not a TF resource

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameters"]
        Resource = [
          "arn:aws:ssm:us-east-1:405749097490:parameter/demo-001/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03"]
      }
    ]
  })
}

// =============================================================================
// [8] app/.github/workflows/deploy-beta-001.yaml:418 — the actual out-of-band
// mutator. GitHub Actions registers a task definition revision itself. This is
// what the module's ignore_changes is really accommodating for WORKER services
// (which use the plain ECS controller, not CodeDeploy — see the AWS dump).
// =============================================================================

          TASK_DEF_ARN=$(aws ecs register-task-definition \
          // ... (line 429): --task-definition "${TASK_DEF_ARN}" \

// =============================================================================
// [9] Full ignore_changes inventory across modules/ (grep, 2026-07-15).
// Only ecs_service and connection_pooler carry the task_definition shape.
// The rest ignore VALUES/VERSIONS (passwords, engine versions, AMIs), which is
// a different pattern: those do not gate whether a new task can be launched.
// =============================================================================

//  connection_pooler/main.tf:362     ignore_changes = [task_definition]          <-- trap shape
//  ecs_service/main.tf:153           ignore_changes = [desired_count, task_definition, load_balancer]  <-- trap shape
//  pritunl/main.tf:28                ignore_changes = [ami, user_data, user_data_base64]
//  opensearch/main.tf:130            ignore_changes = [engine_version]
//  mongodb_atlas/database_users.tf:30 ignore_changes = [password]
//  mongodb_atlas/main.tf:8           ignore_changes = [teams]
//  rds_instance/main.tf:51           ignore_changes = [password, engine_version]
//  public_alb/main.tf:190,208,228,248 ignore_changes = [default_action]
//  public_alb/main.tf:277            ignore_changes = [action]
//  internal_alb/main.tf:164          ignore_changes = [default_action]
//  internal_alb/main.tf:188          ignore_changes = [action]
//  codedeploy/main.tf:223            ignore_changes = [source_code_hash, last_modified]
//  codedeploy/main.tf:247            ignore_changes = [source_arn]
//  redis_cloud/main.tf:39            ignore_changes = [password]
//  rds_aurora_cluster/main.tf:35     ignore_changes = [master_password, availability_zones, engine_version]
//  rds_aurora_cluster/main.tf:68     ignore_changes = [engine_version]
