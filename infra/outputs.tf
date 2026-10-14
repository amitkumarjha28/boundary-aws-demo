output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "boundary_controller_public_ip" {
  description = "Public IP of Boundary Controller"
  value       = aws_instance.controller.public_ip
}

output "boundary_controller_url" {
  description = "Boundary Controller Web UI and API endpoint"
  value       = "http://${aws_instance.controller.public_ip}:9200"
}

output "boundary_ingress_worker_public_ip" {
  description = "Public IP of Boundary Ingress Worker"
  value       = aws_instance.ingress_worker.public_ip
}

output "boundary_egress_worker_private_ip" {
  description = "Private IP of Boundary Egress Worker (Private Subnet)"
  value       = aws_instance.egress_worker.private_ip
}

output "linux_target_private_ip" {
  description = "Private IP of Linux SSH and Web Target"
  value       = aws_instance.linux_target.private_ip
}

output "windows_target_private_ip" {
  description = "Private IP of Windows Server RDP Target"
  value       = aws_instance.windows_target.private_ip
}

output "rds_endpoint_address" {
  description = "RDS PostgreSQL Hostname"
  value       = aws_db_instance.postgres.address
}

output "rds_endpoint" {
  description = "RDS PostgreSQL Endpoint with port"
  value       = aws_db_instance.postgres.endpoint
}

output "boundary_recovery_key" {
  description = "Boundary Recovery AEAD Key (Used to bootstrap cluster)"
  value       = local.boundary_recovery_key
  sensitive   = true
}

output "windows_admin_password" {
  description = "Windows Target Administrator Password"
  value       = local.windows_admin_password
  sensitive   = true
}

output "linux_ssh_password" {
  description = "Password for boundary-user on the Linux Target"
  value       = local.linux_ssh_password
  sensitive   = true
}

output "demo_db_password" {
  description = "Password for demouser in the appdb demo database"
  value       = local.demo_db_password
  sensitive   = true
}

output "quick_start_summary" {
  description = "Quick-start guide and next steps"
  value       = <<-EOT
    ========================================================================
    🎉 HASHICORP BOUNDARY AWS ENVIRONMENT READY!
    ========================================================================

    1. Access Boundary Web UI:
       http://${aws_instance.controller.public_ip}:9200

    2. Boundary Scopes, Targets, Credentials & Users:
       The boundary-demo-config workspace runs automatically after this
       apply (run trigger). Then launch: ./scripts/demo-menu.sh

    3. Architecture Breakdown:
       - Public Subnet:  Controller (${aws_instance.controller.public_ip}), Ingress Worker (${aws_instance.ingress_worker.public_ip})
       - Private Subnet: Egress Worker (${aws_instance.egress_worker.private_ip})
       - Private Targets: Linux (${aws_instance.linux_target.private_ip}), Windows (${aws_instance.windows_target.private_ip}), RDS (${aws_db_instance.postgres.address})
       - Ops (private):  OpenLDAP, Prometheus, Grafana (${aws_instance.ops.private_ip}) - reach via Boundary targets
       - Worker Multi-Hop: Client -> Ingress Worker (Public) -> Egress Worker (Private) -> Targets

    4. Target Use Cases Configured:
       - Linux SSH Target (Port 22)
       - Windows RDP Target (Port 3389)
       - PostgreSQL RDS Target (Port 5432)
       - Internal Web Portal Target (Port 8080)
    ========================================================================
  EOT
}

output "ops_private_ip" {
  description = "Private IP of the Ops instance (OpenLDAP :389, Prometheus :9090, Grafana :3000)"
  value       = aws_instance.ops.private_ip
}

output "ldap" {
  description = "LDAP connection settings for the Boundary LDAP auth method"
  value = {
    url      = "ldap://${aws_instance.ops.private_ip}:389"
    base_dn  = local.ldap_base_dn
    user_dn  = "ou=people,${local.ldap_base_dn}"
    group_dn = "ou=groups,${local.ldap_base_dn}"
    bind_dn  = "cn=readonly,${local.ldap_base_dn}"
  }
}

output "ldap_bind_password" {
  description = "Password of the read-only LDAP bind user used by Boundary"
  value       = random_password.ldap_readonly.result
  sensitive   = true
}

output "ldap_users" {
  description = "Demo LDAP users with their group and generated password"
  value       = { for u, g in var.ldap_users : u => { group = g, password = random_password.ldap_user[u].result } }
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Grafana 'admin' password (Grafana is reached via the Boundary grafana target)"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "aws_region" {
  description = "AWS region of the deployment"
  value       = var.aws_region
}

output "session_recording_bucket" {
  description = "S3 bucket that stores Boundary session recordings"
  value       = aws_s3_bucket.session_recordings.bucket
}

output "session_recording_role_arn" {
  description = "IAM role the Boundary AWS storage plugin assumes for session recording"
  value       = aws_iam_role.session_recording.arn
}
