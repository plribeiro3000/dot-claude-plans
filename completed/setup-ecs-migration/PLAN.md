# Plan: Setup Project — Migration from EC2 to ECS with Blue/Green Deployment

## Context

The `setup` project is a Rails 8.1 API-only application that serves as the **single source of truth** for mobile app configuration (iOS and Android). It currently runs on EC2 instances with no containerized deployment infrastructure.

This plan migrates the compute layer from EC2 to ECS with blue/green deployment via CodeDeploy, following the same patterns as the `app` project. The database (RDS) and other infrastructure already exist — only the compute/deploy layer changes.

**Key decisions:**
- **Naming**: `setup` (no `-001` suffix — this is a unique, centralized service, not a multi-instance environment)
- **Cluster**: dedicated ECS cluster (not shared with `app`)
- **VPC**: Production
- **Domain**: `setup.app4shark.com` (DNS managed in Cloudflare, not Route53)
- **Terraform**: same repo as app, new directory `terraform/setup/`
- **Duplication strategy**: all GitHub Actions code is duplicated from app (not shared). Maintenance cost of duplication is lower than over-engineering a shared solution.
- **Environment variables**: managed by the user directly in GitHub Actions environment configuration. Not part of this plan.

**Estimated monthly cost: ~$50-55 USD**
| Resource | Estimate |
|----------|----------|
| EC2 (2x t3a.small) | ~$27/month |
| ALB | ~$20/month |
| CloudWatch Logs | ~$3-5/month |
| ECR | ~$1-2/month |
| RDS | Already exists (no new cost) |

---

## Scope

4 workstreams across 2 repositories:

| # | Workstream | Repository | Files |
|---|-----------|------------|-------|
| 1 | Terraform infrastructure | `terraform/setup/` | 5 files |
| 2 | Health check endpoint | `setup/` | 2 files (1 new, 1 modified) |
| 3 | Dockerfile + version | `setup/` | 2 new files |
| 4 | GitHub Actions workflow | `setup/` | 2 new files |

---

## Pre-requisites (before implementation)

1. **RDS Security Group**: verify the existing RDS security group allows inbound traffic from the Production VPC private subnets (where ECS tasks will run). If not, add a rule.
2. **ACM Certificate**: the wildcard `*.app4shark.com` certificate already exists: `arn:aws:acm:us-east-1:405749097490:certificate/6789893d-2c48-452a-90ea-3f2fc9ca8e35`
3. **S3 Terraform State Bucket**: `4shark-terraform-state` already exists (used by other environments)
4. **GitHub Environment**: create a `setup` environment in the setup repository's GitHub settings (for secrets/variables)

---

## 1. Terraform Infrastructure (`terraform/setup/`)

### 1.1 `terraform/setup/providers.tf`

```hcl
provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket = "4shark-terraform-state"
    key    = "setup/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### 1.2 `terraform/setup/variables.tf`

```hcl
variable "environment" {
  description = "Environment identifier"
  type        = string
}

variable "vpc_name" {
  description = "Name of the existing VPC to use"
  type        = string
}

variable "subnet_name_prefix" {
  description = "Prefix for subnet name tags (e.g., 'production' for production-prv-*). Defaults to vpc_name."
  type        = string
  default     = null
}

## ECS Cluster
variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "volume_size" {
  description = "EBS volume size in GB"
  type        = number
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address"
  type        = bool
}

variable "manage_iam" {
  description = "If true, creates IAM role and instance profile for ECS"
  type        = bool
  default     = false
}

# Capacity
variable "web_min_size" {
  description = "Minimum ASG size for web"
  type        = number
  default     = 0
}

variable "web_max_size" {
  description = "Maximum ASG size for web"
  type        = number
  default     = 6
}

# ALB
variable "alb_record_name" {
  description = "FQDN for the ALB (used for tagging, DNS is managed in Cloudflare)"
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed in ALB security group"
  type        = list(string)
}

variable "enable_blue_green" {
  description = "Enable blue/green deployment resources"
  type        = bool
  default     = false
}

variable "production_listener_rule_priority" {
  description = "Priority of the production listener rule"
  type        = number
  default     = 100
}

variable "blue_green_test_path" {
  description = "Path for blue/green test listener rule"
  type        = string
  default     = "/bg-test*"
}

variable "blue_green_test_priority" {
  description = "Priority of the blue/green test listener rule"
  type        = number
  default     = 50
}

# AWS
variable "aws_account_id" {
  type        = string
  description = "AWS Account ID"
}

# Services
variable "services" {
  description = "Map of ECS services to create"
  type        = any
  default     = {}
}
```

### 1.3 `terraform/setup/terraform.tfvars`

```hcl
environment        = "setup"
vpc_name           = "Production"
subnet_name_prefix = "production"

# ECS Cluster
key_name                    = "4Shark-key"
instance_type               = "t3a.small"
volume_size                 = 30
volume_type                 = "gp3"
associate_public_ip_address = false
manage_iam                  = true

# Capacity
web_min_size = 2
web_max_size = 6

# ALB (DNS managed in Cloudflare, not Route53)
alb_record_name   = "setup.app4shark.com"
alb_ingress_cidrs = ["0.0.0.0/0"]
enable_blue_green = true

# AWS
aws_account_id = "405749097490"

# Services
services = {
  setup-web-service = {
    task_family                  = "setup-web"
    container_name               = "setup-web"
    image                        = "405749097490.dkr.ecr.us-east-1.amazonaws.com/setup-web:latest"
    task_cpu                     = 1024
    task_memory                  = 1024
    container_cpu                = 0
    container_memory             = null
    container_memory_reservation = null
    container_port               = 3000
    desired_count                = 2
    deployment_strategy          = "BLUE_GREEN"
    bake_time_in_minutes         = 2
    enable_execute_command       = true

    execution_role_arn = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
    task_role_arn      = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"

    cloudwatch_log_group_name              = "/ecs/setup-web"
    create_cloudwatch_log_group            = true
    cloudwatch_log_group_retention_in_days = 30
    enable_cloudwatch_logging              = true
  }
}
```

### 1.4 `terraform/setup/main.tf`

```hcl
# =============================================================================
# Locals
# =============================================================================
locals {
  environment = var.environment

  # Resource naming
  role_name            = "${var.environment}-ecs-instance-role"
  ecs_instance_profile = "${var.environment}-ecs-instance-profile"
  sgname               = "${var.environment}-ecs-sg"
  alb_name_prefix      = "${var.environment}-pub"
  service_with_alb     = "${var.environment}-web-service"

  # ECR repositories derived from services map
  ecr_repositories = toset([
    for k, v in var.services :
    regex("^.*/([^:]+):.*$", v.image)[0]
  ])

  tags = {
    Environment = var.environment
    Automation  = "terraform"
    Cluster     = "${var.environment}-cluster"
  }

  # Service enrichment: add ALB + CODE_DEPLOY config to web service
  services = {
    for k, v in var.services :
    k => merge(
      v,
      {
        env = merge(
          lookup(v, "env", {}),
          { ALB_HOSTNAME = module.public_alb.alb_dns_name }
        )
        load_balancers                     = lookup(v, "load_balancers", [])
        deployment_controller_type         = lookup(v, "deployment_controller_type", null)
        deployment_minimum_healthy_percent = lookup(v, "deployment_minimum_healthy_percent", 50)
        deployment_maximum_percent         = lookup(v, "deployment_maximum_percent", 200)
        enable_deployment_circuit_breaker  = lookup(v, "enable_deployment_circuit_breaker", true)
        deployment_rollback                = lookup(v, "deployment_rollback", true)
        create_cloudwatch_log_group        = lookup(v, "create_cloudwatch_log_group", false)
      },
      k == local.service_with_alb ? {
        load_balancers = [{
          target_group_arn = module.public_alb.target_group_arn
          container_name   = lookup(v, "container_name", k)
          container_port   = lookup(v, "container_port", null)
        }]
        advanced_configuration             = null
        deployment_controller_type         = "CODE_DEPLOY"
        deployment_minimum_healthy_percent = 100
        deployment_maximum_percent         = 200
        deployment_strategy                = null
        bake_time_in_minutes               = null
        enable_deployment_circuit_breaker  = false
        deployment_rollback                = false
        } : {
        load_balancers                     = lookup(v, "load_balancers", [])
        advanced_configuration             = lookup(v, "advanced_configuration", null)
        deployment_controller_type         = lookup(v, "deployment_controller_type", null)
        deployment_minimum_healthy_percent = lookup(v, "deployment_minimum_healthy_percent", 50)
        deployment_maximum_percent         = lookup(v, "deployment_maximum_percent", 200)
        deployment_strategy                = lookup(v, "deployment_strategy", null)
        bake_time_in_minutes               = lookup(v, "bake_time_in_minutes", null)
        enable_deployment_circuit_breaker  = lookup(v, "enable_deployment_circuit_breaker", true)
        deployment_rollback                = lookup(v, "deployment_rollback", true)
      }
    )
  }
}

# =============================================================================
# Data Sources
# =============================================================================
data "aws_ami" "ecs_optimized" {
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }

  most_recent = true
  owners      = ["amazon"]
}

# =============================================================================
# VPC Data
# =============================================================================
module "vpc_data" {
  source             = "../modules/vpc_data"
  vpc_name           = var.vpc_name
  subnet_name_prefix = var.subnet_name_prefix
}

# =============================================================================
# ALB (no Route53 — DNS managed in Cloudflare)
# =============================================================================
module "public_alb" {
  source = "../modules/public_alb"

  name_prefix       = local.alb_name_prefix
  vpc_id            = module.vpc_data.vpc_id
  subnet_ids        = module.vpc_data.public_ids
  record_name       = var.alb_record_name
  alb_ingress_cidrs = var.alb_ingress_cidrs
  tags              = local.tags

  enable_blue_green                 = var.enable_blue_green
  manage_default_action             = true
  production_listener_rule_priority = var.production_listener_rule_priority
  blue_green_test_path              = var.blue_green_test_path
  blue_green_test_priority          = var.blue_green_test_priority

  # HTTPS with ACM wildcard certificate
  certificate_arn = "arn:aws:acm:us-east-1:405749097490:certificate/6789893d-2c48-452a-90ea-3f2fc9ca8e35"

  # Health check optimized for fast deploys
  health_check_path                = "/health"
  health_check_matcher             = "200-399"
  health_check_interval            = 10
  health_check_timeout             = 5
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 3

  # Faster rollbacks
  deregistration_delay = 30

  # No public_zone_id — Route53 record is NOT created (DNS in Cloudflare)
}

# =============================================================================
# ECS Cluster
# =============================================================================
module "ecs_cluster" {
  depends_on = [module.ecr]
  source     = "../modules/ecs_cluster"

  vpc_id                      = module.vpc_data.vpc_id
  subnets                     = module.vpc_data.private_ids
  key_name                    = var.key_name
  create_key_pair             = false
  instance_type               = var.instance_type
  ami_id                      = data.aws_ami.ecs_optimized.id
  volume_size                 = var.volume_size
  volume_type                 = var.volume_type
  associate_public_ip_address = var.associate_public_ip_address
  role_name                   = local.role_name
  tags                        = local.tags
  environment                 = local.environment
  sgname                      = local.sgname
  ecs_instance_profile        = local.ecs_instance_profile
  manage_iam                  = var.manage_iam

  # No shared ASG — dedicated Capacity Provider below
  create_asg = false
}

# =============================================================================
# Cluster Capacity Provider (web only — no workers)
# =============================================================================
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = module.ecs_cluster.ecs_cluster_name

  capacity_providers = [
    module.capacity_web.capacity_provider_name,
  ]

  default_capacity_provider_strategy {
    capacity_provider = module.capacity_web.capacity_provider_name
    weight            = 1
    base              = 0
  }
}

module "capacity_web" {
  source = "../modules/ecs_capacity"

  name                        = "${var.environment}-web"
  cluster_name                = module.ecs_cluster.ecs_cluster_name
  ami_id                      = data.aws_ami.ecs_optimized.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnets                     = module.vpc_data.private_ids
  security_groups             = [module.ecs_cluster.security_group_id]
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile_name   = local.ecs_instance_profile
  volume_size                 = var.volume_size
  volume_type                 = var.volume_type
  min_size                    = var.web_min_size
  max_size                    = var.web_max_size
  tags = merge(local.tags, {
    Role    = "web"
    Service = "web"
  })

  enable_managed_scaling     = true
  enable_managed_termination = false
  enable_managed_draining    = true

  depends_on = [module.ecs_cluster]
}

# =============================================================================
# ECS Service (web only)
# =============================================================================
locals {
  service_capacity_providers = {
    "${var.environment}-web-service" = module.capacity_web.capacity_provider_name
  }
}

module "ecs_services" {
  source      = "../modules/ecs_service"
  for_each    = local.services
  environment = var.environment
  depends_on  = [module.ecs_cluster]

  cluster_name      = module.ecs_cluster.ecs_cluster_name
  capacity_provider = local.service_capacity_providers[each.key]

  service_name   = each.key
  task_family    = lookup(each.value, "task_family", each.key)
  container_name = lookup(each.value, "container_name", each.key)

  image  = each.value.image
  cpu    = each.value.task_cpu
  memory = each.value.task_memory

  container_cpu                      = lookup(each.value, "container_cpu", null)
  container_memory                   = lookup(each.value, "container_memory", null)
  container_memory_reservation       = lookup(each.value, "container_memory_reservation", null)
  container_port                     = lookup(each.value, "container_port", null)
  desired_count                      = lookup(each.value, "desired_count", 1)
  environment_variables              = lookup(each.value, "env", {})
  secrets                            = lookup(each.value, "secrets", [])
  command                            = lookup(each.value, "command", [])
  entrypoint                         = lookup(each.value, "entrypoint", [])
  health_check                       = lookup(each.value, "health_check", null)
  volumes                            = lookup(each.value, "volumes", [])
  load_balancers                     = lookup(each.value, "load_balancers", [])
  execution_role_arn                 = lookup(each.value, "execution_role_arn", null)
  task_role_arn                      = lookup(each.value, "task_role_arn", null)
  capacity_provider_weight           = lookup(each.value, "capacity_provider_weight", 1)
  capacity_provider_base             = lookup(each.value, "capacity_provider_base", 0)
  deployment_minimum_healthy_percent = lookup(each.value, "deployment_minimum_healthy_percent", 50)
  deployment_maximum_percent         = lookup(each.value, "deployment_maximum_percent", 200)
  enable_deployment_circuit_breaker  = lookup(each.value, "enable_deployment_circuit_breaker", true)
  deployment_rollback                = lookup(each.value, "deployment_rollback", true)
  advanced_configuration             = lookup(each.value, "advanced_configuration", null)
  deployment_strategy                = lookup(each.value, "deployment_strategy", null)
  bake_time_in_minutes               = lookup(each.value, "bake_time_in_minutes", null)
  deployment_controller_type         = lookup(each.value, "deployment_controller_type", null)
  enable_execute_command             = lookup(each.value, "enable_execute_command", false)

  health_check_grace_period_seconds = lookup(each.value, "health_check_grace_period_seconds", 60)

  subnets          = module.vpc_data.private_ids
  security_groups  = [module.ecs_cluster.security_group_id]
  assign_public_ip = lookup(each.value, "assign_public_ip", false)

  enable_cloudwatch_logging              = lookup(each.value, "enable_cloudwatch_logging", true)
  create_cloudwatch_log_group            = lookup(each.value, "create_cloudwatch_log_group", false)
  cloudwatch_log_group_name              = lookup(each.value, "cloudwatch_log_group_name", null)
  cloudwatch_log_group_use_name_prefix   = lookup(each.value, "cloudwatch_log_group_use_name_prefix", false)
  cloudwatch_log_group_retention_in_days = lookup(each.value, "cloudwatch_log_group_retention_in_days", 30)
  cloudwatch_log_group_kms_key_id        = lookup(each.value, "cloudwatch_log_group_kms_key_id", null)

  tags = merge(local.tags, lookup(each.value, "tags", {}))
}

# =============================================================================
# ECR Repository
# =============================================================================
module "ecr" {
  source = "../modules/ecr"

  for_each = local.ecr_repositories

  name = each.value

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# CodeDeploy Blue/Green for Web Service
# =============================================================================
module "codedeploy_web" {
  source = "../modules/codedeploy"

  environment = var.environment
  app_name    = "web"

  cluster_name = module.ecs_cluster.ecs_cluster_name
  service_name = local.service_with_alb

  listener_arn                = module.public_alb.https_listener_arn
  test_listener_arn           = module.public_alb.listener_arn
  target_group_name           = module.public_alb.target_group_name
  alternate_target_group_name = module.public_alb.alternate_target_group_name

  deployment_config_name           = "CodeDeployDefault.ECSAllAtOnce"
  termination_wait_time_in_minutes = 0

  create_iam_role       = true
  create_codedeploy_app = true

  tags = local.tags

  depends_on = [
    module.ecs_services,
    module.public_alb
  ]
}

# =============================================================================
# IAM User + Policy for Deploy (GitHub Actions)
# =============================================================================
resource "aws_iam_user" "deploy" {
  name = "app-setup"

  tags = local.tags
}

module "iam_deploy" {
  source = "../modules/iam_deploy"

  environment        = var.environment
  policy_name_prefix = "app-setup"
  cluster_name       = module.ecs_cluster.ecs_cluster_name

  ecr_repository_arns = [
    for repo in local.ecr_repositories :
    "arn:aws:ecr:us-east-1:405749097490:repository/${repo}"
  ]

  task_execution_role_arns = [
    "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
  ]

  enable_codedeploy                = true
  codedeploy_app_name              = module.codedeploy_web.app_name
  codedeploy_deployment_group_name = module.codedeploy_web.deployment_group_name

  iam_user_name = aws_iam_user.deploy.name

  create_policy = true

  tags = local.tags
}

# No S3 policy — setup does not use S3 for application storage
```

### 1.5 `terraform/setup/output.tf`

```hcl
output "codedeploy_app_name" {
  description = "CodeDeploy application name"
  value       = module.codedeploy_web.app_name
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy deployment group name"
  value       = module.codedeploy_web.deployment_group_name
}

output "codedeploy_role_arn" {
  description = "CodeDeploy IAM role ARN"
  value       = module.codedeploy_web.role_arn
}

output "alb_dns_name" {
  description = "ALB DNS name (use this to create Cloudflare CNAME)"
  value       = module.public_alb.alb_dns_name
}
```

### Modules reused (NO modifications needed)

All modules from `terraform/modules/`:
- `vpc_data` — VPC/subnet lookup
- `public_alb` — ALB with blue/green (Route53 record NOT created since `public_zone_id` defaults to null)
- `ecs_cluster` — ECS cluster + SG + IAM (with `create_asg = false`)
- `ecs_capacity` — dedicated capacity provider with managed scaling
- `ecs_service` — ECS service + task definition
- `codedeploy` — CodeDeploy blue/green with BeforeAllowTraffic hook Lambda
- `ecr` — ECR repository
- `iam_deploy` — IAM deploy user + policy

---

## 2. Health Check Endpoint (`setup/`)

### 2.1 Create `setup/app/controllers/health_controller.rb`

Duplicated from `app/app/controllers/health_controller.rb`:

```ruby
# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    if request.format.json?
      render json: { status: 'healthy' }, status: :ok
    else
      render :show, layout: false
    end
  end
end
```

**Note**: Inherits from `ApplicationController` which has `protect_from_forgery with: :exception` and `layout 'application'`. The `skip_before_action` handles CSRF, and `layout: false` (for HTML) / `render json:` (for JSON) prevent the layout from being applied. This is the same pattern as the app project.

**Requires**: a view file `setup/app/views/health/show.html.erb` for the HTML format:

```html
<p>healthy</p>
```

### 2.2 Modify `setup/config/routes.rb`

Add after `root to: 'root#show'`:

```ruby
resource :health, only: :show, controller: :health
```

---

## 3. Dockerfile + Version (`setup/`)

### 3.1 Create `setup/.github/docker/web/Dockerfile`

Duplicated from `app/.github/docker/web/Dockerfile` with simplifications:

```dockerfile
FROM ruby:3.4.1

ARG BUNDLE_WITHOUT
ARG DIFFEND_PROJECT_ID
ARG DIFFEND_SHAREABLE_ID
ARG DIFFEND_SHAREABLE_KEY
ARG RAILS_ENV=production
ARG SECRET_KEY_BASE_DUMMY=1

ENV RAILS_ENV=$RAILS_ENV

WORKDIR /app

# System dependencies (simplified vs app — no graphicsmagick, graphviz, libmagickwand)
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  curl \
  git \
  libicu-dev \
  libpq-dev \
  libxml2-dev \
  libxslt1-dev \
  && rm -rf /var/lib/apt/lists/*

# Bundler
RUN gem install bundler -v 2.7.1

# Copy Gemfile and required lib file before bundle install
# (Gemfile requires lib/development_configuration.rb)
COPY Gemfile Gemfile.lock ./
COPY lib/development_configuration.rb ./lib/

# Configure and install gems
RUN bundle config set --local deployment 'true' && \
  bundle config set --local path 'vendor/bundle' && \
  if [ -n "$BUNDLE_WITHOUT" ]; then \
  bundle config set --local without "$BUNDLE_WITHOUT"; \
  fi
RUN bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# NO assets:precompile — Tailwind is loaded via CDN, images are static in public/

ENV PATH="/app/vendor/bundle/ruby/3.4.1/bin:$PATH"
ENV BUNDLE_PATH=/app/vendor/bundle
ENV GEM_HOME=/app/vendor/bundle
ENV GEM_PATH=/app/vendor/bundle

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://localhost:3000/health || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

**Key differences from app's Dockerfile:**
- Removed system deps: `graphicsmagick`, `graphviz`, `libmagickwand-dev` (setup doesn't process images)
- Removed `assets:precompile` step (setup uses Tailwind via CDN, static images in `public/`)
- Everything else identical

**Note**: The Procfile references `bin/start-pgbouncer` which does not exist — it's a Heroku leftover. The Dockerfile connects directly to RDS, no PgBouncer.

### 3.2 Create `setup/config/version.rb`

The deploy-ecs action determines the image tag via `grep "VERSION = " config/version.rb | cut -d"'" -f2`. This file must exist:

```ruby
# frozen_string_literal: true

module Setup
  VERSION = '1.0.0'
end
```

---

## 4. GitHub Actions Workflow (`setup/`)

### 4.1 Create `setup/.github/actions/deploy-ecs/action.yaml`

Duplicated from `app/.github/actions/deploy-ecs/action.yaml`. Identical copy — the action already handles web-only deployments via the `dockerfile: web` input. The `sidekiq-config` input has a default of `''` and is simply unused for web deploys.

**Copy the entire file as-is from:**
`app/.github/actions/deploy-ecs/action.yaml`

### 4.2 Create `setup/.github/workflows/deploy-setup.yaml`

Simplified version of `app/.github/workflows/deploy-beta-001.yaml`. Removed all Sidekiq/worker-related jobs and Redis lock (no autoscaling Lambda to coordinate with).

```yaml
name: Deploy Setup

# ==============================================================================
# BLUE/GREEN DEPLOYMENT WORKFLOW (WEB ONLY)
# ==============================================================================
#
# Simplified deployment for setup (no Sidekiq workers, no autoscaling Lambda).
#
# DEPLOYMENT FLOW:
# ----------------
# 1. VALIDATE SECRETS: Verify all required secrets are configured
# 2. PREPARE AND MIGRATE: Build/push image, register task def, run migrations
# 3. DEPLOY WEB: Create CodeDeploy deployment (pauses at BeforeAllowTraffic hook)
# 4. RESUME DEPLOYMENT: Signal CodeDeploy to continue (via SSM parameter)
# 5. TRAFFIC SHIFT: Monitor CodeDeploy until deployment succeeds
# 6. CLEANUP ON FAILURE: Stop CodeDeploy if any step fails
#
# EXTERNAL DEPENDENCIES:
# ----------------------
# - CodeDeploy Application: configured with BeforeAllowTraffic hook
# - Hook Lambda: writes lifecycle hook ID to SSM parameter at
#   /codedeploy-hooks/${DEPLOYMENT_ID}/hook-id
#
# ==============================================================================

on:
  workflow_dispatch:

env:
  AWS_REGION: us-east-1
  CLUSTER_NAME: ${{ vars.CLUSTER_NAME }}
  ENVIRONMENT: ${{ vars.ENVIRONMENT }}
  WEB_SERVICE_NAME: ${{ vars.WEB_SERVICE_NAME }}
  WEB_ECR_REPO: ${{ vars.WEB_ECR_REPO }}
  CODEDEPLOY_APP_NAME: ${{ vars.CODEDEPLOY_APP_NAME }}
  CODEDEPLOY_DEPLOYMENT_GROUP: ${{ vars.CODEDEPLOY_DEPLOYMENT_GROUP }}
  CODEDEPLOY_HOOK_LAMBDA_ARN: ${{ vars.CODEDEPLOY_HOOK_LAMBDA_ARN }}

jobs:
  # ============================================================================
  # VALIDATE SECRETS
  # ============================================================================
  validate-secrets:
    name: Validate Secrets
    runs-on: ubuntu-latest
    environment: setup
    steps:
      - name: Validate required secrets
        run: |
          ERRORS=()

          if [ -z "${{ secrets.AWS_ACCESS_KEY_ID }}" ]; then
            ERRORS+=("AWS_ACCESS_KEY_ID is required")
          fi
          if [ -z "${{ secrets.AWS_SECRET_ACCESS_KEY }}" ]; then
            ERRORS+=("AWS_SECRET_ACCESS_KEY is required")
          fi

          if [ ${#ERRORS[@]} -gt 0 ]; then
            echo "============================================"
            echo "  MISSING REQUIRED SECRETS"
            echo "============================================"
            for ERROR in "${ERRORS[@]}"; do
              echo "  - $ERROR"
            done
            echo ""
            echo "Configure these secrets in GitHub Environment: ${{ env.ENVIRONMENT }}"
            exit 1
          fi

          echo "[OK] All required secrets are configured"

  # ============================================================================
  # PREPARE AND MIGRATE
  # ============================================================================
  prepare-and-migrate:
    name: Prepare and Migrate
    runs-on: ubuntu-latest
    needs: validate-secrets
    environment: setup
    outputs:
      task_def_arn: ${{ steps.build-web.outputs.task-def-arn }}
    steps:
      - uses: actions/checkout@v4
      - name: Build/Push image and register task definition
        id: build-web
        uses: ./.github/actions/deploy-ecs
        with:
          dockerfile: web
          ecr-repo: ${{ env.WEB_ECR_REPO }}
          ecs-cluster: ${{ env.CLUSTER_NAME }}
          ecs-service: ${{ env.WEB_SERVICE_NAME }}-service
          rails-env: production
          secrets-json: ${{ toJSON(secrets) }}
          service-name: ${{ env.WEB_SERVICE_NAME }}
          task-family: ${{ env.WEB_SERVICE_NAME }}
          wait-stable: 'false'
          deployment-mode: codedeploy
          vars-json: ${{ toJSON(vars) }}
      - name: Run database migrations
        id: run-migrations
        run: |
          TASK_DEF_ARN="${{ steps.build-web.outputs.task-def-arn }}"

          echo "============================================"
          echo "  RUNNING DATABASE MIGRATIONS"
          echo "============================================"
          echo ""
          echo "Task Definition: ${TASK_DEF_ARN}"
          echo "Cluster: ${{ env.CLUSTER_NAME }}"
          echo ""

          # Run migration task (EC2 with bridge network mode)
          TASK_ARN=$(aws ecs run-task \
            --cluster "${{ env.CLUSTER_NAME }}" \
            --task-definition "${TASK_DEF_ARN}" \
            --overrides '{
              "containerOverrides": [{
                "name": "${{ env.WEB_SERVICE_NAME }}",
                "command": ["bin/rails", "db:migrate"]
              }]
            }' \
            --started-by "github-actions-migrate-${{ github.run_id }}" \
            --count 1 \
            --query 'tasks[0].taskArn' \
            --output text)

          if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
            echo "[ERROR] Failed to start migration task"
            exit 1
          fi

          TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
          echo "Migration task started: ${TASK_ID}"
          echo ""

          echo "Waiting for migration task to complete..."
          aws ecs wait tasks-stopped \
            --cluster "${{ env.CLUSTER_NAME }}" \
            --tasks "${TASK_ARN}"

          EXIT_CODE=$(aws ecs describe-tasks \
            --cluster "${{ env.CLUSTER_NAME }}" \
            --tasks "${TASK_ARN}" \
            --query 'tasks[0].containers[0].exitCode' \
            --output text)

          echo ""
          echo "Migration task completed with exit code: ${EXIT_CODE}"

          if [ "$EXIT_CODE" != "0" ]; then
            echo ""
            echo "[ERROR] Migration failed!"
            echo "Check CloudWatch logs for details"
            exit 1
          fi

          echo ""
          echo "[OK] Database migrations completed successfully"

  # ============================================================================
  # DEPLOY WEB - Create CodeDeploy deployment
  # ============================================================================
  deploy-web:
    name: Deploy Web
    runs-on: ubuntu-latest
    needs: prepare-and-migrate
    environment: setup
    outputs:
      status: ${{ steps.result.outputs.status }}
      deployment_id: ${{ steps.codedeploy-web.outputs.deployment_id }}
    steps:
      - name: Setup AWS credentials from secrets
        run: |
          echo '${{ toJSON(secrets) }}' | jq -r "
            to_entries[] |
            select(.key | test(\"^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)\")) |
            \"\(.key)=\(.value)\"
          " >> $GITHUB_ENV
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ env.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ env.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Create CodeDeploy deployment
        id: codedeploy-web
        run: |
          TASK_DEF_ARN="${{ needs.prepare-and-migrate.outputs.task_def_arn }}"
          HOOK_LAMBDA_ARN="${{ env.CODEDEPLOY_HOOK_LAMBDA_ARN }}"

          if [ -z "$TASK_DEF_ARN" ] || [ "$TASK_DEF_ARN" = "null" ]; then
            echo "Task definition ARN not found"
            exit 1
          fi
          if [ -z "$HOOK_LAMBDA_ARN" ] || [ "$HOOK_LAMBDA_ARN" = "null" ]; then
            echo "CODEDEPLOY_HOOK_LAMBDA_ARN not set (configure GitHub env var)"
            exit 1
          fi

          cat > appspec.json <<'APPSPEC_EOF'
          {
            "version": 0.0,
            "Resources": [
              {
                "TargetService": {
                  "Type": "AWS::ECS::Service",
                  "Properties": {
                    "TaskDefinition": "__TASK_DEF__",
                    "LoadBalancerInfo": {
                      "ContainerName": "__CONTAINER_NAME__",
                      "ContainerPort": 3000
                    }
                  }
                }
              }
            ],
            "Hooks": [
              {
                "BeforeAllowTraffic": "__HOOK_LAMBDA_ARN__"
              }
            ]
          }
          APPSPEC_EOF

          jq --arg TASK_DEF "$TASK_DEF_ARN" \
             --arg HOOK_ARN "$HOOK_LAMBDA_ARN" \
             --arg CONTAINER "${{ env.WEB_SERVICE_NAME }}" \
            '.Resources[0].TargetService.Properties.TaskDefinition = $TASK_DEF |
             .Resources[0].TargetService.Properties.LoadBalancerInfo.ContainerName = $CONTAINER |
             .Hooks[0].BeforeAllowTraffic = $HOOK_ARN' \
            appspec.json > appspec.rendered.json

          APP_SPEC_CONTENT=$(jq -c . appspec.rendered.json | jq -R .)

          cat > codedeploy-input.json <<CODEDEPLOY_EOF
          {
            "applicationName": "${{ env.CODEDEPLOY_APP_NAME }}",
            "deploymentGroupName": "${{ env.CODEDEPLOY_DEPLOYMENT_GROUP }}",
            "revision": {
              "revisionType": "AppSpecContent",
              "appSpecContent": {
                "content": $APP_SPEC_CONTENT
              }
            }
          }
          CODEDEPLOY_EOF

          DEPLOYMENT_ID=$(aws deploy create-deployment \
            --cli-input-json file://codedeploy-input.json \
            --query 'deploymentId' \
            --output text)

          if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "None" ]; then
            echo "Failed to create CodeDeploy deployment"
            exit 1
          fi

          echo "deployment_id=$DEPLOYMENT_ID" >> "$GITHUB_OUTPUT"
          echo "CODEDEPLOY_DEPLOYMENT_ID=$DEPLOYMENT_ID" >> "$GITHUB_ENV"

      - name: Set result
        id: result
        if: always()
        run: echo "status=${{ job.status }}" >> "$GITHUB_OUTPUT"

  # ============================================================================
  # RESUME DEPLOYMENT - Signal CodeDeploy to continue
  # ============================================================================
  resume-deployment:
    name: Resume Web Deployment
    runs-on: ubuntu-latest
    needs: deploy-web
    environment: setup
    outputs:
      status: ${{ steps.result.outputs.status }}
    steps:
      - name: Setup AWS credentials from secrets
        run: |
          echo '${{ toJSON(secrets) }}' | jq -r "
            to_entries[] |
            select(.key | test(\"^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)\")) |
            \"\(.key)=\(.value)\"
          " >> $GITHUB_ENV
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ env.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ env.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Resume CodeDeploy Deployment
        run: |
          DEPLOYMENT_ID="${{ needs.deploy-web.outputs.deployment_id }}"
          SSM_PARAM_NAME_HOOK_ID="/codedeploy-hooks/${DEPLOYMENT_ID}/hook-id"

          MAX_ATTEMPTS=30
          SLEEP_SECONDS=10
          SSM_ERR_FILE=$(mktemp)

          for ((ATTEMPT=1; ATTEMPT<=MAX_ATTEMPTS; ATTEMPT++)); do
            if LIFECYCLE_EVENT_HOOK_EXECUTION_ID=$(aws ssm get-parameter \
              --name "${SSM_PARAM_NAME_HOOK_ID}" \
              --query "Parameter.Value" \
              --output text 2>"$SSM_ERR_FILE"); then
              if [ -n "$LIFECYCLE_EVENT_HOOK_EXECUTION_ID" ] && [ "$LIFECYCLE_EVENT_HOOK_EXECUTION_ID" != "None" ]; then
                break
              fi
            fi

            echo "[${ATTEMPT}/${MAX_ATTEMPTS}] Waiting for hook ID in SSM..."
            sleep "$SLEEP_SECONDS"
          done

          if [ -z "$LIFECYCLE_EVENT_HOOK_EXECUTION_ID" ] || [ "$LIFECYCLE_EVENT_HOOK_EXECUTION_ID" = "None" ]; then
            echo "Failed to retrieve LifecycleEventHookExecutionId from SSM."
            cat "$SSM_ERR_FILE"
            exit 1
          fi

          rm -f "$SSM_ERR_FILE"
          echo "Resuming deployment ${DEPLOYMENT_ID} with hook ID ${LIFECYCLE_EVENT_HOOK_EXECUTION_ID}"

          aws deploy put-lifecycle-event-hook-execution-status \
            --deployment-id "${DEPLOYMENT_ID}" \
            --lifecycle-event-hook-execution-id "${LIFECYCLE_EVENT_HOOK_EXECUTION_ID}" \
            --status Succeeded
      - name: Set result
        id: result
        if: always()
        run: echo "status=${{ job.status }}" >> "$GITHUB_OUTPUT"

  # ============================================================================
  # TRAFFIC SHIFT - Monitor CodeDeploy until completion
  # ============================================================================
  traffic-shift:
    name: Traffic Shift
    runs-on: ubuntu-latest
    needs: [resume-deployment, deploy-web]
    environment: setup
    outputs:
      status: ${{ steps.result.outputs.status }}
    steps:
      - name: Setup AWS credentials from secrets
        run: |
          echo '${{ toJSON(secrets) }}' | jq -r "
            to_entries[] |
            select(.key | test(\"^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)\")) |
            \"\(.key)=\(.value)\"
          " >> $GITHUB_ENV
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ env.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ env.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Monitor CodeDeploy deployment
        run: |
          DEPLOYMENT_ID="${{ needs.deploy-web.outputs.deployment_id }}"
          MAX_ATTEMPTS=40
          SLEEP_SECONDS=15

          if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "None" ]; then
            echo "Missing deployment ID"
            exit 1
          fi

          for ((ATTEMPT=1; ATTEMPT<=MAX_ATTEMPTS; ATTEMPT++)); do
            STATUS=$(aws deploy get-deployment \
              --deployment-id "$DEPLOYMENT_ID" \
              --query 'deploymentInfo.status' \
              --output text)

            echo "[${ATTEMPT}/${MAX_ATTEMPTS}] Deployment status: $STATUS"

            if [ "$STATUS" = "Succeeded" ]; then
              echo "CodeDeploy deployment succeeded"
              exit 0
            fi

            if [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Stopped" ]; then
              echo "CodeDeploy deployment failed with status: $STATUS"
              exit 1
            fi

            if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
              sleep $SLEEP_SECONDS
            fi
          done

          echo "Deployment did not finish within timeout"
          exit 1
      - name: Set result
        id: result
        if: always()
        run: echo "status=${{ job.status }}" >> "$GITHUB_OUTPUT"

  # ============================================================================
  # SUCCESS
  # ============================================================================
  success:
    name: Deployment Success
    runs-on: ubuntu-latest
    needs: [deploy-web, traffic-shift]
    environment: setup
    if: success()
    steps:
      - name: Setup AWS credentials from secrets
        run: |
          echo '${{ toJSON(secrets) }}' | jq -r "
            to_entries[] |
            select(.key | test(\"^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)\")) |
            \"\(.key)=\(.value)\"
          " >> $GITHUB_ENV
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ env.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ env.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Cleanup SSM parameters
        run: |
          DEPLOYMENT_ID="${{ needs.deploy-web.outputs.deployment_id }}"

          if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "None" ]; then
            echo "[WARN] No deployment ID available, skipping SSM cleanup"
            exit 0
          fi

          SSM_PARAM_PATH="/codedeploy-hooks/${DEPLOYMENT_ID}"
          echo "Cleaning up SSM parameters at ${SSM_PARAM_PATH}..."

          PARAMS=$(aws ssm get-parameters-by-path \
            --path "${SSM_PARAM_PATH}" \
            --query 'Parameters[].Name' \
            --output text 2>/dev/null) || true

          if [ -z "$PARAMS" ] || [ "$PARAMS" = "None" ]; then
            echo "[OK] No SSM parameters to clean up"
            exit 0
          fi

          for PARAM in $PARAMS; do
            if aws ssm delete-parameter --name "$PARAM" 2>/dev/null; then
              echo "[OK] Deleted ${PARAM}"
            else
              echo "[WARN] Failed to delete ${PARAM}"
            fi
          done

          echo "SSM cleanup completed"
      - name: Deployment completed
        run: |
          echo "============================================"
          echo "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
          echo "============================================"
          echo ""
          echo "Environment: ${{ env.ENVIRONMENT }}"
          echo "Cluster: ${{ env.CLUSTER_NAME }}"
          echo ""
          echo "Services deployed:"
          echo "  - ${{ env.WEB_SERVICE_NAME }}-service"

  # ============================================================================
  # CLEANUP ON FAILURE
  # ============================================================================
  cleanup-on-failure:
    name: Cleanup on Failure
    runs-on: ubuntu-latest
    needs: [deploy-web, resume-deployment, traffic-shift]
    environment: setup
    if: failure()
    steps:
      - name: Setup AWS credentials from secrets
        run: |
          echo '${{ toJSON(secrets) }}' | jq -r "
            to_entries[] |
            select(.key | test(\"^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)\")) |
            \"\(.key)=\(.value)\"
          " >> $GITHUB_ENV
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ env.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ env.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Stop CodeDeploy deployment
        run: |
          DEPLOYMENT_ID="${{ needs.deploy-web.outputs.deployment_id }}"

          if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "None" ]; then
            echo "[WARN] No deployment ID available, skipping"
            exit 0
          fi

          STATUS=$(aws deploy get-deployment \
            --deployment-id "$DEPLOYMENT_ID" \
            --query 'deploymentInfo.status' \
            --output text 2>/dev/null) || true

          if [ "$STATUS" = "InProgress" ]; then
            aws deploy stop-deployment --deployment-id "$DEPLOYMENT_ID"
            echo "[OK] Stopped CodeDeploy deployment $DEPLOYMENT_ID"
          else
            echo "[OK] Deployment $DEPLOYMENT_ID is already $STATUS, no action needed"
          fi
      - name: Cleanup SSM parameters
        run: |
          DEPLOYMENT_ID="${{ needs.deploy-web.outputs.deployment_id }}"

          if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "None" ]; then
            echo "[WARN] No deployment ID available, skipping SSM cleanup"
            exit 0
          fi

          SSM_PARAM_PATH="/codedeploy-hooks/${DEPLOYMENT_ID}"
          echo "Cleaning up SSM parameters at ${SSM_PARAM_PATH}..."

          PARAMS=$(aws ssm get-parameters-by-path \
            --path "${SSM_PARAM_PATH}" \
            --query 'Parameters[].Name' \
            --output text 2>/dev/null) || true

          if [ -z "$PARAMS" ] || [ "$PARAMS" = "None" ]; then
            echo "[OK] No SSM parameters to clean up"
            exit 0
          fi

          for PARAM in $PARAMS; do
            if aws ssm delete-parameter --name "$PARAM" 2>/dev/null; then
              echo "[OK] Deleted ${PARAM}"
            else
              echo "[WARN] Failed to delete ${PARAM}"
            fi
          done

          echo "SSM cleanup completed"
```

**GitHub Environment variables needed** (configure in GitHub settings for `setup` environment):

| Variable | Value |
|----------|-------|
| `CLUSTER_NAME` | `setup-cluster` |
| `ENVIRONMENT` | `setup` |
| `WEB_SERVICE_NAME` | `setup-web` |
| `WEB_ECR_REPO` | `405749097490.dkr.ecr.us-east-1.amazonaws.com/setup-web` |
| `CODEDEPLOY_APP_NAME` | `setup-web-app` |
| `CODEDEPLOY_DEPLOYMENT_GROUP` | `setup-web-dg` |
| `CODEDEPLOY_HOOK_LAMBDA_ARN` | *(from Terraform output after apply)* |

**GitHub Secrets needed:**

| Secret | Source |
|--------|--------|
| `AWS_ACCESS_KEY_ID` | IAM user `app-setup` (created by Terraform) |
| `AWS_SECRET_ACCESS_KEY` | IAM user `app-setup` (created by Terraform) |

**Note**: `rails-env` is set to `production` (unlike beta-001 which uses `development`). This affects `BUNDLE_WITHOUT` — production excludes development and test gems.

---

## Removed vs app's deploy workflow

| Feature | app (beta-001) | setup | Reason |
|---------|---------------|-------|--------|
| Redis lock | acquire-lock / release-lock | Removed | No autoscaling Lambda to coordinate with |
| Sidekiq quiet mode | Send TSTP to all workers | Removed | No Sidekiq workers |
| Deploy Sidekiq | Matrix job for 3 workers | Removed | No Sidekiq workers |
| ASG scaling | Scale up/down for rolling deploy | Removed | No worker ASGs |
| Migration lock | Permanent lock on failure | Removed | No autoscaling Lambda to block |
| Validate job | Check all services | Simplified | Only web service to check |

---

## Implementation Order

### Phase 1: Terraform (must be done first)

1. Create `terraform/setup/` directory with all 5 files
2. `cd terraform/setup && terraform init`
3. `terraform plan -var-file=terraform.tfvars` — verify plan creates:
   - 1 ECS cluster
   - 1 capacity provider (web)
   - 1 ALB with 2 target groups (blue/green)
   - 1 ECS service
   - 1 CodeDeploy app + deployment group
   - 1 ECR repository (`setup-web`)
   - 1 IAM user (`app-setup`) + deploy policy
   - 1 CodeDeploy hook Lambda
4. `terraform apply -var-file=terraform.tfvars`
5. Note outputs: `alb_dns_name` (for Cloudflare CNAME), `codedeploy_*` values (for GitHub env vars)
6. Create IAM access key for `app-setup` user

### Phase 2: Setup app changes (can start in parallel)

1. Create `app/controllers/health_controller.rb`
2. Create `app/views/health/show.html.erb`
3. Add route to `config/routes.rb`
4. Create `config/version.rb`
5. Create `.github/docker/web/Dockerfile`
6. Copy `.github/actions/deploy-ecs/action.yaml` from app
7. Create `.github/workflows/deploy-setup.yaml`

### Phase 3: DNS + GitHub config (after Terraform apply)

1. In Cloudflare: create CNAME `setup.app4shark.com` → ALB DNS name (from Terraform output)
2. In GitHub: create `setup` environment with variables and secrets (table above)
3. Trigger `workflow_dispatch` to test first deployment

---

## Reference files

### Modules (read-only, no modifications)
- `terraform/modules/vpc_data/` — VPC/subnet lookup
- `terraform/modules/public_alb/` — ALB with blue/green
- `terraform/modules/ecs_cluster/` — ECS cluster + SG
- `terraform/modules/ecs_capacity/` — dedicated capacity provider
- `terraform/modules/ecs_service/` — ECS service + task definition
- `terraform/modules/codedeploy/` — CodeDeploy blue/green
- `terraform/modules/ecr/` — ECR repository
- `terraform/modules/iam_deploy/` — IAM deploy policy

### Patterns followed (source of truth)
- `terraform/beta-001/main.tf` — Terraform environment template
- `terraform/beta-001/locals.tf` — service enrichment for CODE_DEPLOY
- `app/.github/actions/deploy-ecs/action.yaml` — deploy composite action
- `app/.github/workflows/deploy-beta-001.yaml` — deploy workflow
- `app/.github/docker/web/Dockerfile` — web Dockerfile
- `app/app/controllers/health_controller.rb` — health check controller

---

## Verification checklist

1. **Terraform plan**: `terraform plan` shows expected resources (no errors)
2. **Terraform apply**: all resources created successfully
3. **Cloudflare**: `dig setup.app4shark.com` resolves to ALB
4. **Health endpoint**: `curl https://setup.app4shark.com/health` returns `{"status":"healthy"}`
5. **Dockerfile**: `docker build -f .github/docker/web/Dockerfile .` builds successfully
6. **First deploy**: trigger workflow_dispatch, verify blue/green deployment completes
7. **Landing page**: `https://setup.app4shark.com/` renders the landing page with app store badges
