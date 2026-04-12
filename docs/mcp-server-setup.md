# Wazuh MCP Server Setup Guide

Connect Claude Code to your Wazuh SIEM so you can query alerts, investigate incidents, and take response actions using natural language.

This guide uses [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server) v4.2.1, which exposes 48 tools spanning alert search, agent management, vulnerability queries, compliance checks, and active response.

## Architecture

The MCP server runs as an HTTP service on port 3000 and exposes a `/mcp` endpoint. Claude Code connects to it with a bearer token.

```
Claude Code ──(HTTP + Bearer)──> MCP Server :3000/mcp ──(HTTPS)──> Wazuh Manager (55000) + Indexer (9200)
```

Pick one install path:
- **Docker Compose** (recommended — isolated, reproducible, matches upstream docs)
- **From source** (Python 3.11+, useful if you already have a Python environment and don't want to run Docker)

## Prerequisites

- Wazuh lab deployed and healthy (`./scripts/doctor.sh` all green)
- Credentials from `.lab-credentials.txt` (created by `./scripts/bootstrap.sh`)
- Claude Code installed
- **Docker path:** Docker 20.10+ with Compose v2
- **Source path:** Python 3.11+ (NOT 3.10 — the server depends on `fastmcp` which requires 3.11)

---

## Path A — Docker Compose (recommended)

### Step 1 — Clone the MCP server

```bash
cd ~/projects  # or wherever you keep code
git clone https://github.com/gensecaihq/Wazuh-MCP-Server.git
cd Wazuh-MCP-Server
cp .env.example .env
```

### Step 2 — Generate an MCP API key

The server requires a bearer token. Upstream recommends:

```bash
python3 -c "import secrets; print('wazuh_' + secrets.token_urlsafe(32))"
```

Save the output — you'll use it in two places (the server's `.env` and Claude Code's `.mcp.json`).

### Step 3 — Edit .env

Open `.env` in the Wazuh-MCP-Server directory and fill in the CloudVault lab values:

```
# --- Wazuh Manager API ---
WAZUH_HOST=https://YOUR_MANAGER_IP
WAZUH_PORT=55000
WAZUH_USER=wazuh-wui
WAZUH_PASS=YOUR_WAZUH_WUI_PASSWORD
WAZUH_VERIFY_SSL=false
WAZUH_ALLOW_SELF_SIGNED=true

# --- Wazuh Indexer (required for alert search + vulnerabilities) ---
WAZUH_INDEXER_HOST=YOUR_MANAGER_IP
WAZUH_INDEXER_PORT=9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASS=YOUR_ADMIN_PASSWORD

# --- MCP Server ---
MCP_HOST=127.0.0.1
MCP_PORT=3000
AUTH_MODE=bearer
AUTH_SECRET_KEY=GENERATE_WITH_openssl_rand_hex_32
MCP_API_KEY=wazuh_<key-you-generated-in-step-2>
```

Generate the `AUTH_SECRET_KEY` (used internally for JWT signing) with:

```bash
openssl rand -hex 32
```

Replace:
- `YOUR_MANAGER_IP` → `terraform output -raw manager_public_ip`
- `YOUR_WAZUH_WUI_PASSWORD` → from `.lab-credentials.txt` (the `wazuh-wui` entry)
- `YOUR_ADMIN_PASSWORD` → from `.lab-credentials.txt` (the `admin` entry)
- `MCP_API_KEY` and `AUTH_SECRET_KEY` → values you just generated

**Easy-to-miss details:**
- `WAZUH_HOST` is a **full URL** (`https://...`), not just an IP
- Env var is `WAZUH_PASS` (NOT `WAZUH_PASSWORD`), and `WAZUH_INDEXER_PASS` (NOT `WAZUH_INDEXER_PASSWORD`)
- For the lab, `WAZUH_VERIFY_SSL=false` + `WAZUH_ALLOW_SELF_SIGNED=true` are both required (the manager uses a self-signed cert)

### Step 4 — Start the server

```bash
docker compose up -d
```

Verify it's healthy:

```bash
curl http://localhost:3000/health
```

You should get `{"status":"ok", ...}`. If you get connection refused, check `docker compose logs`.

To stop later: `docker compose down`.

### Step 5 — Connect Claude Code

Add this to your ContextOS workspace `.mcp.json` (same directory you run Claude Code from):

```json
{
  "mcpServers": {
    "wazuh": {
      "type": "http",
      "url": "http://127.0.0.1:3000/mcp",
      "headers": {
        "Authorization": "Bearer wazuh_<your-key-from-step-2>"
      }
    }
  }
}
```

Two things that trip people up:
1. The URL ends in `/mcp` — not just `/` or `/sse`. That endpoint uses MCP Streamable HTTP.
2. The bearer token must match `MCP_API_KEY` in the server's `.env` exactly — copy-paste, don't retype.

Restart Claude Code to pick up the config.

### Step 6 — Verify

In Claude Code, ask:

```
Show me all connected Wazuh agents and their status.
```

You should see web-server-01, app-server-01, and dev-server-01 listed as Active.

---

## Path B — From Source (Python 3.11+)

Use this if you'd rather not run Docker.

### Step 1 — Clone and install

```bash
cd ~/projects
git clone https://github.com/gensecaihq/Wazuh-MCP-Server.git
cd Wazuh-MCP-Server
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e .
```

(The `-e .` installs it as an editable package using the `pyproject.toml`.)

### Step 2-3 — Generate key + edit .env

Same as Path A Steps 2 and 3.

### Step 4 — Run the server

```bash
# from inside the cloned repo, with the venv active
python -m wazuh_mcp_server
```

You should see it bind to `127.0.0.1:3000`. Leave the terminal running.

For background:

```bash
nohup python -m wazuh_mcp_server > ~/wazuh-mcp.log 2>&1 &
```

Stop with `pkill -f wazuh_mcp_server`. Check if running: `lsof -i :3000`.

### Step 5-6 — Connect Claude Code + verify

Same as Path A Steps 5 and 6.

---

## What the MCP Server Can Do

48 tools across these categories:

**Investigation (read-only)**
- `get_wazuh_alerts`, `get_wazuh_alert_summary`, `analyze_alert_patterns`, `search_security_events`
- `get_wazuh_agents`, `check_agent_health`, `get_agent_processes`, `get_agent_ports`
- `get_wazuh_vulnerabilities`, `get_critical_vulnerabilities`
- `analyze_security_threat`, `perform_risk_assessment`

**Active response (requires `wazuh:write` scope)**
- `wazuh_block_ip`, `wazuh_isolate_host`, `wazuh_kill_process`, `wazuh_quarantine_file`, `wazuh_disable_user`
- Verification: `wazuh_check_blocked_ip`, `wazuh_check_agent_isolation`, `wazuh_check_process`
- Rollback: `wazuh_unisolate_host`, `wazuh_enable_user`, `wazuh_restore_file`, `wazuh_firewall_allow`

**Reports and compliance**
- `generate_security_report`, `run_compliance_check` (PCI-DSS, HIPAA, NIST, GDPR)
- `get_wazuh_cluster_health`, `get_wazuh_rules_summary`, `search_wazuh_manager_logs`

## What It CANNOT Do

- Create or modify Wazuh detection rules (use rule XML + `wazuh-logtest` instead — covered in Lesson 5)
- Query external threat intel (the `check_ioc_reputation` tool searches your own Wazuh history, not VirusTotal/AbuseIPDB)
- Modify agent configuration or enroll new agents

## Active Response — a word on permissions

In a default single-API-key bearer setup, your key has full `wazuh:read` + `wazuh:write` scope, so all active response tools work. If you switch to multiple-key mode (via `API_KEYS` JSON) or authless mode, write tools are disabled unless you explicitly enable them.

If an active response call fails with `"scope wazuh:write required"`, either:
- Your token doesn't have write scope (check `.env`), OR
- You're in authless mode without `AUTHLESS_ALLOW_WRITE=true`

For the lab, the single-key bearer setup above gives you everything.

## Troubleshooting

**"Connection refused" from Claude Code:**
- The MCP server isn't running. Check: `curl http://localhost:3000/health`
- Or port 3000 is in use: `lsof -i :3000`

**"401 Unauthorized" from MCP:**
- The bearer token in `.mcp.json` doesn't match `MCP_API_KEY` in the server's `.env`. Copy-paste the full `wazuh_...` string into both.

**"Wazuh API authentication failed" in server logs:**
- Check `WAZUH_PASS` and `WAZUH_INDEXER_PASS`. These are the #1 source of auth errors.
- Verify `WAZUH_HOST` includes `https://` prefix.

**"No alerts found" but you see them in the dashboard:**
- Alert tools query the Indexer (9200), not the Manager. Verify all four `WAZUH_INDEXER_*` values.
- Run `./scripts/doctor.sh` — if Indexer check fails, that's your root cause (usually OOM on small instances).

**Docker container restarts in a loop:**
- Almost always a config error. Check `docker compose logs wazuh-mcp` — the first error in the log is the real one.

**"Tool execution error" in the server log:**
- Circuit breaker opens after 5 consecutive failures. Wait 60s and retry.
- Check logs for the specific Wazuh API error (`docker compose logs` or `~/wazuh-mcp.log`).
