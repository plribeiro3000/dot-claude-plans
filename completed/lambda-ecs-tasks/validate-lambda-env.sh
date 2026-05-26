#!/bin/bash
# Validate Lambda environment for ECS autoscaling
#
# Usage:
#   ./validate-lambda-env.sh <environment>
#
# Example:
#   ./validate-lambda-env.sh beta-001
#
# Environments: beta-001, demo-001, shared-001, atento-001
#
# This script validates resources created by setup-lambda-env.sh which uses
# EventBridge Scheduler (recommended) instead of legacy EventBridge Rules.

ENV="${1:?Usage: $0 <environment> (beta-001|demo-001|shared-001|atento-001)}"
REGION="${AWS_REGION:-us-east-1}"
SCHEDULE_EXPRESSION="${SCHEDULE_EXPRESSION:-rate(1 minute)}"

# Auto-detect ACCOUNT_ID from current credentials if not set
if [[ -n "$AWS_ACCOUNT_ID" ]]; then
    ACCOUNT_ID="$AWS_ACCOUNT_ID"
else
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$ACCOUNT_ID" ]]; then
        echo "ERROR: Could not detect AWS Account ID. Check your AWS credentials."
        exit 1
    fi
fi

# Validate environment
case "$ENV" in
    beta-001|demo-001|shared-001|atento-001) ;;
    *) echo "Error: Invalid environment '$ENV'. Must be: beta-001, demo-001, shared-001, atento-001"; exit 1 ;;
esac

CLUSTER="${ENV}-cluster"
SCHEDULER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/EventBridge-${ENV}-scheduler-role"

echo "=========================================="
echo "Validating Lambda environment: $ENV"
echo "=========================================="
echo ""
echo "  Account:  $ACCOUNT_ID"
echo "  Region:   $REGION"
echo ""
echo "=========================================="
echo ""

ERRORS=0

# ===========================================
# ECS Prerequisites
# ===========================================
echo "=== ECS Prerequisites ==="

if aws ecs describe-clusters --clusters "${CLUSTER}" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q ACTIVE; then
    echo "[1] [OK] ECS cluster ${CLUSTER} exists and is ACTIVE"
else
    echo "[1] [FAIL] ECS cluster ${CLUSTER} does NOT exist or is NOT ACTIVE"
    ERRORS=$((ERRORS + 1))
fi

if aws ecs describe-services --cluster "${CLUSTER}" --services "${ENV}-worker-commission-service" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null | grep -qE '(ACTIVE|DRAINING)'; then
    echo "[2] [OK] ECS service ${ENV}-worker-commission-service exists"
else
    echo "[2] [FAIL] ECS service ${ENV}-worker-commission-service does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws ecs describe-services --cluster "${CLUSTER}" --services "${ENV}-worker-user-service" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null | grep -qE '(ACTIVE|DRAINING)'; then
    echo "[3] [OK] ECS service ${ENV}-worker-user-service exists"
else
    echo "[3] [FAIL] ECS service ${ENV}-worker-user-service does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws ecs describe-services --cluster "${CLUSTER}" --services "${ENV}-worker-system-service" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null | grep -qE '(ACTIVE|DRAINING)'; then
    echo "[4] [OK] ECS service ${ENV}-worker-system-service exists"
else
    echo "[4] [FAIL] ECS service ${ENV}-worker-system-service does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Policies
# ===========================================
echo "=== Policies ==="

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudWatch-${ENV}-lambda-logs-policy" > /dev/null 2>&1; then
    echo "[5] [OK] CloudWatch-${ENV}-lambda-logs-policy exists"
else
    echo "[5] [FAIL] CloudWatch-${ENV}-lambda-logs-policy does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ECS-${ENV}-lambda-worker-policy" > /dev/null 2>&1; then
    echo "[6] [OK] ECS-${ENV}-lambda-worker-policy exists"
else
    echo "[6] [FAIL] ECS-${ENV}-lambda-worker-policy does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/EventBridge-${ENV}-lambda-invoke-policy" > /dev/null 2>&1; then
    echo "[7] [OK] EventBridge-${ENV}-lambda-invoke-policy exists"
else
    echo "[7] [FAIL] EventBridge-${ENV}-lambda-invoke-policy does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Policy Content
# ===========================================
echo "=== Policy Content ==="

# CloudWatch logs policy content check
CLOUDWATCH_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/CloudWatch-${ENV}-lambda-logs-policy"
CLOUDWATCH_POLICY_VERSION=$(aws iam get-policy --policy-arn "$CLOUDWATCH_POLICY_ARN" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")

if [[ -z "$CLOUDWATCH_POLICY_VERSION" ]]; then
    echo "[8] [SKIP] CloudWatch-${ENV}-lambda-logs-policy content check skipped (policy not found)"
else
    CLOUDWATCH_POLICY_DOC=$(aws iam get-policy-version --policy-arn "$CLOUDWATCH_POLICY_ARN" --version-id "$CLOUDWATCH_POLICY_VERSION" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "")

    CLOUDWATCH_MISSING_ACTIONS=()
    if ! echo "$CLOUDWATCH_POLICY_DOC" | grep -q "\"logs:CreateLogGroup\""; then
        CLOUDWATCH_MISSING_ACTIONS+=("logs:CreateLogGroup")
    fi
    if ! echo "$CLOUDWATCH_POLICY_DOC" | grep -q "\"logs:CreateLogStream\""; then
        CLOUDWATCH_MISSING_ACTIONS+=("logs:CreateLogStream")
    fi
    if ! echo "$CLOUDWATCH_POLICY_DOC" | grep -q "\"logs:PutLogEvents\""; then
        CLOUDWATCH_MISSING_ACTIONS+=("logs:PutLogEvents")
    fi

    if [[ ${#CLOUDWATCH_MISSING_ACTIONS[@]} -eq 0 ]]; then
        echo "[8] [OK] CloudWatch-${ENV}-lambda-logs-policy has correct actions"
    else
        echo "[8] [FAIL] CloudWatch-${ENV}-lambda-logs-policy missing actions: ${CLOUDWATCH_MISSING_ACTIONS[*]}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ECS policy content check
ECS_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/ECS-${ENV}-lambda-worker-policy"
ECS_POLICY_VERSION=$(aws iam get-policy --policy-arn "$ECS_POLICY_ARN" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")

if [[ -z "$ECS_POLICY_VERSION" ]]; then
    echo "[9] [SKIP] ECS-${ENV}-lambda-worker-policy content check skipped (policy not found)"
else
    ECS_POLICY_DOC=$(aws iam get-policy-version --policy-arn "$ECS_POLICY_ARN" --version-id "$ECS_POLICY_VERSION" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "")

    ECS_MISSING_ACTIONS=()
    if ! echo "$ECS_POLICY_DOC" | grep -q "\"ecs:DescribeServices\""; then
        ECS_MISSING_ACTIONS+=("ecs:DescribeServices")
    fi
    if ! echo "$ECS_POLICY_DOC" | grep -q "\"ecs:UpdateService\""; then
        ECS_MISSING_ACTIONS+=("ecs:UpdateService")
    fi

    if [[ ${#ECS_MISSING_ACTIONS[@]} -eq 0 ]]; then
        echo "[9] [OK] ECS-${ENV}-lambda-worker-policy has correct actions"
    else
        echo "[9] [FAIL] ECS-${ENV}-lambda-worker-policy missing actions: ${ECS_MISSING_ACTIONS[*]}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# EventBridge Scheduler invoke policy content check
SCHEDULER_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/EventBridge-${ENV}-lambda-invoke-policy"
SCHEDULER_POLICY_VERSION=$(aws iam get-policy --policy-arn "$SCHEDULER_POLICY_ARN" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")

if [[ -z "$SCHEDULER_POLICY_VERSION" ]]; then
    echo "[10] [SKIP] EventBridge-${ENV}-lambda-invoke-policy content check skipped (policy not found)"
else
    SCHEDULER_POLICY_DOC=$(aws iam get-policy-version --policy-arn "$SCHEDULER_POLICY_ARN" --version-id "$SCHEDULER_POLICY_VERSION" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "")

    if echo "$SCHEDULER_POLICY_DOC" | grep -q "\"lambda:InvokeFunction\""; then
        echo "[10] [OK] EventBridge-${ENV}-lambda-invoke-policy has correct actions"
    else
        echo "[10] [FAIL] EventBridge-${ENV}-lambda-invoke-policy missing action: lambda:InvokeFunction"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# ===========================================
# Roles
# ===========================================
echo "=== Roles ==="

if aws iam get-role --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" > /dev/null 2>&1; then
    echo "[11] [OK] Lambda-${ENV}-worker-commission-autoscaling-role exists"
else
    echo "[11] [FAIL] Lambda-${ENV}-worker-commission-autoscaling-role does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws iam get-role --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" > /dev/null 2>&1; then
    echo "[12] [OK] Lambda-${ENV}-worker-standard-autoscaling-role exists"
else
    echo "[12] [FAIL] Lambda-${ENV}-worker-standard-autoscaling-role does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws iam get-role --role-name "EventBridge-${ENV}-scheduler-role" > /dev/null 2>&1; then
    echo "[13] [OK] EventBridge-${ENV}-scheduler-role exists"
else
    echo "[13] [FAIL] EventBridge-${ENV}-scheduler-role does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Role Policy Attachments
# ===========================================
echo "=== Role Policy Attachments ==="

if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" --query "AttachedPolicies[?PolicyName==\`CloudWatch-${ENV}-lambda-logs-policy\`]" --output text 2>/dev/null | grep -q CloudWatch; then
    echo "[14] [OK] CloudWatch logs policy attached to commission-autoscaling role"
else
    echo "[14] [FAIL] CloudWatch logs policy NOT attached to commission-autoscaling role"
    ERRORS=$((ERRORS + 1))
fi

if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" --query "AttachedPolicies[?PolicyName==\`ECS-${ENV}-lambda-worker-policy\`]" --output text 2>/dev/null | grep -q ECS; then
    echo "[15] [OK] ECS policy attached to commission-autoscaling role"
else
    echo "[15] [FAIL] ECS policy NOT attached to commission-autoscaling role"
    ERRORS=$((ERRORS + 1))
fi

if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" --query "AttachedPolicies[?PolicyName==\`CloudWatch-${ENV}-lambda-logs-policy\`]" --output text 2>/dev/null | grep -q CloudWatch; then
    echo "[16] [OK] CloudWatch logs policy attached to standard-autoscaling role"
else
    echo "[16] [FAIL] CloudWatch logs policy NOT attached to standard-autoscaling role"
    ERRORS=$((ERRORS + 1))
fi

if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" --query "AttachedPolicies[?PolicyName==\`ECS-${ENV}-lambda-worker-policy\`]" --output text 2>/dev/null | grep -q ECS; then
    echo "[17] [OK] ECS policy attached to standard-autoscaling role"
else
    echo "[17] [FAIL] ECS policy NOT attached to standard-autoscaling role"
    ERRORS=$((ERRORS + 1))
fi

if aws iam list-attached-role-policies --role-name "EventBridge-${ENV}-scheduler-role" --query "AttachedPolicies[?PolicyName==\`EventBridge-${ENV}-lambda-invoke-policy\`]" --output text 2>/dev/null | grep -q EventBridge; then
    echo "[18] [OK] Lambda invoke policy attached to scheduler role"
else
    echo "[18] [FAIL] Lambda invoke policy NOT attached to scheduler role"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Lambda Functions
# ===========================================
echo "=== Lambda Functions ==="

if aws lambda get-function --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "[19] [OK] Lambda-${ENV}-worker-commission-autoscaling exists"
else
    echo "[19] [FAIL] Lambda-${ENV}-worker-commission-autoscaling does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws lambda get-function --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "[20] [OK] Lambda-${ENV}-worker-user-autoscaling exists"
else
    echo "[20] [FAIL] Lambda-${ENV}-worker-user-autoscaling does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

if aws lambda get-function --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "[21] [OK] Lambda-${ENV}-worker-system-autoscaling exists"
else
    echo "[21] [FAIL] Lambda-${ENV}-worker-system-autoscaling does NOT exist"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Lambda Configuration (runtime, timeout, memory)
# ===========================================
echo "=== Lambda Configuration ==="

EXPECTED_RUNTIME="ruby3.4"
EXPECTED_TIMEOUT=30
EXPECTED_MEMORY=128

# Commission Lambda configuration
COMMISSION_RUNTIME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Runtime' --output text 2>/dev/null || echo "")
COMMISSION_TIMEOUT=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Timeout' --output text 2>/dev/null || echo "")
COMMISSION_MEMORY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'MemorySize' --output text 2>/dev/null || echo "")

if [[ -z "$COMMISSION_RUNTIME" ]]; then
    echo "[22] [SKIP] Lambda-${ENV}-worker-commission-autoscaling configuration check skipped (function not found)"
else
    COMMISSION_CONFIG_OK=true
    if [[ "$COMMISSION_RUNTIME" != "$EXPECTED_RUNTIME" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling runtime: expected '$EXPECTED_RUNTIME', got '$COMMISSION_RUNTIME'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_CONFIG_OK=false
    fi
    if [[ "$COMMISSION_TIMEOUT" != "$EXPECTED_TIMEOUT" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling timeout: expected '$EXPECTED_TIMEOUT', got '$COMMISSION_TIMEOUT'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_CONFIG_OK=false
    fi
    if [[ "$COMMISSION_MEMORY" != "$EXPECTED_MEMORY" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling memory: expected '$EXPECTED_MEMORY', got '$COMMISSION_MEMORY'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_CONFIG_OK=false
    fi
    if $COMMISSION_CONFIG_OK; then
        echo "[22] [OK] Lambda-${ENV}-worker-commission-autoscaling configuration correct (runtime=$COMMISSION_RUNTIME, timeout=$COMMISSION_TIMEOUT, memory=$COMMISSION_MEMORY)"
    fi
fi

# User Lambda configuration
USER_RUNTIME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Runtime' --output text 2>/dev/null || echo "")
USER_TIMEOUT=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Timeout' --output text 2>/dev/null || echo "")
USER_MEMORY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'MemorySize' --output text 2>/dev/null || echo "")

if [[ -z "$USER_RUNTIME" ]]; then
    echo "[23] [SKIP] Lambda-${ENV}-worker-user-autoscaling configuration check skipped (function not found)"
else
    USER_CONFIG_OK=true
    if [[ "$USER_RUNTIME" != "$EXPECTED_RUNTIME" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling runtime: expected '$EXPECTED_RUNTIME', got '$USER_RUNTIME'"
        ERRORS=$((ERRORS + 1))
        USER_CONFIG_OK=false
    fi
    if [[ "$USER_TIMEOUT" != "$EXPECTED_TIMEOUT" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling timeout: expected '$EXPECTED_TIMEOUT', got '$USER_TIMEOUT'"
        ERRORS=$((ERRORS + 1))
        USER_CONFIG_OK=false
    fi
    if [[ "$USER_MEMORY" != "$EXPECTED_MEMORY" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling memory: expected '$EXPECTED_MEMORY', got '$USER_MEMORY'"
        ERRORS=$((ERRORS + 1))
        USER_CONFIG_OK=false
    fi
    if $USER_CONFIG_OK; then
        echo "[23] [OK] Lambda-${ENV}-worker-user-autoscaling configuration correct (runtime=$USER_RUNTIME, timeout=$USER_TIMEOUT, memory=$USER_MEMORY)"
    fi
fi

# System Lambda configuration
SYSTEM_RUNTIME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Runtime' --output text 2>/dev/null || echo "")
SYSTEM_TIMEOUT=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Timeout' --output text 2>/dev/null || echo "")
SYSTEM_MEMORY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'MemorySize' --output text 2>/dev/null || echo "")

if [[ -z "$SYSTEM_RUNTIME" ]]; then
    echo "[24] [SKIP] Lambda-${ENV}-worker-system-autoscaling configuration check skipped (function not found)"
else
    SYSTEM_CONFIG_OK=true
    if [[ "$SYSTEM_RUNTIME" != "$EXPECTED_RUNTIME" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling runtime: expected '$EXPECTED_RUNTIME', got '$SYSTEM_RUNTIME'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_CONFIG_OK=false
    fi
    if [[ "$SYSTEM_TIMEOUT" != "$EXPECTED_TIMEOUT" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling timeout: expected '$EXPECTED_TIMEOUT', got '$SYSTEM_TIMEOUT'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_CONFIG_OK=false
    fi
    if [[ "$SYSTEM_MEMORY" != "$EXPECTED_MEMORY" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling memory: expected '$EXPECTED_MEMORY', got '$SYSTEM_MEMORY'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_CONFIG_OK=false
    fi
    if $SYSTEM_CONFIG_OK; then
        echo "[24] [OK] Lambda-${ENV}-worker-system-autoscaling configuration correct (runtime=$SYSTEM_RUNTIME, timeout=$SYSTEM_TIMEOUT, memory=$SYSTEM_MEMORY)"
    fi
fi

echo ""

# ===========================================
# Lambda Role Assignments
# ===========================================
echo "=== Lambda Role Assignments ==="

COMMISSION_ROLE=$(aws lambda get-function --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query "Configuration.Role" --output text 2>/dev/null || echo "")
if [[ -z "$COMMISSION_ROLE" ]]; then
    echo "[25] [SKIP] Lambda-${ENV}-worker-commission-autoscaling role check skipped (function not found)"
elif [[ "$COMMISSION_ROLE" == *"Lambda-${ENV}-worker-commission-autoscaling-role"* ]]; then
    echo "[25] [OK] Lambda-${ENV}-worker-commission-autoscaling uses correct role"
else
    echo "[25] [FAIL] Lambda-${ENV}-worker-commission-autoscaling uses wrong role: $COMMISSION_ROLE"
    ERRORS=$((ERRORS + 1))
fi

USER_ROLE=$(aws lambda get-function --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query "Configuration.Role" --output text 2>/dev/null || echo "")
if [[ -z "$USER_ROLE" ]]; then
    echo "[26] [SKIP] Lambda-${ENV}-worker-user-autoscaling role check skipped (function not found)"
elif [[ "$USER_ROLE" == *"Lambda-${ENV}-worker-standard-autoscaling-role"* ]]; then
    echo "[26] [OK] Lambda-${ENV}-worker-user-autoscaling uses correct role"
else
    echo "[26] [FAIL] Lambda-${ENV}-worker-user-autoscaling uses wrong role: $USER_ROLE"
    ERRORS=$((ERRORS + 1))
fi

SYSTEM_ROLE=$(aws lambda get-function --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query "Configuration.Role" --output text 2>/dev/null || echo "")
if [[ -z "$SYSTEM_ROLE" ]]; then
    echo "[27] [SKIP] Lambda-${ENV}-worker-system-autoscaling role check skipped (function not found)"
elif [[ "$SYSTEM_ROLE" == *"Lambda-${ENV}-worker-standard-autoscaling-role"* ]]; then
    echo "[27] [OK] Lambda-${ENV}-worker-system-autoscaling uses correct role"
else
    echo "[27] [FAIL] Lambda-${ENV}-worker-system-autoscaling uses wrong role: $SYSTEM_ROLE"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ===========================================
# Lambda Environment Variables
# ===========================================
echo "=== Lambda Environment Variables ==="

# Commission Lambda env vars
COMMISSION_ECS_CLUSTER=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_CLUSTER_NAME' --output text 2>/dev/null || echo "")
COMMISSION_ECS_SERVICE=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_SERVICE_NAME' --output text 2>/dev/null || echo "")
COMMISSION_PROCESS_NAME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Environment.Variables.PROCESS_NAME' --output text 2>/dev/null || echo "")
COMMISSION_MIN_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Environment.Variables.MINIMUM_CAPACITY' --output text 2>/dev/null || echo "")
COMMISSION_MAX_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" --query 'Environment.Variables.MAXIMUM_CAPACITY' --output text 2>/dev/null || echo "")

if [[ -z "$COMMISSION_ECS_CLUSTER" || "$COMMISSION_ECS_CLUSTER" == "None" ]]; then
    echo "[28] [SKIP] Lambda-${ENV}-worker-commission-autoscaling env vars skipped (function not found)"
else
    COMMISSION_ENV_OK=true
    if [[ "$COMMISSION_ECS_CLUSTER" != "${ENV}-cluster" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling ECS_CLUSTER_NAME: expected '${ENV}-cluster', got '$COMMISSION_ECS_CLUSTER'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_ENV_OK=false
    fi
    if [[ "$COMMISSION_ECS_SERVICE" != "${ENV}-worker-commission-service" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling ECS_SERVICE_NAME: expected '${ENV}-worker-commission-service', got '$COMMISSION_ECS_SERVICE'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_ENV_OK=false
    fi
    if [[ "$COMMISSION_PROCESS_NAME" != "worker_commission" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling PROCESS_NAME: expected 'worker_commission', got '$COMMISSION_PROCESS_NAME'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_ENV_OK=false
    fi
    if [[ "$COMMISSION_MIN_CAPACITY" != "1" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling MINIMUM_CAPACITY: expected '1', got '$COMMISSION_MIN_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_ENV_OK=false
    fi
    if [[ "$COMMISSION_MAX_CAPACITY" != "15" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-commission-autoscaling MAXIMUM_CAPACITY: expected '15', got '$COMMISSION_MAX_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        COMMISSION_ENV_OK=false
    fi
    if $COMMISSION_ENV_OK; then
        echo "[28] [OK] Lambda-${ENV}-worker-commission-autoscaling environment variables correct"
    fi
fi

# User Lambda env vars
USER_ECS_CLUSTER=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_CLUSTER_NAME' --output text 2>/dev/null || echo "")
USER_ECS_SERVICE=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_SERVICE_NAME' --output text 2>/dev/null || echo "")
USER_PROCESS_NAME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Environment.Variables.PROCESS_NAME' --output text 2>/dev/null || echo "")
USER_MIN_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Environment.Variables.MINIMUM_CAPACITY' --output text 2>/dev/null || echo "")
USER_MAX_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" --query 'Environment.Variables.MAXIMUM_CAPACITY' --output text 2>/dev/null || echo "")

if [[ -z "$USER_ECS_CLUSTER" || "$USER_ECS_CLUSTER" == "None" ]]; then
    echo "[29] [SKIP] Lambda-${ENV}-worker-user-autoscaling env vars skipped (function not found)"
else
    USER_ENV_OK=true
    if [[ "$USER_ECS_CLUSTER" != "${ENV}-cluster" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling ECS_CLUSTER_NAME: expected '${ENV}-cluster', got '$USER_ECS_CLUSTER'"
        ERRORS=$((ERRORS + 1))
        USER_ENV_OK=false
    fi
    if [[ "$USER_ECS_SERVICE" != "${ENV}-worker-user-service" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling ECS_SERVICE_NAME: expected '${ENV}-worker-user-service', got '$USER_ECS_SERVICE'"
        ERRORS=$((ERRORS + 1))
        USER_ENV_OK=false
    fi
    if [[ "$USER_PROCESS_NAME" != "worker_user" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling PROCESS_NAME: expected 'worker_user', got '$USER_PROCESS_NAME'"
        ERRORS=$((ERRORS + 1))
        USER_ENV_OK=false
    fi
    if [[ "$USER_MIN_CAPACITY" != "1" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling MINIMUM_CAPACITY: expected '1', got '$USER_MIN_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        USER_ENV_OK=false
    fi
    if [[ "$USER_MAX_CAPACITY" != "5" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-user-autoscaling MAXIMUM_CAPACITY: expected '5', got '$USER_MAX_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        USER_ENV_OK=false
    fi
    if $USER_ENV_OK; then
        echo "[29] [OK] Lambda-${ENV}-worker-user-autoscaling environment variables correct"
    fi
fi

# System Lambda env vars
SYSTEM_ECS_CLUSTER=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_CLUSTER_NAME' --output text 2>/dev/null || echo "")
SYSTEM_ECS_SERVICE=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Environment.Variables.ECS_SERVICE_NAME' --output text 2>/dev/null || echo "")
SYSTEM_PROCESS_NAME=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Environment.Variables.PROCESS_NAME' --output text 2>/dev/null || echo "")
SYSTEM_MIN_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Environment.Variables.MINIMUM_CAPACITY' --output text 2>/dev/null || echo "")
SYSTEM_MAX_CAPACITY=$(aws lambda get-function-configuration --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" --query 'Environment.Variables.MAXIMUM_CAPACITY' --output text 2>/dev/null || echo "")

if [[ -z "$SYSTEM_ECS_CLUSTER" || "$SYSTEM_ECS_CLUSTER" == "None" ]]; then
    echo "[30] [SKIP] Lambda-${ENV}-worker-system-autoscaling env vars skipped (function not found)"
else
    SYSTEM_ENV_OK=true
    if [[ "$SYSTEM_ECS_CLUSTER" != "${ENV}-cluster" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling ECS_CLUSTER_NAME: expected '${ENV}-cluster', got '$SYSTEM_ECS_CLUSTER'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_ENV_OK=false
    fi
    if [[ "$SYSTEM_ECS_SERVICE" != "${ENV}-worker-system-service" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling ECS_SERVICE_NAME: expected '${ENV}-worker-system-service', got '$SYSTEM_ECS_SERVICE'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_ENV_OK=false
    fi
    if [[ "$SYSTEM_PROCESS_NAME" != "worker_system" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling PROCESS_NAME: expected 'worker_system', got '$SYSTEM_PROCESS_NAME'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_ENV_OK=false
    fi
    if [[ "$SYSTEM_MIN_CAPACITY" != "1" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling MINIMUM_CAPACITY: expected '1', got '$SYSTEM_MIN_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_ENV_OK=false
    fi
    if [[ "$SYSTEM_MAX_CAPACITY" != "5" ]]; then
        echo "[FAIL] Lambda-${ENV}-worker-system-autoscaling MAXIMUM_CAPACITY: expected '5', got '$SYSTEM_MAX_CAPACITY'"
        ERRORS=$((ERRORS + 1))
        SYSTEM_ENV_OK=false
    fi
    if $SYSTEM_ENV_OK; then
        echo "[30] [OK] Lambda-${ENV}-worker-system-autoscaling environment variables correct"
    fi
fi

echo ""

# ===========================================
# EventBridge Scheduler - Commission
# ===========================================
echo "=== EventBridge Scheduler ==="

COMMISSION_SCHEDULE="Lambda-${ENV}-worker-commission-autoscaling-schedule"
COMMISSION_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-commission-autoscaling"

if ! aws scheduler get-schedule --name "$COMMISSION_SCHEDULE" --region "$REGION" > /dev/null 2>&1; then
    echo "[31] [FAIL] Schedule $COMMISSION_SCHEDULE does NOT exist"
    echo "[32] [SKIP] Schedule target check skipped (schedule not found)"
    echo "[33] [SKIP] Schedule role check skipped (schedule not found)"
    echo "[34] [SKIP] Schedule expression check skipped (schedule not found)"
    echo "[35] [SKIP] Schedule state check skipped (schedule not found)"
    ERRORS=$((ERRORS + 1))
else
    echo "[31] [OK] Schedule $COMMISSION_SCHEDULE exists"

    COMMISSION_SCHEDULE_TARGET=$(aws scheduler get-schedule --name "$COMMISSION_SCHEDULE" --region "$REGION" --query 'Target.Arn' --output text 2>/dev/null || echo "")
    if [[ "$COMMISSION_SCHEDULE_TARGET" == "$COMMISSION_LAMBDA_ARN" ]]; then
        echo "[32] [OK] Schedule $COMMISSION_SCHEDULE targets correct Lambda"
    else
        echo "[32] [FAIL] Schedule $COMMISSION_SCHEDULE targets wrong Lambda: $COMMISSION_SCHEDULE_TARGET"
        ERRORS=$((ERRORS + 1))
    fi

    COMMISSION_SCHEDULE_ROLE=$(aws scheduler get-schedule --name "$COMMISSION_SCHEDULE" --region "$REGION" --query 'Target.RoleArn' --output text 2>/dev/null || echo "")
    if [[ "$COMMISSION_SCHEDULE_ROLE" == "$SCHEDULER_ROLE_ARN" ]]; then
        echo "[33] [OK] Schedule $COMMISSION_SCHEDULE uses correct role"
    else
        echo "[33] [FAIL] Schedule $COMMISSION_SCHEDULE uses wrong role: $COMMISSION_SCHEDULE_ROLE"
        ERRORS=$((ERRORS + 1))
    fi

    COMMISSION_SCHEDULE_EXPR=$(aws scheduler get-schedule --name "$COMMISSION_SCHEDULE" --region "$REGION" --query 'ScheduleExpression' --output text 2>/dev/null || echo "")
    if [[ "$COMMISSION_SCHEDULE_EXPR" == "$SCHEDULE_EXPRESSION" ]]; then
        echo "[34] [OK] Schedule $COMMISSION_SCHEDULE has correct expression ($COMMISSION_SCHEDULE_EXPR)"
    else
        echo "[34] [FAIL] Schedule $COMMISSION_SCHEDULE has wrong expression: expected '$SCHEDULE_EXPRESSION', got '$COMMISSION_SCHEDULE_EXPR'"
        ERRORS=$((ERRORS + 1))
    fi

    COMMISSION_SCHEDULE_STATE=$(aws scheduler get-schedule --name "$COMMISSION_SCHEDULE" --region "$REGION" --query 'State' --output text 2>/dev/null || echo "")
    if [[ "$COMMISSION_SCHEDULE_STATE" == "ENABLED" ]]; then
        echo "[35] [OK] Schedule $COMMISSION_SCHEDULE is ENABLED"
    else
        echo "[35] [FAIL] Schedule $COMMISSION_SCHEDULE is NOT ENABLED (state: $COMMISSION_SCHEDULE_STATE)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ===========================================
# EventBridge Scheduler - User
# ===========================================

USER_SCHEDULE="Lambda-${ENV}-worker-user-autoscaling-schedule"
USER_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-user-autoscaling"

if ! aws scheduler get-schedule --name "$USER_SCHEDULE" --region "$REGION" > /dev/null 2>&1; then
    echo "[36] [FAIL] Schedule $USER_SCHEDULE does NOT exist"
    echo "[37] [SKIP] Schedule target check skipped (schedule not found)"
    echo "[38] [SKIP] Schedule role check skipped (schedule not found)"
    echo "[39] [SKIP] Schedule expression check skipped (schedule not found)"
    echo "[40] [SKIP] Schedule state check skipped (schedule not found)"
    ERRORS=$((ERRORS + 1))
else
    echo "[36] [OK] Schedule $USER_SCHEDULE exists"

    USER_SCHEDULE_TARGET=$(aws scheduler get-schedule --name "$USER_SCHEDULE" --region "$REGION" --query 'Target.Arn' --output text 2>/dev/null || echo "")
    if [[ "$USER_SCHEDULE_TARGET" == "$USER_LAMBDA_ARN" ]]; then
        echo "[37] [OK] Schedule $USER_SCHEDULE targets correct Lambda"
    else
        echo "[37] [FAIL] Schedule $USER_SCHEDULE targets wrong Lambda: $USER_SCHEDULE_TARGET"
        ERRORS=$((ERRORS + 1))
    fi

    USER_SCHEDULE_ROLE=$(aws scheduler get-schedule --name "$USER_SCHEDULE" --region "$REGION" --query 'Target.RoleArn' --output text 2>/dev/null || echo "")
    if [[ "$USER_SCHEDULE_ROLE" == "$SCHEDULER_ROLE_ARN" ]]; then
        echo "[38] [OK] Schedule $USER_SCHEDULE uses correct role"
    else
        echo "[38] [FAIL] Schedule $USER_SCHEDULE uses wrong role: $USER_SCHEDULE_ROLE"
        ERRORS=$((ERRORS + 1))
    fi

    USER_SCHEDULE_EXPR=$(aws scheduler get-schedule --name "$USER_SCHEDULE" --region "$REGION" --query 'ScheduleExpression' --output text 2>/dev/null || echo "")
    if [[ "$USER_SCHEDULE_EXPR" == "$SCHEDULE_EXPRESSION" ]]; then
        echo "[39] [OK] Schedule $USER_SCHEDULE has correct expression ($USER_SCHEDULE_EXPR)"
    else
        echo "[39] [FAIL] Schedule $USER_SCHEDULE has wrong expression: expected '$SCHEDULE_EXPRESSION', got '$USER_SCHEDULE_EXPR'"
        ERRORS=$((ERRORS + 1))
    fi

    USER_SCHEDULE_STATE=$(aws scheduler get-schedule --name "$USER_SCHEDULE" --region "$REGION" --query 'State' --output text 2>/dev/null || echo "")
    if [[ "$USER_SCHEDULE_STATE" == "ENABLED" ]]; then
        echo "[40] [OK] Schedule $USER_SCHEDULE is ENABLED"
    else
        echo "[40] [FAIL] Schedule $USER_SCHEDULE is NOT ENABLED (state: $USER_SCHEDULE_STATE)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ===========================================
# EventBridge Scheduler - System
# ===========================================

SYSTEM_SCHEDULE="Lambda-${ENV}-worker-system-autoscaling-schedule"
SYSTEM_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-system-autoscaling"

if ! aws scheduler get-schedule --name "$SYSTEM_SCHEDULE" --region "$REGION" > /dev/null 2>&1; then
    echo "[41] [FAIL] Schedule $SYSTEM_SCHEDULE does NOT exist"
    echo "[42] [SKIP] Schedule target check skipped (schedule not found)"
    echo "[43] [SKIP] Schedule role check skipped (schedule not found)"
    echo "[44] [SKIP] Schedule expression check skipped (schedule not found)"
    echo "[45] [SKIP] Schedule state check skipped (schedule not found)"
    ERRORS=$((ERRORS + 1))
else
    echo "[41] [OK] Schedule $SYSTEM_SCHEDULE exists"

    SYSTEM_SCHEDULE_TARGET=$(aws scheduler get-schedule --name "$SYSTEM_SCHEDULE" --region "$REGION" --query 'Target.Arn' --output text 2>/dev/null || echo "")
    if [[ "$SYSTEM_SCHEDULE_TARGET" == "$SYSTEM_LAMBDA_ARN" ]]; then
        echo "[42] [OK] Schedule $SYSTEM_SCHEDULE targets correct Lambda"
    else
        echo "[42] [FAIL] Schedule $SYSTEM_SCHEDULE targets wrong Lambda: $SYSTEM_SCHEDULE_TARGET"
        ERRORS=$((ERRORS + 1))
    fi

    SYSTEM_SCHEDULE_ROLE=$(aws scheduler get-schedule --name "$SYSTEM_SCHEDULE" --region "$REGION" --query 'Target.RoleArn' --output text 2>/dev/null || echo "")
    if [[ "$SYSTEM_SCHEDULE_ROLE" == "$SCHEDULER_ROLE_ARN" ]]; then
        echo "[43] [OK] Schedule $SYSTEM_SCHEDULE uses correct role"
    else
        echo "[43] [FAIL] Schedule $SYSTEM_SCHEDULE uses wrong role: $SYSTEM_SCHEDULE_ROLE"
        ERRORS=$((ERRORS + 1))
    fi

    SYSTEM_SCHEDULE_EXPR=$(aws scheduler get-schedule --name "$SYSTEM_SCHEDULE" --region "$REGION" --query 'ScheduleExpression' --output text 2>/dev/null || echo "")
    if [[ "$SYSTEM_SCHEDULE_EXPR" == "$SCHEDULE_EXPRESSION" ]]; then
        echo "[44] [OK] Schedule $SYSTEM_SCHEDULE has correct expression ($SYSTEM_SCHEDULE_EXPR)"
    else
        echo "[44] [FAIL] Schedule $SYSTEM_SCHEDULE has wrong expression: expected '$SCHEDULE_EXPRESSION', got '$SYSTEM_SCHEDULE_EXPR'"
        ERRORS=$((ERRORS + 1))
    fi

    SYSTEM_SCHEDULE_STATE=$(aws scheduler get-schedule --name "$SYSTEM_SCHEDULE" --region "$REGION" --query 'State' --output text 2>/dev/null || echo "")
    if [[ "$SYSTEM_SCHEDULE_STATE" == "ENABLED" ]]; then
        echo "[45] [OK] Schedule $SYSTEM_SCHEDULE is ENABLED"
    else
        echo "[45] [FAIL] Schedule $SYSTEM_SCHEDULE is NOT ENABLED (state: $SYSTEM_SCHEDULE_STATE)"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# ===========================================
# Summary
# ===========================================
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "[OK] All validations passed for: $ENV"
    exit 0
else
    echo "[FAIL] $ERRORS validation(s) failed for: $ENV"
    exit 1
fi

