# Cost Breakdown

This lab is designed to be cheap to run. Here's exactly what you'll pay.

## Hourly Costs (When Running)

| Resource | Type | Hourly Cost |
|----------|------|-------------|
| Wazuh Manager | t3.medium (2 vCPU, 4GB RAM) | $0.0416 |
| Wazuh Agent | t3.micro (2 vCPU, 1GB RAM) | $0.0104 |
| EBS (Manager) | 30GB gp3 | ~$0.003* |
| EBS (Agent) | 20GB gp3 | ~$0.002* |
| Elastic IP | Attached to running instance | $0.00 |
| **Total** | | **~$0.056/hr** |

*EBS is billed monthly but shown as hourly equivalent for comparison.

Prices are for us-east-1. Other regions may vary slightly.

## Scenario Costs

### Weekend Lab (48 hours)

The typical use case — deploy Friday evening, learn over the weekend, destroy Sunday night.

| Resource | Cost |
|----------|------|
| Manager compute (48h) | $2.00 |
| Agent compute (48h) | $0.50 |
| EBS storage (50GB, 2 days) | $0.27 |
| Data transfer (minimal) | ~$0.10 |
| **Total** | **~$2.87** |

### One Week

| Resource | Cost |
|----------|------|
| Manager compute (168h) | $6.99 |
| Agent compute (168h) | $1.75 |
| EBS storage (50GB, 7 days) | $0.93 |
| **Total** | **~$9.67** |

### One Month (Running Continuously)

| Resource | Cost |
|----------|------|
| Manager compute (730h) | $30.37 |
| Agent compute (730h) | $7.59 |
| EBS storage (50GB) | $4.00 |
| Elastic IP | $0.00 |
| **Total** | **~$41.96** |

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
