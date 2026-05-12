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

## Tools

Extracted from `gensecaihq/Wazuh-MCP-Server` tag **v4.2.1** (2026-03-26) via tool-registration scan of `src/wazuh_mcp_server/server.py`. Total: **48 tools**.

> **C3 draft claim:** "48 tools at your fingertips" — **verified correct** at v4.2.1.

### Alert & Event Search (4)
| Tool | Description |
|------|-------------|
| `get_wazuh_alerts` | Retrieve Wazuh security alerts with optional filtering |
| `get_wazuh_alert_summary` | Get a summary of Wazuh alerts grouped by specified field |
| `analyze_alert_patterns` | Analyze alert patterns to identify trends and anomalies |
| `search_security_events` | Search for specific security events across all Wazuh data (Lucene syntax) |

### Agent Management (6)
| Tool | Description |
|------|-------------|
| `get_wazuh_agents` | Retrieve information about Wazuh agents |
| `get_wazuh_running_agents` | Get list of currently running/active Wazuh agents |
| `check_agent_health` | Check the health status of a specific Wazuh agent |
| `get_agent_processes` | Get running processes from a specific Wazuh agent |
| `get_agent_ports` | Get open ports from a specific Wazuh agent |
| `get_agent_configuration` | Get configuration details for a specific Wazuh agent |

### Vulnerability Detection (3)
| Tool | Description |
|------|-------------|
| `get_wazuh_vulnerabilities` | Retrieve vulnerability information from Wazuh Indexer |
| `get_wazuh_critical_vulnerabilities` | Get critical vulnerabilities from Wazuh Indexer |
| `get_wazuh_vulnerability_summary` | Get vulnerability summary statistics from Wazuh Indexer |

### Security Analysis & Reporting (6)
| Tool | Description |
|------|-------------|
| `analyze_security_threat` | Analyze a security threat indicator using AI-powered analysis |
| `check_ioc_reputation` | Check reputation of an Indicator of Compromise (IoC) |
| `perform_risk_assessment` | Perform comprehensive risk assessment for agents or the environment |
| `get_top_security_threats` | Get top security threats based on alert frequency and severity |
| `generate_security_report` | Generate comprehensive security report |
| `run_compliance_check` | Run compliance check against security frameworks (NIST, PCI-DSS, etc.) |

### Statistics & Health (8)
| Tool | Description |
|------|-------------|
| `get_wazuh_statistics` | Get comprehensive Wazuh statistics and metrics |
| `get_wazuh_weekly_stats` | Get weekly statistics including alerts, agents, and trends |
| `get_wazuh_cluster_health` | Get Wazuh cluster health information |
| `get_wazuh_cluster_nodes` | Get information about Wazuh cluster nodes |
| `get_wazuh_rules_summary` | Get summary of Wazuh rules and their effectiveness |
| `get_wazuh_remoted_stats` | Get Wazuh remoted (agent communication) statistics |
| `get_wazuh_log_collector_stats` | Get Wazuh log collector statistics |
| `validate_wazuh_connection` | Validate connection to Wazuh server and return status |

### Log Management (2)
| Tool | Description |
|------|-------------|
| `search_wazuh_manager_logs` | Search Wazuh manager logs for specific patterns |
| `get_wazuh_manager_error_logs` | Get recent error logs from Wazuh manager |

### Active Response — Block / Isolate / Restrict (8)
| Tool | Description |
|------|-------------|
| `wazuh_block_ip` | **[ACTION]** Block an IP via firewall-drop. Risk: LOW, Reversible. Use `duration` param for auto-expiry. |
| `wazuh_isolate_host` | **[ACTION]** Isolate a host from the network. Risk: MEDIUM, Reversible. |
| `wazuh_kill_process` | **[ACTION]** Terminate a process on an agent. Risk: MEDIUM, Not reversible. |
| `wazuh_disable_user` | **[ACTION]** Disable a user account on an agent. Risk: HIGH, Reversible. |
| `wazuh_quarantine_file` | **[ACTION]** Quarantine a file on an agent. Risk: LOW, Reversible. |
| `wazuh_active_response` | **[ACTION]** Execute a generic active response command. Risk: HIGH, Not reversible. |
| `wazuh_firewall_drop` | **[ACTION]** Add a firewall drop rule. Risk: MEDIUM, Reversible. |
| `wazuh_host_deny` | **[ACTION]** Add an entry to hosts.deny. Risk: MEDIUM, Reversible. |

### Active Response — Restart (1)
| Tool | Description |
|------|-------------|
| `wazuh_restart` | **[ACTION]** Restart Wazuh agent or manager service. Risk: CRITICAL, Not reversible. |

### Active Response — Status Checks (5)
| Tool | Description |
|------|-------------|
| `wazuh_check_blocked_ip` | Check if an IP was blocked (searches alert history, not live firewall state) |
| `wazuh_check_agent_isolation` | Check agent isolation status (alert history, not live network state) |
| `wazuh_check_process` | Check if a specific process is running on an agent |
| `wazuh_check_user_status` | Check if a user account was disabled (alert history, not live OS state) |
| `wazuh_check_file_quarantine` | Check if a file has been quarantined on an agent |

### Active Response — Reversals (5)
| Tool | Description |
|------|-------------|
| `wazuh_unisolate_host` | **[ACTION]** Remove host network isolation. Reversal of `wazuh_isolate_host`. |
| `wazuh_enable_user` | **[ACTION]** Re-enable a disabled user account. Reversal of `wazuh_disable_user`. |
| `wazuh_restore_file` | **[ACTION]** Restore a quarantined file. Reversal of `wazuh_quarantine_file`. |
| `wazuh_firewall_allow` | **[ACTION]** Remove a firewall drop rule. Reversal of `wazuh_firewall_drop`. ⚠️ Known bug in v4.2.1 — may add duplicate DROP rule instead of removing original. Use `wazuh_block_ip` with `duration` instead. |
| `wazuh_host_allow` | **[ACTION]** Remove a hosts.deny entry. Reversal of `wazuh_host_deny`. |

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
