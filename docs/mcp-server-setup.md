# Wazuh MCP Server Setup Guide

Connect Claude Code to your Wazuh SIEM so you can query alerts, investigate incidents, and take response actions using natural language.

This guide uses [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server) **v4.2.1**, which exposes 48 tools spanning alert search, agent management, vulnerability queries, compliance checks, and active response.

## Architecture

The MCP server runs as an HTTP service on port 3000 and exposes a `/mcp` endpoint. Claude Code connects to it with a bearer token.

```
Claude Code ──(HTTP + Bearer JWT)──> MCP Server :3000/mcp ──(HTTPS)──> Wazuh Manager (:55000) + Indexer (:9200)
```

**Authentication is TWO steps.** This is the subtle part of the setup:
1. You generate an **API key** (`wazuh_...`). This goes in the server's `.env` file.
2. You exchange the API key at the `/auth/token` endpoint for a **JWT**. The JWT goes in Claude Code's `.mcp.json`.

The API key is NOT a valid bearer token on its own. If you try using it directly as a bearer, you'll get `{"detail":"Invalid or expired token"}`. Exchange it first.

## Prerequisites

- Wazuh lab deployed and healthy (`./scripts/doctor.sh` all green)
- Credentials from `.lab-credentials.txt` (created by `./scripts/bootstrap.sh`)
- Claude Code installed
- **Python 3.11+ required** (the server depends on `fastmcp` which does not support 3.10)

## Step 1 — Clone the MCP server + install

```bash
cd ~/projects  # or wherever you keep code
git clone https://github.com/gensecaihq/Wazuh-MCP-Server.git
cd Wazuh-MCP-Server
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e .
```

The `-e .` does an editable install using `pyproject.toml`. Takes ~90 seconds.

## Step 2 — Generate two secrets

You need two values: an API key and a JWT signing secret. Generate both:

```bash
# API key — what clients present to exchange for a JWT
python3 -c "import secrets; print('MCP_API_KEY=wazuh_' + secrets.token_urlsafe(32))"

# JWT signing key — server uses this internally to sign tokens
echo "AUTH_SECRET_KEY=$(openssl rand -hex 32)"
```

Save both lines — you'll paste them into `.env` next.

## Step 3 — Create .env

In the `Wazuh-MCP-Server` directory, create `.env`:

```
# --- Wazuh Manager API ---
WAZUH_HOST=https://YOUR_MANAGER_IP
WAZUH_PORT=55000
WAZUH_USER=wazuh-wui
WAZUH_PASS=YOUR_WAZUH_WUI_PASSWORD
WAZUH_VERIFY_SSL=false
WAZUH_ALLOW_SELF_SIGNED=true

# --- Wazuh Indexer ---
WAZUH_INDEXER_HOST=YOUR_MANAGER_IP
WAZUH_INDEXER_PORT=9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASS=YOUR_ADMIN_PASSWORD
WAZUH_INDEXER_VERIFY_SSL=false

# --- MCP Server ---
MCP_HOST=127.0.0.1
MCP_PORT=3000
AUTH_MODE=bearer
AUTH_SECRET_KEY=your-hex-secret-from-step-2
MCP_API_KEY=wazuh_your-key-from-step-2

# --- JWT lifetime ---
# Default is 24h. Bump to 30 days so you're not re-exchanging mid-session.
TOKEN_LIFETIME_HOURS=720

# --- CORS (allow local Claude Code + claude.ai) ---
ALLOWED_ORIGINS=http://localhost:*,https://claude.ai,https://*.anthropic.com
LOG_LEVEL=INFO
```

Replace:
- `YOUR_MANAGER_IP` → `terraform output -raw manager_public_ip`
- `YOUR_WAZUH_WUI_PASSWORD` → from `.lab-credentials.txt` (the `wazuh-wui` block)
- `YOUR_ADMIN_PASSWORD` → from `.lab-credentials.txt` (the `admin` block)
- Both secret values from Step 2

**Variable names that trip people up:**
- `WAZUH_HOST` is a **full URL** (`https://...`), not just an IP.
- `WAZUH_PASS` (NOT `WAZUH_PASSWORD`); `WAZUH_INDEXER_PASS` (NOT `WAZUH_INDEXER_PASSWORD`).
- `WAZUH_VERIFY_SSL=false` **and** `WAZUH_ALLOW_SELF_SIGNED=true` — you need both for the lab's self-signed cert.

## Step 4 — Start the server

⚠️ **The server does NOT auto-load `.env`.** You must export the variables into the shell environment before running it. This is a known gotcha upstream.

```bash
# From inside the Wazuh-MCP-Server directory, with .venv active:
set -a
source .env
set +a
python -m wazuh_mcp_server
```

You should see:
```
INFO: Uvicorn running on http://127.0.0.1:3000
```

Verify it's healthy:
```bash
curl http://127.0.0.1:3000/health | python3 -m json.tool
```

All three services should show `"healthy"`:
```json
{
  "services": {
    "wazuh_manager": "healthy",
    "wazuh_indexer": "healthy",
    "mcp": "healthy"
  }
}
```

If manager is `"unhealthy"` or indexer is `"not_configured"` — the env vars didn't export. Re-run the `set -a` block.

## Step 5 — Exchange API key for a JWT

```bash
JWT=$(curl -s -X POST http://127.0.0.1:3000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"api_key":"'"$MCP_API_KEY"'"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
echo "$JWT"
```

You get back a long `eyJ...` string. That's your bearer token for Claude Code.

(If you skipped `set -a && source .env` in Step 4, substitute your actual `wazuh_...` key for `$MCP_API_KEY` above.)

## Step 6 — Add Wazuh to Claude Code's `.mcp.json`

In your ContextOS workspace `.mcp.json`:

```json
{
  "mcpServers": {
    "wazuh": {
      "type": "http",
      "url": "http://127.0.0.1:3000/mcp",
      "headers": {
        "Authorization": "Bearer PASTE_YOUR_JWT_HERE"
      }
    }
  }
}
```

Three things that catch people:
- The URL ends in `/mcp` — not `/`, not `/sse`.
- Paste the full `eyJ...` JWT, not the `wazuh_...` API key.
- Restart Claude Code after editing `.mcp.json`.

## Step 7 — Verify in Claude Code

After restarting Claude Code, ask:

```
Show me all connected Wazuh agents and their status.
```

You should see web-server-01, app-server-01, and dev-server-01 listed as Active. If you see them — you're connected.

## Running in the background

For multi-day use:

```bash
# From the Wazuh-MCP-Server directory, with .venv active and env exported:
nohup python -m wazuh_mcp_server > ~/wazuh-mcp.log 2>&1 &
```

Stop with `pkill -f wazuh_mcp_server`. Check status: `lsof -i :3000`. Tail the log: `tail -f ~/wazuh-mcp.log`.

## Refreshing the JWT

With `TOKEN_LIFETIME_HOURS=720` your JWT is valid for 30 days. When it expires (or if you rotate the server's `AUTH_SECRET_KEY`), re-run Step 5 to get a new one, paste into `.mcp.json`, restart Claude Code.

## What the MCP Server Can Do

48 tools across these categories:

**Investigation (read-only)**
- `get_wazuh_alerts`, `get_wazuh_alert_summary`, `analyze_alert_patterns`, `search_security_events`
- `get_wazuh_agents`, `check_agent_health`, `get_agent_processes`, `get_agent_ports`
- `get_wazuh_vulnerabilities`, `get_critical_vulnerabilities`
- `analyze_security_threat`, `perform_risk_assessment`, `get_top_security_threats`

**Active response (requires `wazuh:write` scope — bearer mode gives it automatically)**
- `wazuh_block_ip`, `wazuh_isolate_host`, `wazuh_kill_process`, `wazuh_quarantine_file`, `wazuh_disable_user`
- Verification: `wazuh_check_blocked_ip`, `wazuh_check_agent_isolation`, `wazuh_check_process`
- Rollback: `wazuh_unisolate_host`, `wazuh_enable_user`, `wazuh_restore_file`, `wazuh_firewall_allow`

**Reports + compliance**
- `generate_security_report`, `run_compliance_check` (PCI-DSS, HIPAA, NIST, GDPR)
- `get_wazuh_cluster_health`, `get_wazuh_rules_summary`, `search_wazuh_manager_logs`

## What It Cannot Do

- Create or modify Wazuh detection rules (use rule XML + `wazuh-logtest` — covered in Lesson 5)
- Query external threat intel (the `check_ioc_reputation` tool searches your own Wazuh history, not VirusTotal/AbuseIPDB)
- Modify agent configuration or enroll new agents

## Known upstream issue (v4.2.1) — active response rollback

**`wazuh_firewall_allow` doesn't reliably remove the iptables rule.** Upstream's rollback path expects the Wazuh manager to time out the block based on ossec.conf's `<timeout>` value, not to receive an explicit delete command. When the MCP tool is called to unblock, the agent-side `firewall-drop` binary often adds a duplicate rule instead of removing the original.

**Recommended workaround — use duration-based blocks:**

Always call `wazuh_block_ip` with a `duration` parameter (seconds):

```
Block 192.0.2.99 on web-server-01 for 300 seconds.
```

After 300s, Wazuh's timeout mechanism removes the block automatically. This is also the production pattern — humans shouldn't be manually unblocking IPs; the SIEM's timeout + re-evaluation handles it.

**If you need to unblock before the timeout expires,** SSH to the agent:

```bash
ssh ubuntu@<agent-ip> 'sudo iptables -D INPUT -s <blocked-ip> -j DROP'
```

Course Lesson 5 Part 2 teaches both patterns.

## Troubleshooting

**"Invalid or expired token" on /mcp:**
- You're sending the `wazuh_...` API key as the bearer. You need the JWT. Re-run Step 5.
- Your JWT expired. Re-run Step 5.
- Server's `AUTH_SECRET_KEY` changed. Restart the server (re-export env), then re-run Step 5.

**"Connection refused" from Claude Code:**
- MCP server isn't running. Check: `curl http://localhost:3000/health`.
- Port 3000 is in use: `lsof -i :3000`.

**Health endpoint shows `wazuh_manager: unhealthy`:**
- `.env` wasn't exported. Kill the server, re-run `set -a && source .env && set +a && python -m wazuh_mcp_server`.
- `WAZUH_HOST` doesn't include `https://` prefix.
- `WAZUH_PASS` is wrong (check `.lab-credentials.txt`).

**Health endpoint shows `wazuh_indexer: not_configured`:**
- `WAZUH_INDEXER_HOST` wasn't exported (same `.env` issue as above).
- Value missing entirely (check `.env`).

**Indexer tools return empty / "connection refused" to :9200:**
- Run `doctor.sh`. If indexer check fails, network.host binding issue on the manager. Should be fixed automatically by bootstrap, but if not, SSH to the manager and run: `sudo sed -i 's/^network.host: .*/network.host: "0.0.0.0"/' /etc/wazuh-indexer/opensearch.yml && sudo systemctl restart wazuh-indexer`.

**"Tool execution error" in server log:**
- Circuit breaker opens after 5 consecutive failures — wait 60s and retry.
- Check `~/wazuh-mcp.log` for the specific Wazuh API error.

**"No module named wazuh_mcp_server" when you try to start the server:**
- The editable install didn't persist (happens after `--force-reinstall --no-deps` or venv reuse). From the Wazuh-MCP-Server directory with the venv active: `pip install -e .`. Then start the server again.
