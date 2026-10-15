#!/usr/bin/env bash
# ==============================================================================
# Update the AWS credentials on the infra workspace (e.g. when temporary
# credentials expire). Uses AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY /
# AWS_SESSION_TOKEN from your environment if set, otherwise prompts.
# Secrets are stored as sensitive workspace variables and never printed.
#
# Run from the repository root:   ./scripts/set-aws-credentials.sh
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

TFC_HOST=app.terraform.io; TFC_ORG=Amit_TFC; WS_INFRA=boundary-demo-infra
# shellcheck disable=SC1091
[ -f .deploy.env ] && source ./.deploy.env

TFC_TOKEN=$(jq -r --arg h "$TFC_HOST" '.credentials[$h].token // empty' ~/.terraform.d/credentials.tfrc.json 2>/dev/null || true)
[ -n "$TFC_TOKEN" ] || { read -r -s -p "HCP Terraform API token: " TFC_TOKEN; echo; }

KEY_ID=${AWS_ACCESS_KEY_ID:-}; SECRET=${AWS_SECRET_ACCESS_KEY:-}; SESSION=${AWS_SESSION_TOKEN:-}
if [ -z "$KEY_ID" ] || [ -z "$SECRET" ]; then
  read -r -p "AWS access key ID: " KEY_ID
  read -r -s -p "AWS secret access key: " SECRET; echo
  read -r -s -p "AWS session token (Enter if none): " SESSION; echo
else
  echo "Using AWS credentials from your environment (key ${KEY_ID:0:4}…${KEY_ID: -4})."
fi
[ -n "$KEY_ID" ] && [ -n "$SECRET" ] || { echo "Access key ID and secret are required." >&2; exit 1; }

api() {
  local m=$1 p=$2 b=${3:-}
  curl -sS -X "$m" -H "Authorization: Bearer $TFC_TOKEN" -H "Content-Type: application/vnd.api+json" ${b:+--data "$b"} "https://$TFC_HOST/api/v2$p"
}
WS=$(api GET "/organizations/$TFC_ORG/workspaces/$WS_INFRA" | jq -r '.data.id // empty')
[ -n "$WS" ] || { echo "Workspace $TFC_ORG/$WS_INFRA not found." >&2; exit 1; }
VARS=$(api GET "/workspaces/$WS/vars")

set_env() { # key value sensitive
  local vid body
  vid=$(jq -r --arg k "$1" '.data[] | select(.attributes.key==$k and .attributes.category=="env") | .id' <<<"$VARS" | head -1)
  body=$(jq -n --arg k "$1" --arg v "$2" --argjson s "$3" '{data: {type: "vars", attributes: {key: $k, value: $v, category: "env", hcl: false, sensitive: $s}}}')
  if [ -n "$vid" ]; then api PATCH "/workspaces/$WS/vars/$vid" "$body" >/dev/null; else api POST "/workspaces/$WS/vars" "$body" >/dev/null; fi
  echo "  set $1"
}
del_env() {
  local vid; vid=$(jq -r --arg k "$1" '.data[] | select(.attributes.key==$k and .attributes.category=="env") | .id' <<<"$VARS" | head -1)
  if [ -n "$vid" ]; then api DELETE "/workspaces/$WS/vars/$vid" >/dev/null; echo "  removed $1"; fi
}

echo "Updating $TFC_ORG/$WS_INFRA:"
set_env AWS_ACCESS_KEY_ID "$KEY_ID" false
set_env AWS_SECRET_ACCESS_KEY "$SECRET" true
if [ -n "$SESSION" ]; then set_env AWS_SESSION_TOKEN "$SESSION" true; else del_env AWS_SESSION_TOKEN; fi
del_env AWS_SESSION_EXPIRATION
echo "Done."
