# Troubleshooting

## Wazuh Dashboard Not Loading

**Symptom:** Can't reach `https://<manager-ip>`

1. Check the instance is running: `aws ec2 describe-instances --filters "Name=tag:Name,Values=wazuh-manager-lab"`
2. Check security group allows port 443 from your IP
3. SSH in and check services: `sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard`
4. Bootstrap may still be running — wait 10-15 minutes after first launch: `sudo tail -f /var/log/cloud-init-output.log`

## Agent Not Registering

**Symptom:** No agents showing in Wazuh dashboard

1. SSH to agent: `sudo systemctl status wazuh-agent`
2. Check manager IP is correct in agent config: `cat /var/ossec/etc/ossec.conf | grep address`
3. Check security group on manager allows 1514/1515 from agent security group
4. Restart agent: `sudo systemctl restart wazuh-agent`

## Terraform Apply Fails

**Invalid key pair:** Make sure the key pair exists in the correct region: `aws ec2 describe-key-pairs --region us-east-1`

**IP CIDR format:** your_ip_cidr must be in CIDR format: `curl ifconfig.me` then add `/32` — e.g., `1.2.3.4/32`

**Insufficient capacity:** Try a different availability zone or instance type.

## SSH Connection Refused

1. Confirm the instance is running and has finished booting (2-3 min)
2. Confirm your key file permissions: `chmod 400 your-key.pem`
3. Confirm your IP hasn't changed since you ran Terraform: `curl ifconfig.me`

## High CPU on Manager

Wazuh indexer is memory-hungry. t3.medium is the minimum — if you see constant high CPU, the instance is undersized. Upgrade to t3.large if budget allows for extended labs.

## Can't Afford to Leave It Running?

Use the stop script: `bash scripts/stop-lab.sh`

This stops instances but keeps your data. Resume anytime with `bash scripts/start-lab.sh`.

Cost when stopped: ~$0.005/hr for the Elastic IP. Essentially free.
