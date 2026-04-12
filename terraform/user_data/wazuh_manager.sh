#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/wazuh-install.log) 2>&1
echo "=== Wazuh manager install started: $(date) ==="
echo "=== Installer series: ${wazuh_installer_series} ==="

cd /root

# Wait for apt (we don't use `cloud-init status --wait` — this script IS
# cloud-init's final stage and that command would deadlock waiting on itself)
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock..."
  sleep 5
done

apt-get update -y
apt-get install -y curl apt-transport-https unzip

echo "=== Downloading Wazuh installer: $(date) ==="
curl -fsSL "https://packages.wazuh.com/${wazuh_installer_series}/wazuh-install.sh" -o wazuh-install.sh
chmod +x wazuh-install.sh

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

# --- Indexer JVM heap tuning ---
# The indexer (OpenSearch) defaults can be too low or too high depending on
# instance size. Setting explicit heap at ~50% of available RAM prevents OOM
# kills (the #1 cause of indexer failures on smaller instances).
TOTAL_MEM_MB=$(awk '/MemTotal/ { printf "%.0f", $2/1024 }' /proc/meminfo)
HEAP_MB=$((TOTAL_MEM_MB / 2))
# Cap at 4GB per OpenSearch recommendation for single-node deployments
if [ "$HEAP_MB" -gt 4096 ]; then
  HEAP_MB=4096
fi
# Floor at 1GB (below this, the indexer struggles even with no load)
if [ "$HEAP_MB" -lt 1024 ]; then
  HEAP_MB=1024
fi

echo "=== Setting indexer JVM heap to $${HEAP_MB}m (total RAM: $${TOTAL_MEM_MB}m) ==="
mkdir -p /etc/wazuh-indexer/jvm.options.d
cat > /etc/wazuh-indexer/jvm.options.d/heap.options << HEAPEOF
-Xms$${HEAP_MB}m
-Xmx$${HEAP_MB}m
HEAPEOF

# Restart indexer with the new heap settings
systemctl restart wazuh-indexer || true

# Wait for indexer to be back up (max 60s)
for i in $(seq 1 30); do
  if ss -tln | grep -q ':9200 '; then
    echo "=== Indexer listening on :9200 after $${i}x2s ==="
    break
  fi
  sleep 2
done

# Expose Wazuh API on all interfaces (default binds to 127.0.0.1)
if [ -f /var/ossec/api/configuration/api.yaml ]; then
  sed -i 's/^  host: 127.0.0.1/  host: 0.0.0.0/' /var/ossec/api/configuration/api.yaml
  systemctl restart wazuh-manager
fi

# Extract credentials to /root/wazuh-install-files/ so they can be retrieved
# later (by terraform remote-exec, by students via SSH, or by doctor.sh)
echo "=== CREDENTIALS ==="
tar -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -C /root/ 2>/dev/null || true
cat /root/wazuh-install-files/wazuh-passwords.txt 2>/dev/null || echo "Passwords file not yet extracted — check wazuh-install-files.tar"

PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)
echo "=== Dashboard: https://$PUBLIC_IP ==="
echo "=== Manager install done: $(date) ==="
