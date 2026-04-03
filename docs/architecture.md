# Architecture

## Overview

The AI-Powered SOC Lab deploys a complete Wazuh SIEM stack on AWS with a single managed workload. An AI analyst connects to the Wazuh API to provide intelligent alert analysis.

## Architecture Diagram

```
                          ┌──────────────────────────────────────────────────────────┐
                          │                     AWS VPC (10.0.0.0/16)               │
                          │                                                          │
                          │   ┌──────────────── Public Subnet (10.0.1.0/24) ──────┐ │
                          │   │                                                    │ │
                          │   │   ┌────────────────────┐  ┌────────────────────┐   │ │
                          │   │   │  Wazuh Manager     │  │  Wazuh Agent       │   │ │
                          │   │   │  (t3.medium)       │  │  (t3.micro)        │   │ │
                          │   │   │                    │  │                    │   │ │
                          │   │   │  ┌──────────────┐  │  │  Simulated         │   │ │
                          │   │   │  │ Wazuh Mgr    │  │◄─│  workload that     │   │ │
                          │   │   │  │ (1514/1515)  │  │  │  generates events  │   │ │
                          │   │   │  ├──────────────┤  │  │                    │   │ │
                          │   │   │  │ Indexer      │  │  │  wazuh-agent       │   │ │
                          │   │   │  │ (9200)       │  │  │  sends logs on     │   │ │
                          │   │   │  ├──────────────┤  │  │  port 1514         │   │ │
                          │   │   │  │ Dashboard    │  │  │                    │   │ │
                          │   │   │  │ (:443)       │  │  └────────────────────┘   │ │
                          │   │   │  ├──────────────┤  │                            │ │
                          │   │   │  │ API          │  │                            │ │
                          │   │   │  │ (:55000)     │  │                            │ │
                          │   │   │  └──────────────┘  │                            │ │
                          │   │   └────────┬───────────┘                            │ │
                          │   │            │                                        │ │
                          │   └────────────│────────────────────────────────────────┘ │
                          │                │ Elastic IP                               │
                          └────────────────│─────────────────────────────────────────┘
                                           │
                            ┌──────────────┼──────────────┐
                            │              │              │
                      ┌─────▼─────┐  ┌─────▼─────┐  ┌────▼──────┐
                      │  Browser  │  │  SSH       │  │  AI       │
                      │  :443     │  │  :22       │  │  Analyst  │
                      │           │  │            │  │  (MCP)    │
                      │  Dashboard│  │  Admin     │  │  :55000   │
                      └───────────┘  └───────────┘  └───────────┘
```

## Components

### Wazuh Manager (All-in-One)

A single t3.medium instance running the complete Wazuh stack:

- **Wazuh Manager** — Receives and processes security events from agents. Runs detection rules, triggers alerts, and manages agent configuration.
- **Wazuh Indexer** — OpenSearch-based data store. Indexes alerts and events for search and visualization.
- **Wazuh Dashboard** — Web UI built on OpenSearch Dashboards. Provides alert visualization, agent management, and compliance reporting.
- **Wazuh API** — RESTful API on port 55000. Used by the dashboard, CLI tools, and the AI analyst (via MCP).

### Wazuh Agent

A t3.micro instance running the Wazuh agent. Represents a typical workload being monitored:

- Collects system logs (syslog, auth.log, etc.)
- Monitors file integrity on critical directories
- Runs rootkit detection checks
- Reports to the manager on port 1514

### AI Analyst (External)

Not deployed as part of the infrastructure. Connects from your local machine to the Wazuh API via MCP:

- Queries alerts and agent data through the Wazuh API
- Provides natural language analysis of security events
- Helps with triage, investigation, and recommendations

## Network Architecture

### VPC Design

- Single VPC: `10.0.0.0/16`
- Single public subnet: `10.0.1.0/24`
- Internet gateway for outbound access (package downloads, updates)
- All instances in the public subnet for simplicity (this is a lab, not production)

### Security Groups

**Manager Security Group:**
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |
| 443 | TCP | Your IP | Wazuh Dashboard |
| 1514 | TCP | VPC (10.0.0.0/16) | Agent event forwarding |
| 1515 | TCP | VPC (10.0.0.0/16) | Agent enrollment |
| 55000 | TCP | Your IP | Wazuh API |

**Agent Security Group:**
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |

Both security groups allow all outbound traffic.

## Data Flow

1. **Agent collects events** — File changes, log entries, system calls, rootkit checks
2. **Agent sends to manager** — Encrypted on port 1514
3. **Manager processes events** — Decodes, applies rules, generates alerts
4. **Alerts indexed** — Stored in the Wazuh Indexer (OpenSearch)
5. **Dashboard visualizes** — Charts, tables, and compliance reports
6. **AI analyzes** — Queries the API and provides insights

## Production Considerations

This lab uses a simplified single-node architecture. In production, you would:

- Separate the indexer, manager, and dashboard onto different instances
- Use a multi-node indexer cluster for high availability
- Place instances in private subnets with a bastion host or VPN
- Use a load balancer with a proper TLS certificate for the dashboard
- Enable Wazuh's built-in vulnerability detection and compliance modules
- Configure log rotation and retention policies
