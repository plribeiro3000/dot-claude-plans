#!/bin/bash
# Setup Lambda environment for ECS autoscaling
#
# Usage:
#   ./setup-lambda-env.sh <environment>
#
# Example:
#   ./setup-lambda-env.sh beta-001
#
# Environments: beta-001, demo-001, shared-001, atento-001
#
# This script uses EventBridge Scheduler (recommended) instead of legacy EventBridge Rules.
# Each Lambda gets its own schedule (1 target per schedule, unlike Rules which support multiple).
#
# KNOWN ISSUES AND SOLUTIONS:
# ---------------------------
# 1. "The role defined for the function cannot be assumed by Lambda"
#    Cause: IAM propagation delay (roles take 10-30 seconds to propagate)
#    Solution: Wait 30 seconds and run the script again. It's idempotent.
#
# 2. "ConflictException" on Scheduler create-schedule
#    Cause: Schedule already exists
#    Solution: Script handles this - it will update the existing schedule
#
# 3. "InvalidParameterValueException" on Lambda create
#    Cause: Usually runtime not available or role doesn't exist
#    Solution: Check AWS Lambda supported runtimes, verify role was created
#
# 4. zip files not found
#    Cause: bin/generate_lambda failed or Lambda repo path is wrong
#    Solution: Check LAMBDA_REPO path, run bin/generate_lambda manually

set -e

ENV="${1:?Usage: $0 <environment> (beta-001|demo-001|shared-001|atento-001)}"
LAMBDA_REPO="${LAMBDA_REPO:-$HOME/Projects/4Shark/lambda}"
ORIGINAL_DIR="$(pwd)"
REGION="${AWS_REGION:-us-east-1}"
SCHEDULE_EXPRESSION="${SCHEDULE_EXPRESSION:-rate(1 minute)}"
SKIP_PREREQUISITES="${SKIP_PREREQUISITES:-false}"

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
    *) echo "ERROR: Invalid environment '$ENV'. Must be: beta-001, demo-001, shared-001, atento-001"; exit 1 ;;
esac

CLUSTER="${ENV}-cluster"

# Environment-specific service names
COMMISSION_SERVICE="${ENV}-worker-commission-service"
USER_SERVICE="${ENV}-worker-user-service"
SYSTEM_SERVICE="${ENV}-worker-system-service"

echo ""
echo "=========================================="
echo "  SETUP LAMBDA ENVIRONMENT: $ENV"
echo "=========================================="
echo ""
echo "  Account:  $ACCOUNT_ID"
echo "  Region:   $REGION"
echo "  Cluster:  $CLUSTER"
echo "  Lambda Repo: $LAMBDA_REPO"
echo "  Skip Prerequisites: $SKIP_PREREQUISITES"
echo ""
echo "=========================================="
echo ""

# ===========================================
# PHASE 0: PRE-FLIGHT CHECKS
# ===========================================
echo "==========================================="
echo "  PHASE 0: Pre-flight Checks"
echo "==========================================="
echo ""

# Check Lambda repo exists
echo "[1] Checking Lambda repository exists..."
if [[ ! -d "$LAMBDA_REPO" ]]; then
    echo ""
    echo "ERROR: Lambda repository not found at: $LAMBDA_REPO"
    echo ""
    echo "Solutions:"
    echo "  1. Clone the repository: git clone <repo-url> $LAMBDA_REPO"
    echo "  2. Or update LAMBDA_REPO variable in this script"
    echo ""
    exit 1
fi
echo "       OK: $LAMBDA_REPO exists"

# Check bin/generate_lambda exists
echo "[2] Checking bin/generate_lambda exists..."
if [[ ! -x "$LAMBDA_REPO/bin/generate_lambda" ]]; then
    echo ""
    echo "ERROR: bin/generate_lambda not found or not executable"
    echo ""
    echo "Solutions:"
    echo "  1. Check file exists: ls -la $LAMBDA_REPO/bin/generate_lambda"
    echo "  2. Make it executable: chmod +x $LAMBDA_REPO/bin/generate_lambda"
    echo ""
    exit 1
fi
echo "       OK: bin/generate_lambda exists and is executable"

# Check ECS cluster exists
echo "[3] Checking ECS cluster ${CLUSTER} exists..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${CLUSTER}" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        echo "       WARN: ECS cluster '${CLUSTER}' not found or not ACTIVE (status: $CLUSTER_STATUS)"
        echo "       Continuing because SKIP_PREREQUISITES=true"
    else
        echo ""
        echo "ERROR: ECS cluster '${CLUSTER}' not found or not ACTIVE (status: $CLUSTER_STATUS)"
        echo ""
        echo "This script creates Lambda functions that scale ECS services."
        echo "The ECS cluster must exist before running this script."
        echo ""
        echo "To skip this check: SKIP_PREREQUISITES=true $0 $ENV"
        echo ""
        exit 1
    fi
else
    echo "       OK: Cluster ${CLUSTER} is ACTIVE"
fi

# Check ECS services exist
echo "[4] Checking ECS services exist..."

SERVICE_STATUS=$(aws ecs describe-services --cluster "${CLUSTER}" --services "$COMMISSION_SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$SERVICE_STATUS" != "ACTIVE" && "$SERVICE_STATUS" != "DRAINING" ]]; then
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        echo "       WARN: ECS service '$COMMISSION_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
    else
        echo ""
        echo "ERROR: ECS service '$COMMISSION_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
        echo ""
        echo "The Lambda functions will scale these services. They must exist first."
        echo ""
        echo "To skip this check: SKIP_PREREQUISITES=true $0 $ENV"
        echo ""
        exit 1
    fi
else
    echo "       OK: Service $COMMISSION_SERVICE exists"
fi

SERVICE_STATUS=$(aws ecs describe-services --cluster "${CLUSTER}" --services "$USER_SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$SERVICE_STATUS" != "ACTIVE" && "$SERVICE_STATUS" != "DRAINING" ]]; then
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        echo "       WARN: ECS service '$USER_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
    else
        echo ""
        echo "ERROR: ECS service '$USER_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
        echo ""
        echo "The Lambda functions will scale these services. They must exist first."
        echo ""
        echo "To skip this check: SKIP_PREREQUISITES=true $0 $ENV"
        echo ""
        exit 1
    fi
else
    echo "       OK: Service $USER_SERVICE exists"
fi

SERVICE_STATUS=$(aws ecs describe-services --cluster "${CLUSTER}" --services "$SYSTEM_SERVICE" --region "$REGION" --query 'services[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$SERVICE_STATUS" != "ACTIVE" && "$SERVICE_STATUS" != "DRAINING" ]]; then
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        echo "       WARN: ECS service '$SYSTEM_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
    else
        echo ""
        echo "ERROR: ECS service '$SYSTEM_SERVICE' not found or not ACTIVE (status: $SERVICE_STATUS)"
        echo ""
        echo "The Lambda functions will scale these services. They must exist first."
        echo ""
        echo "To skip this check: SKIP_PREREQUISITES=true $0 $ENV"
        echo ""
        exit 1
    fi
else
    echo "       OK: Service $SYSTEM_SERVICE exists"
fi

echo ""
echo "[PRE-FLIGHT] All checks passed!"
echo ""

# Trust policy for Lambda
TRUST_POLICY_LAMBDA='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

# Trust policy for EventBridge Scheduler
TRUST_POLICY_SCHEDULER='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "scheduler.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

# ===========================================
# PHASE 1: IAM POLICIES
# ===========================================
echo "==========================================="
echo "  PHASE 1: Creating IAM Policies"
echo "==========================================="
echo ""

# Create CloudWatch logs policy
echo "[5] Creating policy: CloudWatch-${ENV}-lambda-logs-policy"
LOGS_POLICY="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"CreateLogGroup\",
            \"Effect\": \"Allow\",
            \"Action\": \"logs:CreateLogGroup\",
            \"Resource\": \"arn:aws:logs:${REGION}:${ACCOUNT_ID}:*\"
        },
        {
            \"Sid\": \"WriteLogs\",
            \"Effect\": \"Allow\",
            \"Action\": [
                \"logs:CreateLogStream\",
                \"logs:PutLogEvents\"
            ],
            \"Resource\": \"arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/Lambda-${ENV}-*:*\"
        }
    ]
}"

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudWatch-${ENV}-lambda-logs-policy" > /dev/null 2>&1; then
    echo "       Policy already exists, skipping..."
else
    aws iam create-policy \
        --policy-name "CloudWatch-${ENV}-lambda-logs-policy" \
        --policy-document "$LOGS_POLICY" \
        --description "CloudWatch Logs permissions for Lambda-${ENV}-* functions" \
        --no-cli-pager
    echo "       Policy created successfully"
fi

# Create ECS policy
echo "[6] Creating policy: ECS-${ENV}-lambda-worker-policy"
ECS_POLICY="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"ECSAccess\",
            \"Effect\": \"Allow\",
            \"Action\": [
                \"ecs:DescribeServices\",
                \"ecs:UpdateService\"
            ],
            \"Resource\": [
                \"arn:aws:ecs:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER}\",
                \"arn:aws:ecs:${REGION}:${ACCOUNT_ID}:service/${CLUSTER}/*\"
            ]
        }
    ]
}"

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ECS-${ENV}-lambda-worker-policy" > /dev/null 2>&1; then
    echo "       Policy already exists, skipping..."
else
    aws iam create-policy \
        --policy-name "ECS-${ENV}-lambda-worker-policy" \
        --policy-document "$ECS_POLICY" \
        --description "ECS permissions for Lambda-${ENV}-worker-* functions" \
        --no-cli-pager
    echo "       Policy created successfully"
fi

# Create EventBridge Scheduler Lambda invoke policy
echo "[7] Creating policy: EventBridge-${ENV}-lambda-invoke-policy"
SCHEDULER_INVOKE_POLICY="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"InvokeLambda\",
            \"Effect\": \"Allow\",
            \"Action\": \"lambda:InvokeFunction\",
            \"Resource\": \"arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-*\"
        }
    ]
}"

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/EventBridge-${ENV}-lambda-invoke-policy" > /dev/null 2>&1; then
    echo "       Policy already exists, skipping..."
else
    aws iam create-policy \
        --policy-name "EventBridge-${ENV}-lambda-invoke-policy" \
        --policy-document "$SCHEDULER_INVOKE_POLICY" \
        --description "EventBridge Scheduler permissions to invoke Lambda-${ENV}-* functions" \
        --no-cli-pager
    echo "       Policy created successfully"
fi

echo ""

# ===========================================
# PHASE 2: IAM ROLES
# ===========================================
echo "==========================================="
echo "  PHASE 2: Creating IAM Roles"
echo "==========================================="
echo ""

# Create commission-autoscaling role
echo "[8] Creating role: Lambda-${ENV}-worker-commission-autoscaling-role"
if aws iam get-role --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" > /dev/null 2>&1; then
    echo "       Role already exists, skipping..."
else
    aws iam create-role \
        --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" \
        --assume-role-policy-document "$TRUST_POLICY_LAMBDA" \
        --description "Execution role for Lambda-${ENV}-worker-commission-autoscaling" \
        --no-cli-pager
    echo "       Role created successfully"
fi

# Attach logs policy to commission-autoscaling role
echo "[9] Attaching CloudWatch policy to commission-autoscaling role"
if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" --query "AttachedPolicies[?PolicyName=='CloudWatch-${ENV}-lambda-logs-policy']" --output text 2>/dev/null | grep -q CloudWatch; then
    echo "       Policy already attached, skipping..."
else
    aws iam attach-role-policy \
        --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudWatch-${ENV}-lambda-logs-policy"
    echo "       Policy attached successfully"
fi

# Attach ECS policy to commission-autoscaling role
echo "[10] Attaching ECS policy to commission-autoscaling role"
if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" --query "AttachedPolicies[?PolicyName=='ECS-${ENV}-lambda-worker-policy']" --output text 2>/dev/null | grep -q ECS; then
    echo "       Policy already attached, skipping..."
else
    aws iam attach-role-policy \
        --role-name "Lambda-${ENV}-worker-commission-autoscaling-role" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ECS-${ENV}-lambda-worker-policy"
    echo "       Policy attached successfully"
fi

# Create standard-autoscaling role
echo "[11] Creating role: Lambda-${ENV}-worker-standard-autoscaling-role"
if aws iam get-role --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" > /dev/null 2>&1; then
    echo "       Role already exists, skipping..."
else
    aws iam create-role \
        --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" \
        --assume-role-policy-document "$TRUST_POLICY_LAMBDA" \
        --description "Execution role for Lambda-${ENV}-worker-user-autoscaling and Lambda-${ENV}-worker-system-autoscaling" \
        --no-cli-pager
    echo "       Role created successfully"
fi

# Attach logs policy to standard-autoscaling role
echo "[12] Attaching CloudWatch policy to standard-autoscaling role"
if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" --query "AttachedPolicies[?PolicyName=='CloudWatch-${ENV}-lambda-logs-policy']" --output text 2>/dev/null | grep -q CloudWatch; then
    echo "       Policy already attached, skipping..."
else
    aws iam attach-role-policy \
        --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudWatch-${ENV}-lambda-logs-policy"
    echo "       Policy attached successfully"
fi

# Attach ECS policy to standard-autoscaling role
echo "[13] Attaching ECS policy to standard-autoscaling role"
if aws iam list-attached-role-policies --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" --query "AttachedPolicies[?PolicyName=='ECS-${ENV}-lambda-worker-policy']" --output text 2>/dev/null | grep -q ECS; then
    echo "       Policy already attached, skipping..."
else
    aws iam attach-role-policy \
        --role-name "Lambda-${ENV}-worker-standard-autoscaling-role" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ECS-${ENV}-lambda-worker-policy"
    echo "       Policy attached successfully"
fi

# Create EventBridge Scheduler role
echo "[14] Creating role: EventBridge-${ENV}-scheduler-role"
if aws iam get-role --role-name "EventBridge-${ENV}-scheduler-role" > /dev/null 2>&1; then
    echo "       Role already exists, skipping..."
else
    aws iam create-role \
        --role-name "EventBridge-${ENV}-scheduler-role" \
        --assume-role-policy-document "$TRUST_POLICY_SCHEDULER" \
        --description "Execution role for EventBridge Scheduler to invoke Lambda-${ENV}-* functions" \
        --no-cli-pager
    echo "       Role created successfully"
fi

# Attach invoke policy to scheduler role
echo "[15] Attaching Lambda invoke policy to scheduler role"
if aws iam list-attached-role-policies --role-name "EventBridge-${ENV}-scheduler-role" --query "AttachedPolicies[?PolicyName=='EventBridge-${ENV}-lambda-invoke-policy']" --output text 2>/dev/null | grep -q EventBridge; then
    echo "       Policy already attached, skipping..."
else
    aws iam attach-role-policy \
        --role-name "EventBridge-${ENV}-scheduler-role" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/EventBridge-${ENV}-lambda-invoke-policy"
    echo "       Policy attached successfully"
fi

echo ""
echo "[IAM] Waiting 15 seconds for IAM propagation..."
echo "      (If Lambda creation fails with 'role cannot be assumed', run script again)"
sleep 15
echo ""

# ===========================================
# PHASE 3: GENERATE LAMBDA PACKAGES
# ===========================================
echo "==========================================="
echo "  PHASE 3: Generating Lambda Packages"
echo "==========================================="
echo ""

echo "[16] Changing to Lambda repository: $LAMBDA_REPO"
cd "$LAMBDA_REPO"

echo "[17] Cleaning dist/ directory..."
./bin/generate_lambda --clean

echo "[18] Running bin/generate_lambda to create zip packages..."
./bin/generate_lambda --lambda-name worker-commission-autoscaling
./bin/generate_lambda --lambda-name worker-autoscaling

echo "[19] Copying zip files from dist/ to working directory..."
# bin/generate_lambda outputs to dist/ with timestamp, copy latest to expected names
LATEST_COMMISSION=$(ls -t dist/worker-commission-autoscaling_*.zip 2>/dev/null | head -1)
LATEST_STANDARD=$(ls -t dist/worker-autoscaling_*.zip 2>/dev/null | head -1)

if [[ -z "$LATEST_COMMISSION" ]]; then
    echo ""
    echo "ERROR: No worker-commission-autoscaling zip found in dist/"
    echo ""
    exit 1
fi

if [[ -z "$LATEST_STANDARD" ]]; then
    echo ""
    echo "ERROR: No worker-autoscaling zip found in dist/"
    echo ""
    exit 1
fi

cp "$LATEST_COMMISSION" worker-commission-autoscaling.zip
echo "       Copied: $LATEST_COMMISSION -> worker-commission-autoscaling.zip"

cp "$LATEST_STANDARD" worker-autoscaling.zip
echo "       Copied: $LATEST_STANDARD -> worker-autoscaling.zip"

echo "[20] Verifying zip files are ready..."

if [[ -f "worker-commission-autoscaling.zip" ]]; then
    echo "       Found: worker-commission-autoscaling.zip ($(du -h "worker-commission-autoscaling.zip" | cut -f1))"
else
    echo ""
    echo "ERROR: worker-commission-autoscaling.zip not found!"
    echo ""
    echo "The copy from dist/ should have created this file."
    echo "Check the output above for errors."
    echo ""
    exit 1
fi

if [[ -f "worker-autoscaling.zip" ]]; then
    echo "       Found: worker-autoscaling.zip ($(du -h "worker-autoscaling.zip" | cut -f1))"
else
    echo ""
    echo "ERROR: worker-autoscaling.zip not found!"
    echo ""
    echo "The copy from dist/ should have created this file."
    echo "Check the output above for errors."
    echo ""
    exit 1
fi

echo ""

# ===========================================
# PHASE 4: CREATE LAMBDA FUNCTIONS
# ===========================================
echo "==========================================="
echo "  PHASE 4: Creating Lambda Functions"
echo "==========================================="
echo ""

# Commission autoscaling Lambda
echo "[21] Creating Lambda: Lambda-${ENV}-worker-commission-autoscaling"
if aws lambda get-function --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "       Lambda already exists, updating code and configuration..."

    # Update code
    aws lambda update-function-code \
        --function-name "Lambda-${ENV}-worker-commission-autoscaling" \
        --zip-file "fileb://worker-commission-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    # Update configuration (role, env vars, etc)
    aws lambda update-function-configuration \
        --function-name "Lambda-${ENV}-worker-commission-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-commission-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${COMMISSION_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=15,PROCESS_NAME=worker_commission}" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for configuration update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-commission-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    echo "       Code and configuration updated successfully"
else
    echo "       Creating new Lambda function..."

    # Create function; if IAM propagation fails, rerun script (it's idempotent)
    if ! aws lambda create-function \
        --function-name "Lambda-${ENV}-worker-commission-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-commission-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${COMMISSION_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=15,PROCESS_NAME=worker_commission}" \
        --zip-file "fileb://worker-commission-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager; then

        echo ""
        echo "ERROR: Failed to create Lambda function 'Lambda-${ENV}-worker-commission-autoscaling'"
        echo ""
        echo "If the error mentions 'role cannot be assumed by Lambda':"
        echo "  This is an IAM propagation delay. Wait 30 seconds and run this script again."
        echo "  The script is idempotent - it will skip already-created resources."
        echo ""
        exit 1
    fi

    echo "       Lambda created successfully"
fi

# User autoscaling Lambda
echo "[22] Creating Lambda: Lambda-${ENV}-worker-user-autoscaling"
if aws lambda get-function --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "       Lambda already exists, updating code and configuration..."

    # Update code
    aws lambda update-function-code \
        --function-name "Lambda-${ENV}-worker-user-autoscaling" \
        --zip-file "fileb://worker-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    # Update configuration (role, env vars, etc)
    aws lambda update-function-configuration \
        --function-name "Lambda-${ENV}-worker-user-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-standard-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${USER_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=5,PROCESS_NAME=worker_user}" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for configuration update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-user-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    echo "       Code and configuration updated successfully"
else
    echo "       Creating new Lambda function..."

    # Create function; if IAM propagation fails, rerun script (it's idempotent)
    if ! aws lambda create-function \
        --function-name "Lambda-${ENV}-worker-user-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-standard-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${USER_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=5,PROCESS_NAME=worker_user}" \
        --zip-file "fileb://worker-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager; then

        echo ""
        echo "ERROR: Failed to create Lambda function 'Lambda-${ENV}-worker-user-autoscaling'"
        echo ""
        echo "If the error mentions 'role cannot be assumed by Lambda':"
        echo "  This is an IAM propagation delay. Wait 30 seconds and run this script again."
        echo "  The script is idempotent - it will skip already-created resources."
        echo ""
        exit 1
    fi

    echo "       Lambda created successfully"
fi

# System autoscaling Lambda
echo "[23] Creating Lambda: Lambda-${ENV}-worker-system-autoscaling"
if aws lambda get-function --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" > /dev/null 2>&1; then
    echo "       Lambda already exists, updating code and configuration..."

    # Update code
    aws lambda update-function-code \
        --function-name "Lambda-${ENV}-worker-system-autoscaling" \
        --zip-file "fileb://worker-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    # Update configuration (role, env vars, etc)
    aws lambda update-function-configuration \
        --function-name "Lambda-${ENV}-worker-system-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-standard-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${SYSTEM_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=5,PROCESS_NAME=worker_system}" \
        --region "$REGION" \
        --no-cli-pager > /dev/null

    # Wait for configuration update to complete
    aws lambda wait function-updated --function-name "Lambda-${ENV}-worker-system-autoscaling" --region "$REGION" 2>/dev/null || sleep 5

    echo "       Code and configuration updated successfully"
else
    echo "       Creating new Lambda function..."

    # Create function; if IAM propagation fails, rerun script (it's idempotent)
    if ! aws lambda create-function \
        --function-name "Lambda-${ENV}-worker-system-autoscaling" \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/Lambda-${ENV}-worker-standard-autoscaling-role" \
        --runtime ruby3.4 \
        --handler lambda_function.lambda_handler \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={ECS_CLUSTER_NAME=${CLUSTER},ECS_SERVICE_NAME=${SYSTEM_SERVICE},MINIMUM_CAPACITY=1,MAXIMUM_CAPACITY=5,PROCESS_NAME=worker_system}" \
        --zip-file "fileb://worker-autoscaling.zip" \
        --region "$REGION" \
        --no-cli-pager; then

        echo ""
        echo "ERROR: Failed to create Lambda function 'Lambda-${ENV}-worker-system-autoscaling'"
        echo ""
        echo "If the error mentions 'role cannot be assumed by Lambda':"
        echo "  This is an IAM propagation delay. Wait 30 seconds and run this script again."
        echo "  The script is idempotent - it will skip already-created resources."
        echo ""
        exit 1
    fi

    echo "       Lambda created successfully"
fi

echo ""

# ===========================================
# PHASE 5: EVENTBRIDGE SCHEDULER
# ===========================================
echo "==========================================="
echo "  PHASE 5: Creating EventBridge Schedules"
echo "==========================================="
echo ""

SCHEDULER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/EventBridge-${ENV}-scheduler-role"

# Commission autoscaling schedule
echo "[24] Creating schedule: Lambda-${ENV}-worker-commission-autoscaling-schedule"
COMMISSION_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-commission-autoscaling"

if aws scheduler get-schedule --name "Lambda-${ENV}-worker-commission-autoscaling-schedule" --region "$REGION" > /dev/null 2>&1; then
    echo "       Schedule already exists, updating..."
    aws scheduler update-schedule \
        --name "Lambda-${ENV}-worker-commission-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${COMMISSION_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule updated successfully"
else
    aws scheduler create-schedule \
        --name "Lambda-${ENV}-worker-commission-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${COMMISSION_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule created successfully"
fi

# User autoscaling schedule
echo "[25] Creating schedule: Lambda-${ENV}-worker-user-autoscaling-schedule"
USER_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-user-autoscaling"

if aws scheduler get-schedule --name "Lambda-${ENV}-worker-user-autoscaling-schedule" --region "$REGION" > /dev/null 2>&1; then
    echo "       Schedule already exists, updating..."
    aws scheduler update-schedule \
        --name "Lambda-${ENV}-worker-user-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${USER_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule updated successfully"
else
    aws scheduler create-schedule \
        --name "Lambda-${ENV}-worker-user-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${USER_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule created successfully"
fi

# System autoscaling schedule
echo "[26] Creating schedule: Lambda-${ENV}-worker-system-autoscaling-schedule"
SYSTEM_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:Lambda-${ENV}-worker-system-autoscaling"

if aws scheduler get-schedule --name "Lambda-${ENV}-worker-system-autoscaling-schedule" --region "$REGION" > /dev/null 2>&1; then
    echo "       Schedule already exists, updating..."
    aws scheduler update-schedule \
        --name "Lambda-${ENV}-worker-system-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${SYSTEM_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule updated successfully"
else
    aws scheduler create-schedule \
        --name "Lambda-${ENV}-worker-system-autoscaling-schedule" \
        --schedule-expression "$SCHEDULE_EXPRESSION" \
        --flexible-time-window '{"Mode": "OFF"}' \
        --target "{\"Arn\": \"${SYSTEM_LAMBDA_ARN}\", \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\"}" \
        --state ENABLED \
        --region "$REGION" \
        --no-cli-pager > /dev/null
    echo "       Schedule created successfully"
fi

echo ""

# ===========================================
# SUMMARY
# ===========================================
echo "==========================================="
echo "  SETUP COMPLETE: $ENV"
echo "==========================================="
echo ""
echo "  Created/Updated resources:"
echo "    - Policy: CloudWatch-${ENV}-lambda-logs-policy"
echo "    - Policy: ECS-${ENV}-lambda-worker-policy"
echo "    - Policy: EventBridge-${ENV}-lambda-invoke-policy"
echo "    - Role: Lambda-${ENV}-worker-commission-autoscaling-role"
echo "    - Role: Lambda-${ENV}-worker-standard-autoscaling-role"
echo "    - Role: EventBridge-${ENV}-scheduler-role"
echo "    - Lambda: Lambda-${ENV}-worker-commission-autoscaling"
echo "    - Lambda: Lambda-${ENV}-worker-user-autoscaling"
echo "    - Lambda: Lambda-${ENV}-worker-system-autoscaling"
echo "    - Schedule: Lambda-${ENV}-worker-commission-autoscaling-schedule"
echo "    - Schedule: Lambda-${ENV}-worker-user-autoscaling-schedule"
echo "    - Schedule: Lambda-${ENV}-worker-system-autoscaling-schedule"
echo ""
echo "  Next step:"
echo "    Run ./validate-lambda-env.sh $ENV"
echo ""
echo "==========================================="

# Cleanup temporary files
rm -f "$LAMBDA_REPO/worker-autoscaling.zip"
rm -f "$LAMBDA_REPO/worker-commission-autoscaling.zip"

# Return to original directory
cd "$ORIGINAL_DIR"
