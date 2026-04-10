#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/wazuh-agent-install.log) 2>&1
echo "=== Wazuh Agent installation started at $(date) ==="
echo "=== Agent Name: ${agent_name} ==="

MANAGER_IP="${manager_ip}"
AGENT_NAME="${agent_name}"

# Wait for cloud-init to finish and apt to be available
cloud-init status --wait
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# System updates
apt-get update -y
apt-get upgrade -y

# Install the Wazuh agent
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
apt-get update -y

WAZUH_MANAGER="$MANAGER_IP" WAZUH_AGENT_NAME="$AGENT_NAME" apt-get install -y wazuh-agent

# Install tools for lab exercises (no offensive tools beyond what's needed for simulations)
apt-get install -y nmap net-tools sshpass

# --- CloudVault Financial Setup ---

# Create CloudVault data directories (monitored by FIM)
mkdir -p /opt/cloudvault/{client-data,financial-records,config,logs}

# Set up role-specific content
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
    echo "# FAKE CREDENTIALS — Lab training data only" > /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "aws_access_key_id=AKIAIOSFODNN7EXAMPLE" >> /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" >> /opt/cloudvault/dev/credentials/aws-creds.txt
    echo "# FAKE CREDENTIALS — Lab training data only" > /opt/cloudvault/dev/credentials/.env
    echo "DB_PASSWORD=cloudvault_dev_2026" >> /opt/cloudvault/dev/credentials/.env
    ;;
esac

# Add sample client data (for FIM alerts when modified)
cat > /opt/cloudvault/client-data/client-index.csv << 'EOF'
client_id,name,aum,risk_profile,last_review
CV-001,Peterson Trust,4500000,moderate,2026-03-15
CV-002,Morrison Family,2100000,conservative,2026-02-28
CV-003,Chen Holdings,8900000,aggressive,2026-03-01
CV-004,Wellington Partners,12300000,moderate,2026-01-15
CV-005,Nakamura Estate,3200000,conservative,2026-03-20
EOF

# Configure Wazuh agent with CloudVault-specific FIM
cat >> /var/ossec/etc/ossec.conf << 'OSSECEOF'

<!-- CloudVault Financial — Custom FIM monitoring -->
<syscheck>
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/client-data</directories>
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/financial-records</directories>
  <directories check_all="yes" realtime="yes">/opt/cloudvault/config</directories>
</syscheck>
OSSECEOF

# Download the event generation script from the lab repo
curl -sL https://raw.githubusercontent.com/botz-pillar/ai-csl-wazuh-lab/main/scripts/generate-events.sh -o /home/ubuntu/generate-events.sh
chmod +x /home/ubuntu/generate-events.sh
chown ubuntu:ubuntu /home/ubuntu/generate-events.sh

# Enable and start the agent
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

echo "=== Wazuh Agent ($AGENT_NAME) installation completed at $(date) ==="
echo "=== Agent configured to connect to manager at $MANAGER_IP ==="
