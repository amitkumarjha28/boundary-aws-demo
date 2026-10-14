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

# Prometheus scrapes the Boundary ops listener (port 9203) on every node
resource "aws_security_group_rule" "metrics_from_ops" {
  for_each = {
    controller     = aws_security_group.controller.id
    ingress_worker = aws_security_group.ingress_worker.id
    egress_worker  = aws_security_group.egress_worker.id
  }

  type                     = "ingress"
  from_port                = 9203
  to_port                  = 9203
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ops.id
  security_group_id        = each.value
  description              = "Boundary ops listener (metrics) from Prometheus"
}

# Grafana reads the Boundary data warehouse tables (read-only role)
resource "aws_security_group_rule" "rds_from_ops" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ops.id
  security_group_id        = aws_security_group.rds.id
  description              = "PostgreSQL warehouse reads from Grafana"
}

resource "aws_instance" "ops" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_ops
  subnet_id                   = aws_subnet.private_primary.id
  vpc_security_group_ids      = [aws_security_group.ops.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  # Gzipped to stay under the 16 KB user-data limit (cloud-init decompresses it)
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

  depends_on = [
    aws_route.private_nat_instance,
    aws_route.private_nat_gateway
  ]
}
