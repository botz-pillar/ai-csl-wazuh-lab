#!/bin/bash
# CloudVault Wazuh Lab - Health check / diagnostic
#
# Runs a series of checks to identify why the lab isn't working.
# Exit 0 = healthy, exit 1 = one or more checks failed.

set -uo pipefail

# --- Colors ---
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

pass()    { echo -e "  ${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail()    { echo -e "  ${RED}✗${NC} $*"; FAILS=$((FAILS + 1)); }
warn()    { echo -e "  ${YELLOW}!${NC} $*"; WARNS=$((WARNS + 1)); }
info()    { echo -e "  ${BLUE}i${NC} $*"; }
section() { echo -e "\n${BOLD}$*${NC}"; }

PASS=0
FAILS=0
WARNS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$REPO_ROOT/terraform"

echo -e "${BOLD}"
cat << 'BANNER'
============================================
  CloudVault Wazuh Lab - Doctor
============================================
BANNER
echo -e "${NC}"

# --- 1. Prerequisites ---
section "Prerequisites"

if command -v terraform >/dev/null 2>&1; then
  pass "terraform installed ($(terraform version | head -1 | awk '{print $2}'))"
else
  fail "terraform not installed"
fi

if command -v aws >/dev/null 2>&1; then
  pass "aws CLI installed"
else
  fail "aws CLI not installed"
fi

if command -v curl >/dev/null 2>&1; then
  pass "curl installed"
else
  fail "curl not installed"
fi

# --- 2. AWS credentials ---
section "AWS credentials"
if aws sts get-caller-identity >/dev/null 2>&1; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  pass "AWS credentials valid (account: $ACCOUNT)"
else
  fail "AWS credentials not configured — run: aws configure"
fi

# --- 3. Terraform state ---
section "Terraform state"
if [ ! -d "$TF_DIR" ]; then
  fail "Terraform directory not found: $TF_DIR"
  echo ""
  echo "Summary: $PASS passed, $FAILS failed, $WARNS warnings"
  exit 1
fi

cd "$TF_DIR"
if [ ! -f "terraform.tfstate" ]; then
  warn "No terraform.tfstate — lab not deployed yet? Run: ./scripts/bootstrap.sh"
  echo ""
  echo "Summary: $PASS passed, $FAILS failed, $WARNS warnings"
  exit 1
fi
pass "Terraform state found"

# --- 4. Get manager IP ---
MANAGER_IP=$(terraform output -raw manager_public_ip 2>/dev/null || echo "")
if [ -z "$MANAGER_IP" ]; then
  fail "Could not read manager_public_ip from Terraform outputs"
  echo ""
  echo "Summary: $PASS passed, $FAILS failed, $WARNS warnings"
  exit 1
fi
pass "Manager IP: $MANAGER_IP"

# --- 5. EC2 instance status ---
section "EC2 instances"
INSTANCES_JSON=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ai-csl-wazuh-lab" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[*].Instances[*].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,InstanceId:InstanceId}' \
  --output json 2>/dev/null || echo "[]")

INSTANCE_COUNT=$(echo "$INSTANCES_JSON" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(sum(len(r) for r in d))' 2>/dev/null || echo 0)

if [ "$INSTANCE_COUNT" -eq 0 ]; then
  fail "No lab instances found in AWS"
elif [ "$INSTANCE_COUNT" -lt 4 ]; then
  warn "Found $INSTANCE_COUNT instances (expected 4: manager + 3 agents)"
else
  pass "Found $INSTANCE_COUNT instances"
fi

# Detail each instance
echo "$INSTANCES_JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for r in d:
  for i in r:
    state = i.get("State", "?")
    name = i.get("Name", "?")
    state_icon = "✓" if state == "running" else "!"
    print(f"    {state_icon} {name}: {state}")
' 2>/dev/null || true

# --- 6. Manager API reachability ---
section "Manager API (:55000)"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://$MANAGER_IP:55000/" || echo "000")
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
  pass "API responding (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "000" ]; then
  fail "API not responding — check security group or wait for install to finish"
else
  warn "API returned HTTP $HTTP_CODE (expected 401 when auth-required)"
fi

# --- 7. Indexer reachability ---
section "Wazuh Indexer (:9200)"
INDEXER_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://$MANAGER_IP:9200/" || echo "000")
if [ "$INDEXER_CODE" = "401" ] || [ "$INDEXER_CODE" = "200" ]; then
  pass "Indexer responding (HTTP $INDEXER_CODE)"
elif [ "$INDEXER_CODE" = "000" ]; then
  fail "Indexer not responding — common cause: OOM kill on smaller instances"
  info "  SSH to manager and run: sudo systemctl status wazuh-indexer"
  info "  Check memory: sudo dmesg | grep -i 'killed process'"
else
  warn "Indexer returned HTTP $INDEXER_CODE"
fi

# --- 8. Dashboard reachability ---
section "Wazuh Dashboard (:443)"
DASH_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://$MANAGER_IP/" || echo "000")
if [ "$DASH_CODE" = "200" ] || [ "$DASH_CODE" = "302" ] || [ "$DASH_CODE" = "401" ]; then
  pass "Dashboard responding (HTTP $DASH_CODE)"
elif [ "$DASH_CODE" = "000" ]; then
  fail "Dashboard not responding"
else
  warn "Dashboard returned HTTP $DASH_CODE"
fi

# --- 9. Agent registration (requires credentials) ---
section "Agents"
CREDS_FILE="$REPO_ROOT/.lab-credentials.txt"
if [ -f "$CREDS_FILE" ]; then
  WUI_PASS=$(awk '/The password for user wazuh-wui/ {getline; print $2}' "$CREDS_FILE" | tr -d "'" || echo "")
  if [ -n "$WUI_PASS" ]; then
    # Get auth token
    TOKEN=$(curl -sk -u "wazuh-wui:$WUI_PASS" -X POST "https://$MANAGER_IP:55000/security/user/authenticate" 2>/dev/null | \
      python3 -c 'import sys, json; print(json.load(sys.stdin).get("data",{}).get("token",""))' 2>/dev/null || echo "")
    if [ -n "$TOKEN" ]; then
      AGENT_DATA=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://$MANAGER_IP:55000/agents?limit=10" 2>/dev/null || echo "{}")
      ACTIVE=$(echo "$AGENT_DATA" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(sum(1 for a in d.get("data",{}).get("affected_items",[]) if a.get("status")=="active"))' 2>/dev/null || echo "0")
      TOTAL=$(echo "$AGENT_DATA" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("data",{}).get("total_affected_items",0))' 2>/dev/null || echo "0")
      if [ "$ACTIVE" -ge 4 ]; then
        pass "$ACTIVE/$TOTAL agents active (manager + 3 CloudVault servers)"
      elif [ "$ACTIVE" -ge 1 ]; then
        warn "$ACTIVE/$TOTAL agents active — still registering? Wait 5 min and re-check"
      else
        fail "No active agents — check agent install logs"
        info "  ssh to agent: sudo tail -f /var/log/wazuh-agent-install.log"
      fi
    else
      warn "Could not get API token — credentials may be stale"
    fi
  else
    warn "wazuh-wui password not found in credentials file"
  fi
else
  warn "No credentials file at $CREDS_FILE (run bootstrap.sh or fetch manually)"
fi

# --- 10. Alert count ---
if [ -f "$CREDS_FILE" ] && [ -n "${TOKEN:-}" ]; then
  section "Alerts"
  # Use indexer directly for alert count
  ADMIN_PASS=$(awk '/The password for user admin/ {getline; print $2}' "$CREDS_FILE" | tr -d "'" || echo "")
  if [ -n "$ADMIN_PASS" ] && { [ "$INDEXER_CODE" = "401" ] || [ "$INDEXER_CODE" = "200" ]; }; then
    ALERT_COUNT=$(curl -sk -u "admin:$ADMIN_PASS" --max-time 5 \
      "https://$MANAGER_IP:9200/wazuh-alerts-*/_count" 2>/dev/null | \
      python3 -c 'import sys, json; print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo "0")
    if [ "$ALERT_COUNT" -gt 0 ]; then
      pass "$ALERT_COUNT alerts in the indexer"
    else
      warn "No alerts yet — agents may still be initializing"
    fi
  fi
fi

# --- Summary ---
echo ""
echo -e "${BOLD}Summary:${NC} ${GREEN}$PASS passed${NC}, ${RED}$FAILS failed${NC}, ${YELLOW}$WARNS warnings${NC}"
echo ""

if [ "$FAILS" -gt 0 ]; then
  echo -e "${YELLOW}Common fixes:${NC}"
  echo "  - If manager/indexer/dashboard not responding: wait 15 min after deploy for install to finish"
  echo "  - If agents not registering: check agent-to-manager network (SG rule 1514/1515 from 10.0.0.0/16)"
  echo "  - If indexer down after it was up: likely OOM — upgrade to t3.large or larger"
  echo "  - See docs/troubleshooting.md for more"
  exit 1
fi

echo -e "${GREEN}Lab looks healthy.${NC}"
exit 0
