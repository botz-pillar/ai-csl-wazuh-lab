#!/bin/bash
# CloudVault Wazuh Lab - Resume a stopped lab, refresh JWT + IP
#
# Starts instances, waits for Wazuh + MCP to come back, and automatically:
#   - Detects if your public IP changed (SG refresh via terraform apply, if you confirm)
#   - Exchanges the API key for a fresh JWT and rewrites .mcp.json
#
# Eliminates the #1 day-2 mystery failure: "MCP disconnected and I don't know why"

set -uo pipefail

# --- Colors ---
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[i]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$REPO_ROOT/terraform"

echo ""
info "Starting AI-CSL Wazuh Lab instances..."

# --- 1. Start stopped instances ---
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_IDS" ]; then
  # Check if any are already running
  RUNNING=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
  if [ -n "$RUNNING" ]; then
    info "Lab instances are already running. Continuing to IP + JWT refresh..."
  else
    warn "No lab instances found — has the lab been deployed? Run ./scripts/bootstrap.sh first."
    exit 1
  fi
else
  aws ec2 start-instances --instance-ids $INSTANCE_IDS >/dev/null
  info "Starting: $INSTANCE_IDS"
  info "Waiting for instances to reach 'running' state..."
  aws ec2 wait instance-running --instance-ids $INSTANCE_IDS
  success "Instances running."
fi

# --- 2. Pull manager IP from Terraform outputs ---
if [ ! -d "$TF_DIR" ] || [ ! -f "$TF_DIR/terraform.tfstate" ]; then
  warn "No Terraform state found. Can't refresh .mcp.json without the manager IP."
  exit 0
fi

MANAGER_IP=$(cd "$TF_DIR" && terraform output -raw manager_public_ip 2>/dev/null || echo "")
if [ -z "$MANAGER_IP" ]; then
  warn "Couldn't read manager_public_ip from Terraform outputs."
  exit 0
fi
success "Manager IP: $MANAGER_IP"

KEY_NAME=$(cd "$TF_DIR" && terraform output -raw key_name 2>/dev/null || echo "ai-csl-wazuh-lab")

# --- 3. Check if your public IP changed since the last deploy ---
CURRENT_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
TFVARS_IP=""
if [ -f "$TF_DIR/terraform.tfvars" ]; then
  TFVARS_IP=$(grep -E "^\s*your_ip_cidr" "$TF_DIR/terraform.tfvars" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | sed 's|/32||' || echo "")
fi

if [ -n "$CURRENT_IP" ] && [ -n "$TFVARS_IP" ] && [ "$CURRENT_IP" != "$TFVARS_IP" ]; then
  warn "Your public IP has changed since deploy:"
  warn "  tfvars says: $TFVARS_IP"
  warn "  you are at:  $CURRENT_IP"
  warn "This means the security group is blocking you. Fix:"
  warn "  1. Edit $TF_DIR/terraform.tfvars and set your_ip_cidr = \"$CURRENT_IP/32\""
  warn "  2. Run: cd terraform && terraform apply"
  warn "  3. Re-run this script."
  exit 1
elif [ -n "$CURRENT_IP" ] && [ -n "$TFVARS_IP" ]; then
  success "Public IP matches tfvars — SG should allow you through."
fi

# --- 4. Wait for MCP /health to come back ---
info "Waiting for MCP server to return /health 200 (up to 3 minutes)..."
for i in $(seq 1 36); do
  MCP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://$MANAGER_IP:3000/health" 2>/dev/null || echo "000")
  if [ "$MCP_CODE" = "200" ]; then
    success "MCP /health OK."
    break
  fi
  sleep 5
done

if [ "${MCP_CODE:-000}" != "200" ]; then
  warn "MCP didn't return /health 200 after 3 min. Dashboard may still be fine."
  warn "Try ./scripts/doctor.sh for a deeper diagnosis."
  exit 0
fi

# --- 5. Fetch fresh JWT by re-exchanging the API key ---
info "Refreshing MCP JWT (the previous one may have expired after 24h)..."

API_KEY=$(ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  ubuntu@$MANAGER_IP 'sudo cat /root/wazuh-mcp-api-key.txt 2>/dev/null' 2>/dev/null || echo "")

if [ -z "$API_KEY" ]; then
  warn "Could not fetch MCP API key from manager. Skipping JWT refresh."
  warn "Manual workaround: re-run ./scripts/bootstrap.sh"
  exit 0
fi

JWT=$(curl -s --max-time 10 -X POST "http://$MANAGER_IP:3000/auth/token" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\":\"$API_KEY\"}" 2>/dev/null | \
  python3 -c 'import sys, json
try:
    d=json.load(sys.stdin)
    print(d.get("access_token") or d.get("token") or "")
except Exception:
    print("")' 2>/dev/null || echo "")

if [ -z "$JWT" ]; then
  warn "Could not exchange API key for JWT. MCP server may be initializing."
  warn "Wait 1-2 minutes and re-run this script, or re-run ./scripts/bootstrap.sh"
  exit 0
fi

cat > "$REPO_ROOT/.mcp.json" <<EOF
{
  "mcpServers": {
    "wazuh": {
      "type": "http",
      "url": "http://$MANAGER_IP:3000/mcp",
      "headers": {
        "Authorization": "Bearer $JWT"
      }
    }
  }
}
EOF
chmod 600 "$REPO_ROOT/.mcp.json"
success "Fresh JWT written to .mcp.json"

echo ""
echo -e "${BOLD}${GREEN}Lab is back up and MCP is re-wired.${NC}"
echo ""
echo -e "  Dashboard:   https://$MANAGER_IP"
echo -e "  MCP:         http://$MANAGER_IP:3000  (JWT refreshed)"
echo ""
echo -e "  ${BOLD}Important:${NC} restart Claude Code so it picks up the fresh .mcp.json"
echo -e "    1. /exit in Claude Code"
echo -e "    2. claude  (from this directory)"
echo -e "    3. /mcp to confirm wazuh shows connected"
echo ""
echo -e "  Full health check: ${BOLD}./scripts/doctor.sh${NC}"
echo ""
