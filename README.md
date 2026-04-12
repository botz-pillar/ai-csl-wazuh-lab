# AI-Powered SOC Lab — CloudVault Financial

**Learn cloud security by deploying a real SIEM, monitoring a fictional financial firm's servers, and investigating threats through an AI-powered MCP.**

This lab is Course 3 of the [AI Cloud Security Lab (AI-CSL)](https://github.com/botz-pillar) curriculum. It pairs a production-grade Wazuh SIEM on AWS with the [Wazuh MCP Server](https://github.com/gensecaihq/Wazuh-MCP-Server) so you can investigate, hunt, and respond to incidents in natural language.

## What You'll Build

```
┌──────────────────────── AWS VPC (10.0.0.0/16) ────────────────────────┐
│                                                                       │
│   ┌──────────────────────┐        ┌──────────────────────────┐        │
│   │  Wazuh Manager       │        │  CloudVault Financial     │        │
│   │  (t3.large)          │◄──1514─│  web-server-01  (t3.micro)│        │
│   │                      │◄──1514─│  app-server-01  (t3.micro)│        │
│   │  Manager / Indexer   │◄──1514─│  dev-server-01  (t3.micro)│        │
│   │  / Dashboard         │        │                           │        │
│   └──────────┬───────────┘        └──────────────────────────┘        │
│              │ :443 :55000 :9200                                       │
└──────────────│────────────────────────────────────────────────────────┘
               │
   ┌───────────┴────────────┐
   │  Your laptop           │
   │  - Browser → Dashboard │
   │  - Claude Code + MCP   │
   │    (Docker on :3000)   │
   └────────────────────────┘
```

## What You'll Learn

- Deploy a production-grade SIEM (manager + indexer + dashboard) on AWS with Terraform
- Monitor three fictional CloudVault servers with File Integrity Monitoring, SCA, and vulnerability scanning
- Simulate 4 attack scenarios mapped to MITRE ATT&CK (SSH brute force, FIM violations, privilege escalation, persistence)
- Investigate alerts through the Wazuh dashboard AND through Claude Code + MCP server (48 tools)
- Hunt for threats proactively — find things the rules didn't alert on
- Verify AI output against raw data (catch Claude being confidently wrong)
- Write custom detection rules in XML and test with `wazuh-logtest`
- Take active response actions (block IPs, isolate hosts) through natural language

## Cost Transparency

| Resource | Hourly | 4h session | Monthly (if left running) |
|----------|--------|------------|---------------------------|
| Wazuh manager (t3.large) | $0.083 | $0.33 | $60.59 |
| 3× CloudVault agents (t3.micro) | $0.031 | $0.12 | $22.78 |
| EBS storage (~90 GB gp3) | — | — | ~$7 |
| Elastic IP (while running) | free | free | free |
| **Running total** | **~$0.11/hr** | **~$0.45** | **~$80–90/month** |

Run `terraform destroy` when done — don't leave it running overnight. Set up a $10 AWS budget alert to catch surprises.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/botz-pillar/ai-csl-wazuh-lab.git
cd ai-csl-wazuh-lab

# 2. Configure Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars — set your_ip_cidr and key_name

# 3. Deploy (one-command: runs terraform apply, waits for install, fetches credentials)
./scripts/bootstrap.sh

# 4. Verify everything is healthy
./scripts/doctor.sh
```

Bootstrap takes ~12–20 minutes end-to-end (1–2 min Terraform, 10–15 min Wazuh install, 3–5 min for agents to register).

Then follow [Course 3 on Skool](https://skool.com/ai-csl) (members only) or the [lab-guide/](lab-guide/) files for the standalone path.

## Prerequisites

- AWS account with CLI configured (`aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- An EC2 key pair in `us-east-1` (or whichever region you set in `tfvars`)
- Docker 20.10+ with Compose v2 (for the MCP server — Path A in the MCP guide)
- Claude Code CLI (for MCP connection and AI investigation)

## Documentation

- [Architecture](docs/architecture.md) — Detailed architecture and data flow
- [Cost Breakdown](docs/costs.md) — Detailed cost analysis and optimization tips
- [MCP Server Setup](docs/mcp-server-setup.md) — Connect Claude Code to your SIEM (48 tools)
- [Custom Detection Rules](docs/custom-detection-rules.md) — Write, test, and deploy rules with `wazuh-logtest`
- [Troubleshooting](docs/troubleshooting.md) — Common issues and fixes

## Helper Scripts

- `scripts/bootstrap.sh` — one-command deploy + verify + fetch credentials
- `scripts/doctor.sh` — diagnostic health check (prerequisites, AWS, Terraform, EC2, Wazuh services, agents, alerts)
- `scripts/start-lab.sh` / `scripts/stop-lab.sh` — stop instances to pause costs, resume later without rebuild

## Contributing

This is a teaching resource. If you find an issue or want to improve the lab, open a PR. Keep it beginner-friendly.

## License

MIT
