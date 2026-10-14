# -------------------------------------------------------------------------
# LDAP Authentication (OpenLDAP on the ops instance)
# Group membership in LDAP decides Boundary permissions via managed groups:
#   boundary-admins -> org admin       boundary-users -> connect to demo targets
# -------------------------------------------------------------------------

resource "boundary_auth_method_ldap" "corp" {
  name          = "corp-ldap"
  description   = "Corporate LDAP directory"
  scope_id      = boundary_scope.org.id
  state         = "active-public"
  urls          = [local.infra.ldap.url]
  user_dn       = local.infra.ldap.user_dn
  user_attr     = "uid"
  group_dn      = local.infra.ldap.group_dn
  group_attr    = "cn"
  enable_groups = true
  bind_dn       = local.infra.ldap.bind_dn
  bind_password = local.infra.ldap_bind_password

  # Primary auth method: Boundary auto-creates a user on first LDAP login
  is_primary_for_scope = true

  account_attribute_maps = ["cn=fullName", "mail=email"]
}

resource "boundary_managed_group_ldap" "admins" {
  name           = "ldap-boundary-admins"
  description    = "Members of the LDAP boundary-admins group"
  auth_method_id = boundary_auth_method_ldap.corp.id
  group_names    = ["boundary-admins"]
}

resource "boundary_managed_group_ldap" "users" {
  name           = "ldap-boundary-users"
  description    = "Members of the LDAP boundary-users group"
  auth_method_id = boundary_auth_method_ldap.corp.id
  group_names    = ["boundary-users"]
}

# LDAP users: connect to all demo targets (no admin rights)
resource "boundary_role" "ldap_users" {
  name          = "ldap-users-role"
  description   = "LDAP boundary-users: connect to the demo targets"
  scope_id      = boundary_scope.project.id
  principal_ids = [boundary_managed_group_ldap.users.id]
  grant_strings = [
    for t in [
      boundary_target.linux_ssh,
      boundary_target.windows_rdp,
      boundary_target.rds_postgres,
      boundary_target.internal_web,
    ] : "ids=${t.id};actions=read,authorize-session"
  ]
}

# -------------------------------------------------------------------------
# Monitoring Targets (admins only, via org-admin-role)
# -------------------------------------------------------------------------

resource "boundary_host_static" "ops" {
  name            = "ops-private-host"
  description     = "Ops instance: OpenLDAP, Prometheus, Grafana"
  address         = local.infra.ops_private_ip
  host_catalog_id = boundary_host_catalog_static.aws_private.id
}

resource "boundary_host_set_static" "ops" {
  name            = "ops-host-set"
  host_catalog_id = boundary_host_catalog_static.aws_private.id
  host_ids        = [boundary_host_static.ops.id]
}

resource "boundary_target" "grafana" {
  name                  = "grafana-target"
  description           = "Grafana dashboards (Boundary metrics & user activity)"
  type                  = "tcp"
  default_port          = 3000
  scope_id              = boundary_scope.project.id
  ingress_worker_filter = local.ingress_filter
  egress_worker_filter  = local.egress_filter
  host_source_ids       = [boundary_host_set_static.ops.id]
}

resource "boundary_target" "prometheus" {
  name                  = "prometheus-target"
  description           = "Prometheus UI"
  type                  = "tcp"
  default_port          = 9090
  scope_id              = boundary_scope.project.id
  ingress_worker_filter = local.ingress_filter
  egress_worker_filter  = local.egress_filter
  host_source_ids       = [boundary_host_set_static.ops.id]
}
