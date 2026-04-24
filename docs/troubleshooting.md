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

---

## MCP-specific issues

### `/mcp` in Claude Code shows nothing or "no servers configured"

`.mcp.json` isn't present in the current directory, OR Claude Code was launched in a different directory than the repo root. Verify:
```bash
ls -la .mcp.json   # should be present in the repo root
```
If missing, re-run `./scripts/bootstrap.sh` — the MCP-wiring step writes it.

### `/mcp` shows `wazuh` but status is `failed` or `disconnected`

Three causes in order of likelihood:

1. **Claude Code started before bootstrap finished.** MCP config is loaded only at session start. `/exit` and re-launch `claude`.
2. **JWT expired (24h default TTL).** Re-run `./scripts/bootstrap.sh` to write a fresh `.mcp.json`.
3. **IP changed since deploy.** SG allows port 3000 only from your tfvars IP. If `curl ifconfig.me` differs from what's in `tfvars`, update tfvars and run `terraform apply`.

### Container not running on the manager

```bash
MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'sudo docker ps -a | grep wazuh-mcp'
```
If the container is in `Exited` state, grab logs:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'cd /opt/wazuh-mcp && sudo docker compose logs --tail 100'
```
Restart:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'cd /opt/wazuh-mcp && sudo docker compose up -d'
```

### MCP responds but every tool call returns 401/403 against Wazuh

The MCP reached itself but can't authenticate to Wazuh. Check `.env` on the manager:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'sudo cat /opt/wazuh-mcp/.env | grep -E "WAZUH_(USER|PASS|VERIFY)"'
```
Compare `WAZUH_PASS` against the `wazuh-wui` password in `/root/wazuh-install-files/wazuh-passwords.txt`. `WAZUH_VERIFY_SSL` must be `false` for the self-signed cert on the manager.

### "Invalid or expired token" from /auth/token

The `MCP_API_KEY` you sent doesn't match what's in `.env`. Verify:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'sudo cat /root/wazuh-mcp-api-key.txt'
```
This is the authoritative API key. If it's different from what you sent to `/auth/token`, you have a stale value.

---

## Known upstream quirks

### Rule 510 on `/bin/diff`

Wazuh's rootcheck flags `/bin/diff` as a hidden-file anomaly routinely. It's a known false positive. Document and ignore — don't try to suppress it unless it's genuinely cluttering your view.

### `wazuh_firewall_allow` active-response quirk

The stock `firewall-drop` active-response pathway has edge cases around unblocking. Always use duration-based blocks (`<timeout>300</timeout>` in AR config, or a duration argument via MCP) so rules auto-expire. Permanent blocks accumulate and eventually cause outages. See SKILL.md §11 Step 11.5 for the pattern.
