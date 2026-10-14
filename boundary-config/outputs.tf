output "boundary_addr" {
  description = "Boundary Controller API / UI address"
  value       = local.infra.boundary_controller_url
}

output "org_id" {
  description = "Demo Organization Scope ID"
  value       = boundary_scope.org.id
}

output "project_id" {
  description = "Core Infrastructure Project Scope ID"
  value       = boundary_scope.project.id
}

output "auth_method_id" {
  description = "Password Auth Method ID"
  value       = boundary_auth_method.password.id
}

output "linux_ssh_target_id" {
  description = "Boundary Target ID for Linux SSH"
  value       = boundary_target.linux_ssh.id
}

output "windows_rdp_target_id" {
  description = "Boundary Target ID for Windows RDP"
  value       = boundary_target.windows_rdp.id
}

output "rds_postgres_target_id" {
  description = "Boundary Target ID for RDS PostgreSQL"
  value       = boundary_target.rds_postgres.id
}

output "web_target_id" {
  description = "Boundary Target ID for Internal Web Portal"
  value       = boundary_target.internal_web.id
}

output "user_passwords" {
  description = "Generated passwords for the demo Boundary login accounts (admin, devops, sysadmin, analyst)"
  value       = { for u in local.demo_users : u => random_password.user[u].result }
  sensitive   = true
}

output "storage_bucket_id" {
  description = "Boundary storage bucket ID for session recordings"
  value       = boundary_storage_bucket.session_recordings.id
}

output "ldap_auth_method_id" {
  description = "LDAP Auth Method ID (primary for Demo-Org)"
  value       = boundary_auth_method_ldap.corp.id
}

output "grafana_target_id" {
  description = "Boundary Target ID for Grafana (admins only)"
  value       = boundary_target.grafana.id
}

output "prometheus_target_id" {
  description = "Boundary Target ID for Prometheus (admins only)"
  value       = boundary_target.prometheus.id
}
