# Connecting Wazuh to Claude Code via MCP

For the full setup guide see [`docs/mcp-server-setup.md`](../docs/mcp-server-setup.md) — this directory is for supplementary files.

## What's here

- `firewall-allow-fix.patch` — AI-CSL patch fixing the upstream `wazuh_firewall_allow` bug in v4.2.1 (missing `alert.data.srcip` causes iptables rollback to fail)

## Applying the firewall_allow patch

After cloning the Wazuh MCP server, apply the patch before starting it:

```bash
cd ~/projects/Wazuh-MCP-Server
git apply /path/to/ai-csl-wazuh-lab/mcp/firewall-allow-fix.patch
```

Then reinstall (editable mode picks up the change automatically if you're using `pip install -e .`):

```bash
source .venv/bin/activate
pip install -e . --force-reinstall --no-deps
```

Verify the patch applied:

```bash
grep -A2 "alert.*srcip" src/wazuh_mcp_server/api/wazuh_client.py | head -10
```

You should see `"alert": {"data": {"srcip": src_ip}}` in BOTH `firewall_allow` and `host_allow` methods.

## Why the patch is needed

Upstream v4.2.1's `firewall_allow` tool sends an empty `alert.data` structure to the agent's `firewall-drop.sh`. That script reads `srcip` from `alert.data.srcip` to know which IP to unblock. With the field missing, it logs `"Cannot read 'srcip' from data"` and leaves the iptables DROP rule in place. Our patch mirrors the `block_ip` tool's data structure so rollback works.

Upstream PR status: **filed** (link once merged, remove this patch).

## Direct Wazuh API access (no MCP fallback)

If you can't get the MCP server running, you can still query Wazuh's API directly:

```bash
# Get an auth token
TOKEN=$(curl -s -u wazuh-wui:YOUR_PASSWORD -k \
  -X POST https://YOUR_MANAGER_IP:55000/security/user/authenticate \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')

# Recent alerts
curl -s -k -H "Authorization: Bearer $TOKEN" \
  "https://YOUR_MANAGER_IP:55000/agents?limit=10" | python3 -m json.tool

# Or query the indexer for alert data
curl -s -k -u "admin:YOUR_ADMIN_PASSWORD" \
  "https://YOUR_MANAGER_IP:9200/wazuh-alerts-*/_count" | python3 -m json.tool
```

Copy output to Claude for analysis.
