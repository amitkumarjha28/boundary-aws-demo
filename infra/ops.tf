# -------------------------------------------------------------------------
# Ops Instance (Private Subnet): OpenLDAP, Prometheus & Grafana
# No public IP. Grafana and Prometheus are reached as Boundary targets.
# -------------------------------------------------------------------------

locals {
  ldap_domain  = "boundary.demo"
  ldap_base_dn = "dc=boundary,dc=demo"
  ldap_groups  = ["boundary-admins", "boundary-users"]

  ldap_bootstrap_ldif = templatefile("${path.module}/templates/ldap-bootstrap.ldif.tftpl", {
    base_dn = local.ldap_base_dn
    domain  = local.ldap_domain
    users   = { for u, g in var.ldap_users : u => random_password.ldap_user[u].result }
    groups  = { for g in local.ldap_groups : g => [for u, ug in var.ldap_users : u if ug == g] }
  })
}

resource "aws_security_group" "ops" {
  name        = "${var.environment}-boundary-ops-sg"
  description = "Ops instance: LDAP for the Controller, Grafana/Prometheus via Boundary Egress Worker"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "LDAP from Boundary Controller"
    from_port       = 389
    to_port         = 389
    protocol        = "tcp"
    security_groups = [aws_security_group.controller.id]
  }

  ingress {
    description     = "Grafana Target access from Boundary Egress Worker"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  ingress {
    description     = "Prometheus Target access from Boundary Egress Worker"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  egress {
    description = "Allow outbound (scrapes, RDS, image pulls via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-ops-sg"
  }
}

# Metrics (9203) and warehouse (RDS 5432) access for this instance are granted
# inline in security_groups.tf to the ops_client SG attached below.

resource "aws_instance" "ops" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_ops
  subnet_id                   = aws_subnet.private_primary.id
  vpc_security_group_ids      = [aws_security_group.ops.id, aws_security_group.ops_client.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  # Gzipped to stay under the 16 KB user-data limit (cloud-init decompresses it)
  user_data_replace_on_change = true
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/ops-init.sh.tftpl", {
    ldap_domain                = local.ldap_domain
    ldap_admin_password        = random_password.ldap_admin.result
    ldap_readonly_password     = random_password.ldap_readonly.result
    ldap_bootstrap_ldif        = local.ldap_bootstrap_ldif
    grafana_admin_password     = random_password.grafana_admin.result
    grafana_db_password        = random_password.grafana_db.result
    rds_endpoint               = aws_db_instance.postgres.endpoint
    controller_private_ip      = aws_instance.controller.private_ip
    ingress_worker_private_ip  = aws_instance.ingress_worker.private_ip
    egress_worker_private_ip   = aws_instance.egress_worker.private_ip
    dashboard_boundary_metrics = file("${path.module}/templates/grafana/boundary-metrics.json")
    dashboard_user_activity    = file("${path.module}/templates/grafana/user-activity.json")
    dashboard_login_report     = file("${path.module}/templates/grafana/login-report.json")
  }))

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-boundary-ops"
    Role = "Ops"
  }

  lifecycle {
    # user-data embeds these instances' private IPs; replace together
    replace_triggered_by = [
      aws_instance.controller.id,
      aws_instance.ingress_worker.id,
      aws_instance.egress_worker.id,
    ]
  }

  depends_on = [
    aws_route.private_nat_instance,
    aws_route.private_nat_gateway
  ]
}
