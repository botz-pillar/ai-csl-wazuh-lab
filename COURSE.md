# AI Cloud Security Lab — Course 3: Deploy Wazuh + AI

> This repo is the infrastructure for Course 3 of the AI Cloud Security Lab (AI-CSL) curriculum, hosted on Skool. The Skool course is the canonical source of lesson content, prompts, and sequencing. This document gives Claude Code (and any other AI assistant helping a student) enough context to guide them through the lab correctly.

---

## Where the course lives

**Primary:** [AI Cloud Security Lab on Skool](https://www.skool.com/cloud-security-lab) — Classroom → Course 3.

This GitHub repo contains only the infrastructure (Terraform, user_data scripts, MCP helpers). It does not contain the lesson text itself.

**If a student asks "what is Course 3 / Lesson 2 / Lab A?" don't push back saying they don't exist.** They exist in Skool. Acknowledge and help the student with the hands-on work their lesson is asking them to do.

---

## Course structure

Course 3 has **6 core lessons + 5 optional labs**.

### Core curriculum

| # | Lesson | What the student does in this repo |
|---|--------|-------------------------------------|
| 1 | 🛡️ Deploy CloudVault's SIEM | Clones this repo, edits `terraform/terraform.tfvars`, runs `./scripts/bootstrap.sh`, then `./scripts/doctor.sh`. Spends Step 6 on a dashboard tour and Step 7 exploring what Wazuh found automatically (SCA, vulns, FIM). |
| 2 | 🎯 Simulate Attacks + Investigate Manually | SSHes to dev-server-01 and runs `sudo bash /home/ubuntu/generate-events.sh`. Investigates the resulting alerts in the Wazuh dashboard **manually** (no AI), following an 9-step DQL click-path. Times themselves. |
| 3 | 🔗 Connect the MCP Server + AI Investigation | Sets up [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server), connects it to Claude Code via `.mcp.json`, re-investigates the same alerts with AI. Times the comparison. Generates an executive report for "Dana" (fictional CISO). |
| 4 | 🎯 Threat Hunting + AI That's Wrong | Runs 4 proactive hunts (processes, ports, persistence artifacts, user anomalies) through MCP. Practices verifying AI claims against raw data. Picks 5 prompts to save for real SOC work. |
| 5 | ⚡ Detection Engineering + Active Response | Reads a Rule Syntax Primer (OSSEC regex, `<if_sid>` vs `<if_group>`, levels). Writes custom detection rule 100001 for CloudVault-specific FIM-rate patterns. Uses MCP to block/unblock IPs with duration-based active response. |
| 6 | 🧹 Clean Up + Portfolio | Writes a Project Card + reflections for interview stories. Points at the 5 labs. Destroys the lab with `terraform destroy`. |

### Optional labs (career-path oriented)

Located in the main AI-CSL `shared-context` repo at `curriculum/courses/03-lab-wazuh-labs/`. Each uses this same Wazuh deployment via `start-lab.sh` / `stop-lab.sh`:

- **Lab A — Custom Decoder Deep Dive** (Detection Engineering): 3 custom decoders + rules for CloudVault API, nginx access log, sudo allow-list inversion
- **Lab B — SOC 2 Evidence Package** (GRC/Audit): Auditor-grade evidence for CC7.2, CC6.1, CC7.1
- **Lab C — Threat Hunting Playbook** (SOC Analyst): 10 hunts with dispositions and detection-gap recommendations
- **Lab D — Automated Incident Response** (SOAR/Platform Sec): 1 full auto-chain + 2 MCP-driven playbooks
- **Lab E — Vulnerability Management Workflow** (SRE w/ security scope): 4-axis triage + live-validated remediation

---

## Fictional scenario: CloudVault Financial

The lab runs against a fictional wealth-management firm. Context lives in:
- `contextOS-personal/lab-data/cloudvault-financial/` (public repo, submodule) — company profile, CloudTrail dataset, answer key
- This repo's `terraform/user_data/` — deploys a web-server-01 (nginx+TLS CloudVault portal), app-server-01 (Python API `/health` + `/api/accounts`), dev-server-01 (dev workstation), all monitored by Wazuh

**The Wazuh lab is the live infrastructure.** The `cloudvault-financial/` dataset is separate static training data used in Courses 1-2. Don't conflate them.

---

## Quick reference for Claude Code

When a student asks about something Course 3 promises but you don't see evidence of:

1. **"Has the student actually run the generator on the agent?"** — The course instructs SSH into dev-server-01 and run `sudo bash /home/ubuntu/generate-events.sh`. If there are no alerts, they probably haven't run it yet. Check the dashboard or `get_wazuh_alerts` MCP tool for recent events from dev-server-01.
2. **"The script on the agent is the source of truth"** — not any file in `scripts/` of this repo. The file at `/home/ubuntu/generate-events.sh` on each agent is what actually runs. `scripts/agent-events-generator.sh` in this repo is just the source — it's deployed verbatim via Terraform user_data base64.
3. **"CloudVault paths on the agents"** — `/opt/cloudvault/client-data/`, `/opt/cloudvault/financial-records/`, `/opt/cloudvault/config/`. These are real directories on the Wazuh agents, monitored by FIM in realtime. Scenario 2 in the generator modifies files there.
4. **"Filter syntax"** — Wazuh 4.9 dashboard uses DQL by default (`rule.level >= 5 and agent.name : "dev-server-01"`), not Lucene (`rule.level:>=5`). If the student hits "Expected value" syntax errors, it's DQL vs Lucene.
5. **"Expected false positives"** — Rule 510 on `/bin/diff` fires routinely as a known Wazuh rootcheck FP. Don't escalate it; document and move on.

---

## Contributing / feedback

This lab is actively developed. File issues or PRs against this repo for infrastructure bugs. For course content feedback (lesson text, prompts, pedagogy), use the Skool classroom comments — course text is maintained in a separate (private) curriculum repo.
