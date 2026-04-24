# AI Cloud Security Lab — Course 3: Wazuh SIEM + AI-augmented SOC

> Course context for any AI assistant helping with this repo. The primary teaching surface is `.claude/skills/course-3-instructor/SKILL.md` (the Mateo persona) which auto-loads in Claude Code. This file is a cold-start map for assistants that don't load that skill.

---

## Where the course lives

**The course is the repo.** Students clone this repo, launch Claude Code, and tell it "I'm starting Course 3." The course-3-instructor skill activates Mateo (a senior-SOC-analyst persona), who guides the student through all six lessons end-to-end.

Skool is the front door — landing page, outline, help-question channel, community. It does NOT hold the lesson content. Don't refer students back to Skool lessons; they don't exist there.

**If a student asks something the skill file doesn't cover:** read `.claude/skills/course-3-instructor/SKILL.md` — that's the source of truth.

---

## Course structure

Course 3 has **6 core lessons** that run as one ~2-hour continuous session, plus **5 optional modular labs** (paid add-ons) that use the same deployed lab.

### Core curriculum (in SKILL.md §7–§12)

| # | Lesson | What happens |
|---|--------|--------------|
| L1 | 🛡️ Deploy + dashboard tour | Student clones the repo, edits `tfvars`, runs `./scripts/bootstrap.sh`. Mateo teaches Terraform/CloudVault/Wazuh-arch/MCP-preview/dashboard during the ~20-min install wait. Login, dashboard tour, first reverse-prompt cycle, SCA + vuln exploration. |
| L2 | 🎯 Attack sim + manual investigation | SSH to dev-server-01, run `sudo bash /home/ubuntu/generate-events.sh` (4 MITRE-mapped scenarios). Investigate manually in the Wazuh dashboard. Dana exec summary. |
| L3 | 🔗 MCP + AI investigation | MCP is pre-installed by user_data + auto-wired into `.mcp.json` by bootstrap.sh. Student inspects what's running, threat-models it (3 failure modes), replays L2's investigation via natural language. 10x speedup is felt, not claimed. |
| L4 | 🎯 Threat hunting + AI verification | 4 structured hunts (unexpected accounts, listening ports, persistence, AI-verification stress test). Hypothesis / query / disposition framing. |
| L5 | ⚡ Detection engineering + active response | Rule-syntax primer against a real Wazuh default. Student writes rule 100001 (CloudVault FIM-rate), validates with `wazuh-logtest`, deploys, triggers, verifies firing via MCP. Duration-based active response (anti-`wazuh_firewall_allow` quirk). |
| L6 | 🧹 IR + portfolio + close | Compressed Dana IR scenario. Project Card draft for student's portfolio. #wins post for Skool. `terraform destroy` with verification. |

### Optional paid labs (career-path oriented)

Not in this repo — sold as modular add-ons post-launch. Each uses the same core lab deploy:

- **Lab A — AWS Log Connection** (Cloud Detection Engineer): ingest CloudTrail + VPC Flow Logs + GuardDuty into Wazuh, write detection rules on real AWS log shapes
- **Lab B — SOC 2 Evidence Package** (GRC/Audit): auditor-grade evidence for CC7.2, CC6.1, CC7.1
- **Lab C — Threat Hunting Playbook** (SOC Analyst): 10 hunts with dispositions and detection-gap recommendations
- **Lab D — Automated Incident Response** (SOAR/Platform Sec): 1 full auto-chain + 2 MCP-driven playbooks
- **Lab E — Vulnerability Management Workflow** (SRE w/ security scope): 4-axis triage + live-validated remediation

**If a student asks about a paid lab before purchase:** acknowledge it exists as a paid add-on, don't pretend to run it. Direct them to the Skool upgrade path.

---

## Fictional scenario: CloudVault Financial

Wealth-management firm, ~80 employees, $2B AUM. Dana is the IT director who hired the student to stand up a SIEM. Audit pressure drives FIM + SCA requirements.

- **Three servers deployed:** `web-server-01` (nginx+TLS portal), `app-server-01` (Python API `/health` + `/api/accounts`), `dev-server-01` (dev workstation + attack launch point)
- **Wazuh manager + 3 agents**, all monitored by FIM, SCA, rootcheck, vulnerability detection
- **CloudVault paths on agents** (monitored by FIM in realtime): `/opt/cloudvault/client-data/`, `/opt/cloudvault/financial-records/`, `/opt/cloudvault/config/`

---

## Architecture facts any assistant should know

- **Static private IPs** — manager `10.0.1.10`, web `10.0.1.20`, app `10.0.1.30`, dev `10.0.1.40`. Mappings live in `/etc/hosts` on each agent.
- **MCP server** — pre-installed on the manager by `terraform/user_data/wazuh_manager.sh`. Docker container listens on port 3000 with bearer auth. `bootstrap.sh` fetches the JWT and writes `.mcp.json` in the repo root.
- **Attack generator** — `scripts/agent-events-generator.sh` is the source. It's deployed to `/home/ubuntu/generate-events.sh` on each agent via user_data base64 encode. The agent copy is what actually runs.
- **Credentials** — `.lab-credentials.txt` (gitignored, written by bootstrap.sh from the install tarball). `.mcp.json` (gitignored, written by bootstrap.sh from MCP /auth/token exchange).
- **Idempotency** — `bootstrap.sh` is re-runnable; re-running fetches fresh credentials and re-writes `.mcp.json`. `terraform apply` is idempotent.

---

## Quick reference for AI assistants in this repo

1. **"Has the student run the generator yet?"** — Check the indexer for recent alerts from dev-server-01 via the MCP (`get_alerts` with `agent.name:"dev-server-01"`, last 15 min). If empty, they haven't run it. Path on the agent: `/home/ubuntu/generate-events.sh`.
2. **"MCP isn't connected" in Claude Code** — Restart Claude Code (it only reads `.mcp.json` at launch). If still broken: JWT may have expired (24h default) — re-run `bootstrap.sh` or its MCP-wiring section.
3. **"Filter syntax in the dashboard"** — Wazuh 4.9 defaults to DQL (`rule.level >= 5 and agent.name : "dev-server-01"`), NOT the old Lucene syntax (`rule.level:>=5`). If the student sees "Expected value" syntax errors, it's DQL vs Lucene.
4. **"Dashboard menu paths"** — Wazuh 4.9 renamed things vs older docs. See SKILL.md §5 Block 6 for the authoritative map (`☰ → Threat intelligence → Threat Hunting` is home base for alerts, not the old "Modules → Security Events").
5. **"Expected false positives"** — Rule 510 on `/bin/diff` is a known Wazuh rootcheck FP. Document and ignore.

---

## Contributing / feedback

- **Infrastructure bugs** (Terraform, user_data, bootstrap, MCP install): GitHub Issue + PR
- **Course content** (Mateo voice, lesson pedagogy): GitHub Issue + PR against SKILL.md
- **Upstream Wazuh / MCP issues**: upstream to gensecaihq/Wazuh-MCP-Server or wazuh/wazuh

MIT licensed — use in training, workshops, demos. Attribution appreciated.
