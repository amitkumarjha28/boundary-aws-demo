#!/usr/bin/env bash
# ==============================================================================
# HashiCorp Boundary Demo Interactive Menu
# ==============================================================================
# Run from the repository root. Target IDs and passwords are read from the
# boundary-demo-config workspace outputs (requires `terraform init` in
# boundary-config/ once), or from boundary_demo_targets.json if the bash
# bootstrap fallback was used.
set -e

CONFIG_FILE="boundary_demo_targets.json"
CONFIG_DIR="boundary-config"

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -d "$CONFIG_DIR/.terraform" ]; then
    echo "Fetching demo details from HCP Terraform workspace outputs..."
    terraform -chdir="$CONFIG_DIR" output -json | jq '{
      boundary_addr:  .boundary_addr.value,
      org_id:         .org_id.value,
      project_id:     .project_id.value,
      auth_method_id: .auth_method_id.value,
      targets: {
        linux_ssh:    .linux_ssh_target_id.value,
        windows_rdp:  .windows_rdp_target_id.value,
        rds_postgres: .rds_postgres_target_id.value,
        internal_web: .web_target_id.value
      },
      users: (.user_passwords.value | with_entries(.value = {user: .key, password: .value}))
    }' > "$CONFIG_FILE"
  else
    echo "Error: $CONFIG_FILE not found."
    echo "Run 'terraform -chdir=$CONFIG_DIR init' (HCP Terraform login required),"
    echo "or './scripts/bootstrap_boundary.sh' if you are not using the config workspace."
    exit 1
  fi
fi

BOUNDARY_ADDR=$(jq -r '.boundary_addr' "$CONFIG_FILE")
AUTH_METHOD_ID=$(jq -r '.auth_method_id' "$CONFIG_FILE")
TARGET_SSH=$(jq -r '.targets.linux_ssh' "$CONFIG_FILE")
TARGET_RDP=$(jq -r '.targets.windows_rdp' "$CONFIG_FILE")
TARGET_RDS=$(jq -r '.targets.rds_postgres' "$CONFIG_FILE")
TARGET_WEB=$(jq -r '.targets.internal_web' "$CONFIG_FILE")

export BOUNDARY_ADDR="$BOUNDARY_ADDR"

login() {
  echo "Authenticating as $1..."
  # The Boundary CLI reads the login password from this env var
  BOUNDARY_AUTHENTICATE_PASSWORD_PASSWORD=$(jq -r --arg u "$1" '.users[$u].password' "$CONFIG_FILE") \
    boundary authenticate password -auth-method-id="$AUTH_METHOD_ID" -login-name="$1"
}

clear
echo "======================================================================="
echo "       HASHICORP BOUNDARY ZERO-TRUST DEMO INTERACTIVE LAUNCHER         "
echo "======================================================================="
echo "Boundary Controller: $BOUNDARY_ADDR"
echo "Auth Method ID:      $AUTH_METHOD_ID"
echo "======================================================================="
echo "Choose an action:"
echo " 1) Authenticate as Administrator (admin)"
echo " 2) Authenticate as DevOps persona (devops)"
echo " 3) Authenticate as SysAdmin persona (sysadmin)"
echo " 4) Authenticate as Data Analyst persona (analyst)"
echo " --------------------------------------------------"
echo " 5) Connect to Linux SSH Target       (Port 22)"
echo " 6) Connect to Windows RDP Target     (Port 3389)"
echo " 7) Connect to RDS PostgreSQL Target   (Port 5432)"
echo " 8) Connect to Internal Web Target     (Port 8080)"
echo " --------------------------------------------------"
echo " 9) View Target & Credential Details"
echo " q) Quit"
echo "======================================================================="
read -p "Enter choice [1-9]: " choice

case $choice in
  1) login admin ;;
  2) login devops ;;
  3) login sysadmin ;;
  4) login analyst ;;
  5)
    echo "Launching Boundary SSH session to Linux Target ($TARGET_SSH)..."
    boundary connect ssh -target-id "$TARGET_SSH"
    ;;
  6)
    echo "Launching Boundary RDP session to Windows Target ($TARGET_RDP)..."
    boundary connect rdp -target-id "$TARGET_RDP"
    ;;
  7)
    echo "Launching Boundary PostgreSQL session to RDS Target ($TARGET_RDS)..."
    boundary connect postgres -target-id "$TARGET_RDS" -dbname appdb
    ;;
  8)
    echo "Launching Boundary HTTP tunnel to Internal Web Portal ($TARGET_WEB)..."
    echo "Open the displayed localhost URL in your browser!"
    boundary connect http -target-id "$TARGET_WEB"
    ;;
  9)
    jq . "$CONFIG_FILE"
    ;;
  q|Q)
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
