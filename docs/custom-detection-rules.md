# Writing Custom Wazuh Detection Rules

This guide walks through creating custom detection rules and testing them with `wazuh-logtest`.

## How Wazuh Rules Work

Wazuh rules are XML files that match patterns in log data. When a log line matches a rule, an alert fires with the rule's severity level, description, and MITRE ATT&CK mapping.

Rules live in: `/var/ossec/etc/rules/`
- `local_rules.xml` — your custom rules (this is where you write new ones)
- Other files are built-in rules (don't modify these)

## Example 1: Detect Rapid SSH Brute Force

This rule detects when multiple SSH login failures happen from a single source in a short time window — the exact pattern the lab's brute force simulation generates.

### Step 1 — Write the rule

SSH into the Wazuh manager and edit the local rules file:

```bash
sudo nano /var/ossec/etc/rules/local_rules.xml
```

Add these rules:

```xml
<group name="cloudvault,custom_detection">

  <!-- Detect rapid SSH brute force: 10+ failures in 60 seconds -->
  <rule id="100001" level="12" frequency="10" timeframe="60">
    <if_matched_sid>5710</if_matched_sid>
    <description>CloudVault: SSH brute force detected — 10+ failed logins in 60 seconds.</description>
    <mitre>
      <id>T1110.001</id>
    </mitre>
    <group>authentication_failures,brute_force,</group>
  </rule>

  <!-- Detect file modifications in CloudVault client data directories -->
  <rule id="100002" level="10">
    <if_sid>550</if_sid>
    <field name="file">/opt/cloudvault/client-data</field>
    <description>CloudVault: File modified in client data directory. Possible unauthorized data access.</description>
    <mitre>
      <id>T1565.001</id>
    </mitre>
    <group>data_integrity,fim,</group>
  </rule>

  <!-- Detect creation of hidden files in suspicious locations -->
  <rule id="100003" level="8">
    <if_sid>554</if_sid>
    <field name="file">^\.</field>
    <description>CloudVault: Hidden file created. Possible attacker staging or persistence.</description>
    <mitre>
      <id>T1564.001</id>
    </mitre>
    <group>defense_evasion,persistence,</group>
  </rule>

</group>
```

### Step 2 — Test with wazuh-logtest

Before restarting Wazuh, test your rule against a sample log:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Paste a sample SSH failure log line:

```
Apr 10 14:30:22 dev-server-01 sshd[12345]: Failed password for invalid user fakeuser1 from 10.0.1.50 port 54321 ssh2
```

You should see output showing which decoder matched and which rule fired. The base rule 5710 (sshd: Attempt to login using a non-existent user) should match. Your frequency-based rule 100001 fires after 10+ matching events within 60 seconds during the brute force simulation.

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

Run the event generation script again on dev-server-01. Your new rules should fire on the brute force attempts, the FIM violations in /opt/cloudvault/client-data/, and the hidden file creation.

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
