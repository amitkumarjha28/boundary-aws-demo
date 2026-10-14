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

The `boundary-demo-infra` workspace needs the `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables. See [README → HCP Terraform Setup](README.md#hcp-terraform-setup).

## What gets created

- VPC with a public subnet and two private subnets
- t3.nano NAT instance (or a NAT Gateway with `enable_nat_gateway = true`)
- Boundary controller and ingress worker (public), egress worker (private)
- Private targets: Linux (SSH + web on 8080), Windows Server 2022 (RDP), RDS PostgreSQL
- Boundary org/project, password auth, 4 personas, credential store, 4 multi-hop targets, RBAC

## Demo flow

1. `./scripts/demo-menu.sh` → **1** (login as admin) → **5** (SSH). You get a shell on a private instance with no public IP and no internet-facing port 22.
2. **6** (RDP). Log in as `Administrator` with `terraform -chdir=infra output -raw windows_admin_password`.
3. **7** (Postgres) → `SELECT * FROM demo_customers;`
4. **8** (Web). Open the printed `127.0.0.1` URL.
5. RBAC: **4** (login as analyst) → **7** works, **5** is denied.

## Web UI

Open the `boundary_addr` output → **Demo-Org** → **corp-password-auth**, and log in as `admin` with the password from `terraform -chdir=boundary-config output -json user_passwords`.

## Troubleshooting

| Problem | Check |
| :--- | :--- |
| Infra apply stuck on `data.http.controller_health` | Controller user-data still running or failed. Open an SSM session to the controller and check `/var/log/cloud-init-output.log` |
| Config run can't reach controller | `authorized_client_cidr` must allow HCP Terraform runners (default `0.0.0.0/0`) |
| Config run: remote state access denied | Enable remote state sharing on `boundary-demo-infra` for `boundary-demo-config` |
| Stale demo IDs in menu | Delete `boundary_demo_targets.json` and re-run the menu |
