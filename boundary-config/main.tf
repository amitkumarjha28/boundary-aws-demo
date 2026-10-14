# -------------------------------------------------------------------------
# Boundary Scopes: Organization & Project
# -------------------------------------------------------------------------

resource "boundary_scope" "org" {
  name                     = "Demo-Org"
  description              = "HashiCorp Boundary Enterprise Demo Organization"
  scope_id                 = "global"
  auto_create_admin_role   = true
  auto_create_default_role = true
}

resource "boundary_scope" "project" {
  name                   = "Core-Infrastructure"
  description            = "Private Subnet Core Workloads"
  scope_id               = boundary_scope.org.id
  auto_create_admin_role = true
}

# -------------------------------------------------------------------------
# Password Authentication Method & Accounts
# Passwords are generated per deployment; see `terraform output user_passwords`
# -------------------------------------------------------------------------

locals {
  demo_users = toset(["admin", "devops", "sysadmin", "analyst"])
}

resource "random_password" "user" {
  for_each         = local.demo_users
  length           = 16
  override_special = "!-_+="
}

resource "boundary_auth_method" "password" {
  name        = "corp-password-auth"
  description = "Corporate Password Authentication"
  scope_id    = boundary_scope.org.id
  type        = "password"
}

resource "boundary_account_password" "admin" {
  auth_method_id = boundary_auth_method.password.id
  login_name     = "admin"
  password       = random_password.user["admin"].result
  name           = "Admin Account"
}

resource "boundary_user" "admin" {
  name        = "boundary-admin"
  description = "Cluster Administrator"
  account_ids = [boundary_account_password.admin.id]
  scope_id    = boundary_scope.org.id
}

resource "boundary_account_password" "devops" {
  auth_method_id = boundary_auth_method.password.id
  login_name     = "devops"
  password       = random_password.user["devops"].result
  name           = "DevOps Engineer Account"
}

resource "boundary_user" "devops" {
  name        = "devops-engineer"
  description = "DevOps Engineer"
  account_ids = [boundary_account_password.devops.id]
  scope_id    = boundary_scope.org.id
}

resource "boundary_account_password" "sysadmin" {
  auth_method_id = boundary_auth_method.password.id
  login_name     = "sysadmin"
  password       = random_password.user["sysadmin"].result
  name           = "SysAdmin Account"
}

resource "boundary_user" "sysadmin" {
  name        = "windows-sysadmin"
  description = "Windows Systems Administrator"
  account_ids = [boundary_account_password.sysadmin.id]
  scope_id    = boundary_scope.org.id
}

resource "boundary_account_password" "analyst" {
  auth_method_id = boundary_auth_method.password.id
  login_name     = "analyst"
  password       = random_password.user["analyst"].result
  name           = "Data Analyst Account"
}

resource "boundary_user" "analyst" {
  name        = "data-analyst"
  description = "Data Analyst"
  account_ids = [boundary_account_password.analyst.id]
  scope_id    = boundary_scope.org.id
}

# -------------------------------------------------------------------------
# Host Catalog, Host Sets & Hosts
# -------------------------------------------------------------------------

resource "boundary_host_catalog_static" "aws_private" {
  name        = "aws-private-catalog"
  description = "AWS Private Subnet Infrastructure"
  scope_id    = boundary_scope.project.id
}

# 1. Linux Host
resource "boundary_host_static" "linux" {
  name            = "linux-private-target"
  description     = "Amazon Linux 2023 EC2 in Private Subnet"
  address         = local.infra.linux_target_private_ip
  host_catalog_id = boundary_host_catalog_static.aws_private.id
}

resource "boundary_host_set_static" "linux" {
  name            = "linux-host-set"
  host_catalog_id = boundary_host_catalog_static.aws_private.id
  host_ids        = [boundary_host_static.linux.id]
}

# 2. Windows Host
resource "boundary_host_static" "windows" {
  name            = "windows-private-target"
  description     = "Windows Server 2022 EC2 in Private Subnet"
  address         = local.infra.windows_target_private_ip
  host_catalog_id = boundary_host_catalog_static.aws_private.id
}

resource "boundary_host_set_static" "windows" {
  name            = "windows-host-set"
  host_catalog_id = boundary_host_catalog_static.aws_private.id
  host_ids        = [boundary_host_static.windows.id]
}

# 3. RDS Host
resource "boundary_host_static" "rds" {
  name            = "rds-postgres-target"
  description     = "RDS PostgreSQL Instance in Private Subnet"
  address         = local.infra.rds_endpoint_address
  host_catalog_id = boundary_host_catalog_static.aws_private.id
}

resource "boundary_host_set_static" "rds" {
  name            = "rds-host-set"
  host_catalog_id = boundary_host_catalog_static.aws_private.id
  host_ids        = [boundary_host_static.rds.id]
}

# -------------------------------------------------------------------------
# Credential Store & Static Credentials
# -------------------------------------------------------------------------

resource "boundary_credential_store_static" "demo_store" {
  name        = "demo-static-credentials"
  description = "Static Credential Store for Demo Targets"
  scope_id    = boundary_scope.project.id
}

resource "boundary_credential_username_password" "linux_ssh" {
  name                = "linux-ssh-cred"
  description         = "Linux SSH credentials"
  credential_store_id = boundary_credential_store_static.demo_store.id
  username            = "boundary-user"
  password            = local.infra.linux_ssh_password
}

resource "boundary_credential_username_password" "windows_rdp" {
  name                = "windows-rdp-cred"
  description         = "Windows Server Administrator credentials"
  credential_store_id = boundary_credential_store_static.demo_store.id
  username            = "Administrator"
  password            = local.infra.windows_admin_password
}

resource "boundary_credential_username_password" "rds_postgres" {
  name                = "rds-postgres-cred"
  description         = "RDS PostgreSQL demouser credentials"
  credential_store_id = boundary_credential_store_static.demo_store.id
  username            = "demouser"
  password            = local.infra.demo_db_password
}

# -------------------------------------------------------------------------
# Targets: Multi-Hop (Ingress -> Egress Worker Filtering)
# -------------------------------------------------------------------------

locals {
  ingress_filter = "\"ingress\" in \"/tags/type\""
  egress_filter  = "\"egress\" in \"/tags/type\""
}

# 1. Linux SSH Target (Port 22)
resource "boundary_target" "linux_ssh" {
  name                           = "linux-ssh-target"
  description                    = "Secure SSH Access via Boundary Multi-Hop"
  type                           = "tcp"
  default_port                   = 22
  scope_id                       = boundary_scope.project.id
  ingress_worker_filter          = local.ingress_filter
  egress_worker_filter           = local.egress_filter
  host_source_ids                = [boundary_host_set_static.linux.id]
  brokered_credential_source_ids = [boundary_credential_username_password.linux_ssh.id]
}

# 2. Windows RDP Target (Port 3389)
resource "boundary_target" "windows_rdp" {
  name                           = "windows-rdp-target"
  description                    = "Secure RDP Desktop Access via Boundary Multi-Hop"
  type                           = "tcp"
  default_port                   = 3389
  scope_id                       = boundary_scope.project.id
  ingress_worker_filter          = local.ingress_filter
  egress_worker_filter           = local.egress_filter
  host_source_ids                = [boundary_host_set_static.windows.id]
  brokered_credential_source_ids = [boundary_credential_username_password.windows_rdp.id]
}

# 3. RDS PostgreSQL Target (Port 5432)
resource "boundary_target" "rds_postgres" {
  name                           = "rds-postgres-target"
  description                    = "Secure PostgreSQL Database Access via Boundary Multi-Hop"
  type                           = "tcp"
  default_port                   = 5432
  scope_id                       = boundary_scope.project.id
  ingress_worker_filter          = local.ingress_filter
  egress_worker_filter           = local.egress_filter
  host_source_ids                = [boundary_host_set_static.rds.id]
  brokered_credential_source_ids = [boundary_credential_username_password.rds_postgres.id]
}

# 4. Web Application Target (Port 8080)
resource "boundary_target" "internal_web" {
  name                  = "internal-web-target"
  description           = "Secure Tunnel to Internal Corporate Portal via Boundary Multi-Hop"
  type                  = "tcp"
  default_port          = 8080
  scope_id              = boundary_scope.project.id
  ingress_worker_filter = local.ingress_filter
  egress_worker_filter  = local.egress_filter
  host_source_ids       = [boundary_host_set_static.linux.id]
}

# -------------------------------------------------------------------------
# RBAC: Granular Roles
# -------------------------------------------------------------------------

# Org Admin Role (full access to the org and its projects)
resource "boundary_role" "org_admin" {
  name            = "org-admin-role"
  description     = "Full administrative access to Demo-Org and its projects (admin user + LDAP boundary-admins)"
  scope_id        = boundary_scope.org.id
  grant_scope_ids = ["this", "descendants"]
  principal_ids   = [boundary_user.admin.id, boundary_managed_group_ldap.admins.id]
  grant_strings   = ["ids=*;type=*;actions=*"]
}

# DevOps Role
resource "boundary_role" "devops" {
  name          = "devops-role"
  description   = "Allows DevOps to connect to Linux SSH and Web Target"
  scope_id      = boundary_scope.project.id
  principal_ids = [boundary_user.devops.id]
  grant_strings = [
    "ids=${boundary_target.linux_ssh.id};actions=read,authorize-session",
    "ids=${boundary_target.internal_web.id};actions=read,authorize-session"
  ]
}

# Windows SysAdmin Role
resource "boundary_role" "sysadmin" {
  name          = "sysadmin-role"
  description   = "Allows SysAdmin to connect to Windows RDP Target"
  scope_id      = boundary_scope.project.id
  principal_ids = [boundary_user.sysadmin.id]
  grant_strings = [
    "ids=${boundary_target.windows_rdp.id};actions=read,authorize-session"
  ]
}

# Data Analyst Role
resource "boundary_role" "analyst" {
  name          = "analyst-role"
  description   = "Allows Data Analyst to connect to RDS PostgreSQL Target"
  scope_id      = boundary_scope.project.id
  principal_ids = [boundary_user.analyst.id]
  grant_strings = [
    "ids=${boundary_target.rds_postgres.id};actions=read,authorize-session"
  ]
}
