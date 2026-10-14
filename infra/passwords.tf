# -------------------------------------------------------------------------
# Demo credentials
# Generated per deployment so no secrets live in the repository.
# Override any of them with the matching variable (set it as a sensitive
# variable in the HCP Terraform workspace). Retrieve them with:
#   terraform output -raw <name>
# Special characters are limited to ones safe inside PostgreSQL URLs,
# SQL string literals, shell and PowerShell double-quoted strings.
# -------------------------------------------------------------------------

locals {
  safe_special = "!-_+="
}

resource "random_password" "rds" {
  length           = 20
  override_special = local.safe_special
}

resource "random_password" "windows_admin" {
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = local.safe_special
}

resource "random_password" "linux_ssh" {
  length           = 20
  override_special = local.safe_special
}

resource "random_password" "demo_db_user" {
  length           = 20
  override_special = local.safe_special
}

locals {
  rds_password           = coalesce(var.rds_password, random_password.rds.result)
  windows_admin_password = coalesce(var.windows_admin_password, random_password.windows_admin.result)
  linux_ssh_password     = coalesce(var.linux_ssh_password, random_password.linux_ssh.result)
  demo_db_password       = coalesce(var.demo_db_password, random_password.demo_db_user.result)
}
