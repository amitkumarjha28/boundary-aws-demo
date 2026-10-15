#!/usr/bin/env bash
# ==============================================================================
# Boundary Enterprise demo: deploy from scratch with HCP Terraform
# ==============================================================================
# Prompts for everything it needs (HCP Terraform token and org, AWS
# credentials, Boundary Enterprise license), then:
#   1. creates/updates the two HCP Terraform workspaces and their variables
#   2. deploys the AWS infrastructure            (boundary-demo-infra)
#   3. waits until both Boundary workers are connected
#   4. deploys the Boundary configuration        (boundary-demo-config)
#   5. writes DEMO.md with IPs, URLs and credentials for the demo
#
# Re-runnable: existing workspaces and variables are updated in place, and a
# second run on a deployed environment just applies any pending changes.
#
# Run from the repository root:   ./scripts/deploy.sh
# Requires: terraform, jq, curl, boundary (CLI), git
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)
SETTINGS_FILE="$REPO_ROOT/.deploy.env"

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
info() { echo -e "    $*"; }
warn() { echo -e "${YELLOW}    ! $*${NC}"; }
die()  { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }

# ask VAR "Prompt" [default] [secret]
ask() {
  local __var=$1 __prompt=$2 __default=${3:-} __secret=${4:-} __value
  if [ -n "$__default" ] && [ -z "$__secret" ]; then __prompt="$__prompt [$__default]"; fi
  if [ -n "$__secret" ]; then
    [ -n "$__default" ] && __prompt="$__prompt [press Enter to keep the current value]"
    read -r -s -p "    $__prompt: " __value; echo
  else
    read -r -p "    $__prompt: " __value
  fi
  printf -v "$__var" '%s' "${__value:-$__default}"
}
confirm() { local a; read -r -p "    $1 [y/N]: " a; [[ "$a" =~ ^[Yy] ]]; }

# ------------------------------------------------------------------------------
step "Checking prerequisites"
for t in terraform jq curl boundary git; do
  command -v "$t" >/dev/null || die "'$t' is not installed (see README prerequisites)."
done
info "terraform $(terraform version -json | jq -r .terraform_version), boundary $(boundary version 2>/dev/null | awk '/Version Number/{print $3}')"

# Defaults from a previous run
TFC_HOST=app.terraform.io; TFC_ORG=""; WS_INFRA=boundary-demo-infra; WS_CONFIG=boundary-demo-config
WORKFLOW=""; VCS_REPO=""; AWS_REGION=us-east-1; CLIENT_CIDR=0.0.0.0/0
# shellcheck disable=SC1090
[ -f "$SETTINGS_FILE" ] && source "$SETTINGS_FILE"

# ------------------------------------------------------------------------------
step "HCP Terraform"
ask TFC_HOST "HCP Terraform hostname" "$TFC_HOST"
SAVED_TOKEN=$(jq -r --arg h "$TFC_HOST" '.credentials[$h].token // empty' ~/.terraform.d/credentials.tfrc.json 2>/dev/null || true)
ask TFC_TOKEN "HCP Terraform API token (user or team token)" "$SAVED_TOKEN" secret
[ -n "$TFC_TOKEN" ] || die "An HCP Terraform token is required."

API="https://$TFC_HOST/api/v2"
api() { # api METHOD PATH [JSON]
  local m=$1 p=$2 b=${3:-}
  if [ -n "$b" ]; then
    curl -sS -X "$m" -H "Authorization: Bearer $TFC_TOKEN" -H "Content-Type: application/vnd.api+json" --data "$b" "$API$p"
  else
    curl -sS -X "$m" -H "Authorization: Bearer $TFC_TOKEN" -H "Content-Type: application/vnd.api+json" "$API$p"
  fi
}
USERNAME=$(api GET /account/details | jq -r '.data.attributes.username // empty')
[ -n "$USERNAME" ] || die "The token was rejected by $TFC_HOST."
info "Authenticated as ${BOLD}$USERNAME${NC}"

ORGS=$(api GET /organizations | jq -r '.data[].id')
info "Organizations you can access: $(echo $ORGS | tr ' ' ',')"
ask TFC_ORG "Organization to deploy into" "${TFC_ORG:-$(echo "$ORGS" | head -1)}"
echo "$ORGS" | grep -qx "$TFC_ORG" || die "Organization '$TFC_ORG' not found for this token."
ask WS_INFRA "Infrastructure workspace name" "$WS_INFRA"
ask WS_CONFIG "Boundary config workspace name" "$WS_CONFIG"

# Workflow: VCS-driven (runs on git push) needs a VCS connection in the org;
# CLI-driven uploads this local checkout instead.
OAUTH_TOKEN_ID=$(api GET "/organizations/$TFC_ORG/oauth-clients" \
  | jq -r '[.data[] | select(.attributes."service-provider" | test("github"))][0].relationships."oauth-tokens".data[0].id // empty')
if [ -n "$OAUTH_TOKEN_ID" ]; then
  info "The org has a GitHub VCS connection."
  DEFAULT_REPO=${VCS_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}
  ask WORKFLOW "Workflow: 'vcs' (runs on git push) or 'cli' (uploads this folder)" "${WORKFLOW:-vcs}"
else
  warn "No GitHub VCS connection in '$TFC_ORG' - using the CLI-driven workflow."
  WORKFLOW=cli
fi
[[ "$WORKFLOW" =~ ^(vcs|cli)$ ]] || die "Workflow must be 'vcs' or 'cli'."
if [ "$WORKFLOW" = vcs ]; then
  ask VCS_REPO "GitHub repository (owner/name)" "$DEFAULT_REPO"
  info "The VCS workflow deploys the latest commit on the repo's main branch (push local changes first)."
fi

# ------------------------------------------------------------------------------
step "AWS"
ask AWS_REGION "AWS region" "$AWS_REGION"
ask AWS_KEY_ID "AWS access key ID" ""
ask AWS_SECRET "AWS secret access key" "" secret
ask AWS_SESSION "AWS session token (only for temporary credentials, else press Enter)" "" secret
[ -n "$AWS_KEY_ID" ] && [ -n "$AWS_SECRET" ] || die "AWS access key ID and secret access key are required."
info "HCP Terraform runners must reach the controller API (port 9200) to configure Boundary,"
info "so the default allows all source addresses. Narrowing it requires an HCP Terraform agent."
ask CLIENT_CIDR "CIDR allowed to reach Boundary (controller 9200, ingress worker 9202)" "$CLIENT_CIDR"

# ------------------------------------------------------------------------------
step "Boundary Enterprise license"
DEFAULT_LIC=$(ls "$REPO_ROOT"/*.hclic "$REPO_ROOT"/../*/boundary.hclic 2>/dev/null | head -1 || true)
ask LICENSE_FILE "Path to the Boundary Enterprise license file (.hclic)" "$DEFAULT_LIC"
LICENSE_FILE=${LICENSE_FILE/#\~/$HOME}
[ -s "$LICENSE_FILE" ] || die "License file '$LICENSE_FILE' not found or empty."
info "License file found ($(wc -c <"$LICENSE_FILE" | tr -d ' ') bytes). It is stored only as a sensitive workspace variable."

# ------------------------------------------------------------------------------
step "Summary"
info "HCP Terraform : $TFC_HOST / org $TFC_ORG, workspaces $WS_INFRA + $WS_CONFIG ($WORKFLOW workflow${VCS_REPO:+, repo $VCS_REPO})"
info "AWS           : region $AWS_REGION, key ${AWS_KEY_ID:0:4}…${AWS_KEY_ID: -4}${AWS_SESSION:+ (temporary credentials)}"
info "Access CIDR   : $CLIENT_CIDR"
info "Cost          : about \$0.45-0.50/hour while deployed (controller t3.xlarge, workers t3.large)."
confirm "Create/update the workspaces and deploy?" || die "Aborted - nothing was changed."

cat > "$SETTINGS_FILE" <<EOF
# Saved by scripts/deploy.sh (no secrets)
TFC_HOST=$TFC_HOST
TFC_ORG=$TFC_ORG
WS_INFRA=$WS_INFRA
WS_CONFIG=$WS_CONFIG
WORKFLOW=$WORKFLOW
VCS_REPO=$VCS_REPO
AWS_REGION=$AWS_REGION
CLIENT_CIDR=$CLIENT_CIDR
EOF

# ------------------------------------------------------------------------------
step "Workspaces"
ensure_workspace() { # name working-dir -> prints id
  local name=$1 dir=$2 id attrs
  attrs=$(jq -n --arg n "$name" --arg d "$dir" --arg wf "$WORKFLOW" --arg repo "$VCS_REPO" --arg ot "${OAUTH_TOKEN_ID:-}" '
    {name: $n, "working-directory": $d, "execution-mode": "remote", "auto-apply": false}
    + (if $wf == "vcs" then {"file-triggers-enabled": true, "trigger-patterns": [($d + "/**/*")],
         "vcs-repo": {identifier: $repo, branch: "main", "oauth-token-id": $ot}}
       else {"vcs-repo": null} end)')   # CLI applies are rejected on VCS-connected workspaces
  id=$(api GET "/organizations/$TFC_ORG/workspaces/$name" | jq -r '.data.id // empty')
  if [ -z "$id" ]; then
    id=$(api POST "/organizations/$TFC_ORG/workspaces" "{\"data\":{\"type\":\"workspaces\",\"attributes\":$attrs}}" | jq -r '.data.id // empty')
    [ -n "$id" ] || die "Could not create workspace $name."
    info "created  $name ($id)" >&2
  else
    api PATCH "/workspaces/$id" "{\"data\":{\"type\":\"workspaces\",\"attributes\":$attrs}}" >/dev/null
    info "updated  $name ($id)" >&2
  fi
  echo "$id"
}
INFRA_ID=$(ensure_workspace "$WS_INFRA" infra)
CONFIG_ID=$(ensure_workspace "$WS_CONFIG" boundary-config)

set_var() { # workspace-id key value category(terraform|env) sensitive(true|false)
  local ws=$1 key=$2 val=$3 cat=$4 sens=$5 vid body
  vid=$(api GET "/workspaces/$ws/vars" | jq -r --arg k "$key" --arg c "$cat" '.data[] | select(.attributes.key==$k and .attributes.category==$c) | .id' | head -1)
  body=$(jq -n --arg k "$key" --arg v "$val" --arg c "$cat" --argjson s "$sens" \
    '{data: {type: "vars", attributes: {key: $k, value: $v, category: $c, hcl: false, sensitive: $s}}}')
  if [ -n "$vid" ]; then api PATCH "/workspaces/$ws/vars/$vid" "$body" >/dev/null; else api POST "/workspaces/$ws/vars" "$body" >/dev/null; fi
  info "variable $key ($cat$( [ "$sens" = true ] && echo ', sensitive'))"
}
del_var() { # workspace-id key category
  local vid; vid=$(api GET "/workspaces/$1/vars" | jq -r --arg k "$2" --arg c "$3" '.data[] | select(.attributes.key==$k and .attributes.category==$c) | .id' | head -1)
  [ -n "$vid" ] && api DELETE "/workspaces/$1/vars/$vid" >/dev/null && info "removed  $2 ($3)"
  return 0
}

step "Workspace variables"
set_var "$INFRA_ID" aws_region "$AWS_REGION" terraform false
set_var "$INFRA_ID" authorized_client_cidr "$CLIENT_CIDR" terraform false
set_var "$INFRA_ID" boundary_license "$(tr -d '\r' <"$LICENSE_FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" terraform true
set_var "$INFRA_ID" AWS_ACCESS_KEY_ID "$AWS_KEY_ID" env false
set_var "$INFRA_ID" AWS_SECRET_ACCESS_KEY "$AWS_SECRET" env true
if [ -n "$AWS_SESSION" ]; then set_var "$INFRA_ID" AWS_SESSION_TOKEN "$AWS_SESSION" env true; else del_var "$INFRA_ID" AWS_SESSION_TOKEN env; fi
del_var "$INFRA_ID" AWS_SESSION_EXPIRATION env
set_var "$CONFIG_ID" tfc_organization "$TFC_ORG" terraform false
set_var "$CONFIG_ID" infra_workspace_name "$WS_INFRA" terraform false
unset AWS_SECRET AWS_SESSION

api POST "/workspaces/$INFRA_ID/relationships/remote-state-consumers" \
  "{\"data\":[{\"type\":\"workspaces\",\"id\":\"$CONFIG_ID\"}]}" >/dev/null
info "remote state sharing: $WS_INFRA -> $WS_CONFIG"

# Local CLI (demo menu, terraform output) talks to these workspaces
for d in infra boundary-config; do
  ws=$([ "$d" = infra ] && echo "$WS_INFRA" || echo "$WS_CONFIG")
  cat > "$d/cloud_override.tf" <<EOF
# Generated by scripts/deploy.sh (gitignored): points the local CLI at your workspace
terraform {
  cloud {
    hostname     = "$TFC_HOST"
    organization = "$TFC_ORG"
    workspaces {
      name = "$ws"
    }
  }
}
EOF
done
# Terraform reads TF_TOKEN_<host> with "." -> "_" and "-" -> "__"
export "TF_TOKEN_$(echo "$TFC_HOST" | sed -e 's/-/__/g' -e 's/\./_/g')=$TFC_TOKEN"
if [ "$SAVED_TOKEN" != "$TFC_TOKEN" ] && confirm "Save this token to ~/.terraform.d/credentials.tfrc.json so the demo menu can read outputs later?"; then
  mkdir -p ~/.terraform.d
  f=~/.terraform.d/credentials.tfrc.json
  ( [ -s "$f" ] && cat "$f" || echo '{}' ) | jq --arg h "$TFC_HOST" --arg t "$TFC_TOKEN" '.credentials[$h].token = $t' > "$f.tmp"
  mv "$f.tmp" "$f"; chmod 600 "$f"; info "saved"
fi
for d in infra boundary-config; do
  terraform -chdir="$d" init -input=false -no-color >/dev/null || die "terraform init failed in $d"
done

# ------------------------------------------------------------------------------
# Run helpers
run_status() { api GET "/runs/$1" | jq -r .data.attributes.status; }
wait_run() { # run-id pattern
  local s; until s=$(run_status "$1"); [[ "$s" =~ ^($2)$ ]]; do sleep 10; done; echo "$s"
}
plan_summary() {
  local p; p=$(api GET "/runs/$1" | jq -r .data.relationships.plan.data.id)
  api GET "/plans/$p" | jq -r '.data.attributes | "+\(."resource-additions") ~\(."resource-changes") -\(."resource-destructions")"'
}
run_url() { echo "https://$TFC_HOST/app/$TFC_ORG/workspaces/$1/runs/$2"; }

# deploy_workspace label dir ws-name ws-id  -> returns 0 on applied / no changes
deploy_workspace() {
  local label=$1 dir=$2 wsname=$3 wsid=$4
  step "Deploying $label ($wsname)"
  if [ "$WORKFLOW" = cli ]; then
    terraform -chdir="$dir" apply -input=false
    return $?
  fi
  local r s
  r=$(api POST /runs "{\"data\":{\"type\":\"runs\",\"attributes\":{\"message\":\"deploy.sh: $label\"},\"relationships\":{\"workspace\":{\"data\":{\"type\":\"workspaces\",\"id\":\"$wsid\"}}}}}" | jq -r '.data.id // empty')
  [ -n "$r" ] || { warn "could not queue a run"; return 1; }
  info "run: $(run_url "$wsname" "$r")"
  s=$(wait_run "$r" 'planned|planned_and_finished|policy_checked|cost_estimated|errored|canceled|discarded')
  case $s in
    planned_and_finished) info "no changes"; return 0 ;;
    errored|canceled|discarded) warn "plan $s - see the run URL above"; return 1 ;;
  esac
  info "plan: $(plan_summary "$r") (add ~change -destroy)"
  confirm "Apply this plan?" || { api POST "/runs/$r/actions/discard" '{}' >/dev/null; warn "discarded"; return 1; }
  api POST "/runs/$r/actions/apply" '{}' >/dev/null
  info "applying (infra takes ~15-25 minutes; RDS is the slow part)..."
  s=$(wait_run "$r" 'applied|errored|canceled')
  [ "$s" = applied ] || { warn "apply $s - see the run URL above"; return 1; }
}

# ------------------------------------------------------------------------------
deploy_workspace "AWS infrastructure" infra "$WS_INFRA" "$INFRA_ID" || die "Infrastructure deployment failed."

step "Waiting for both Boundary workers to connect"
export BOUNDARY_ADDR; BOUNDARY_ADDR=$(terraform -chdir=infra output -raw boundary_controller_url)
REC=$(mktemp); trap 'rm -f "$REC"' EXIT; chmod 600 "$REC"
printf 'kms "aead" {\n  purpose   = "recovery"\n  aead_type = "aes-gcm"\n  key       = "%s"\n  key_id    = "global_recovery"\n}\n' \
  "$(terraform -chdir=infra output -raw boundary_recovery_key)" > "$REC"
for i in $(seq 1 90); do
  n=$(boundary workers list -recovery-config "$REC" -format json 2>/dev/null \
      | jq --arg now "$(date -u +%s)" '[.items[]? | select((.last_status_time | sub("\\.[0-9]+Z$"; "Z") | fromdate) > (($now|tonumber) - 90))] | length' 2>/dev/null || echo 0)
  [ "${n:-0}" -ge 2 ] && { info "both workers connected"; break; }
  [ $((i % 6)) = 0 ] && info "connected workers: ${n:-0}/2 (waiting; first boot installs packages)..."
  sleep 10
done
[ "${n:-0}" -ge 2 ] || warn "Workers not both connected after 15 minutes; continuing (session recording setup may fail)."

if ! deploy_workspace "Boundary configuration" boundary-config "$WS_CONFIG" "$CONFIG_ID"; then
  warn "Retrying the Boundary configuration once in 60 seconds (workers may still be settling)..."
  sleep 60
  deploy_workspace "Boundary configuration (retry)" boundary-config "$WS_CONFIG" "$CONFIG_ID" || die "Boundary configuration failed."
fi

# Run trigger so future infra applies re-run the config (VCS workflow only)
if [ "$WORKFLOW" = vcs ]; then
  if ! api GET "/workspaces/$CONFIG_ID/run-triggers?filter%5Brun-trigger%5D%5Btype%5D=inbound" | jq -e --arg s "$INFRA_ID" '.data[] | select(.relationships.sourceable.data.id==$s)' >/dev/null; then
    api POST "/workspaces/$CONFIG_ID/run-triggers" "{\"data\":{\"relationships\":{\"sourceable\":{\"data\":{\"id\":\"$INFRA_ID\",\"type\":\"workspaces\"}}}}}" >/dev/null
    info "run trigger: $WS_INFRA -> $WS_CONFIG"
  fi
fi

# ------------------------------------------------------------------------------
step "Writing DEMO.md"
rm -f boundary_demo_targets.json
"$REPO_ROOT/scripts/generate-demo-doc.sh"

echo -e "\n${GREEN}${BOLD}Deployment complete.${NC} Open ${BOLD}DEMO.md${NC} for IPs, URLs, credentials and the demo walkthrough."
echo "Start the demo with: ./scripts/demo-menu.sh"
