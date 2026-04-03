# Step 5: Teardown

When you're done with the lab, clean everything up to stop incurring charges.

## Option A: Stop Instances (Pause the Lab)

If you want to come back later, stop the instances instead of destroying them. You'll keep your configuration and data but stop paying for compute.

```bash
# From the repo root
./scripts/stop-lab.sh
```

Or manually:
```bash
cd terraform
MANAGER_ID=$(terraform output -raw manager_public_ip 2>/dev/null)

aws ec2 stop-instances --instance-ids \
  $(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text)
```

**Cost when stopped:**
- EBS storage: ~$4/month (50GB total)
- Elastic IP (unattached): $0.005/hr (~$3.60/month)
- **Total when stopped: ~$7.60/month**

To resume later:
```bash
./scripts/start-lab.sh
```

## Option B: Destroy Everything (Full Cleanup)

To completely remove all resources and stop all charges:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This removes:
- Both EC2 instances and their EBS volumes
- The Elastic IP
- Security groups
- Subnet, route table, internet gateway
- The VPC

**After destroy, your cost is $0.**

## Verify Cleanup

After destroying, confirm nothing is left:

```bash
# Check for any remaining resources with the lab tag
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table

# Check for orphaned Elastic IPs
aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" \
  --output table
```

Both should return empty results.

## Cost Summary

| Scenario | Cost |
|----------|------|
| Running for a weekend (48h) | ~$3-5 |
| Running for a week | ~$10-12 |
| Stopped (storage only) | ~$7.60/month |
| Destroyed | $0 |
| Left running and forgot about it | ~$42/month |

The last row is why teardown matters. Set a calendar reminder if you plan to leave it running.

## What to Keep

Before destroying, you might want to save:
- Your Terraform state (`terraform.tfstate`) if you want to reference outputs later
- Any custom Wazuh rules you created
- Alert data exports from the dashboard
- Screenshots of interesting findings

## Re-deploying

To run the lab again later, just start from [Step 1: Deploy](01-deploy.md). The whole process takes about 15 minutes. Your Terraform configuration is ready to go.
