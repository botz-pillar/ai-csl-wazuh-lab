# Lab IAM User — Recommended Policy

A leaked Codespace, a checked-in credential, a forgotten browser tab — any of them can hand your AWS keys to someone else. The defense is to put a tight policy on the keys you actually use for the lab so the blast radius is bounded.

This document gives you a starter policy. It permits exactly what the AI-CSL labs need and nothing more.

## How to use

1. AWS Console → IAM → Users → Create user
2. Name: `ai-csl-lab` (or similar — single user across all AI-CSL labs is fine)
3. Attach policies → **Create policy** → JSON tab → paste the policy below → name it `AICSLLabPolicy`
4. Back on the user → attach `AICSLLabPolicy`
5. Create access key → "Application running outside AWS" → copy the key + secret
6. Drop them into Codespaces user secrets (<https://github.com/settings/codespaces>)

## Starter policy

> ⚠️ **Read before using.** This grants broad EC2/VPC/IAM-passrole authority, which the lab needs to Terraform infrastructure end-to-end. It is **not** a least-privilege policy for production. Treat the IAM user as scoped to your lab account only.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2AndVPC",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:Describe*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMForLabRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagRole",
        "iam:TagPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3StateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::ai-csl-tfstate-*",
        "arn:aws:s3:::ai-csl-tfstate-*/*"
      ]
    },
    {
      "Sid": "DynamoDBLockTable",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/ai-csl-tfstate-locks"
    },
    {
      "Sid": "BillingVisibility",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "budgets:ViewBudget"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSWhoAmI",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## What this policy does NOT allow

- Account-wide IAM user/group management
- KMS key creation (use AWS-managed keys for lab)
- Route53, CloudFront, RDS — none of the labs use them yet
- Cross-account access

If a future course adds new services, the policy expands here in a single PR rather than students discovering missing permissions mid-lab.
