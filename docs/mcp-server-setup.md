# Wazuh MCP Server Setup Guide

Connect Claude Code to your Wazuh SIEM so you can query alerts, investigate incidents, and take response actions using natural language.

## Prerequisites

- Wazuh lab deployed and running (all agents reporting)
- Claude Code installed
- Python 3.10+ installed
- Your Wazuh manager public IP (from Terraform outputs)

## Step 1 — Get your Wazuh credentials

SSH into your Wazuh manager:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<MANAGER_PUBLIC_IP>
```

Get the dashboard admin password:

```bash
sudo tar -xf /var/ossec/wazuh-install-files.tar -C /tmp ./wazuh-install-files/wazuh-passwords.txt
sudo cat /tmp/wazuh-install-files/wazuh-passwords.txt
```

Note the `admin` password and the `wazuh-wui` API user password. You'll need both.

## Step 2 — Install the MCP server

On your local machine (not the AWS instance):

```bash
pip install wazuh-mcp-server
```

Or clone the repo for the latest version:

```bash
git clone https://github.com/gensecaihq/Wazuh-MCP-Server.git
cd Wazuh-MCP-Server
pip install -r requirements.txt
```

## Step 3 — Configure the MCP server

Create a `.env` file in the MCP server directory:

```
WAZUH_HOST=<MANAGER_PUBLIC_IP>
WAZUH_PORT=55000
WAZUH_USER=wazuh-wui
WAZUH_PASSWORD=<password from step 1>
WAZUH_PROTOCOL=https
WAZUH_VERIFY_SSL=false

WAZUH_INDEXER_HOST=<MANAGER_PUBLIC_IP>
WAZUH_INDEXER_PORT=9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASSWORD=<admin password from step 1>
WAZUH_INDEXER_VERIFY_SSL=false
```

Note: `VERIFY_SSL=false` is fine for lab use. In production you'd use proper certificates.

## Step 4 — Connect to Claude Code

Add the MCP server to your Claude Code configuration.

For the **VS Code extension**, add to your settings:

```json
{
  "claude.mcpServers": {
    "wazuh": {
      "command": "python",
      "args": ["-m", "wazuh_mcp_server"],
      "env": {
        "WAZUH_HOST": "<MANAGER_PUBLIC_IP>",
        "WAZUH_PORT": "55000",
        "WAZUH_USER": "wazuh-wui",
        "WAZUH_PASSWORD": "<password>",
        "WAZUH_PROTOCOL": "https",
        "WAZUH_VERIFY_SSL": "false",
        "WAZUH_INDEXER_HOST": "<MANAGER_PUBLIC_IP>",
        "WAZUH_INDEXER_PORT": "9200",
        "WAZUH_INDEXER_USER": "admin",
        "WAZUH_INDEXER_PASSWORD": "<admin-password>",
        "WAZUH_INDEXER_VERIFY_SSL": "false"
      }
    }
  }
}
```

For the **CLI**, add to `.mcp.json` in your workspace:

```json
{
  "mcpServers": {
    "wazuh": {
      "command": "python",
      "args": ["-m", "wazuh_mcp_server"],
      "env": {
        "WAZUH_HOST": "<MANAGER_PUBLIC_IP>",
        "WAZUH_PORT": "55000",
        "WAZUH_USER": "wazuh-wui",
        "WAZUH_PASSWORD": "<password>",
        "WAZUH_PROTOCOL": "https",
        "WAZUH_VERIFY_SSL": "false",
        "WAZUH_INDEXER_HOST": "<MANAGER_PUBLIC_IP>",
        "WAZUH_INDEXER_PORT": "9200",
        "WAZUH_INDEXER_USER": "admin",
        "WAZUH_INDEXER_PASSWORD": "<admin-password>",
        "WAZUH_INDEXER_VERIFY_SSL": "false"
      }
    }
  }
}
```

## Step 5 — Verify the connection

Open Claude Code and ask:

```
Show me all connected Wazuh agents and their status.
```

You should see your 3 CloudVault agents (web-server-01, app-server-01, dev-server-01) listed as active.

If this works, try:

```
What alerts have fired in the last hour?
```

If you get results, the MCP server is working. You're connected to your SIEM.

## What you can do

The MCP server exposes 48 tools. Key capabilities:

**Query and investigate:**
- Search alerts by severity, agent, rule, IP, or time range
- Analyze alert patterns and trends
- Check agent health, processes, and open ports
- Generate security reports (daily/weekly/incident)
- Run compliance checks (NIST, PCI-DSS, HIPAA)

**Take action:**
- Block IPs on specific agents or all agents
- Isolate compromised hosts
- Kill suspicious processes
- Quarantine files
- Disable user accounts

**Verify and rollback:**
- Check if an IP is blocked
- Check if a host is isolated
- Restore blocked IPs, isolated hosts, disabled accounts

## What you CANNOT do through MCP

- Write or create Wazuh detection rules (use the rule XML files and wazuh-logtest instead)
- Query external threat intel (VirusTotal, AbuseIPDB) — the MCP server only searches your own Wazuh data
- Modify Wazuh agent configuration
- Enroll new agents

## Troubleshooting

**"Connection refused" or timeout:**
- Check that port 55000 (API) and 9200 (Indexer) are open in the manager's security group
- Check that your IP is in the `my_ip` Terraform variable
- Verify the manager is running: `ssh` in and check `systemctl status wazuh-manager`

**"Authentication failed":**
- Double-check the username and password from Step 1
- The API user is `wazuh-wui`, not `admin` (admin is for the indexer)
- Password may have special characters — make sure they're properly escaped

**"No alerts found" but you know there are alerts:**
- The alert tools query the Indexer (port 9200), not the Manager
- Make sure `WAZUH_INDEXER_HOST` and `WAZUH_INDEXER_PASSWORD` are set
- Check that the Indexer is running: `curl -k https://<IP>:9200 -u admin:<password>`
- Alerts may take 1-2 minutes to appear in the Indexer after firing

**MCP server won't start:**
- Check Python version: `python --version` (needs 3.10+)
- Install dependencies: `pip install -r requirements.txt`
- Check for port conflicts if running locally
