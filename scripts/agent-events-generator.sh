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
echo "What this does: generates 15 failed SSH login attempts from this agent"
echo "AGAINST web-server-01. The source IP for each attempt will be this"
echo "agent's private IP (10.0.1.x), NOT 127.0.0.1."
echo ""
echo "How Wazuh detects it: sshd on web-server-01 writes each failure to"
echo "/var/log/auth.log. Wazuh fires rule 5710 (invalid user), then after"
echo "~8 rapid failures the composite rule 5712 (brute force detected)."
echo "Because the source IP is NOT in Wazuh's default AR whitelist (which"
echo "includes 127.0.0.1), the configured active-response trigger on rule"
echo "5712 will fire — web-server-01 will auto-add an iptables DROP for"
echo "this agent's IP for 300 seconds."
echo ""

# Resolve target via /etc/hosts (populated by Terraform user_data with static
# IPs). This avoids the v4 bug where TARGET_IP was hardcoded to 10.0.1.12 but
# the actual deploy used a different IP — SSH packets went to a non-existent
# host and nothing fired.
TARGET="web-server-01"
TARGET_IP=$(getent hosts "$TARGET" 2>/dev/null | awk '{print $1}')
MY_IP=$(hostname -I | awk '{print $1}')

if [ -z "$TARGET_IP" ]; then
  echo "[ERROR] Can't resolve '$TARGET' — /etc/hosts may not have been populated"
  echo "        by Terraform user_data. Check /etc/hosts and re-run, or manually"
  echo "        set TARGET_IP in this script."
  echo ""
  echo "Current /etc/hosts entries:"
  grep -E "^[0-9]" /etc/hosts | head -10
  exit 1
fi

if [ "$MY_IP" = "$TARGET_IP" ]; then
  echo "(running on $TARGET itself — falling back to localhost for this scenario)"
  TARGET_IP="127.0.0.1"
fi

for i in $(seq 1 15); do
  sshpass -p "wrongpass$i" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "fakeuser$i@$TARGET_IP" exit 2>/dev/null || true
  echo "  Attempt $i/15 (source=$MY_IP dst=$TARGET_IP [$TARGET] user=fakeuser$i)"
  sleep 0.5
done
echo "[DONE] 15 failed SSH attempts sent from $MY_IP → $TARGET_IP ($TARGET)"
echo ""
echo "After detection, check iptables on web-server-01 (expect DROP for $MY_IP)."

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

# --- Scenario 3: Account creation + privilege escalation (MITRE T1136 + T1548.003) ---
echo ""
echo "--- [3/4] Account creation + privilege escalation ---"
echo "What this does: creates a new local user (contractor-test) and then"
echo "uses sudo to run privileged commands AS that new user. This is a"
echo "classic persistence + escalation pattern — attackers create an account"
echo "that'll survive reboots, then escalate through it."
echo ""
echo "How Wazuh detects it (4 rules, reliably):"
echo "  - Rule 5901 (new group added) — level 8, MITRE T1136"
echo "  - Rule 5902 (new user added)  — level 8, MITRE T1136"
echo "  - Rule 5403 (first-time sudo) — level 4, MITRE T1548.003"
echo "  - Rule 5402 (successful sudo to ROOT, fires multiple times)"
echo "    — level 3, MITRE T1548.003"
echo ""

sudo useradd -m -s /bin/bash contractor-test 2>/dev/null || true
echo "  Created user: contractor-test (intentional persistence artifact)"

for i in $(seq 1 5); do
  # Each sudo invocation becomes contractor-test, then runs a privileged read.
  # Fires 5403 on first iteration, 5402 on all 5. Produces a clean timeline of
  # "new account used for privileged operations" — the signal students should
  # learn to recognize.
  sudo -u contractor-test sudo -n /usr/bin/id 2>/dev/null || \
    sudo -u contractor-test /usr/bin/id
  echo "  Action $i/5: ran 'id' as contractor-test (captured by sudo audit)"
  sleep 1
done

echo "[DONE] 4 distinct rule IDs should fire: 5901, 5902, 5403, 5402 (5x)."

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
