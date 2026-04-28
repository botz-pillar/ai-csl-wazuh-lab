#!/usr/bin/env bash
# Post-create setup for the AI-CSL Wazuh lab Codespace.
# Runs once after the container is built. Keep it idempotent and quiet.

set -euo pipefail

echo "==> Installing extras: jq, unzip, openssh-client, dnsutils"
sudo apt-get update -qq
sudo apt-get install -y -qq jq unzip openssh-client dnsutils >/dev/null

echo "==> Tool versions"
terraform version
aws --version
docker --version
gh --version | head -1
jq --version

if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
  echo "==> AWS credentials detected — verifying identity"
  aws sts get-caller-identity || echo "WARN: AWS credentials present but sts call failed (check region/permissions)."
else
  echo "==> AWS credentials not set."
  echo "    Add AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as Codespaces user secrets:"
  echo "    https://github.com/settings/codespaces"
  echo "    Then rebuild the Codespace (Cmd/Ctrl-Shift-P → Codespaces: Rebuild Container)."
fi

echo "==> Codespace ready."
echo "    Next:"
echo "      1. ./scripts/bootstrap-tfstate.sh    (one-time, creates remote state)"
echo "      2. cd terraform && cp terraform.tfvars.example terraform.tfvars"
echo "      3. terraform init -backend-config=backend.hcl"
echo "      4. ./scripts/bootstrap.sh            (deploy + verify)"
