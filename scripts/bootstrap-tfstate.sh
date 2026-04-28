#!/usr/bin/env bash
# One-time bootstrap: creates the S3 bucket + DynamoDB lock table that
# Terraform will use as its remote backend, then writes terraform/backend.hcl
# so subsequent `terraform init` runs find them.
#
# Idempotent — safe to re-run; it skips resources that already exist.
#
# Why remote state: Codespaces are ephemeral. Local terraform.tfstate would
# disappear with the container. S3 backend keeps state durable so you can
# destroy the Codespace, spin up a new one, and pick up where you left off.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="ai-csl-tfstate-${ACCOUNT_ID}"
TABLE="ai-csl-tfstate-locks"
KEY="wazuh-lab/terraform.tfstate"

echo "==> Account: ${ACCOUNT_ID}"
echo "==> Region:  ${REGION}"
echo "==> Bucket:  ${BUCKET}"
echo "==> Table:   ${TABLE}"

# --- S3 bucket ---------------------------------------------------------------
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "==> Bucket already exists — skipping create."
else
  echo "==> Creating S3 bucket"
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi

  aws s3api put-bucket-versioning \
    --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "${BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws s3api put-public-access-block \
    --bucket "${BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

# --- DynamoDB lock table ----------------------------------------------------
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "==> Lock table already exists — skipping create."
else
  echo "==> Creating DynamoDB lock table"
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" >/dev/null
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

# --- backend.hcl ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_FILE="${SCRIPT_DIR}/../terraform/backend.hcl"
cat > "${BACKEND_FILE}" <<EOF
bucket         = "${BUCKET}"
key            = "${KEY}"
region         = "${REGION}"
dynamodb_table = "${TABLE}"
encrypt        = true
EOF

echo "==> Wrote ${BACKEND_FILE}"
echo
echo "Next:"
echo "  cd terraform"
echo "  terraform init -backend-config=backend.hcl"
