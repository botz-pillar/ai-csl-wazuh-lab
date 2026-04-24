# Cost Breakdown

This lab is designed to be cheap to run. Here's exactly what you'll pay.

## Hourly Costs (When Running)

| Resource | Type | Hourly Cost |
|----------|------|-------------|
| Wazuh Manager (includes MCP server container) | t3.large (2 vCPU, 8GB RAM) | $0.0832 |
| Wazuh Agents (×3) | t3.micro each (2 vCPU, 1GB RAM) | $0.0312 |
| EBS (Manager) | 30GB gp3 | ~$0.003* |
| EBS (Agents ×3) | 20GB gp3 each | ~$0.008* |
| Elastic IP | Attached to running instance | $0.00 |
| **Total** | | **~$0.126/hr** |

*EBS is billed monthly but shown as hourly equivalent for comparison.

**Why t3.large for the manager?** The Wazuh manager + indexer + dashboard alone uses ~2 GB RAM. Adding the Docker-based MCP server uses another ~300-500 MB. On t3.medium (4 GB), the MCP install would put memory pressure high enough to risk OOM kills on the indexer. t3.large (8 GB) has plenty of headroom and doubles the manager cost from $0.042 to $0.083/hr — worth it for reliability.

Prices are for us-east-1. Other regions may vary slightly.

## Scenario Costs

### Typical 2-hour session (course target)

| Resource | Cost |
|----------|------|
| Manager compute (2h) | $0.17 |
| Agents compute (2h) | $0.06 |
| EBS storage (2h) | $0.02 |
| Data transfer (minimal) | ~$0.01 |
| **Total** | **~$0.26** |

### Weekend Lab (48 hours, forgot to destroy)

| Resource | Cost |
|----------|------|
| Manager compute (48h) | $3.99 |
| Agents compute (48h) | $1.50 |
| EBS storage (50GB, 2 days) | $0.27 |
| Data transfer (minimal) | ~$0.10 |
| **Total** | **~$5.86** |

### One Week (forgot about it entirely)

| Resource | Cost |
|----------|------|
| Manager compute (168h) | $13.98 |
| Agents compute (168h) | $5.25 |
| EBS storage (50GB, 7 days) | $0.93 |
| **Total** | **~$20.16** |

### One Month (Running Continuously — DON'T DO THIS)

| Resource | Cost |
|----------|------|
| Manager compute (730h) | $60.74 |
| Agents compute (730h) | $22.78 |
| EBS storage (50GB) | $4.00 |
| Elastic IP | $0.00 |
| **Total** | **~$87.52** |

### Stopped (Storage Only)

When you stop instances but don't destroy them:

| Resource | Monthly Cost |
|----------|-------------|
| EBS storage (50GB) | $4.00 |
| Elastic IP (unattached) | $3.60 |
| **Total** | **~$7.60/month** |

The Elastic IP costs money when it's allocated but not attached to a running instance. If you're stopping for more than a few days, consider destroying and redeploying instead.

## Cost Optimization Tips

### Use Start/Stop Scripts

Don't leave instances running when you're not using them:

```bash
# Done for the day
./scripts/stop-lab.sh

# Back at it
./scripts/start-lab.sh
```

### Destroy When Done

If you won't use the lab for a week or more, destroy it. Redeploying takes ~15 minutes:

```bash
cd terraform && terraform destroy
```

### Use Spot Instances (Advanced)

For even cheaper compute, you can modify the Terraform to use spot instances. Add to the `aws_instance` resource:

```hcl
instance_market_options {
  market_type = "spot"
  spot_options {
    max_price = "0.02"  # Set your max price
  }
}
```

Spot instances can save 60-90% but may be interrupted. Fine for a lab, not for production.

### Free Tier

If your AWS account is less than 12 months old, t3.micro instances are covered under the free tier (750 hours/month). The agent would be free, saving ~$7.59/month. The manager needs a t3.medium, which is not free tier eligible.

## AWS Billing Alerts

Set up a billing alert so you don't get surprised:

```bash
# Create a $10 billing alarm (requires CloudWatch in us-east-1)
aws cloudwatch put-metric-alarm \
  --alarm-name "ai-csl-lab-spending" \
  --alarm-description "Alert when lab spending exceeds $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:billing-alerts \
  --region us-east-1
```

Or just set one up in the AWS Console under Billing > Budgets.
