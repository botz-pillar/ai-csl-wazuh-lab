#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/wazuh-agent-install.log) 2>&1
echo "=== Wazuh Agent installation started at $(date) ==="

MANAGER_IP="${manager_ip}"

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

WAZUH_MANAGER="$MANAGER_IP" apt-get install -y wazuh-agent

# Enable and start the agent
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# Install tools useful for the lab exercises
apt-get install -y nmap hydra net-tools

echo "=== Wazuh Agent installation completed at $(date) ==="
echo "=== Agent configured to connect to manager at $MANAGER_IP ==="
