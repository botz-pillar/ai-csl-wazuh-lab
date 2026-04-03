# AI-Powered SOC Lab

**Learn cloud security by building a real Security Operations Center — then let AI help you analyze the threats.**

This lab teaches you how a modern SOC works by deploying a production-grade SIEM (Wazuh) on AWS and connecting it to an AI security analyst. You'll generate real security events, investigate alerts, and learn how AI can accelerate threat detection and response.

This is a project from the [AI Cloud Security Lab (AI-CSL)](https://github.com/ai-csl) community.

## What You'll Build

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC                              │
│                                                             │
│   ┌─────────────────────┐     ┌─────────────────────┐      │
│   │   Wazuh Manager     │     │   Wazuh Agent        │     │
│   │   (t3.medium)       │◄────│   (t3.micro)         │     │
│   │                     │1514 │                      │     │
│   │  ┌───────────────┐  │     │  Simulated workload  │     │
│   │  │ Indexer       │  │     │  that generates       │     │
│   │  │ Dashboard :443│  │     │  security events      │     │
│   │  │ Manager       │  │     └─────────────────────┘      │
│   │  └───────────────┘  │                                   │
│   └─────────────────────┘                                   │
│            ▲                                                │
└────────────│────────────────────────────────────────────────┘
             │ HTTPS :443
             │
   ┌─────────┴──────────┐
   │   Your Browser      │
   │   + AI Analyst      │
   │   (via MCP)         │
   └─────────────────────┘
```

## What You'll Learn

- **SIEM Fundamentals** — How Wazuh collects, normalizes, and correlates security events
- **Infrastructure as Code** — Deploy the entire lab with `terraform apply`
- **Threat Detection** — Generate and investigate real alerts: brute force attacks, file integrity changes, rootkit checks, port scans
- **AI-Powered Analysis** — Connect an AI analyst to your SIEM and ask questions like "What are the top critical alerts?" and "Are we meeting CIS benchmarks?"
- **Cloud Cost Management** — Start/stop your lab to keep costs under $5 for a weekend

## Cost Transparency

| Resource | Hourly Cost | Weekend (48h) | Monthly |
|----------|------------|----------------|---------|
| Wazuh Manager (t3.medium) | $0.0416 | $2.00 | $30.37 |
| Wazuh Agent (t3.micro) | $0.0104 | $0.50 | $7.59 |
| EBS Storage (50GB total) | — | $0.16 | $4.00 |
| Elastic IP (when running) | Free | Free | Free |
| **Total** | **~$0.052** | **~$3-5** | **~$42** |

Stop your instances when not in use. An idle Elastic IP costs $0.005/hr.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/ai-csl/ai-csl-wazuh-lab.git
cd ai-csl-wazuh-lab

# 2. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your IP and key pair name

# 3. Deploy
terraform init
terraform apply

# 4. Wait ~10 minutes for Wazuh to fully initialize, then open the dashboard
# URL is printed in the Terraform output
```

Then follow the [Lab Guide](lab-guide/01-deploy.md) step by step.

## Lab Guide

1. [Deploy the Lab](lab-guide/01-deploy.md) — Terraform setup and deployment
2. [Verify Wazuh](lab-guide/02-verify.md) — Confirm services are running and agents are connected
3. [Generate Noise](lab-guide/03-generate-noise.md) — Simulate real attacks and security events
4. [AI Analysis](lab-guide/04-ai-analysis.md) — Connect your AI analyst and investigate
5. [Teardown](lab-guide/05-teardown.md) — Clean up and cost management

## Prerequisites

- AWS account with CLI configured (`aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- An EC2 key pair in your target region
- Basic comfort with Linux terminal
- (Optional) Claude or another AI assistant with MCP support for the AI analysis section

## Documentation

- [Architecture](docs/architecture.md) — Detailed architecture and data flow
- [Cost Breakdown](docs/costs.md) — Detailed cost analysis and optimization tips
- [Troubleshooting](docs/troubleshooting.md) — Common issues and fixes
- [MCP Setup](mcp/README.md) — Connect Wazuh to your AI analyst

## Contributing

This is a community teaching resource. If you find an issue or want to improve the lab, open a PR. Keep it beginner-friendly.

## License

MIT
