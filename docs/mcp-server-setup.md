# Wazuh MCP Server Setup Guide

Connect Claude Code to your Wazuh SIEM so you can query alerts, investigate incidents, and take response actions using natural language.

This guide uses [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server), which exposes 48 tools spanning alert search, agent management, vulnerability queries, compliance checks, and active response.

## Architecture

The MCP server runs as an HTTP server on port 3000 (not stdio). Claude Code connects to it over HTTP with a bearer token.

```
Claude Code ──(HTTP + bearer)──> MCP Server ──(HTTPS)──> Wazuh Manager + Indexer
```

## Prerequisites

- Wazuh lab deployed and healthy (`./scripts/doctor.sh` all green)
- Python 3.10+ on your local machine
- Credentials from `.lab-credentials.txt` (created by `./scripts/bootstrap.sh`)
- Claude Code installed

## Step 1 — Clone the MCP server

The package is NOT on PyPI. Install from source:

```bash
cd ~/projects  # or wherever you keep code
git clone https://github.com/gensecaihq/Wazuh-MCP-Server.git
cd Wazuh-MCP-Server
pip install -r requirements.txt
```

## Step 2 — Generate an MCP API key

The server requires a bearer token. The format is `wazuh_<43-char-base64-string>`.

Generate one:

```bash
echo "wazuh_$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-43)"
```

Save the output — you'll use it in two places.

## Step 3 — Create the .env file

In the Wazuh-MCP-Server directory, create `.env`:

```
# --- Wazuh Manager API ---
WAZUH_HOST=YOUR_MANAGER_IP
WAZUH_PORT=55000
WAZUH_USER=wazuh-wui
WAZUH_PASS=YOUR_WAZUH_WUI_PASSWORD
WAZUH_PROTOCOL=https
WAZUH_VERIFY_SSL=false

# --- Wazuh Indexer (required for alert queries) ---
WAZUH_INDEXER_HOST=YOUR_MANAGER_IP
WAZUH_INDEXER_PORT=9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASS=YOUR_ADMIN_PASSWORD
WAZUH_INDEXER_VERIFY_SSL=false

# --- MCP Server Auth ---
MCP_API_KEY=wazuh_<your-43-char-key-from-step-2>
MCP_HOST=127.0.0.1
MCP_PORT=3000
```

Replace:
- `YOUR_MANAGER_IP` → `terraform output manager_public_ip`
- `YOUR_WAZUH_WUI_PASSWORD` → from `.lab-credentials.txt` (the `wazuh-wui` entry)
- `YOUR_ADMIN_PASSWORD` → from `.lab-credentials.txt` (the `admin` entry)
- `MCP_API_KEY` → the key you generated in step 2

**Variable names that trip people up:** this server uses `WAZUH_PASS` (NOT `WAZUH_PASSWORD`) and `WAZUH_INDEXER_PASS` (NOT `WAZUH_INDEXER_PASSWORD`). Getting these wrong produces misleading auth errors.

## Step 4 — Run the MCP server

In one terminal:

```bash
python -m wazuh_mcp_server
```

You should see:

```
INFO: Started server at http://127.0.0.1:3000
INFO: Loaded 48 tools
```

Leave it running. The server must be up for Claude Code to connect.

**For background running** (so you don't have to keep a terminal open):

```bash
nohup python -m wazuh_mcp_server > ~/wazuh-mcp.log 2>&1 &
```

To stop: `pkill -f wazuh_mcp_server`. Check if running: `lsof -i :3000`.

**Optional systemd service** for persistent runs across reboots:

```bash
# /etc/systemd/system/wazuh-mcp.service
[Unit]
Description=Wazuh MCP Server
After=network.target

[Service]
Type=simple
User=YOUR_USER
WorkingDirectory=/path/to/Wazuh-MCP-Server
EnvironmentFile=/path/to/Wazuh-MCP-Server/.env
ExecStart=/usr/bin/python3 -m wazuh_mcp_server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Then: `sudo systemctl enable --now wazuh-mcp`.

## Step 5 — Connect Claude Code

The server is HTTP, not stdio. Your Claude Code config needs the `"type": "http"` form:

Add to your ContextOS workspace `.mcp.json` (or `~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "wazuh": {
      "type": "http",
      "url": "http://127.0.0.1:3000",
      "headers": {
        "Authorization": "Bearer wazuh_<your-43-char-key-from-step-2>"
      }
    }
  }
}
```

Replace the bearer token with the same `MCP_API_KEY` value from step 2.

Restart Claude Code to pick up the config.

## Step 6 — Verify

In Claude Code, ask:

```
Show me all connected Wazuh agents and their status.
```

You should see web-server-01, app-server-01, and dev-server-01 listed as Active.

## What the MCP Server Can Do

48 tools:

**Investigation**
- Alert search and pattern analysis (requires Indexer)
- Agent health, processes, open ports
- Vulnerability queries (requires Indexer)
- Full Lucene-syntax security event search

**Active response** (needs `wazuh:write` scope)
- Block/unblock IPs (per agent or all)
- Isolate/unisolate hosts
- Kill processes
- Quarantine/restore files
- Disable/enable users

**Reports and compliance**
- Daily/weekly/monthly/incident reports
- Compliance checks: PCI-DSS, HIPAA, NIST, GDPR

## What It CANNOT Do

- Create or modify Wazuh detection rules (use rule XML + `wazuh-logtest` instead)
- Query external threat intel (the "IOC reputation" tool searches your own Wazuh history, not VirusTotal/AbuseIPDB)
- Modify agent configuration
- Enroll new agents

## Troubleshooting

**"Connection refused" from Claude Code:**
- The MCP server isn't running. Start it.
- Or port 3000 is in use: `lsof -i :3000`.

**"Authentication failed" — two layers:**
1. Claude Code → MCP server: check `MCP_API_KEY` in `.env` matches the bearer token in `.mcp.json`.
2. MCP server → Wazuh: check `WAZUH_PASS` and `WAZUH_INDEXER_PASS` in `.env`.

**"No alerts found" but you see them in the dashboard:**
- Alert tools query the Indexer (port 9200), not the Manager. Verify `WAZUH_INDEXER_*` values.
- Run `./scripts/doctor.sh` — if Indexer check fails, that's your root cause.

**MCP server won't start:**
- Python 3.10+ required: `python --version`
- Install deps: `pip install -r requirements.txt`
- Port in use: `lsof -i :3000`

**"Tool execution error" in the server log:**
- Circuit breaker opens after 5 consecutive failures. Wait 60s and retry.
- Check `~/wazuh-mcp.log` for the specific error.
