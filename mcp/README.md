# Connecting Wazuh to Your AI Analyst via MCP

The Model Context Protocol (MCP) lets AI assistants like Claude interact with external tools and data sources. By connecting Wazuh's API to an MCP server, you can ask your AI analyst to query alerts, check agent status, and investigate incidents directly.

## How It Works

```
You ──► AI Assistant (Claude/Silas) ──► MCP Server ──► Wazuh API ──► Your Lab Data
```

The MCP server acts as a bridge: it exposes Wazuh's API as tools the AI can call. When you ask "What are the top alerts?", the AI calls the appropriate Wazuh API endpoint through MCP and interprets the results.

## Option 1: Use the Wazuh MCP Server

The community maintains a Wazuh MCP server that wraps the Wazuh API.

### Prerequisites

- Node.js >= 18 or Python >= 3.10
- Network access to your Wazuh manager's API (port 55000)
- Wazuh API credentials (from the installation)

### Setup with Claude Desktop / Claude Code

Add the Wazuh MCP server to your Claude configuration:

**Claude Desktop** — edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "wazuh": {
      "command": "npx",
      "args": ["-y", "wazuh-mcp-server"],
      "env": {
        "WAZUH_API_URL": "https://YOUR_MANAGER_IP:55000",
        "WAZUH_API_USER": "wazuh-wui",
        "WAZUH_API_PASSWORD": "YOUR_API_PASSWORD"
      }
    }
  }
}
```

**Claude Code** — add to your ContextOS workspace's `.mcp.json` or `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "wazuh": {
      "command": "python",
      "args": ["-m", "wazuh_mcp_server"],
      "env": {
        "WAZUH_HOST": "YOUR_MANAGER_IP",
        "WAZUH_PORT": "55000",
        "WAZUH_USER": "wazuh-wui",
        "WAZUH_PASSWORD": "YOUR_API_PASSWORD",
        "WAZUH_PROTOCOL": "https",
        "WAZUH_VERIFY_SSL": "false",
        "WAZUH_INDEXER_HOST": "YOUR_MANAGER_IP",
        "WAZUH_INDEXER_PORT": "9200",
        "WAZUH_INDEXER_USER": "admin",
        "WAZUH_INDEXER_PASSWORD": "YOUR_ADMIN_PASSWORD",
        "WAZUH_INDEXER_VERIFY_SSL": "false"
      }
    }
  }
}
```

Replace `YOUR_MANAGER_IP` with your Wazuh manager's public IP (from `terraform output manager_public_ip`).

You need TWO passwords from the installation:
- `wazuh-wui` password → for `WAZUH_PASSWORD` (Manager API)
- `admin` password → for `WAZUH_INDEXER_PASSWORD` (Indexer — required for alert queries)

Install the MCP server: `pip install wazuh-mcp-server` (uses the [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server) which exposes 48 tools including alert search, active response, compliance checks, and agent monitoring).

### Getting Your Wazuh API Password

SSH into your Wazuh manager and retrieve the credentials:

```bash
sudo cat /root/wazuh-install-files/wazuh-passwords.txt
```

Look for the `wazuh-wui` user password — this is the API user.

## Option 2: Direct API Access (No MCP)

If you don't have an MCP server available, you can still query the Wazuh API directly and paste results to your AI assistant:

```bash
# Get an auth token
TOKEN=$(curl -s -u wazuh-wui:YOUR_PASSWORD -k \
  -X POST https://YOUR_MANAGER_IP:55000/security/user/authenticate \
  | jq -r '.data.token')

# Get recent alerts
curl -s -k -H "Authorization: Bearer $TOKEN" \
  "https://YOUR_MANAGER_IP:55000/alerts?limit=10&sort=-timestamp" | jq .

# Get agent list
curl -s -k -H "Authorization: Bearer $TOKEN" \
  "https://YOUR_MANAGER_IP:55000/agents?select=id,name,status" | jq .
```

Copy the JSON output and paste it into your AI conversation for analysis.

## Security Notes

- The Wazuh API uses self-signed certificates by default (`-k` flag in curl).
- API credentials should be treated as secrets. Don't commit them to version control.
- The lab's security group restricts API access (port 55000) to your IP only.
- For production use, configure proper TLS certificates and rotate API credentials.

## What You Can Ask

Once connected, try these prompts with your AI analyst:

- "List all active Wazuh agents and their status"
- "Show me the top 10 most recent critical alerts"
- "Are there any brute force attempts in the last hour?"
- "What vulnerabilities has Wazuh detected on the agent?"
- "Summarize the security posture of my lab environment"

See [Lab Guide Step 4](../lab-guide/04-ai-analysis.md) for more example prompts and analysis workflows.
