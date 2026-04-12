#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/wazuh-agent-install.log) 2>&1
echo "=== Wazuh Agent installation started at $(date) ==="
echo "=== Agent Name: ${agent_name} ==="
echo "=== Wazuh Version: ${wazuh_version} ==="

MANAGER_IP="${manager_ip}"
AGENT_NAME="${agent_name}"
WAZUH_VERSION="${wazuh_version}"

# Wait for apt to be available. Note: we don't use `cloud-init status --wait`
# here because THIS script IS cloud-init's final stage — calling that command
# would deadlock (wait for yourself to finish).
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# System update (no full upgrade — AMI is recent, saves 10+ minutes on t3.micro)
apt-get update -y

# Add the Wazuh agent repository
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
apt-get update -y

# Install the agent with version pinned to match the manager.
# Wazuh rejects agents whose version is higher than the manager's.
WAZUH_MANAGER="$MANAGER_IP" WAZUH_AGENT_NAME="$AGENT_NAME" apt-get install -y "wazuh-agent=$${WAZUH_VERSION}-1"

# Install tools needed for lab simulations
apt-get install -y nmap net-tools sshpass

# --- CloudVault Financial Setup ---

mkdir -p /opt/cloudvault/{client-data,financial-records,config,logs}

case "$AGENT_NAME" in
  "web-server-01")
    echo "CloudVault Customer Portal - Production" > /opt/cloudvault/config/app.conf
    echo "server.port=443" >> /opt/cloudvault/config/app.conf
    echo "server.ssl=true" >> /opt/cloudvault/config/app.conf
    echo "session.timeout=3600" >> /opt/cloudvault/config/app.conf
    apt-get install -y nginx
    ;;
  "app-server-01")
    echo "CloudVault API Server - Production" > /opt/cloudvault/config/api.conf
    echo "api.port=8443" >> /opt/cloudvault/config/api.conf
    echo "db.host=cloudvault-prod-db.internal" >> /opt/cloudvault/config/api.conf
    echo "db.port=5432" >> /opt/cloudvault/config/api.conf
    echo "api.rate_limit=100" >> /opt/cloudvault/config/api.conf
    ;;
  "dev-server-01")
    echo "CloudVault Development Environment" > /opt/cloudvault/config/dev.conf
    mkdir -p /opt/cloudvault/dev/{scripts,credentials,temp}
    echo "# FAKE CREDENTIALS - Lab training data only" > /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "aws_access_key_id=AKIAIOSFODNN7EXAMPLE" >> /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" >> /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "# FAKE CREDENTIALS - Lab training data only" > /opt/cloudvault/dev/credentials/.env
    echo "DB_PASSWORD=cloudvault_dev_2026" >> /opt/cloudvault/dev/credentials/.env
    ;;
esac

# Sample client data (monitored by FIM)
cat > /opt/cloudvault/client-data/client-index.csv << 'DATAEOF'
client_id,name,aum,risk_profile,last_review
CV-001,Peterson Trust,4500000,moderate,2026-03-15
CV-002,Morrison Family,2100000,conservative,2026-02-28
CV-003,Chen Holdings,8900000,aggressive,2026-03-01
CV-004,Wellington Partners,12300000,moderate,2026-01-15
CV-005,Nakamura Estate,3200000,conservative,2026-03-20
DATAEOF

# Sample financial records (monitored by FIM)
cat > /opt/cloudvault/financial-records/q1-2026-fees.csv << 'FEESEOF'
client_id,quarter,advisory_fee,transaction_fee,total
CV-001,Q1-2026,5625,1200,6825
CV-002,Q1-2026,2625,450,3075
CV-003,Q1-2026,11125,2800,13925
CV-004,Q1-2026,15375,3100,18475
CV-005,Q1-2026,4000,800,4800
FEESEOF

# Configure FIM for CloudVault directories.
# Must use sed to insert BEFORE </ossec_config> — appending produces invalid XML
# and the agent fails to start with "Invalid element in the configuration".
sed -i '/<\/ossec_config>/i\
\
<!-- CloudVault Financial - Custom FIM monitoring -->\
<syscheck>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/client-data</directories>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/financial-records</directories>\
  <directories check_all="yes" realtime="yes">/opt/cloudvault/config</directories>\
</syscheck>' /var/ossec/etc/ossec.conf

# --- Install the event generation script INLINE (no external URL dependency) ---
cat > /home/ubuntu/generate-events.sh << 'GENEVENTSEOF'
#!/bin/bash
# CloudVault Financial - Wazuh Lab Event Generator
#
# SAFETY: This script only targets the local machine. It does NOT reach
# external systems. All artifacts are cleaned up after detection. Only run
# on your own lab instances.
#
# The script runs four short attack scenarios, each tied to a MITRE ATT&CK
# technique. Each produces Wazuh alerts you can investigate.

set -uo pipefail

cat << 'BANNER'
============================================
  CloudVault Wazuh Lab - Attack Simulations
============================================

This will run 4 scenarios against this instance:

  1. SSH brute force                             (MITRE T1110.001)
  2. Unauthorized data access on client records  (MITRE T1565.001)
  3. Privilege escalation attempts               (MITRE T1548)
  4. Persistence via hidden files                (MITRE T1564.001)

Each scenario produces alerts Wazuh ingests within ~60 seconds.
BANNER

echo ""
read -p "Press Enter to start scenario 1, or Ctrl+C to cancel..."

# --- Scenario 1: SSH brute force (MITRE T1110.001) ---
echo ""
echo "--- [1/4] SSH brute force ---"
echo "What this does: generates 15 failed SSH login attempts against localhost."
echo "How Wazuh detects it: sshd writes each failure to /var/log/auth.log."
echo "Wazuh's decoder parses those lines and fires rule 5710 (invalid user)"
echo "or 5712 (valid user, wrong password). Many failures in a short window"
echo "can also trigger composite rules like 5720 (multiple auth failures)."
echo ""

for i in $(seq 1 15); do
  sshpass -p "wrongpass$i" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
    "fakeuser$i@localhost" exit 2>/dev/null || true
  echo "  Attempt $i/15 (failed login as fakeuser$i)"
  sleep 0.5
done
echo "[DONE] 15 failed SSH attempts generated."

# --- Scenario 2: Unauthorized data access (MITRE T1565.001) ---
echo ""
echo "--- [2/4] Unauthorized data access ---"
echo "What this does: modifies files in CloudVault's client-data and"
echo "financial-records directories."
echo "How Wazuh detects it: FIM (File Integrity Monitoring) is configured"
echo "in realtime mode on these paths. Any add/modify/delete triggers rule"
echo "550 (integrity checksum changed) or 554 (new file added)."
echo ""
sleep 2

if [ -d /opt/cloudvault/client-data ]; then
  echo "MODIFIED: client records accessed at $(date -u)" >> /opt/cloudvault/client-data/client-index.csv
  echo "Sensitive export - Peterson Trust Q1 2026" > /opt/cloudvault/client-data/peterson-trust-export.csv
  echo "CV-001,Peterson Trust,4500000,moderate,MODIFIED" >> /opt/cloudvault/client-data/peterson-trust-export.csv
  echo "  Modified /opt/cloudvault/client-data/client-index.csv"
  echo "  Created /opt/cloudvault/client-data/peterson-trust-export.csv"
fi

if [ -d /opt/cloudvault/financial-records ]; then
  echo "CV-001,Q1-2026,99999,99999,UNAUTHORIZED_CHANGE" >> /opt/cloudvault/financial-records/q1-2026-fees.csv
  echo "  Modified /opt/cloudvault/financial-records/q1-2026-fees.csv"
fi

echo "[DONE] Client data and financial records modified."

# --- Scenario 3: Privilege escalation (MITRE T1548) ---
echo ""
echo "--- [3/4] Privilege escalation attempts ---"
echo "What this does: creates a suspicious user and runs failed sudo attempts."
echo "How Wazuh detects it: sudo/PAM writes to /var/log/auth.log. Failed"
echo "elevation attempts match rule 5401 (sudo failed attempt). Rule 5402"
echo "triggers when the user isn't in the sudoers file. Rule 5301 covers"
echo "failed 'su' attempts."
echo ""

sudo useradd -m -s /bin/bash contractor-test 2>/dev/null || true
echo "  Created suspicious user: contractor-test"

for i in $(seq 1 5); do
  su - contractor-test -c "sudo -S cat /etc/shadow" <<< "wrongpassword" 2>/dev/null || true
  echo "  Failed sudo attempt $i/5 (contractor-test trying /etc/shadow)"
  sleep 1
done

echo "[DONE] 5 failed sudo attempts by contractor-test."

# --- Scenario 4: Persistence via hidden files (MITRE T1564.001) ---
echo ""
echo "--- [4/4] Persistence artifacts ---"
echo "What this does: creates hidden files in locations attackers commonly use"
echo "for persistence (/tmp, /dev/shm, /usr/share with dot-prefixed names)."
echo "How Wazuh detects it: rootcheck + FIM. Rootcheck scans periodically for"
echo "hidden files matching known attacker TTPs (rule 510). FIM on /etc, /bin,"
echo "/usr/bin flags additions."
echo ""

sudo mkdir -p "/usr/share/...hidden-staging" 2>/dev/null || true
sudo touch "/usr/share/...hidden-staging/payload.bin"
sudo touch "/tmp/.cloudvault-backdoor"
sudo touch "/dev/shm/.persistence-marker"

echo "  Created hidden directory: /usr/share/...hidden-staging/"
echo "  Created hidden file: /tmp/.cloudvault-backdoor"
echo "  Created hidden file: /dev/shm/.persistence-marker"
echo "[DONE] Persistence artifacts created."

# --- Cleanup after detection window ---
#
# We clean up SOME artifacts (hidden files in /tmp, /dev/shm, /usr/share) so
# the script can be re-run cleanly. But we DELIBERATELY leave contractor-test
# on the box — it becomes a threat-hunting artifact for Lesson 4 ("find IAM-style
# accounts that shouldn't be here"). Remove it in the cleanup lesson at the end.
echo ""
echo "Waiting 60 seconds for Wazuh to detect and alert on all events..."
sleep 60

echo ""
echo "Cleaning up transient artifacts (leaving contractor-test user in place for threat hunt)..."
sudo rm -rf "/usr/share/...hidden-staging" 2>/dev/null || true
sudo rm -f "/tmp/.cloudvault-backdoor" 2>/dev/null || true
sudo rm -f "/dev/shm/.persistence-marker" 2>/dev/null || true
# NOTE: contractor-test user is INTENTIONALLY not deleted here — used by L4 Hunt 4

cat << 'DONE'

============================================
  All 4 scenarios complete.
============================================

Check your Wazuh dashboard or ask Claude Code via MCP:

  "Show me all alerts from the last 10 minutes on this agent,
   grouped by MITRE technique."

What you should see:
  - Multiple rule 5710/5712/5720 alerts (SSH brute force)
  - FIM alerts (rule 550/554) on /opt/cloudvault files
  - Rule 5401/5402 alerts (sudo failures)
  - Rootcheck/FIM alerts on hidden file creation

Allow 1-2 minutes for all events to reach the indexer.

DONE
GENEVENTSEOF

chmod +x /home/ubuntu/generate-events.sh
chown ubuntu:ubuntu /home/ubuntu/generate-events.sh

# Enable and start the agent
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

echo "=== Wazuh Agent ($AGENT_NAME) installation completed at $(date) ==="
echo "=== Agent configured to connect to manager at $MANAGER_IP ==="
echo "=== Event simulator at /home/ubuntu/generate-events.sh ==="
