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
       - Worker Multi-Hop: Client -> Ingress Worker (Public) -> Egress Worker (Private) -> Targets

    4. Target Use Cases Configured:
       - Linux SSH Target (Port 22)
       - Windows RDP Target (Port 3389)
       - PostgreSQL RDS Target (Port 5432)
       - Internal Web Portal Target (Port 8080)
    ========================================================================
  EOT
}
