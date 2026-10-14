# Boundary Demo — Quick Start

| Step | Action | Where |
| :--- | :--- | :--- |
| **1** | Deploy AWS infra | HCP Terraform → `boundary-demo-infra` → New run → Apply |
| **2** | Configure Boundary | `boundary-demo-config` (auto-queued by run trigger) → Apply |
| **3** | Init local CLI once | `terraform -chdir=infra init && terraform -chdir=boundary-config init` |
| **4** | Launch demo menu | `./scripts/demo-menu.sh` |
| **5** | Tear down | Destroy `boundary-demo-config`, then `boundary-demo-infra` |

## Pre-flight

```bash
terraform version     # >= 1.5
terraform login       # HCP Terraform token
boundary version
jq --version
```

The `boundary-demo-infra` workspace needs the `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables and the sensitive `boundary_license` Terraform variable (Boundary Enterprise license). See [README → HCP Terraform Setup](README.md#hcp-terraform-setup).

## What gets created

- VPC with a public subnet and two private subnets
- t3.nano NAT instance (or a NAT Gateway with `enable_nat_gateway = true`)
- Boundary **Enterprise** controller and ingress worker (public), egress worker (private)
- Private S3 bucket for session recordings (gateway VPC endpoint, dynamic IAM credentials)
- Private targets: Linux (SSH + web on 8080), Windows Server 2022 (RDP), RDS PostgreSQL
- Private ops instance: OpenLDAP, Prometheus, Grafana (reached through Boundary)
- Boundary org/project, LDAP auth (2 groups) + password auth (4 personas), credential store, 6 multi-hop targets, RBAC

## Demo flow

1. `./scripts/demo-menu.sh` → **1** (login as admin) → **5** (SSH). You get a shell on a private instance with no public IP and no internet-facing port 22, **without being asked for a password** (credential injection). Type a few commands, then `exit`.
2. **6** (RDP). Log in as `Administrator` with `terraform -chdir=infra output -raw windows_admin_password`.
3. **7** (Postgres) → `SELECT * FROM demo_customers;`
4. **8** (Web). Open http://127.0.0.1:8080.
5. RBAC: **4** (login as analyst) → **7** works, **5** is denied.
6. LDAP: **l** → `carol` (boundary-users) → **5** works, **g** is denied. **l** → `alice` (boundary-admins) → **g** opens Grafana.
7. Grafana: **Boundary - User Activity** shows the logins and session hours you just generated.
8. Session recording: log in as admin → **r** lists recordings. Play back the SSH session from step 1 in the Admin UI (**Demo-Org → Session Recordings**).

## Web UI

Open the `boundary_addr` output → **Demo-Org** → **corp-password-auth**, and log in as `admin` with the password from `terraform -chdir=boundary-config output -json user_passwords`. Or choose **corp-ldap** and log in as an LDAP user (`terraform -chdir=infra output -json ldap_users`).

## Troubleshooting

| Problem | Check |
| :--- | :--- |
| Infra apply fails on `terraform_data.controller_ready` | The controller did not come up. Read `terraform -chdir=infra output -raw controller_boot_diagnostics` (scrubbed boot log), or open an SSM session to the controller and check `/var/log/cloud-init-output.log` |
| Config run can't reach controller | `authorized_client_cidr` must allow HCP Terraform runners (default `0.0.0.0/0`) |
| Config run: remote state access denied | Enable remote state sharing on `boundary-demo-infra` for `boundary-demo-config` |
| Stale demo IDs in menu | Delete `boundary_demo_targets.json` and re-run the menu |
| `boundary-demo-config` fails creating the storage bucket | Workers can't reach S3 or assume the recording role. Check `boundary workers list` and that the workers have the `storage=s3` tag |
| LDAP login fails | SSM into the `Ops` instance → `sudo docker compose -f /opt/ops/docker-compose.yml logs openldap` |
| Grafana user-activity panels empty | Nobody has logged in during the time range, or the controller's `grafana_ro` step failed (check its `/var/log/cloud-init-output.log`) |
