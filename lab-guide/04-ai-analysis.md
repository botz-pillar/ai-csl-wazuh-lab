# Step 4: AI-Powered Alert Analysis

This is where the lab gets interesting. Instead of manually clicking through alerts in the dashboard, you'll connect an AI analyst to your Wazuh instance and have a conversation about your security posture.

## Setup

Before you start, make sure you've:

1. Completed [Step 3: Generate Noise](03-generate-noise.md) so there are alerts to analyze
2. Set up the MCP connection to Wazuh (see [MCP Setup](../mcp/README.md))

If you don't have MCP configured, you can still do this step — just query the Wazuh API manually and paste the results into your AI conversation.

## Quick API Access (Without MCP)

If you're not using MCP, grab data from the Wazuh API and share it with your AI:

```bash
# SSH to the manager
ssh -i ~/.ssh/wazuh-lab.pem ubuntu@$(terraform output -raw manager_public_ip)

# Authenticate
PASS=$(sudo grep "wazuh-wui" /root/wazuh-install-files/wazuh-passwords.txt | awk '{print $NF}')
TOKEN=$(curl -s -k -u wazuh-wui:$PASS -X POST https://localhost:55000/security/user/authenticate | jq -r '.data.token')

# Get recent alerts (copy this output to your AI)
curl -s -k -H "Authorization: Bearer $TOKEN" \
  "https://localhost:55000/alerts?limit=20&sort=-timestamp" | jq .
```

## Analysis Prompts to Try

Here are example prompts organized by use case. Copy these into your AI conversation (Claude, ChatGPT, or any assistant with Wazuh API access).

### Triage: What Happened?

Start broad, then dig in:

> **"What are the top alerts from the last hour? Group them by severity and category."**

This gives you the big picture. A good AI analyst will summarize the alert volume, highlight the critical ones, and identify patterns.

> **"Show me a timeline of events from the last 30 minutes. Are there any sequences that look like an attack chain?"**

The AI should connect the dots — for example, failed logins followed by a successful login followed by file modifications could indicate a compromise.

> **"Which agent has the most alerts? Is this normal or should I be concerned?"**

Since we only have one agent, this is simple now. In a larger lab, this question becomes very useful for identifying compromised hosts.

### Investigation: Dig Deeper

Once you've identified interesting alerts, drill down:

> **"Tell me about the brute force alerts. How many failed login attempts were there? From what source IP? Did any succeed?"**

> **"What file integrity changes were detected? Which files were modified and when? Are any of these changes concerning?"**

> **"Were there any privilege escalation attempts? Show me the sudo-related alerts."**

> **"I see network scan activity. What ports were scanned? What's the source and target?"**

### Assessment: Security Posture

Ask the AI to assess your overall security:

> **"Based on all the alerts and agent configuration, give me a security posture summary for this environment."**

> **"Are we meeting CIS benchmark requirements? What are the main gaps?"**

> **"What are the top 5 things I should fix to improve security in this environment?"**

> **"If this were a production system, what would you recommend as immediate remediation steps?"**

### Learning: Understand the Alerts

Use the AI as a tutor to understand what you're seeing:

> **"Explain Wazuh rule 5712 to me. What does it detect and why does it matter?"**

> **"What is file integrity monitoring and why is Wazuh watching /etc/passwd?"**

> **"What's the difference between a Wazuh alert level 5 and level 12?"**

> **"How would a real SOC analyst triage the alerts we're seeing?"**

### Advanced: Correlation and Hunting

If you want to push further:

> **"Look at the authentication failures and file integrity alerts together. Could these be part of the same attack? Build a hypothesis."**

> **"If an attacker had gained access through the SSH brute force, what artifacts should we look for to confirm compromise?"**

> **"Write a Wazuh custom rule that would detect the specific attack pattern we simulated."**

> **"What additional log sources would improve our detection capability?"**

## What Good AI Analysis Looks Like

A good AI security analyst should:

1. **Prioritize** — Not just list alerts, but tell you which matter most
2. **Correlate** — Connect related events across time and category
3. **Explain** — Make technical alerts understandable
4. **Recommend** — Suggest concrete next steps
5. **Contextualize** — Distinguish between lab noise and real-world significance

## Tips for Better Results

- **Be specific about time ranges** — "last hour" is better than "recent"
- **Ask follow-up questions** — Dig into anything that seems interesting
- **Challenge the AI** — Ask "Could this be a false positive?" or "What else could explain this?"
- **Request different formats** — "Show me this as a table" or "Summarize in 3 bullets"

## Example Conversation Flow

Here's a realistic analysis session:

1. "What happened in my Wazuh lab in the last hour?"
2. "Those brute force alerts — walk me through exactly what happened"
3. "Did the attacker get in? Check for any successful auth after the failures"
4. "What about the file integrity alerts — are they related?"
5. "Give me a 3-sentence incident summary I could put in a report"
6. "What detection rules should I add to catch this faster next time?"

## Next Step

When you're done exploring, go to [Step 5: Teardown](05-teardown.md) to clean up your lab and avoid unnecessary charges.
