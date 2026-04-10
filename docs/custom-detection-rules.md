# Writing Custom Wazuh Detection Rules

This guide walks through creating a custom detection rule and testing it with `wazuh-logtest`.

## How Wazuh Rules Work

Wazuh rules are XML files that match patterns in log data. When a log line matches a rule, an alert fires with the rule's severity level, description, and MITRE ATT&CK mapping.

Rules live in: `/var/ossec/etc/rules/`
- `local_rules.xml` — your custom rules (this is where you write new ones)
- Other files are built-in rules (don't modify these)

## Example: Detect Suspicious AssumeRole Activity

This rule detects when a non-admin user assumes an admin IAM role — the exact attack pattern from the CloudVault contractor incident.

### Step 1 — Write the rule

SSH into the Wazuh manager and edit the local rules file:

```bash
sudo nano /var/ossec/etc/rules/local_rules.xml
```

Add this rule:

```xml
<group name="cloudvault,aws,privilege_escalation">

  <!-- Detect AssumeRole to admin roles by non-admin users -->
  <rule id="100001" level="12">
    <if_sid>80861</if_sid>
    <field name="aws.eventName">AssumeRole</field>
    <field name="aws.requestParameters.roleArn">AdminRole|admin-role|AdministratorAccess</field>
    <description>AWS IAM: User assumed an administrative role. Possible privilege escalation.</description>
    <mitre>
      <id>T1078.004</id>
    </mitre>
    <group>aws,privilege_escalation,</group>
  </rule>

  <!-- Detect rapid S3 downloads from sensitive buckets -->
  <rule id="100002" level="10" frequency="5" timeframe="60">
    <if_matched_sid>80862</if_matched_sid>
    <field name="aws.eventName">GetObject</field>
    <field name="aws.requestParameters.bucketName">client-docs|financial|confidential</field>
    <description>AWS S3: Multiple downloads from sensitive bucket in short timeframe. Possible data exfiltration.</description>
    <mitre>
      <id>T1530</id>
    </mitre>
    <group>aws,data_exfiltration,</group>
  </rule>

  <!-- Detect attempts to stop CloudTrail logging -->
  <rule id="100003" level="15">
    <if_sid>80861</if_sid>
    <field name="aws.eventName">StopLogging|DeleteTrail</field>
    <description>AWS CloudTrail: Attempt to disable or delete audit logging. Anti-forensics activity.</description>
    <mitre>
      <id>T1562.008</id>
    </mitre>
    <group>aws,defense_evasion,</group>
  </rule>

</group>
```

### Step 2 — Test with wazuh-logtest

Before restarting Wazuh, test your rule against a sample log:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Paste a sample CloudTrail AssumeRole event:

```json
{"eventVersion":"1.08","userIdentity":{"type":"IAMUser","userName":"dev-contractor-01"},"eventTime":"2026-04-03T19:48:33Z","eventSource":"sts.amazonaws.com","eventName":"AssumeRole","requestParameters":{"roleArn":"arn:aws:iam::471923845612:role/CloudVaultAdminRole","roleSessionName":"dev-contractor-01-session"}}
```

You should see output showing which decoder matched and which rule fired. If your rule matches, you'll see:

```
**Rule id: '100001'**
**Level: '12'**
**Description: 'AWS IAM: User assumed an administrative role. Possible privilege escalation.'**
```

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

Run the CloudVault contractor log injection script again. Your new rules should fire on the AssumeRole, the rapid S3 downloads, and the CloudTrail deletion attempts.

Check via MCP:

```
Show me all alerts from rules 100001, 100002, and 100003 in the last 10 minutes.
```

## Rule Writing Tips

- **Rule IDs 100000-120000** are reserved for custom rules. Use this range.
- **Level 0-3:** Informational. Level **4-7:** Low. Level **8-11:** Medium. Level **12-14:** High. Level **15:** Critical.
- **`<if_sid>`** chains rules — your rule fires only if the parent rule already matched.
- **`<field name="...">`** matches decoded fields. Use `wazuh-logtest` to see which fields are available.
- **`frequency` + `timeframe`** creates rate-based rules (e.g., "5 events in 60 seconds").
- **MITRE ATT&CK IDs** make your rules map to the framework automatically in the dashboard.

## Using AI to Write Rules

Ask Claude Code to generate rule XML:

```
Write a Wazuh detection rule (XML format) that alerts when:
- An IAM user creates a new access key for the root account
- Set it to level 15 (critical)
- Map it to MITRE T1098 (Account Manipulation)
- Use rule ID 100004
- Chain it from parent rule 80861 (AWS CloudTrail base rule)
```

Claude will generate the XML. Review it, test with `wazuh-logtest`, then deploy.
