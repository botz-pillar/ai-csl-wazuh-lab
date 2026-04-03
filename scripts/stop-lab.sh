#!/bin/bash
set -euo pipefail

echo "Stopping AI-CSL Wazuh Lab instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No running lab instances found."
  exit 0
fi

aws ec2 stop-instances --instance-ids $INSTANCE_IDS

echo "Stopping instances: $INSTANCE_IDS"
echo "Waiting for instances to stop..."

aws ec2 wait instance-stopped --instance-ids $INSTANCE_IDS

echo ""
echo "Lab instances are stopped."
echo "You're now only paying for EBS storage (~$4/month) and the Elastic IP ($0.005/hr)."
echo ""
echo "To resume: ./scripts/start-lab.sh"
echo "To destroy: cd terraform && terraform destroy"
