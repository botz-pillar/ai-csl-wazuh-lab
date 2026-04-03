#!/bin/bash
exec > /var/log/wazuh-install.log 2>&1
echo "=== Wazuh install started: $(date) ==="

# Work from root home
cd /root

# Wait for apt lock
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock..."
  sleep 5
done

# Update and install prereqs
apt-get update -y
apt-get install -y curl apt-transport-https unzip

echo "=== Downloading Wazuh installer: $(date) ==="
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
chmod +x wazuh-install.sh
ls -la wazuh-install.sh
echo "=== Download complete ==="

# Generate single-node config
cat > /root/config.yml << 'CONFIG'
nodes:
  indexer:
    - name: node-1
      ip: "127.0.0.1"
  server:
    - name: wazuh-1
      ip: "127.0.0.1"
  dashboard:
    - name: dashboard
      ip: "127.0.0.1"
CONFIG

echo "=== Running all-in-one install: $(date) ==="
bash wazuh-install.sh -a -o

echo "=== Install complete: $(date) ==="

# Expose Wazuh API on all interfaces
if [ -f /var/ossec/api/configuration/api.yaml ]; then
  sed -i 's/^  host: 127.0.0.1/  host: 0.0.0.0/' /var/ossec/api/configuration/api.yaml
  systemctl restart wazuh-manager
fi

# Print credentials
echo "=== CREDENTIALS ==="
tar -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -C /root/ 2>/dev/null
cat /root/wazuh-install-files/wazuh-passwords.txt 2>/dev/null || echo "Check wazuh-install-files.tar for passwords"

PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)
echo "=== Dashboard: https://$PUBLIC_IP ==="
echo "=== Done: $(date) ==="
