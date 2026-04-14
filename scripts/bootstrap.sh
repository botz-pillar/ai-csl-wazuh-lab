#!/bin/bash
# CloudVault Wazuh Lab - One-command deploy + verify
#
# Deploys the lab, waits for Wazuh to finish installing, fetches passwords,
# and prints everything you need to start the course.
#
# Usage: ./scripts/bootstrap.sh

set -euo pipefail

# --- Colors ---
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[i]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
fail()    { echo -e "${RED}[✗]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$REPO_ROOT/terraform"

echo -e "${BOLD}"
cat << 'BANNER'
============================================
  CloudVault Wazuh Lab - Bootstrap
============================================
BANNER
echo -e "${NC}"

# --- Pre-flight checks ---
info "Pre-flight checks..."

if ! command -v terraform >/dev/null 2>&1; then
  fail "Terraform not installed. Install from https://terraform.io"
  exit 1
fi
success "Terraform installed ($(terraform version | head -1))"

if ! command -v aws >/dev/null 2>&1; then
  fail "AWS CLI not installed. Install with: brew install awscli (or equivalent)"
  exit 1
fi
success "AWS CLI installed"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  fail "AWS credentials not configured. Run: aws configure"
  exit 1
fi
success "AWS credentials configured (account: $(aws sts get-caller-identity --query Account --output text))"

if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
  fail "terraform.tfvars not found at $TF_DIR/terraform.tfvars"
  info "Copy the example and edit it:"
  info "  cp $TF_DIR/terraform.tfvars.example $TF_DIR/terraform.tfvars"
  exit 1
fi
success "terraform.tfvars configured"

# --- Terraform apply ---
echo ""
info "Running terraform init..."
cd "$TF_DIR"
terraform init -upgrade >/dev/null
success "Terraform initialized"

info "Running terraform apply (this takes ~1-2 minutes)..."
terraform apply -auto-approve
success "Infrastructure deployed"

# --- Gather outputs ---
echo ""
info "Gathering deployment details..."
MANAGER_IP=$(terraform output -raw manager_public_ip)
KEY_NAME=$(terraform output -json | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d["ssh_manager_command"]["value"].split(" ")[2].split("/")[-1].replace(".pem",""))' 2>/dev/null || echo "your-key")
success "Manager IP: $MANAGER_IP"

# --- Wait for Wazuh install to complete ---
echo ""
info "Waiting for Wazuh to finish installing on the manager..."
info "This takes 10-15 minutes. Grab coffee or re-read the CloudVault profile."
echo ""

ATTEMPT=0
MAX_ATTEMPTS=60  # 60 * 30s = 30 minutes max
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Definitive "install done" signal: the Wazuh installer writes
# /root/wazuh-install-files/wazuh-passwords.txt only AFTER every service is up.
# The API starts responding 4-5 minutes before that, so polling the API has a
# race. Poll the passwords file directly instead.
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if ssh -i ~/.ssh/$KEY_NAME.pem $SSH_OPTS ubuntu@$MANAGER_IP \
    'sudo test -f /root/wazuh-install-files/wazuh-passwords.txt' 2>/dev/null; then
    success "Wazuh install complete (attempt $ATTEMPT — passwords file present)"
    break
  fi
  printf "  [%02d/%02d] Waiting for Wazuh install to finish... \r" "$ATTEMPT" "$MAX_ATTEMPTS"
  sleep 30
done

echo ""
if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
  warn "Wazuh install did not complete after 30 minutes."
  warn "Check the install log:"
  warn "  ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$MANAGER_IP 'sudo tail -50 /var/log/wazuh-install.log'"
  exit 1
fi

# --- Verify API reachable ---
info "Verifying Wazuh API is reachable on :55000..."
for i in $(seq 1 10); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://$MANAGER_IP:55000/" || echo "000")
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
    success "API responding on :55000"
    break
  fi
  [ $i -eq 10 ] && warn "API not responding. Check security group :55000 rule."
  sleep 5
done

# --- Verify indexer reachable ---
info "Verifying Wazuh Indexer is up..."
for i in $(seq 1 20); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://$MANAGER_IP:9200/" || echo "000")
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
    success "Indexer responding on :9200"
    break
  fi
  if [ $i -eq 20 ]; then
    warn "Indexer not responding on :9200 after 100s."
    warn "If this persists, run ./scripts/doctor.sh to diagnose (often a network.host binding issue)."
  fi
  sleep 5
done

# --- Fetch credentials ---
echo ""
info "Retrieving Wazuh credentials..."
PASSWORDS=$(ssh -i ~/.ssh/$KEY_NAME.pem $SSH_OPTS \
  ubuntu@$MANAGER_IP 'sudo cat /root/wazuh-install-files/wazuh-passwords.txt 2>/dev/null' 2>/dev/null || echo "")

if [ -z "$PASSWORDS" ]; then
  warn "Could not fetch passwords — unexpected since install is complete. Try manually:"
  warn "  ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$MANAGER_IP 'sudo cat /root/wazuh-install-files/wazuh-passwords.txt'"
else
  # Save to local file for convenience
  echo "$PASSWORDS" > "$REPO_ROOT/.lab-credentials.txt"
  chmod 600 "$REPO_ROOT/.lab-credentials.txt"
  success "Credentials saved to $REPO_ROOT/.lab-credentials.txt (chmod 600)"
fi

# --- Wait for agents ---
echo ""
info "Waiting for all 3 agents to register with the manager..."
info "(Agents need ~5-10 more minutes after the manager is up.)"
info "This step is optional — you can Ctrl+C and check agent status later with doctor.sh."

# Parse passwords file. Actual format (Wazuh 4.9.x):
#   # Admin user for the web user interface and Wazuh indexer...
#     indexer_username: 'admin'
#     indexer_password: 'SECRET'
#
# We grep for the user line, read the line below, and extract the quoted value.
ADMIN_PASS=$(echo "$PASSWORDS" | grep -A1 "indexer_username: 'admin'"   | tail -1 | grep -oE "'[^']+'" | tr -d "'")
WUI_PASS=$(echo "$PASSWORDS"   | grep -A1 "api_username: 'wazuh-wui'"   | tail -1 | grep -oE "'[^']+'" | tr -d "'")

if [ -n "$ADMIN_PASS" ] && [ -n "$WUI_PASS" ]; then
  for i in $(seq 1 20); do
    ACTIVE_AGENTS=$(curl -sk --max-time 5 -u "wazuh-wui:$WUI_PASS" \
      "https://$MANAGER_IP:55000/agents?status=active&limit=10" 2>/dev/null | \
      python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("data",{}).get("total_affected_items",0))' 2>/dev/null || echo "0")
    if [ "$ACTIVE_AGENTS" -ge 4 ]; then
      success "All agents registered ($ACTIVE_AGENTS active including manager node 000)"
      break
    fi
    printf "  [%02d/20] Active agents so far: %s (expecting 4: manager + web + app + dev)\r" "$i" "$ACTIVE_AGENTS"
    sleep 30
  done
  echo ""
fi

# --- Print summary ---
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'SUMMARY'
============================================
  Lab Ready
============================================
SUMMARY
echo -e "${NC}"

echo -e "${BOLD}Dashboard:${NC} https://$MANAGER_IP"
echo -e "${BOLD}SSH:${NC}       ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$MANAGER_IP"
echo -e "${BOLD}Credentials:${NC} $REPO_ROOT/.lab-credentials.txt"
echo ""
echo -e "${BOLD}Next:${NC}"
echo "  1. Log in to the dashboard (admin + password from .lab-credentials.txt)"
echo "  2. Run ./scripts/doctor.sh any time to check lab health"
echo "  3. Continue to Course 3 Lesson 1"
echo ""
echo -e "${YELLOW}When done:${NC} terraform destroy   ← don't forget, ~\$0.11/hr running"
echo ""
