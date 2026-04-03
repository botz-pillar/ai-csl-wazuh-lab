# Step 3: Generate Security Events

A SIEM with no events is just a fancy dashboard. In this step, you'll simulate real attack patterns and security events so Wazuh has something to detect and alert on.

All commands below should be run on the **agent** machine (the simulated workload) unless stated otherwise.

## SSH Into the Agent

```bash
ssh -i ~/.ssh/wazuh-lab.pem -J ubuntu@$(terraform output -raw manager_public_ip) ubuntu@$(terraform output -raw agent_private_ip)
```

Or use the convenience script:
```bash
# From the repo root
./scripts/generate-events.sh
```

## 1. Failed SSH Login Attempts (Brute Force Simulation)

This triggers Wazuh rule 5710 (authentication failure) and eventually 5712 (brute force detected).

```bash
# Simulate 10 failed SSH login attempts from a fake user
for i in $(seq 1 10); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 fakeuser@localhost 2>/dev/null
  sleep 1
done
```

For a more aggressive simulation:

```bash
# Rapid-fire failed logins — triggers brute force detection faster
for i in $(seq 1 20); do
  sshpass -p 'wrongpassword' ssh -o StrictHostKeyChecking=no testuser@localhost 2>/dev/null &
done
wait
```

> **Note:** `sshpass` may not be installed. Install it with `sudo apt-get install -y sshpass` if needed.

**What Wazuh detects:** Authentication failures, possible brute force attack pattern.

## 2. File Integrity Monitoring (FIM) Events

Wazuh monitors critical directories for changes by default. Let's trigger some alerts.

```bash
# Modify a monitored file
sudo cp /etc/passwd /etc/passwd.bak
sudo sh -c 'echo "# test modification" >> /etc/hosts'

# Create a suspicious file in /etc
sudo touch /etc/suspicious_config.conf
sudo sh -c 'echo "malicious_setting=true" > /etc/suspicious_config.conf'

# Modify system binaries directory (highly suspicious)
sudo touch /usr/bin/definitely_not_malware
sudo chmod +x /usr/bin/definitely_not_malware

# Clean up after yourself
sleep 30  # Wait for Wazuh to detect the changes
sudo rm /etc/passwd.bak /etc/suspicious_config.conf /usr/bin/definitely_not_malware
sudo sed -i '/# test modification/d' /etc/hosts
```

**What Wazuh detects:** File creation, modification, and deletion in monitored directories. Permission changes on system binaries.

## 3. Rootkit Detection

Wazuh runs rootkit checks periodically. You can trigger suspicious patterns:

```bash
# Create a hidden directory (common rootkit behavior)
sudo mkdir /usr/share/...hidden
sudo touch /usr/share/...hidden/payload

# Create a file with a suspicious name
sudo touch /tmp/.backdoor
sudo touch /dev/shm/.secret_process

# Clean up
sleep 60  # Wait for rootcheck scan
sudo rm -rf /usr/share/...hidden /tmp/.backdoor /dev/shm/.secret_process
```

**What Wazuh detects:** Hidden files and directories, suspicious file names in temporary directories.

## 4. Port Scan from the Agent

Simulate reconnaissance activity by scanning the manager from the agent:

```bash
# Quick SYN scan of the manager (nmap should be pre-installed)
MANAGER_IP=$(grep '<address>' /var/ossec/etc/ossec.conf | head -1 | sed 's/.*<address>\(.*\)<\/address>.*/\1/')

# TCP connect scan (doesn't require root)
nmap -sT -p 22,443,1514,1515,55000 $MANAGER_IP

# More aggressive scan — this will definitely generate alerts
sudo nmap -sS -p 1-1000 $MANAGER_IP

# Service version detection
sudo nmap -sV -p 22,443 $MANAGER_IP
```

**What Wazuh detects:** Network scan patterns, multiple connection attempts across ports.

## 5. Privilege Escalation Attempts

```bash
# Multiple sudo failures
for i in $(seq 1 5); do
  sudo -u root -S <<< "wrongpassword" ls /root 2>/dev/null
done

# Attempt to access shadow file as regular user
cat /etc/shadow 2>/dev/null

# Try to modify sudoers
echo "hacker ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/test 2>/dev/null
sudo rm -f /etc/sudoers.d/test
```

**What Wazuh detects:** Failed sudo attempts, unauthorized access to sensitive files.

## 6. Suspicious Process Activity

```bash
# Download a file (potential C2 callback pattern)
curl -s https://example.com/test -o /tmp/downloaded_file 2>/dev/null
rm -f /tmp/downloaded_file

# Run a base64 encoded command (common obfuscation technique)
echo "echo 'this is a test'" | base64 | xargs -I{} bash -c 'echo {} | base64 -d | bash'

# Rapid process creation (potential fork bomb detection)
for i in $(seq 1 50); do
  sleep 0.01 &
done
wait
```

## Using the Event Generator Script

For convenience, there's a script that runs all of the above:

```bash
# From the agent
curl -s https://raw.githubusercontent.com/ai-csl/ai-csl-wazuh-lab/main/scripts/generate-events.sh | bash
```

Or copy the script to the agent and run it:

```bash
# From your local machine (repo root)
scp -i ~/.ssh/wazuh-lab.pem -o ProxyJump=ubuntu@MANAGER_IP scripts/generate-events.sh ubuntu@AGENT_IP:~/
```

## Wait for Alerts

After generating events, give Wazuh **2-5 minutes** to process everything. Then check:

1. **Dashboard** — Go to Security Events. You should see a spike in alerts.
2. **Manager CLI** — Check recent alerts:
   ```bash
   # On the manager
   sudo cat /var/ossec/logs/alerts/alerts.json | tail -50 | jq .
   ```

## What to Look For

You should now have alerts across multiple categories:

| Category | Expected Alert Rules |
|----------|---------------------|
| Authentication | 5710, 5712 (failed logins, brute force) |
| File Integrity | 550, 553, 554 (file added, modified, deleted) |
| Rootkit Detection | 510 (hidden files/directories) |
| Network | Scan detection alerts |
| Privilege Escalation | 5401, 5402 (sudo failures) |

## Next Step

Now that you have real alerts, go to [Step 4: AI Analysis](04-ai-analysis.md) to see how an AI analyst can help you investigate.
