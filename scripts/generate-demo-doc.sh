#!/usr/bin/env bash
# ==============================================================================
# Write DEMO.md: IPs, URLs, IDs, credentials and the demo walkthrough for the
# currently deployed environment. Re-run any time (e.g. after a redeploy, since
# passwords and IPs change). DEMO.md contains live credentials and is gitignored.
#
# Run from the repository root:   ./scripts/generate-demo-doc.sh
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-DEMO.md}

CFG=$(terraform -chdir=boundary-config output -json 2>/dev/null) || CFG='{}'
INF=$(terraform -chdir=infra output -json 2>/dev/null) || INF='{}'
[ "$(jq 'length' <<<"$INF")" -gt 0 ] || { echo "No infra outputs found. Deploy first (./scripts/deploy.sh) and make sure 'terraform -chdir=infra init' works." >&2; exit 1; }
[ "$(jq 'length' <<<"$CFG")" -gt 0 ] || echo "Warning: no Boundary config outputs yet - Boundary IDs and logins will be missing." >&2

i() { jq -r --arg k "$1" '.[$k].value // "n/a" | if type == "string" then . else tojson end' <<<"$INF"; }
c() { jq -r --arg k "$1" '.[$k].value // "n/a" | if type == "string" then . else tojson end' <<<"$CFG"; }
upw() { jq -r --arg u "$1" '.user_passwords.value[$u] // "n/a"' <<<"$CFG"; }
lpw() { jq -r --arg u "$1" '.ldap_users.value[$u].password // "n/a"' <<<"$INF"; }
lgrp() { jq -r --arg u "$1" '.ldap_users.value[$u].group // "n/a"' <<<"$INF"; }

ORG_SETTINGS=""
[ -f .deploy.env ] && ORG_SETTINGS=$(. ./.deploy.env; echo "HCP Terraform org \`$TFC_ORG\`, workspaces \`$WS_INFRA\` / \`$WS_CONFIG\` ($WORKFLOW workflow)")

LDAP_ROWS=$(jq -r '.ldap_users.value // {} | to_entries[] |
  "| **\(.key)** | `\(.value.password)` | corp-ldap | " +
  (if .value.group == "boundary-admins" then "Admin (boundary-admins): everything, incl. Grafana, Prometheus, recordings" else "boundary-users: SSH, RDP, Postgres, web portal (no Grafana)" end) + " |"' <<<"$INF")

cat > "$OUT" <<EOF
# Boundary Enterprise Demo: Runbook

> Generated $(date -u '+%Y-%m-%d %H:%M UTC') by \`scripts/generate-demo-doc.sh\`. ${ORG_SETTINGS}
> **Contains live credentials. Do not commit or share.** Re-generate after every redeploy (IPs and passwords change).

## Environment

| Component | Address |
| :--- | :--- |
| **Boundary Admin UI / API** | **$(i boundary_controller_url)** |
| Controller | public \`$(i boundary_controller_public_ip)\`, private \`$(i boundary_controller_private_ip)\` |
| Ingress worker (public subnet) | public \`$(i boundary_ingress_worker_public_ip)\`, private \`$(i boundary_ingress_worker_private_ip)\` (proxy :9202) |
| Egress worker (private subnet) | \`$(i boundary_egress_worker_private_ip)\` |
| Linux target (SSH 22, web 8080) | \`$(i linux_target_private_ip)\` |
| Windows target (RDP 3389) | \`$(i windows_target_private_ip)\` |
| RDS PostgreSQL (Boundary DB + \`appdb\`) | \`$(i rds_endpoint)\` |
| Ops: OpenLDAP 389, Prometheus 9090, Grafana 3000 | \`$(i ops_private_ip)\` |
| Outbound (NAT) public IP | \`$(i nat_public_ip)\` |
| Session recording bucket | \`$(i session_recording_bucket)\` ($(i aws_region)) |
| VPC | \`$(i vpc_id)\` |

| Boundary resource | ID |
| :--- | :--- |
| Org (Demo-Org) / Project (Core-Infrastructure) | \`$(c org_id)\` / \`$(c project_id)\` |
| Auth method corp-password-auth | \`$(c auth_method_id)\` |
| Auth method corp-ldap (primary) | \`$(c ldap_auth_method_id)\` |
| linux-ssh-target (ssh, injected creds, recorded) | \`$(c linux_ssh_target_id)\` |
| windows-rdp-target | \`$(c windows_rdp_target_id)\` |
| rds-postgres-target | \`$(c rds_postgres_target_id)\` |
| internal-web-target | \`$(c web_target_id)\` |
| grafana-target / prometheus-target | \`$(c grafana_target_id)\` / \`$(c prometheus_target_id)\` |
| Storage bucket (recordings) | \`$(c storage_bucket_id)\` |

## 1. Start the demo menu

Run everything from your terminal in the repository folder:

\`\`\`bash
cd $(pwd)
./scripts/demo-menu.sh
\`\`\`

The menu reads target IDs and passwords from Terraform automatically.

| Option | What it does |
| :--- | :--- |
| 1-4 | Log in as \`admin\`, \`devops\`, \`sysadmin\` or \`analyst\` (password logins) |
| l | Log in as an LDAP user; type \`alice\`, \`bob\`, \`carol\`, \`dave\` or \`erin\` |
| 5 | SSH to the private Linux box. No password prompt, and the session is recorded |
| 6 | RDP to Windows (needs the Windows App / Microsoft Remote Desktop on your Mac) |
| 7 | Postgres, then run \`SELECT * FROM demo_customers;\` |
| 8 | Web portal, then open http://127.0.0.1:8080 |
| g / p | Grafana / Prometheus (admins only) |
| r | List session recordings (admins only) |

Each run of the menu does one action and exits, and your login is remembered. Run it once to log in, then again to connect.

If a menu login fails, log in directly and type the password when prompted:

\`\`\`bash
export BOUNDARY_ADDR=$(i boundary_controller_url)
boundary authenticate password -auth-method-id $(c auth_method_id) -login-name admin
boundary authenticate ldap     -auth-method-id $(c ldap_auth_method_id) -login-name alice
\`\`\`

## 2. Credentials

**Boundary Admin UI:** $(i boundary_controller_url), sign in to org **Demo-Org**

| Login | Password | Sign-in method | Access |
| :--- | :--- | :--- | :--- |
| **admin** | \`$(upw admin)\` | corp-password-auth | Full admin (incl. session recordings) |
| devops | \`$(upw devops)\` | corp-password-auth | SSH, web portal |
| sysadmin | \`$(upw sysadmin)\` | corp-password-auth | RDP |
| analyst | \`$(upw analyst)\` | corp-password-auth | Postgres |
${LDAP_ROWS}

Boundary injects or brokers the target logins for you. You only type one yourself for RDP, if the client asks:

| Target | Username | Password |
| :--- | :--- | :--- |
| Windows RDP | Administrator | \`$(i windows_admin_password)\` |
| Linux SSH (injected, never shown to users) | boundary-user | \`$(i linux_ssh_password)\` |
| Postgres \`appdb\` (brokered) | demouser | \`$(i demo_db_password)\` |

## 3. Grafana and the Login Time Report

1. Run the menu and log in as an admin: **1** (\`admin\`), or **l** then \`alice\`.
2. Run the menu again and choose **g**. Keep that terminal open; it is the tunnel.
3. Open **http://127.0.0.1:3000** and sign in as **\`admin\` / \`$(i grafana_admin_password)\`**.
4. The home page is **Boundary - Login Time Report**:
   - **Time logged in per user:** each user's number of logins, time logged in, time on targets, first and last activity, and whether they are still logged in.
   - **Chart:** minutes per user.
   - **Every login:** each login with its own duration.
   - **Time range:** top right; the default is the last 7 days.
5. The other dashboards are under **Dashboards > Boundary**: **User Activity** and **Cluster Metrics**.

Login durations are approximate, because Boundary only refreshes "last activity" every few minutes, so a short login can show 0. Time on targets (SSH, RDP, Postgres, web) is exact. To give the report something to show, log in as two or three users and open a few sessions first.

## 4. Suggested demo order

1. **Least privilege:** log in as \`carol\` (**l**), then **5** SSH works and **g** Grafana is denied.
2. **Admin:** log in as \`alice\`, then **5** SSH, run a few commands, then \`exit\`.
3. **Database:** **7** Postgres, as \`carol\` or \`analyst\`.
4. **Report:** **g** Grafana. The report shows alice's and carol's logins and time.
5. **Recording:** **r** lists recordings. Play them back in the Admin UI (section 5).

## 5. View session recordings in the Admin UI

1. Open $(i boundary_controller_url) (reload the page if you were already signed in).
2. On the sign-in page, choose the scope **Demo-Org** (not Global), then an auth method:
   - **corp-password-auth:** \`admin\` / \`$(upw admin)\`, or
   - **corp-ldap:** \`alice\` / \`$(lpw alice)\` (\`bob\` also works; both are boundary-admins).
3. Go back to the **Global** level: click **Global** or **Home** in the scope switcher at the top left.
4. Click **Session Recordings** in the left sidebar.
5. Click a recording to see its user, target, time and duration, then **Play** to replay the SSH session, or **Download**.

## Good to know

- **Only SSH sessions are recorded**, on \`linux-ssh-target\` (menu option 5). Boundary 0.19 records SSH only, so RDP, Postgres and web-portal sessions show in the Login Time Report but have no recording.
- **Recordings appear after the session ends**, once the worker has uploaded them. Open an SSH session, run a few commands, \`exit\`, then refresh the list.
- **Who can view recordings:** \`admin\`, \`alice\` and \`bob\`. \`carol\`, \`dave\` and \`erin\` (boundary-users) cannot.
- **Provider quirk:** the storage bucket shows a small "update" in every config plan. It is a provider-internal field (\`internal_force_update\`), not a real change, so it is safe to apply.
- **Cost:** about \$0.45-0.50 an hour while deployed. Tear down by queueing a destroy on the config workspace first, then the infra workspace.
EOF
chmod 600 "$OUT"
echo "Wrote $OUT (contains live credentials; gitignored)."
