# Connecting Wazuh to Claude Code via MCP

For the full setup guide see [`docs/mcp-server-setup.md`](../docs/mcp-server-setup.md) — this directory was used for supplementary files (previously housed a firewall_allow patch that v3 no longer needs).

## Active response pattern

The course teaches duration-based blocks, not manual unblocks:

```
Block 192.0.2.99 on web-server-01 for 300 seconds.
```

`wazuh_block_ip` takes a `duration` (seconds). After the duration expires, Wazuh's internal timeout logic removes the iptables rule. This matches how production SOCs actually operate — automatic timeouts prevent orphaned blocks.

**If you need to unblock early,** SSH to the agent:

```bash
ssh ubuntu@<agent-ip> 'sudo iptables -D INPUT -s <blocked-ip> -j DROP'
```

The upstream MCP `wazuh_firewall_allow` tool has a known bug where it adds a duplicate DROP rule instead of removing the original — see `docs/mcp-server-setup.md` for details.

## Direct Wazuh API access (no-MCP fallback)

If the MCP server isn't available, query the Wazuh API directly:

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

Paste the JSON output to Claude for analysis.
