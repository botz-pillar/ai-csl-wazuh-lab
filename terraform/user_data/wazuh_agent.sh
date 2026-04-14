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
    # --- CloudVault Customer Portal: real nginx on :80 + TLS on :443 ---
    # Goal: a realistic web server students can actually curl, with real
    # access.log / error.log for FIM and threat hunting. Self-signed TLS.
    echo "CloudVault Customer Portal - Production" > /opt/cloudvault/config/app.conf
    echo "server.port=443" >> /opt/cloudvault/config/app.conf
    echo "server.ssl=true" >> /opt/cloudvault/config/app.conf
    echo "session.timeout=3600" >> /opt/cloudvault/config/app.conf

    apt-get install -y nginx openssl

    # Generate self-signed TLS cert (valid 1 year, RSA 2048)
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/cloudvault.key \
      -out /etc/nginx/ssl/cloudvault.crt \
      -subj "/C=US/ST=NY/L=NewYork/O=CloudVault Financial/CN=portal.cloudvault.internal" 2>/dev/null
    chmod 600 /etc/nginx/ssl/cloudvault.key

    # Simple customer portal page
    cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>CloudVault Financial — Client Portal</title></head>
<body style="font-family:sans-serif;max-width:800px;margin:2em auto;">
  <h1>CloudVault Financial</h1>
  <p>Secure client portal. Please sign in to access your account.</p>
  <form><input placeholder="Email" /><br/><input type="password" placeholder="Password" /><br/><button>Sign in</button></form>
  <hr/>
  <p style="color:#666;font-size:0.8em;">CloudVault Financial Services — AUM $2.1B — SOC 2 Type II</p>
</body>
</html>
HTMLEOF

    # Nginx config: HTTP redirect + HTTPS with TLS
    cat > /etc/nginx/sites-available/cloudvault << 'NGINXEOF'
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  return 301 https://$host$request_uri;
}
server {
  listen 443 ssl default_server;
  listen [::]:443 ssl default_server;
  ssl_certificate /etc/nginx/ssl/cloudvault.crt;
  ssl_certificate_key /etc/nginx/ssl/cloudvault.key;
  server_name _;
  root /var/www/html;
  index index.html;
  access_log /var/log/nginx/cloudvault-access.log;
  error_log /var/log/nginx/cloudvault-error.log;
}
NGINXEOF
    ln -sf /etc/nginx/sites-available/cloudvault /etc/nginx/sites-enabled/default
    systemctl enable nginx
    systemctl restart nginx
    ;;

  "app-server-01")
    # --- CloudVault API: real Python HTTPS daemon on :8443 + custom log ---
    # Goal: a listening service students can hit, with a custom application
    # log at /var/log/cloudvault-api.log that Wazuh parses. Teaches custom
    # log forwarding (a high-value SOC skill).
    echo "CloudVault API Server - Production" > /opt/cloudvault/config/api.conf
    echo "api.port=8443" >> /opt/cloudvault/config/api.conf
    echo "db.host=cloudvault-prod-db.internal" >> /opt/cloudvault/config/api.conf
    echo "db.port=5432" >> /opt/cloudvault/config/api.conf
    echo "api.rate_limit=100" >> /opt/cloudvault/config/api.conf

    apt-get install -y python3 python3-pip openssl

    mkdir -p /opt/cloudvault/api /etc/cloudvault-api/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/cloudvault-api/ssl/api.key \
      -out /etc/cloudvault-api/ssl/api.crt \
      -subj "/C=US/ST=NY/L=NewYork/O=CloudVault Financial/CN=api.cloudvault.internal" 2>/dev/null
    chmod 600 /etc/cloudvault-api/ssl/api.key

    # The API daemon — minimal Python, no external deps.
    # Logs to /var/log/cloudvault-api.log in a syslog-parseable format:
    #   Apr 14 00:00:00 hostname cloudvault-api[PID]: LEVEL message
    cat > /opt/cloudvault/api/server.py << 'PYEOF'
#!/usr/bin/env python3
"""CloudVault API — minimal HTTPS server for lab purposes."""
import http.server, ssl, json, logging, logging.handlers, sys, os
from http.server import BaseHTTPRequestHandler

LOG_PATH = "/var/log/cloudvault-api.log"
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(hostname)s cloudvault-api[%(process)d]: %(levelname)s %(message)s",
    datefmt="%b %d %H:%M:%S",
)
# Inject hostname into every record
_hostname = os.uname().nodename
old_factory = logging.getLogRecordFactory()
def _factory(*a, **kw):
    r = old_factory(*a, **kw); r.hostname = _hostname; return r
logging.setLogRecordFactory(_factory)
log = logging.getLogger("cloudvault-api")

CLIENTS = {
    "CV-001": {"name": "Peterson Trust",       "aum": 4500000},
    "CV-002": {"name": "Morrison Family",      "aum": 2100000},
    "CV-003": {"name": "Chen Holdings",        "aum": 8900000},
    "CV-004": {"name": "Wellington Partners",  "aum": 12300000},
    "CV-005": {"name": "Nakamura Estate",      "aum": 3200000},
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # suppress stderr access log
    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        src = self.client_address[0]
        if self.path == "/health":
            log.info(f"health_check src={src} status=200")
            return self._json(200, {"status": "ok", "service": "cloudvault-api"})
        if self.path == "/api/accounts":
            log.info(f"accounts_list src={src} count={len(CLIENTS)}")
            return self._json(200, {"accounts": list(CLIENTS.values())})
        if self.path.startswith("/api/accounts/"):
            cid = self.path.rsplit("/", 1)[-1]
            if cid in CLIENTS:
                log.info(f"account_read src={src} client_id={cid}")
                return self._json(200, CLIENTS[cid])
            log.warning(f"account_read src={src} client_id={cid} status=404")
            return self._json(404, {"error": "not found"})
        log.warning(f"unknown_path src={src} path={self.path}")
        self._json(404, {"error": "not found"})

if __name__ == "__main__":
    log.info("cloudvault-api starting port=8443")
    httpd = http.server.HTTPServer(("0.0.0.0", 8443), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("/etc/cloudvault-api/ssl/api.crt", "/etc/cloudvault-api/ssl/api.key")
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    log.info("cloudvault-api listening port=8443 tls=true")
    try: httpd.serve_forever()
    except KeyboardInterrupt: log.info("cloudvault-api stopping")
PYEOF
    chmod +x /opt/cloudvault/api/server.py
    touch /var/log/cloudvault-api.log
    chmod 644 /var/log/cloudvault-api.log

    # systemd unit so the API starts on boot
    cat > /etc/systemd/system/cloudvault-api.service << 'SVCEOF'
[Unit]
Description=CloudVault API (lab)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/cloudvault/api/server.py
Restart=on-failure
StandardOutput=append:/var/log/cloudvault-api.log
StandardError=append:/var/log/cloudvault-api.log

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable cloudvault-api
    systemctl start cloudvault-api

    # Tell Wazuh to tail the custom API log — it parses as syslog format
    # (our Python logger emits "Apr 14 HH:MM:SS hostname cloudvault-api[PID]: LEVEL message").
    # This gets decoded by Wazuh's syslog decoder and the message is searchable via MCP.
    sed -i '/<\/ossec_config>/i\
\
<!-- CloudVault API custom application log -->\
<localfile>\
  <log_format>syslog</log_format>\
  <location>/var/log/cloudvault-api.log</location>\
</localfile>' /var/ossec/etc/ossec.conf
    ;;

  "dev-server-01")
    # --- CloudVault dev environment: real dev tools installed ---
    # Goal: looks like a genuine dev box to threat hunters. Real interpreters,
    # git, build tools. No fake services — it's a workstation, not a server.
    echo "CloudVault Development Environment" > /opt/cloudvault/config/dev.conf

    apt-get install -y git build-essential python3-pip nodejs npm

    mkdir -p /opt/cloudvault/dev/{scripts,credentials,temp}
    # These creds are INTENTIONALLY present — students find them during
    # threat hunting / find a CloudVault security gap (hardcoded secrets in
    # a dev environment). Uses AWS's official example key for safety.
    cat > /opt/cloudvault/dev/credentials/aws-creds.txt << 'CREDEOF'
# FAKE CREDENTIALS - Lab training data only
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
CREDEOF
    cat > /opt/cloudvault/dev/credentials/.env << 'ENVEOF'
# FAKE CREDENTIALS - Lab training data only
DB_PASSWORD=cloudvault_dev_2026
API_TOKEN=dev_token_never_rotated_since_2024
ENVEOF

    # A realistic git repo structure so threat hunts have something to find
    cd /opt/cloudvault/dev
    git init -q scripts 2>/dev/null || true
    cd scripts
    cat > ingest.py << 'PYEOF'
#!/usr/bin/env python3
"""CloudVault nightly client ingest (dev copy)."""
import os, sys, json, logging
# TODO: rotate this credential before moving to production
API_TOKEN = os.environ.get("API_TOKEN", "dev_token_never_rotated_since_2024")
logging.basicConfig(level=logging.INFO)
def main(): logging.info("ingest starting, token=%s...", API_TOKEN[:12])
if __name__ == "__main__": main()
PYEOF
    chmod +x ingest.py
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

# Configure FIM for CloudVault directories AND add an auth.log logcollector.
#
# The default Wazuh 4.9 agent reads auth events via journald, which is less
# reliable in our teaching context: if the manager restarts during a lesson
# (rule deployment, etc.), journald's cursor can skip events. /var/log/auth.log
# is the textbook Linux auth-monitoring target — stable, catches everything
# sshd/sudo/PAM write. We add it explicitly as a logcollector block.
#
# Must use sed to insert BEFORE </ossec_config> — appending produces invalid XML.
sed -i '/<\/ossec_config>/i\
\
<!-- CloudVault Financial - Custom FIM monitoring -->\
<syscheck>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/client-data</directories>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/financial-records</directories>\
  <directories check_all="yes" realtime="yes">/opt/cloudvault/config</directories>\
</syscheck>\
\
<!-- Explicit auth.log tail (more reliable than the default journald reader) -->\
<localfile>\
  <log_format>syslog</log_format>\
  <location>/var/log/auth.log</location>\
</localfile>' /var/ossec/etc/ossec.conf

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
echo "What this does: creates a user (contractor-test) who is NOT in the"
echo "sudoers file, then has that user attempt sudo. Each attempt is"
echo "rejected and logged as a clear privilege-escalation failure."
echo ""
echo "How Wazuh detects it: sudo writes 'user NOT in sudoers' to"
echo "/var/log/auth.log. The log collector (explicit <localfile> on"
echo "auth.log) forwards each event to the manager. Rule 5401 fires on"
echo "'user NOT in sudoers' — a clean, specific privilege-escalation"
echo "signal with no false positives."
echo ""

sudo useradd -m -s /bin/bash contractor-test 2>/dev/null || true
echo "  Created user: contractor-test (NOT granted sudo)"

for i in $(seq 1 5); do
  # Run sudo AS contractor-test. Because they aren't in sudoers, sudo writes
  # 'user NOT in sudoers' to auth.log — the pattern rule 5401 matches cleanly.
  # `-n` makes sudo non-interactive so it doesn't hang waiting for a password.
  sudo -u contractor-test sudo -n /usr/bin/cat /etc/shadow 2>/dev/null || true
  echo "  Attempt $i/5: contractor-test tried sudo cat /etc/shadow — REJECTED"
  sleep 1
done

echo "[DONE] 5 failed sudo attempts by contractor-test — expect 5x rule 5401."

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
