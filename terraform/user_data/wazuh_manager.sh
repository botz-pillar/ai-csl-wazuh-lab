#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/wazuh-install.log) 2>&1
echo "=== Wazuh Manager installation started at $(date) ==="

# Wait for cloud-init to finish and apt to be available
cloud-init status --wait
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# System updates
apt-get update -y
apt-get upgrade -y

# Install prerequisites
apt-get install -y curl apt-transport-https unzip

# Download and run the Wazuh installation assistant
# This installs the complete Wazuh stack: Manager + Indexer + Dashboard
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml

# Generate a single-node config.yml
cat > config.yml <<'CONFIG'
nodes:
  indexer:
    - name: wazuh-indexer
      ip: "127.0.0.1"
  server:
    - name: wazuh-server
      ip: "127.0.0.1"
  dashboard:
    - name: wazuh-dashboard
      ip: "127.0.0.1"
CONFIG

# Run the Wazuh installation assistant (single-node, all-in-one)
bash wazuh-install.sh --generate-config-files

bash wazuh-install.sh --wazuh-indexer wazuh-indexer
bash wazuh-install.sh --start-cluster

bash wazuh-install.sh --wazuh-server wazuh-server
bash wazuh-install.sh --wazuh-dashboard wazuh-dashboard

# Extract the admin credentials
tar -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -C /root/

# Enable Wazuh API to listen on all interfaces
if [ -f /var/ossec/api/configuration/api.yaml ]; then
  sed -i 's/^  host: 127.0.0.1/  host: 0.0.0.0/' /var/ossec/api/configuration/api.yaml
  systemctl restart wazuh-manager
fi

echo "=== Wazuh Manager installation completed at $(date) ==="
echo "=== Dashboard: https://$(curl -s https://checkip.amazonaws.com) ==="
echo "=== Retrieve admin password from /root/wazuh-install-files/wazuh-passwords.txt ==="
