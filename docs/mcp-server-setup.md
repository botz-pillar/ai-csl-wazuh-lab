# MCP Server — reference

The Wazuh MCP server is **pre-installed** on the manager by `terraform/user_data/wazuh_manager.sh` and auto-wired into Claude Code by `scripts/bootstrap.sh`. You don't set it up by hand. This doc exists to explain what was installed, how to troubleshoot it, and how to reproduce the install yourself if you want to run MCP against your own Wazuh deployment (production or homelab).

**Upstream:** [gensecaihq/Wazuh-MCP-Server](https://github.com/gensecaihq/Wazuh-MCP-Server) — containerized HTTP MCP, bearer auth, supports Wazuh 4.8–4.14.

---

## What bootstrap.sh did for you

Four things beyond the Wazuh install:

1. **Installed Docker + Compose v2** on the manager (the distro's `docker.io` package doesn't include Compose v2; cloud-init adds Docker's official apt repo).
2. **Cloned the MCP server repo** to `/opt/wazuh-mcp` on the manager and generated `/opt/wazuh-mcp/.env` with:
   - Wazuh API credentials for the `wazuh-wui` user (pulled from `/root/wazuh-install-files.tar`)
   - Wazuh indexer admin credentials (same source)
   - A generated `AUTH_SECRET_KEY` (32-byte hex, used to sign JWTs)
   - A generated `MCP_API_KEY` (the `wazuh_...` prefix one — client presents this to `/auth/token` to get a JWT)
   - `MCP_HOST=0.0.0.0` so the container binds all interfaces (not just localhost)
3. **Ran `docker compose up -d`** and waited for `GET /health` to respond 200.
4. **Persisted `MCP_API_KEY` to `/root/wazuh-mcp-api-key.txt`** on the manager so bootstrap.sh can retrieve it.

Then bootstrap.sh from your laptop:

5. SSH'd to the manager and pulled `/root/wazuh-mcp-api-key.txt` via `sudo cat`
6. POSTed that API key to `http://<manager-IP>:3000/auth/token` → got back a JWT
7. Wrote `.mcp.json` in the repo root pointing Claude Code at `http://<manager-IP>:3000/mcp` with the JWT as a bearer header

When you launch `claude` in this directory, Claude Code reads `.mcp.json` at startup and auto-mounts the `wazuh` MCP server.

---

## The two-step auth flow

Authentication is TWO steps. This trips up everyone the first time:

1. **API key** (`wazuh_...`) → goes in the server's `/opt/wazuh-mcp/.env` file
2. **JWT** → goes in Claude Code's `.mcp.json`

The API key is NOT a valid bearer token. If you put it directly in `.mcp.json` as the bearer value, you get `{"detail":"Invalid or expired token"}`. **Exchange the API key for a JWT first** by POSTing to `/auth/token`. Bootstrap does this for you; if you set this up by hand, you have to do it yourself.

**Why the two-step?** Separates long-lived credentials (API key, lives in the server env) from short-lived ones (JWT, 24h default, carried by the client). If the JWT leaks, it's expired within a day. If the API key leaks, you rotate it in `.env` + restart.

---

## File reference

| Location | What it is |
|---|---|
| `/opt/wazuh-mcp/` | Cloned MCP repo on the manager |
| `/opt/wazuh-mcp/.env` | MCP config — Wazuh creds + MCP_API_KEY + AUTH_SECRET_KEY. `chmod 600`. |
| `/opt/wazuh-mcp/compose.yml` | Docker Compose manifest |
| `/root/wazuh-mcp-api-key.txt` | API key, persisted for bootstrap.sh retrieval. `chmod 600`. |
| `.mcp.json` (repo root, local) | Claude Code MCP config. Contains JWT. `chmod 600`, gitignored. |

---

## Troubleshooting

### `/mcp` in Claude Code says `wazuh` is not connected

**Most common cause:** your Claude Code session started before bootstrap finished. It loads `.mcp.json` at launch, so a session started too early won't see it.

**Fix:** `/exit` Claude Code, then re-launch `claude` in the repo directory.

### `/mcp` shows `wazuh` but status is "error"

Check the JWT is still valid (24h default lifetime):
```bash
cat .mcp.json | jq -r '.mcpServers.wazuh.headers.Authorization'
```
If the token is stale, re-run `./scripts/bootstrap.sh` — it'll write a fresh `.mcp.json`.

### `/health` doesn't respond

```bash
MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
curl -v http://$MANAGER_IP:3000/health
```

If you get connection refused: security group isn't open on :3000 from your IP. Check `tfvars your_ip_cidr` matches `curl ifconfig.me`, then `terraform apply` to update the SG.

If you get a timeout: container is down. SSH in and check:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'sudo docker ps -a | grep wazuh-mcp'
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'cd /opt/wazuh-mcp && sudo docker compose logs --tail 50'
```

### MCP responds but all queries return 401/403

The server can reach itself but can't reach Wazuh. Most likely: `WAZUH_VERIFY_SSL=false` missing, or `WAZUH_PASS` wrong. SSH in and check:
```bash
ssh -i ~/.ssh/ai-csl-wazuh-lab.pem ubuntu@$MANAGER_IP 'sudo cat /opt/wazuh-mcp/.env'
```
Compare `WAZUH_PASS` against `/root/wazuh-install-files/wazuh-passwords.txt`'s `wazuh-wui` password.

---

## Manual setup — if you want to replicate against your own Wazuh

For students who want to understand the install or replicate against a non-lab Wazuh:

### Prerequisites
- Ubuntu 22.04+ host that can reach your Wazuh manager on :55000 and indexer on :9200
- Docker CE + Compose v2 plugin
- Wazuh API credentials (typically the `wazuh-wui` user from `wazuh-install-files.tar`)

### Steps

```bash
# 1. Docker + Compose v2
apt-get update
apt-get install -y ca-certificates curl gnupg git openssl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-compose-plugin
systemctl enable --now docker

# 2. Clone
git clone --depth 1 https://github.com/gensecaihq/Wazuh-MCP-Server.git /opt/wazuh-mcp
cd /opt/wazuh-mcp

# 3. Generate secrets
AUTH_SECRET_KEY=$(openssl rand -hex 32)
MCP_API_KEY="wazuh_$(openssl rand -hex 24)"

# 4. Write .env (fill in your Wazuh creds)
cat > .env <<EOF
WAZUH_HOST=https://<your-wazuh-manager>
WAZUH_PORT=55000
WAZUH_USER=wazuh-wui
WAZUH_PASS=<your-wazuh-wui-password>
WAZUH_VERIFY_SSL=false
WAZUH_ALLOW_SELF_SIGNED=true
WAZUH_INDEXER_HOST=https://<your-wazuh-manager>
WAZUH_INDEXER_PORT=9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASS=<your-indexer-admin-password>
MCP_HOST=0.0.0.0
MCP_PORT=3000
AUTH_MODE=bearer
AUTH_SECRET_KEY=$AUTH_SECRET_KEY
MCP_API_KEY=$MCP_API_KEY
TOKEN_LIFETIME_HOURS=24
ALLOWED_ORIGINS=https://claude.ai,https://*.anthropic.com,http://localhost:*
EOF
chmod 600 .env

# 5. Bring it up
docker compose up -d

# 6. Wait for health
for i in $(seq 1 30); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/health)" = "200" ]; then
    echo "MCP healthy"; break
  fi
  sleep 5
done

# 7. Exchange API key for JWT
JWT=$(curl -s -X POST http://127.0.0.1:3000/auth/token \
  -H "Content-Type: application/json" \
  -d "{\"api_key\":\"$MCP_API_KEY\"}" | jq -r '.access_token // .token')

# 8. Write .mcp.json wherever you want Claude Code to find it
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "wazuh": {
      "type": "http",
      "url": "http://<your-mcp-host>:3000/mcp",
      "headers": {
        "Authorization": "Bearer $JWT"
      }
    }
  }
}
EOF
chmod 600 .mcp.json
```

### Production hardening (differences from our lab)

Things this lab does for convenience that you would NOT do in production:

- **HTTP on :3000 exposed to your IP** — in prod, put this behind a reverse proxy with TLS, or expose it only via a VPN/bastion
- **`WAZUH_VERIFY_SSL=false`** — replace the manager's self-signed cert with a real one from your internal CA and set `WAZUH_VERIFY_SSL=true`
- **Clones from upstream `main`** — pin to a tagged release + commit hash, sign your container image
- **24h JWT lifetime** — in prod, drop to 1-2h and script a refresh
- **Full-access Wazuh API credentials** — create a scoped API user with only the permissions the MCP tools actually need (read + active-response, NOT user management or config writes)
- **No audit logging** — add request logging on the MCP side so you can trace every tool call

These trade-offs are discussed in SKILL.md §9 (Lesson 3) — the security teaching is the point of the lesson, not an afterthought.

---

## Why this is pre-installed

An earlier version of this lab had students install the MCP server themselves in Lesson 3. Lessons learned: the install is ~45 minutes of Docker + CORS + auth-flow configuration that is NOT the educational point. Students got frustrated, burned their time budget on ops work, and never got to the pedagogy (threat-modeling, prompt injection, natural-language investigation).

Moving the install to bootstrap gives students the payoff with zero ops drudgery. The security teaching — the thing that actually matters — stays front and center in Lesson 3 where it belongs.
