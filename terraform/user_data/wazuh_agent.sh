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

# --- Populate /etc/hosts for inter-agent hostname resolution ---
# Fixes v4's TARGET_IP hardcoding bug: the generator can now use hostnames
# (web-server-01, app-server-01, dev-server-01) instead of hardcoded IPs.
# Mirrors how a production network would use internal DNS.
echo "=== Writing /etc/hosts entries for CloudVault agents + manager ==="
cat >> /etc/hosts << HOSTSEOF

# AI-CSL CloudVault lab — static inter-agent hostname mappings
${web_server_ip}  web-server-01
${app_server_ip}  app-server-01
${dev_server_ip}  dev-server-01
${manager_ip}     wazuh-manager
HOSTSEOF
echo "=== /etc/hosts now has CloudVault entries ==="

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

    # Tell Wazuh to tail the custom API log — syslog format
    # (our Python logger emits "Apr 14 HH:MM:SS hostname cloudvault-api[PID]: LEVEL message").
    # Same delete-then-insert idempotency strategy as the main AI-CSL ossec.conf block.
    sed -i '/<!-- AI-CSL:cloudvault-api-log -->/,/<!-- AI-CSL:cloudvault-api-log-end -->/d' /var/ossec/etc/ossec.conf
    sed -i '0,/<\/ossec_config>/{s|<\/ossec_config>|<!-- AI-CSL:cloudvault-api-log -->\
<localfile>\
  <log_format>syslog</log_format>\
  <location>/var/log/cloudvault-api.log</location>\
</localfile>\
<!-- AI-CSL:cloudvault-api-log-end -->\
</ossec_config>|}' /var/ossec/etc/ossec.conf
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
# Idempotency strategy: DELETE any previous AI-CSL blocks FIRST, then insert
# fresh. Using a guard like `grep -q marker` isn't sufficient — in v3 testing
# we found duplicate blocks in the deployed ossec.conf, possibly from cloud-init
# re-runs or from Wazuh's install writing its own ossec_config. Delete-then-insert
# works regardless of how many times user_data executes.

# Delete any existing AI-CSL blocks (all of them, if there are duplicates).
# The pattern range covers marker → closing </localfile> of the authlog section.
sed -i '/<!-- AI-CSL:cloudvault-fim -->/,/AI-CSL:authlog-tail-end/d' /var/ossec/etc/ossec.conf

# Insert a fresh block BEFORE the first </ossec_config>. The end-marker comment
# makes the range delete above unambiguous on future re-runs.
sed -i '0,/<\/ossec_config>/{s|<\/ossec_config>|<!-- AI-CSL:cloudvault-fim -->\
<syscheck>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/client-data</directories>\
  <directories check_all="yes" realtime="yes" report_changes="yes">/opt/cloudvault/financial-records</directories>\
  <directories check_all="yes" realtime="yes">/opt/cloudvault/config</directories>\
</syscheck>\
<localfile>\
  <log_format>syslog</log_format>\
  <location>/var/log/auth.log</location>\
</localfile>\
<!-- AI-CSL:authlog-tail-end -->\
</ossec_config>|}' /var/ossec/etc/ossec.conf

# Sanity check: verify exactly one AI-CSL block exists. Fail loud if not.
AICSL_COUNT=$(grep -c "AI-CSL:cloudvault-fim" /var/ossec/etc/ossec.conf || true)
if [ "$AICSL_COUNT" != "1" ]; then
  echo "=== ERROR: expected 1 AI-CSL block in ossec.conf, found $AICSL_COUNT ==="
  echo "=== ossec.conf state at failure ==="
  cat /var/ossec/etc/ossec.conf | grep -n "AI-CSL\|<ossec_config\|</ossec_config"
  exit 1
fi
echo "=== AI-CSL ossec.conf block installed (count=1) ==="

# --- Install the event generation script via base64 decode ---
# The script is staged from scripts/agent-events-generator.sh in the repo, passed
# in as a templated base64 variable. This avoids the heredoc parsing fragility
# we hit in v3 where nested heredocs / transit encoding mangled the inline content.
echo "${events_generator_b64}" | base64 -d > /home/ubuntu/generate-events.sh

chmod +x /home/ubuntu/generate-events.sh
chown ubuntu:ubuntu /home/ubuntu/generate-events.sh

# Enable and start the agent
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

echo "=== Wazuh Agent ($AGENT_NAME) installation completed at $(date) ==="
echo "=== Agent configured to connect to manager at $MANAGER_IP ==="
echo "=== Event simulator at /home/ubuntu/generate-events.sh ==="
