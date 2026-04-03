#!/bin/bash
set -euo pipefail

# Generate sample security events for the AI-CSL Wazuh Lab
# Run this script on the Wazuh AGENT machine

echo "============================================"
echo "  AI-CSL Wazuh Lab — Event Generator"
echo "============================================"
echo ""
echo "This script generates security events for Wazuh to detect."
echo "Run it on the agent machine."
echo ""

# Check if we're on the agent
if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
  echo "[OK] Wazuh agent is running"
else
  echo "[WARNING] Wazuh agent doesn't appear to be running on this machine."
  echo "Make sure you're running this on the agent, not the manager."
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

MANAGER_IP=$(grep '<address>' /var/ossec/etc/ossec.conf 2>/dev/null | head -1 | sed 's/.*<address>\(.*\)<\/address>.*/\1/' || echo "unknown")
echo "[INFO] Manager IP: $MANAGER_IP"
echo ""

# --------------------------------------------------------------------------
# 1. Failed SSH Login Attempts
# --------------------------------------------------------------------------
echo "--- [1/6] Simulating failed SSH logins (brute force) ---"

for i in $(seq 1 10); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes fakeuser@localhost 2>/dev/null || true
  sleep 0.5
done

echo "[DONE] 10 failed SSH login attempts generated"
echo ""

# --------------------------------------------------------------------------
# 2. File Integrity Monitoring Events
# --------------------------------------------------------------------------
echo "--- [2/6] Triggering file integrity monitoring alerts ---"

sudo sh -c 'echo "# ai-csl-lab test modification" >> /etc/hosts'
sudo touch /etc/ai_csl_test_config.conf
sudo sh -c 'echo "test_setting=true" > /etc/ai_csl_test_config.conf'
sudo touch /usr/bin/ai_csl_test_binary
sudo chmod +x /usr/bin/ai_csl_test_binary

echo "[DONE] FIM events triggered — files created and modified in /etc and /usr/bin"
echo ""

# --------------------------------------------------------------------------
# 3. Rootkit-like Activity
# --------------------------------------------------------------------------
echo "--- [3/6] Creating suspicious hidden files ---"

sudo mkdir -p /usr/share/...ai_csl_hidden
sudo touch /usr/share/...ai_csl_hidden/payload
sudo touch /tmp/.ai_csl_backdoor
sudo touch /dev/shm/.ai_csl_secret

echo "[DONE] Hidden files and directories created"
echo ""

# --------------------------------------------------------------------------
# 4. Port Scanning
# --------------------------------------------------------------------------
echo "--- [4/6] Running port scan against manager ---"

if command -v nmap &>/dev/null && [ "$MANAGER_IP" != "unknown" ]; then
  nmap -sT -p 22,80,443,1514,1515,55000 "$MANAGER_IP" 2>/dev/null || true
  echo "[DONE] Port scan completed"
else
  echo "[SKIP] nmap not available or manager IP unknown"
fi
echo ""

# --------------------------------------------------------------------------
# 5. Privilege Escalation Attempts
# --------------------------------------------------------------------------
echo "--- [5/6] Simulating privilege escalation attempts ---"

for i in $(seq 1 5); do
  echo "wrongpassword" | sudo -S -u root ls /root 2>/dev/null || true
done

cat /etc/shadow 2>/dev/null || true

echo "[DONE] Privilege escalation attempts simulated"
echo ""

# --------------------------------------------------------------------------
# 6. Suspicious Process Activity
# --------------------------------------------------------------------------
echo "--- [6/6] Generating suspicious process activity ---"

curl -s https://example.com -o /tmp/ai_csl_downloaded_file 2>/dev/null || true
rm -f /tmp/ai_csl_downloaded_file

echo "[DONE] Suspicious process activity generated"
echo ""

# --------------------------------------------------------------------------
# Cleanup (after a delay for detection)
# --------------------------------------------------------------------------
echo "Waiting 30 seconds for Wazuh to detect events before cleanup..."
sleep 30

echo "Cleaning up test artifacts..."
sudo sed -i '/# ai-csl-lab test modification/d' /etc/hosts
sudo rm -f /etc/ai_csl_test_config.conf
sudo rm -f /usr/bin/ai_csl_test_binary
sudo rm -rf /usr/share/...ai_csl_hidden
sudo rm -f /tmp/.ai_csl_backdoor
sudo rm -f /dev/shm/.ai_csl_secret

echo ""
echo "============================================"
echo "  Event generation complete!"
echo "============================================"
echo ""
echo "Check the Wazuh dashboard for new alerts."
echo "It may take 2-5 minutes for all events to appear."
echo ""
echo "Next step: Follow the AI analysis guide"
echo "  -> lab-guide/04-ai-analysis.md"
