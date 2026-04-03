# Step 1: Deploy the Lab

In this step, you'll use Terraform to deploy the entire Wazuh SIEM lab on AWS. By the end, you'll have a Wazuh manager and agent running in a VPC.

## Prerequisites

Before you start, make sure you have:

- **AWS CLI** configured with credentials (`aws sts get-caller-identity` should return your account)
- **Terraform** >= 1.5 installed (`terraform version`)
- **EC2 Key Pair** in your target region. If you don't have one:
  ```bash
  aws ec2 create-key-pair --key-name wazuh-lab --query 'KeyMaterial' --output text > ~/.ssh/wazuh-lab.pem
  chmod 400 ~/.ssh/wazuh-lab.pem
  ```

## Find Your Public IP

You'll need this to restrict access to just your machine:

```bash
curl -s https://checkip.amazonaws.com
```

Take that IP and add `/32` to make it a CIDR block (e.g., `203.0.113.50/32`).

## Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
your_ip_cidr = "203.0.113.50/32"   # Your IP from above
key_name     = "wazuh-lab"          # Your key pair name
```

## Deploy

```bash
# Initialize Terraform (downloads the AWS provider)
terraform init

# Preview what will be created
terraform plan

# Deploy — type 'yes' when prompted
terraform apply
```

This creates:
- A VPC with public subnet, internet gateway, and route table
- Security groups for the manager and agent
- A t3.medium EC2 instance for the Wazuh manager (all-in-one: manager + indexer + dashboard)
- A t3.micro EC2 instance for the Wazuh agent
- An Elastic IP for the manager

## Wait for Installation

The Wazuh installation runs automatically via user data scripts. It takes **8-12 minutes** to complete.

You can monitor progress by SSHing into the manager:

```bash
# Use the SSH command from Terraform output
terraform output ssh_manager_command

# Then watch the install log
tail -f /var/log/wazuh-install.log
```

You'll know it's done when you see:
```
=== Wazuh Manager installation completed ===
```

## Save Your Outputs

```bash
terraform output
```

You'll need these values in the next steps:
- `wazuh_dashboard_url` — where to access the dashboard
- `manager_public_ip` — for SSH and API access
- `ssh_manager_command` — ready-to-use SSH command
- `ssh_agent_command` — SSH to the agent via the manager

## Get Your Dashboard Password

SSH into the manager and retrieve the admin password:

```bash
ssh -i ~/.ssh/wazuh-lab.pem ubuntu@$(terraform output -raw manager_public_ip)
sudo cat /root/wazuh-install-files/wazuh-passwords.txt
```

Look for the line with `admin` — that's your dashboard login. Save this password somewhere safe.

## Next Step

Go to [Step 2: Verify Wazuh](02-verify.md) to confirm everything is working.
