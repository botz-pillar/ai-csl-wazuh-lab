#!/bin/bash
set -euo pipefail

echo "Starting AI-CSL Wazuh Lab instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No stopped lab instances found."
  echo "Either the lab is already running or hasn't been deployed yet."
  exit 0
fi

aws ec2 start-instances --instance-ids $INSTANCE_IDS

echo "Starting instances: $INSTANCE_IDS"
echo "Waiting for instances to be running..."

aws ec2 wait instance-running --instance-ids $INSTANCE_IDS

echo ""
echo "Lab instances are running."
echo "It may take 1-2 minutes for Wazuh services to fully start."
echo ""
echo "Get your connection details:"
echo "  cd terraform && terraform output"
