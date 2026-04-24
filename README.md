# AI Cloud Security Lab — Course 3: Wazuh SIEM + AI-augmented SOC

**CloudVault Financial was breached. You ran the IR. The remediation looks clean, but three persistence categories from your report were never confirmed eliminated — and SOC 2 evidence collection starts in a few weeks. Dana brought in a senior SOC peer (Mateo) to help you stand up a SIEM, baseline the environment, hunt for what's left behind, and produce the evidence package.**

This is the infrastructure and instructor skill for Course 3 of the [AI Cloud Security Lab (AI-CSL)](https://skool.com/ai-csl). Course 3 picks up where Courses 1 and 2 left off: same company, same CISO, same security lead (you), same unresolved threat. Pair a production-grade Wazuh 4.9 SIEM with the [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server), and let Mateo guide you through the post-incident investigation via Claude Code.

**~2 hours. ~$0.50 in AWS. One portfolio artifact.**

---

## How it works

```
   Your laptop                                       AWS
 ┌──────────────────┐                   ┌─────────────────────────────────┐
 │                  │                   │                                 │
 │  Claude Code     │ ── HTTPS :443 ──► │   Wazuh Manager (t3.large)      │
 │  + Mateo skill   │ ── HTTP  :3000 ─► │   ├─ Manager / Indexer          │
 │  + Wazuh MCP     │ ── SSH   :22  ──► │   ├─ Dashboard                  │
 │    (auto-wired)  │                   │   └─ MCP Server (Docker :3000)  │
 │                  │                   │                                 │
 │  Browser         │ ── HTTPS :443 ──► │   CloudVault agents (t3.micro)  │
 │  (dashboard tour)│                   │   ├─ web-server-01  10.0.1.20   │
 │                  │                   │   ├─ app-server-01  10.0.1.30   │
 └──────────────────┘                   │   └─ dev-server-01  10.0.1.40   │
                                        │                                 │
                                        └─────────────────────────────────┘
```

The MCP server runs on the manager. `bootstrap.sh` installs it, fetches a bearer token, and writes `.mcp.json` in this repo. When you launch Claude Code here, the MCP auto-mounts — no manual setup.

---

## Quick start

**Prerequisites** (5 min): AWS account + CLI configured, Terraform ≥ 1.5, an EC2 key pair in your target region, [Claude Code](https://docs.claude.com/claude-code) CLI.

```bash
# 1. Clone
git clone https://github.com/botz-pillar/ai-csl-wazuh-lab.git
cd ai-csl-wazuh-lab

# 2. Configure Terraform (your public IP, your EC2 key name)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars

# 3. Deploy (one command — Terraform + Wazuh install + MCP install + .mcp.json)
./scripts/bootstrap.sh

# 4. Launch Claude Code in the lab directory
claude

# 5. Tell Mateo you're starting
# > I'm starting Course 3
```

Mateo takes it from there. Total deploy time ~20-25 min (Terraform is ~2 min, Wazuh install is ~15 min, MCP install is ~3 min, agent registration is ~5 min — mostly parallel). Mateo teaches during the wait so there's no dead time.

---

## What you'll do

Six phases of the investigation, one continuous ~2-hour session:

| # | Phase | What happens |
|---|---|---|
| 1 | 🛡️ Stand up the SIEM | Bootstrap deploys everything. Mateo briefs you on the case, walks Wazuh architecture, previews the MCP. You log in, tour the dashboard, run your first query. |
| 2 | 🎯 Baseline the environment | Exercise four MITRE TTPs on `dev-server-01` matching the pattern classes from your IR report. Investigate the resulting chain manually. Confirm SIEM coverage before hunting. First update to Dana. |
| 3 | 🔗 Threat-model the MCP, plug it in | Inspect what bootstrap pre-installed. Three concrete failure modes + mitigations (stolen JWT, prompt injection, supply chain). Re-run the baseline investigation through natural language. AI-drafted CISO update, human-verified. |
| 4 | 🎯 The backdoor hunt | Four structured hunts against the three persistence categories from the IR report (account, listener, scheduler) plus an AI-verification drill. Hunt log becomes SOC 2 evidence. |
| 5 | ⚡ Tripwires and response | Write custom rule 100001 — the CloudVault client-data tripwire Dana asked for. Validate with `wazuh-logtest`. Deploy, trigger, verify. Take a duration-based active response. |
| 6 | 🧹 Close the case | Compressed end-to-end IR on a fresh alert. Evidence package for Dana and SOC 2 CC6.7. Personal artifact for interviews. `terraform destroy` with verification. |

---

## Cost

| Resource | Hourly | 2h session | A weekend (if you forget) |
|---|---|---|---|
| Manager (t3.large) | $0.083 | $0.17 | $4.00 |
| 3× agents (t3.micro) | $0.031 | $0.06 | $1.50 |
| EBS (~90 GB gp3) | ~$0.012 | $0.02 | $0.60 |
| Elastic IP (while running) | free | free | free |
| **Running** | **~$0.126/hr** | **~$0.25** | **~$6** |

**Always `terraform destroy` when done.** Set up an AWS Budget Alert at $10 if you haven't already.

---

## Commands you'll use

| Command | What it does |
|---|---|
| `./scripts/bootstrap.sh` | Deploy everything (Terraform + Wazuh install + MCP install + .mcp.json) |
| `./scripts/doctor.sh` | Health check: prereqs, AWS, EC2, Wazuh services, MCP, agents, alerts |
| `./scripts/stop-lab.sh` | Stop compute (EBS still billed at ~$0.01/hr) |
| `./scripts/start-lab.sh` | Resume stopped instances |
| `cd terraform && terraform destroy` | Nuke everything. Always run when done. |

---

## Documentation

- [Architecture](docs/architecture.md) — detailed network + data flow
- [Costs](docs/costs.md) — full cost breakdown + cost-saving tips
- [MCP Server Setup](docs/mcp-server-setup.md) — what bootstrap.sh did on your behalf + manual install reference for reproducing in production
- [Custom Detection Rules](docs/custom-detection-rules.md) — the Wazuh rule syntax primer from L5, standalone
- [Troubleshooting](docs/troubleshooting.md) — common issues including MCP-specific ones
- `.claude/skills/course-3-instructor/SKILL.md` — **the Mateo playbook** (1,200+ lines). Auto-loads in Claude Code. The product.

---

## Prerequisites checklist

- [ ] AWS account with billing enabled
- [ ] `aws configure` works (SSO or long-lived keys, either is fine)
- [ ] Terraform ≥ 1.5 installed (`brew install terraform` on macOS)
- [ ] An EC2 key pair created in your target region (default: `us-east-1`)
- [ ] Private key saved at `~/.ssh/<keyname>.pem` with `chmod 600`
- [ ] [Claude Code](https://docs.claude.com/claude-code) CLI installed (`npm i -g @anthropic-ai/claude-code`)
- [ ] An AWS Budget Alert at $10 (Billing → Budgets → Create budget)

---

## Support

- **In-course issues** (something about the lab itself): open a GitHub Issue here
- **Learning questions** (Wazuh, SOC concepts, the course material): the AI-CSL Skool community → `#build-questions` channel
- **MCP server issues upstream**: [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server/issues)

---

## License

MIT. Use it in your own training, workshops, client demos, whatever. Attribution appreciated but not required.
