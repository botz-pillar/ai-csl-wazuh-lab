# Step 2: Verify Wazuh Is Running

Now that the lab is deployed, let's confirm that all Wazuh components are healthy and the agent is connected.

## Check the Dashboard

1. Open the dashboard URL from Terraform output:
   ```bash
   terraform output wazuh_dashboard_url
   ```

2. Your browser will warn about a self-signed certificate — this is expected. Click through the warning (Advanced > Proceed).

3. Log in with:
   - **Username:** `admin`
   - **Password:** the password from Step 1

4. You should see the Wazuh dashboard. It may take a minute to populate data.

## Verify Services on the Manager

SSH into the manager:

```bash
ssh -i ~/.ssh/wazuh-lab.pem ubuntu@$(terraform output -raw manager_public_ip)
```

Check that all three Wazuh components are running:

```bash
# Wazuh Manager
sudo systemctl status wazuh-manager

# Wazuh Indexer
sudo systemctl status wazuh-indexer

# Wazuh Dashboard
sudo systemctl status wazuh-dashboard
```

All three should show `active (running)`.

## Verify Agent Registration

On the manager, check that the agent has enrolled:

```bash
sudo /var/ossec/bin/agent_control -l
```

You should see one agent listed with status `Active`. If the agent shows `Disconnected` or doesn't appear, wait a few more minutes — the agent installation might still be in progress.

You can also check from the Wazuh API:

```bash
# Get an auth token
TOKEN=$(sudo cat /root/wazuh-install-files/wazuh-passwords.txt | grep "wazuh-wui" | awk '{print $NF}')

curl -s -k -u wazuh-wui:$TOKEN \
  -X POST https://localhost:55000/security/user/authenticate \
  | jq -r '.data.token' > /tmp/api_token

# List agents
curl -s -k -H "Authorization: Bearer $(cat /tmp/api_token)" \
  "https://localhost:55000/agents?select=id,name,status,os.name" | jq .
```

## Verify the Agent

SSH into the agent (through the manager as a jump host):

```bash
# From your local machine
ssh -i ~/.ssh/wazuh-lab.pem -J ubuntu@$(terraform output -raw manager_public_ip) ubuntu@$(terraform output -raw agent_private_ip)
```

Check the agent service:

```bash
sudo systemctl status wazuh-agent
```

Check the agent can reach the manager:

```bash
sudo cat /var/ossec/logs/ossec.log | tail -20
```

Look for messages like `Connected to the server` or `Agent is now connected`.

## What You Should See in the Dashboard

After a few minutes, navigate around the dashboard:

- **Agents** — Your agent should appear with a green status dot
- **Security Events** — You'll see initial events from the agent starting up
- **Integrity Monitoring** — File integrity monitoring is active by default on key directories

If everything checks out, your SIEM is live. Time to make some noise.

## Troubleshooting

If something isn't right, check [Troubleshooting](../docs/troubleshooting.md) before moving on.

## Next Step

Go to [Step 3: Generate Noise](03-generate-noise.md) to simulate security events.
