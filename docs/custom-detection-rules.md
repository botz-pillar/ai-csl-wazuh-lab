# Writing Custom Wazuh Detection Rules

This guide walks through creating custom detection rules and testing them with `wazuh-logtest`.

## How Wazuh Rules Work

Wazuh rules are XML files that match patterns in log data. When a log line matches a rule, an alert fires with the rule's severity level, description, and MITRE ATT&CK mapping.

Rules live in: `/var/ossec/etc/rules/`
- `local_rules.xml` — your custom rules (this is where you write new ones)
- Other files are built-in rules (don't modify these)

## Example 1: Detect Rapid File Access in CloudVault Client Data

This is the rule Lesson 5 builds. It detects when 3 or more file modifications happen inside `/opt/cloudvault/client-data/` within 60 seconds — a pattern that indicates rapid unauthorized data access, not routine admin work. This is a CloudVault-specific rule; Wazuh's built-in 5720 (generic multi-event) isn't tight enough for a financial firm's client records.

### Step 1 — Write the rule

SSH into the Wazuh manager and edit the local rules file:

```bash
sudo nano /var/ossec/etc/rules/local_rules.xml
```

Add these rules:

```xml
<group name="cloudvault,custom_detection">

  <!-- [100001] Rapid FIM changes on CloudVault client data -->
  <!-- Chains from 550 (FIM checksum changed). Fires when 3+ FIM events match -->
  <!-- the client-data path within a 60-second window. -->
  <rule id="100001" level="12" frequency="3" timeframe="60">
    <if_matched_sid>550</if_matched_sid>
    <field name="file">^/opt/cloudvault/client-data</field>
    <description>CloudVault: 3+ rapid file modifications in client-data — possible unauthorized data access.</description>
    <mitre>
      <id>T1565.001</id>
    </mitre>
    <group>data_integrity,fim,cloudvault,</group>
  </rule>

  <!-- [100002] Hidden file created in a suspicious location -->
  <rule id="100002" level="8">
    <if_sid>554</if_sid>
    <field name="file">^\.</field>
    <description>CloudVault: Hidden file created. Possible attacker staging or persistence.</description>
    <mitre>
      <id>T1564.001</id>
    </mitre>
    <group>defense_evasion,persistence,</group>
  </rule>

  <!-- [100003] Example SSH brute force rule — note: this is effectively a
       duplicate of built-in rule 5720 and is included here as a reference
       ONLY. For your own second rule, pick something CloudVault-specific that
       isn't already covered by a built-in rule. -->
  <rule id="100003" level="12" frequency="10" timeframe="60">
    <if_matched_sid>5710</if_matched_sid>
    <description>Reference: 10+ failed SSH logins in 60 seconds (duplicates 5720).</description>
    <mitre>
      <id>T1110.001</id>
    </mitre>
    <group>authentication_failures,brute_force,</group>
  </rule>

</group>
```

### Step 2 — Test with wazuh-logtest

Before restarting Wazuh, test your rule against a real FIM alert from your environment. Grab one from the dashboard (Security Events → filter on rule 550 → pick an event on `/opt/cloudvault/client-data/` → "View alert details" → copy the raw JSON).

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Paste the JSON log. You should see:
- Rule 550 (FIM checksum changed) matching as the parent
- Rule 100001 firing once the frequency threshold is reached (run it 3 times within 60 seconds to see the composite rule fire)

If rule 100001 doesn't fire, check: (a) the `<field name="file">` regex — Wazuh uses OSSEC regex, not PCRE; (b) that your FIM alert actually includes `syscheck.path` starting with `/opt/cloudvault/client-data`; (c) that 3 events fit inside the 60-second window.

### Step 3 — Deploy the rule

Restart the Wazuh manager to load the new rules:

```bash
sudo systemctl restart wazuh-manager
```

Verify the rules are loaded:

```bash
sudo /var/ossec/bin/wazuh-control info | grep rules
```

Or through the MCP server:

```
Show me a summary of all loaded Wazuh rules. Are rules 100001, 100002, and 100003 active?
```

### Step 4 — Test with the simulation

Run the event generation script again on dev-server-01. Your new rules should fire on the FIM violations in /opt/cloudvault/client-data/ (rule 100001), the hidden file creation (rule 100002), and — if you kept the reference rule — the SSH brute force (rule 100003).

Check via MCP:

```
Show me all alerts from rules 100001, 100002, and 100003 in the last 10 minutes.
```

## Rule Writing Tips

- **Rule IDs 100000-120000** are reserved for custom rules. Use this range.
- **Level 0-3:** Informational. Level **4-7:** Low. Level **8-11:** Medium. Level **12-14:** High. Level **15:** Critical.
- **`<if_sid>`** chains rules — your rule fires only if the parent rule already matched.
- **`<if_matched_sid>`** with `frequency` and `timeframe` creates rate-based rules.
- **`<field name="...">`** matches decoded fields. Use `wazuh-logtest` to see which fields are available.
- **MITRE ATT&CK IDs** make your rules map to the framework automatically in the dashboard.

## Using AI to Write Rules

Ask Claude Code to generate rule XML:

```
Write a Wazuh detection rule (XML format) that alerts when:
- 5 or more failed sudo attempts happen within 120 seconds
- Set it to level 10 (medium-high)
- Map it to MITRE T1548 (Abuse Elevation Control Mechanism)
- Use rule ID 100004
- Chain it from parent rule 5401 (sudo failed attempt)
```

Claude will generate the XML. Review it, test with `wazuh-logtest`, then deploy.

## Common Parent Rule IDs for Chaining

| Parent Rule | What It Detects | Use For |
|------------|----------------|---------|
| 5710 | SSH failed login (invalid user) | Brute force detection |
| 5712 | SSH failed login (valid user, wrong password) | Credential stuffing |
| 5401 | sudo: failed attempt | Privilege escalation |
| 5501 | Login session opened | Session monitoring |
| 550 | File integrity: file modified | Data integrity monitoring |
| 554 | File integrity: file added | Persistence detection |
