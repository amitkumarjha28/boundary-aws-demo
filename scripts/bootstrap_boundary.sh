#!/usr/bin/env bash
# ==============================================================================
# HashiCorp Boundary Complete Demo Configuration & Bootstrap Script
# ==============================================================================
# Automatically bootstraps:
# 1. Organization & Project Scopes
# 2. Static Host Catalogs, Host Sets & Hosts
# 3. Static Credential Store & Credential Libraries (SSH, Windows RDP, Postgres)
# 4. Multi-hop Targets:
#    - Linux SSH Target (Port 22)
#    - Windows RDP Target (Port 3389)
#    - RDS PostgreSQL Target (Port 5432)
#    - Internal Web Portal Target (Port 8080)
# 5. Worker Filters (Ingress -> Egress multi-hop routing)
# 6. Granular RBAC: DevOps, SysAdmin, and Data Analyst Roles & Users
# ==============================================================================

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "======================================================================="
echo "        HASHICORP BOUNDARY DEMO - AUTOMATED CONFIGURATION              "
echo "======================================================================="
echo -e "${NC}"

# Optional fallback to the boundary-demo-config workspace. Do not run both:
# the workspace and this script create resources with the same names.
#
# Must be run from the repository root.
INFRA_DIR="infra"

tf_out() { terraform -chdir="$INFRA_DIR" output -raw "$1" 2>/dev/null || echo ""; }

if command -v terraform &> /dev/null && [ -d "$INFRA_DIR/.terraform" ]; then
  echo -e "${BLUE}Extracting environment details from HCP Terraform outputs...${NC}"
  CONTROLLER_URL=$(tf_out boundary_controller_url)
  RECOVERY_KEY=$(tf_out boundary_recovery_key)
  LINUX_PRIVATE_IP=$(tf_out linux_target_private_ip)
  WINDOWS_PRIVATE_IP=$(tf_out windows_target_private_ip)
  RDS_ENDPOINT=$(tf_out rds_endpoint_address)
  WINDOWS_PASS=$(tf_out windows_admin_password)
  LINUX_SSH_PASS=$(tf_out linux_ssh_password)
  DEMO_DB_PASS=$(tf_out demo_db_password)
fi

CONTROLLER_URL="${CONTROLLER_URL:-${BOUNDARY_ADDR:-}}"
RECOVERY_KEY="${RECOVERY_KEY:-${BOUNDARY_RECOVERY_KEY:-}}"

if [ -z "$CONTROLLER_URL" ]; then
  read -p "Enter Boundary Controller URL (e.g., http://<controller-ip>:9200): " CONTROLLER_URL
fi
if [ -z "$RECOVERY_KEY" ]; then
  read -s -p "Enter Boundary Recovery KMS Key (base64 string): " RECOVERY_KEY; echo
fi
if [ -z "${LINUX_PRIVATE_IP:-}" ]; then
  read -p "Enter Linux Target Private IP: " LINUX_PRIVATE_IP
fi
if [ -z "${WINDOWS_PRIVATE_IP:-}" ]; then
  read -p "Enter Windows Target Private IP: " WINDOWS_PRIVATE_IP
fi
if [ -z "${RDS_ENDPOINT:-}" ]; then
  read -p "Enter RDS Endpoint (hostname only, without port): " RDS_ENDPOINT
fi
if [ -z "${WINDOWS_PASS:-}" ]; then
  read -s -p "Enter Windows Administrator password: " WINDOWS_PASS; echo
fi
if [ -z "${LINUX_SSH_PASS:-}" ]; then
  read -s -p "Enter Linux boundary-user password: " LINUX_SSH_PASS; echo
fi
if [ -z "${DEMO_DB_PASS:-}" ]; then
  read -s -p "Enter appdb demouser password: " DEMO_DB_PASS; echo
fi

# Generated passwords for the Boundary login accounts
gen_pass() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-16; }
ADMIN_PASS=$(gen_pass); DEVOPS_PASS=$(gen_pass); SYSADMIN_PASS=$(gen_pass); ANALYST_PASS=$(gen_pass)

export BOUNDARY_ADDR="$CONTROLLER_URL"

# The Boundary CLI authorizes recovery-KMS calls via a KMS config file
RECOVERY_CONFIG=$(mktemp)
trap 'rm -f "$RECOVERY_CONFIG"' EXIT
cat > "$RECOVERY_CONFIG" << EOF
kms "aead" {
  purpose   = "recovery"
  aead_type = "aes-gcm"
  key       = "$RECOVERY_KEY"
  key_id    = "global_recovery"
}
EOF
export BOUNDARY_RECOVERY_CONFIG="$RECOVERY_CONFIG"

echo -e "\n${YELLOW}Testing connection to Boundary Controller at $BOUNDARY_ADDR...${NC}"
for i in {1..30}; do
  if curl -s "$BOUNDARY_ADDR/v1/health" > /dev/null 2>&1; then
    echo -e "${GREEN}Boundary Controller is active and responding!${NC}"
    break
  fi
  echo "Waiting for Controller to initialize ($i/30)..."
  sleep 4
done

echo -e "\n${CYAN}Step 1: Creating Organization Scope ('Demo-Org')...${NC}"
ORG_OUTPUT=$(boundary scopes create -scope-id=global \
  -name="Demo-Org" \
  -description="HashiCorp Boundary Demo Organization" \
  -format=json)
ORG_ID=$(echo "$ORG_OUTPUT" | jq -r '.item.id')
echo -e "${GREEN}Created Org Scope: ${BOLD}$ORG_ID${NC}"

echo -e "\n${CYAN}Step 2: Creating Project Scope ('Core-Infrastructure')...${NC}"
PROJECT_OUTPUT=$(boundary scopes create -scope-id="$ORG_ID" \
  -name="Core-Infrastructure" \
  -description="Production & Demo Workloads Project" \
  -format=json)
PROJECT_ID=$(echo "$PROJECT_OUTPUT" | jq -r '.item.id')
echo -e "${GREEN}Created Project Scope: ${BOLD}$PROJECT_ID${NC}"

echo -e "\n${CYAN}Step 3: Creating Password Auth Method in Demo-Org...${NC}"
AUTH_OUTPUT=$(boundary auth-methods create password -scope-id="$ORG_ID" \
  -name="corp-password-auth" \
  -description="Corporate Password Authentication" \
  -format=json)
AUTH_METHOD_ID=$(echo "$AUTH_OUTPUT" | jq -r '.item.id')
echo -e "${GREEN}Created Auth Method: ${BOLD}$AUTH_METHOD_ID${NC}"

# Create Users & Accounts
echo -e "\n${CYAN}Step 4: Provisioning Demo Users & Accounts...${NC}"

# Admin User
ADMIN_USER_ID=$(boundary users create -scope-id="$ORG_ID" -name="boundary-admin" -description="Demo Administrator" -format=json | jq -r '.item.id')
ADMIN_ACC_ID=$(boundary accounts create password -auth-method-id="$AUTH_METHOD_ID" -login-name="admin" -password="$ADMIN_PASS" -name="Admin Account" -format=json | jq -r '.item.id')
boundary users set-accounts -id="$ADMIN_USER_ID" -account="$ADMIN_ACC_ID" > /dev/null

# DevOps User (Linux SSH + Web Target)
DEVOPS_USER_ID=$(boundary users create -scope-id="$ORG_ID" -name="devops-engineer" -description="DevOps Engineer" -format=json | jq -r '.item.id')
DEVOPS_ACC_ID=$(boundary accounts create password -auth-method-id="$AUTH_METHOD_ID" -login-name="devops" -password="$DEVOPS_PASS" -name="DevOps Account" -format=json | jq -r '.item.id')
boundary users set-accounts -id="$DEVOPS_USER_ID" -account="$DEVOPS_ACC_ID" > /dev/null

# SysAdmin User (Windows RDP Target)
SYSADMIN_USER_ID=$(boundary users create -scope-id="$ORG_ID" -name="windows-sysadmin" -description="Windows Systems Administrator" -format=json | jq -r '.item.id')
SYSADMIN_ACC_ID=$(boundary accounts create password -auth-method-id="$AUTH_METHOD_ID" -login-name="sysadmin" -password="$SYSADMIN_PASS" -name="SysAdmin Account" -format=json | jq -r '.item.id')
boundary users set-accounts -id="$SYSADMIN_USER_ID" -account="$SYSADMIN_ACC_ID" > /dev/null

# Data Analyst User (PostgreSQL RDS Target)
ANALYST_USER_ID=$(boundary users create -scope-id="$ORG_ID" -name="data-analyst" -description="Data Analyst" -format=json | jq -r '.item.id')
ANALYST_ACC_ID=$(boundary accounts create password -auth-method-id="$AUTH_METHOD_ID" -login-name="analyst" -password="$ANALYST_PASS" -name="Analyst Account" -format=json | jq -r '.item.id')
boundary users set-accounts -id="$ANALYST_USER_ID" -account="$ANALYST_ACC_ID" > /dev/null

echo -e "${GREEN}Users configured: admin, devops, sysadmin, analyst${NC}"

echo -e "\n${CYAN}Step 5: Creating Host Catalog & Host Sets...${NC}"
CATALOG_ID=$(boundary host-catalogs create static -scope-id="$PROJECT_ID" \
  -name="aws-private-catalog" \
  -description="AWS Private Subnet Infrastructure" \
  -format=json | jq -r '.item.id')

# Linux Host & Host Set
LINUX_HOST_ID=$(boundary hosts create static -host-catalog-id="$CATALOG_ID" \
  -name="linux-private-target" \
  -address="$LINUX_PRIVATE_IP" \
  -description="Amazon Linux 2023 in Private Subnet" \
  -format=json | jq -r '.item.id')

LINUX_HOSTSET_ID=$(boundary host-sets create static -host-catalog-id="$CATALOG_ID" \
  -name="linux-host-set" \
  -format=json | jq -r '.item.id')
boundary host-sets set-hosts -id="$LINUX_HOSTSET_ID" -host="$LINUX_HOST_ID" > /dev/null

# Windows Host & Host Set
WINDOWS_HOST_ID=$(boundary hosts create static -host-catalog-id="$CATALOG_ID" \
  -name="windows-private-target" \
  -address="$WINDOWS_PRIVATE_IP" \
  -description="Windows Server 2022 in Private Subnet" \
  -format=json | jq -r '.item.id')

WINDOWS_HOSTSET_ID=$(boundary host-sets create static -host-catalog-id="$CATALOG_ID" \
  -name="windows-host-set" \
  -format=json | jq -r '.item.id')
boundary host-sets set-hosts -id="$WINDOWS_HOSTSET_ID" -host="$WINDOWS_HOST_ID" > /dev/null

# RDS PostgreSQL Host & Host Set
RDS_HOST_ID=$(boundary hosts create static -host-catalog-id="$CATALOG_ID" \
  -name="rds-postgres-target" \
  -address="$RDS_ENDPOINT" \
  -description="AWS RDS PostgreSQL Backend & Demo AppDB" \
  -format=json | jq -r '.item.id')

RDS_HOSTSET_ID=$(boundary host-sets create static -host-catalog-id="$CATALOG_ID" \
  -name="rds-host-set" \
  -format=json | jq -r '.item.id')
boundary host-sets set-hosts -id="$RDS_HOSTSET_ID" -host="$RDS_HOST_ID" > /dev/null

echo -e "${GREEN}Host Catalog & Sets created!${NC}"

echo -e "\n${CYAN}Step 6: Creating Static Credential Store & Credentials...${NC}"
CRED_STORE_ID=$(boundary credential-stores create static -scope-id="$PROJECT_ID" \
  -name="demo-static-credentials" \
  -description="Static Credentials for Demo Targets" \
  -format=json | jq -r '.item.id')

# Linux SSH Credential
SSH_CRED_ID=$(boundary credentials create username-password -credential-store-id="$CRED_STORE_ID" \
  -username="boundary-user" \
  -password="$LINUX_SSH_PASS" \
  -name="linux-ssh-cred" \
  -description="Linux SSH boundary-user credentials" \
  -format=json | jq -r '.item.id')

# Windows RDP Credential
RDP_CRED_ID=$(boundary credentials create username-password -credential-store-id="$CRED_STORE_ID" \
  -username="Administrator" \
  -password="$WINDOWS_PASS" \
  -name="windows-rdp-cred" \
  -description="Windows Server Administrator credentials" \
  -format=json | jq -r '.item.id')

# RDS PostgreSQL Credential
RDS_CRED_ID=$(boundary credentials create username-password -credential-store-id="$CRED_STORE_ID" \
  -username="demouser" \
  -password="$DEMO_DB_PASS" \
  -name="rds-postgres-cred" \
  -description="RDS demouser credentials" \
  -format=json | jq -r '.item.id')

echo -e "${GREEN}Credential Store and Credentials provisioned!${NC}"

echo -e "\n${CYAN}Step 7: Creating Multi-Hop Targets...${NC}"
# Ingress and Egress worker filters enable multi-hop tunneling!
INGRESS_FILTER="\"ingress\" in \"/tags/type\""
EGRESS_FILTER="\"egress\" in \"/tags/type\""

# 1. Linux SSH Target
TARGET_SSH_ID=$(boundary targets create tcp -scope-id="$PROJECT_ID" \
  -name="linux-ssh-target" \
  -description="Secure SSH access to Private Linux Instance" \
  -default-port=22 \
  -ingress-worker-filter="$INGRESS_FILTER" \
  -egress-worker-filter="$EGRESS_FILTER" \
  -format=json | jq -r '.item.id')
boundary targets add-host-sets -id="$TARGET_SSH_ID" -host-set="$LINUX_HOSTSET_ID" > /dev/null
boundary targets add-credentials -id="$TARGET_SSH_ID" -brokered-credential-source="$SSH_CRED_ID" > /dev/null
echo -e "${GREEN}✓ Target 1: Linux SSH [Port 22] -> ${BOLD}$TARGET_SSH_ID${NC}"

# 2. Windows RDP Target
TARGET_RDP_ID=$(boundary targets create tcp -scope-id="$PROJECT_ID" \
  -name="windows-rdp-target" \
  -description="Secure RDP access to Private Windows Instance" \
  -default-port=3389 \
  -ingress-worker-filter="$INGRESS_FILTER" \
  -egress-worker-filter="$EGRESS_FILTER" \
  -format=json | jq -r '.item.id')
boundary targets add-host-sets -id="$TARGET_RDP_ID" -host-set="$WINDOWS_HOSTSET_ID" > /dev/null
boundary targets add-credentials -id="$TARGET_RDP_ID" -brokered-credential-source="$RDP_CRED_ID" > /dev/null
echo -e "${GREEN}✓ Target 2: Windows RDP [Port 3389] -> ${BOLD}$TARGET_RDP_ID${NC}"

# 3. RDS PostgreSQL Target
TARGET_RDS_ID=$(boundary targets create tcp -scope-id="$PROJECT_ID" \
  -name="rds-postgres-target" \
  -description="Secure Database access to Private RDS PostgreSQL" \
  -default-port=5432 \
  -ingress-worker-filter="$INGRESS_FILTER" \
  -egress-worker-filter="$EGRESS_FILTER" \
  -format=json | jq -r '.item.id')
boundary targets add-host-sets -id="$TARGET_RDS_ID" -host-set="$RDS_HOSTSET_ID" > /dev/null
boundary targets add-credentials -id="$TARGET_RDS_ID" -brokered-credential-source="$RDS_CRED_ID" > /dev/null
echo -e "${GREEN}✓ Target 3: RDS PostgreSQL [Port 5432] -> ${BOLD}$TARGET_RDS_ID${NC}"

# 4. Internal Web Portal Target
TARGET_WEB_ID=$(boundary targets create tcp -scope-id="$PROJECT_ID" \
  -name="internal-web-target" \
  -description="Secure HTTP Tunnel to Private Corporate Portal" \
  -default-port=8080 \
  -ingress-worker-filter="$INGRESS_FILTER" \
  -egress-worker-filter="$EGRESS_FILTER" \
  -format=json | jq -r '.item.id')
boundary targets add-host-sets -id="$TARGET_WEB_ID" -host-set="$LINUX_HOSTSET_ID" > /dev/null
echo -e "${GREEN}✓ Target 4: Internal Web Portal [Port 8080] -> ${BOLD}$TARGET_WEB_ID${NC}"

echo -e "\n${CYAN}Step 8: Configuring RBAC Roles & Permissions...${NC}"
# Org Admin Role
ORG_ADMIN_ROLE=$(boundary roles create -scope-id="$ORG_ID" \
  -name="org-admin" \
  -grant-scope-id="$ORG_ID" \
  -grant="ids=*;type=*;actions=*" \
  -grant="ids=*;type=*;actions=*;propagation=descendants" \
  -format=json | jq -r '.item.id')
boundary roles set-principals -id="$ORG_ADMIN_ROLE" -principal="$ADMIN_USER_ID" > /dev/null

# DevOps Role (Can connect to SSH and Web Target)
DEVOPS_ROLE=$(boundary roles create -scope-id="$PROJECT_ID" \
  -name="devops-engineer-role" \
  -grant="ids=${TARGET_SSH_ID};actions=read,authorize-session" \
  -grant="ids=${TARGET_WEB_ID};actions=read,authorize-session" \
  -format=json | jq -r '.item.id')
boundary roles set-principals -id="$DEVOPS_ROLE" -principal="$DEVOPS_USER_ID" > /dev/null

# SysAdmin Role (Can connect to Windows RDP Target)
SYSADMIN_ROLE=$(boundary roles create -scope-id="$PROJECT_ID" \
  -name="windows-sysadmin-role" \
  -grant="ids=${TARGET_RDP_ID};actions=read,authorize-session" \
  -format=json | jq -r '.item.id')
boundary roles set-principals -id="$SYSADMIN_ROLE" -principal="$SYSADMIN_USER_ID" > /dev/null

# Data Analyst Role (Can connect to RDS Postgres Target)
ANALYST_ROLE=$(boundary roles create -scope-id="$PROJECT_ID" \
  -name="data-analyst-role" \
  -grant="ids=${TARGET_RDS_ID};actions=read,authorize-session" \
  -format=json | jq -r '.item.id')
boundary roles set-principals -id="$ANALYST_ROLE" -principal="$ANALYST_USER_ID" > /dev/null

# Save target IDs to local JSON config file for convenient reference
cat << EOF > boundary_demo_targets.json
{
  "boundary_addr": "$BOUNDARY_ADDR",
  "org_id": "$ORG_ID",
  "project_id": "$PROJECT_ID",
  "auth_method_id": "$AUTH_METHOD_ID",
  "targets": {
    "linux_ssh": "$TARGET_SSH_ID",
    "windows_rdp": "$TARGET_RDP_ID",
    "rds_postgres": "$TARGET_RDS_ID",
    "internal_web": "$TARGET_WEB_ID"
  },
  "users": {
    "admin": {"user": "admin", "password": "$ADMIN_PASS"},
    "devops": {"user": "devops", "password": "$DEVOPS_PASS"},
    "sysadmin": {"user": "sysadmin", "password": "$SYSADMIN_PASS"},
    "analyst": {"user": "analyst", "password": "$ANALYST_PASS"}
  }
}
EOF

echo -e "\n${GREEN}${BOLD}======================================================================="
echo "        BOUNDARY DEMO SETUP COMPLETED SUCCESSFULLY!                    "
echo "=======================================================================${NC}"

echo -e "\n${BOLD}Boundary Web UI:${NC} $BOUNDARY_ADDR"
echo -e "${BOLD}Auth Method ID:${NC}  $AUTH_METHOD_ID"
echo -e "\n${BOLD}Ready-to-use Connection Commands:${NC}\n"

echo -e "${CYAN}1. Authenticate:${NC}"
echo -e "   boundary authenticate password -auth-method-id $AUTH_METHOD_ID -login-name admin"
echo -e "   (passwords are in boundary_demo_targets.json)\n"

echo -e "${CYAN}2. Connect to Linux SSH (Private Target):${NC}"
echo -e "   boundary connect ssh -target-id $TARGET_SSH_ID\n"

echo -e "${CYAN}3. Connect to Windows RDP (Private Target):${NC}"
echo -e "   boundary connect rdp -target-id $TARGET_RDP_ID\n"

echo -e "${CYAN}4. Connect to RDS PostgreSQL (Private Target):${NC}"
echo -e "   boundary connect postgres -target-id $TARGET_RDS_ID -dbname appdb\n"

echo -e "${CYAN}5. Connect to Internal Web Application (Private Target):${NC}"
echo -e "   boundary connect -listen-port 8080 -target-id $TARGET_WEB_ID  (then open http://127.0.0.1:8080)\n"
