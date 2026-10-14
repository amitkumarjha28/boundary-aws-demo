# -------------------------------------------------------------------------
# Security Groups: Enforcing Zero-Trust Segmentation
# All rules are inline. Do not add aws_security_group_rule resources for these
# groups: inline rules are authoritative and would revoke them on every apply.
# -------------------------------------------------------------------------

# 0. Ops client marker (attached to the ops instance alongside its own SG).
# Node and RDS groups reference this one, so the ops SG can reference the
# controller/egress groups without creating a dependency cycle.
resource "aws_security_group" "ops_client" {
  name        = "${var.environment}-boundary-ops-client-sg"
  description = "Identifies the ops instance (Prometheus/Grafana) as a traffic source"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-boundary-ops-client-sg"
  }
}

# 1. Boundary Controller Security Group (Public Subnet)
resource "aws_security_group" "controller" {
  name        = "${var.environment}-boundary-controller-sg"
  description = "Security group for Boundary Controller"
  vpc_id      = aws_vpc.main.id

  # Controller API & Web UI
  ingress {
    description = "Boundary Controller API and Web UI"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.authorized_client_cidr]
  }

  # Cluster communication from workers
  ingress {
    description     = "Boundary Cluster RPC from Ingress and Egress Workers"
    from_port       = 9201
    to_port         = 9201
    protocol        = "tcp"
    security_groups = [aws_security_group.ingress_worker.id, aws_security_group.egress_worker.id]
  }

  ingress {
    description     = "Boundary ops listener (metrics) from Prometheus"
    from_port       = 9203
    to_port         = 9203
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_client.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-controller-sg"
  }
}

# 2. Boundary Ingress Worker Security Group (Public Subnet)
resource "aws_security_group" "ingress_worker" {
  name        = "${var.environment}-boundary-ingress-worker-sg"
  description = "Security group for Boundary Ingress Worker"
  vpc_id      = aws_vpc.main.id

  # Client proxy traffic
  ingress {
    description = "Boundary Client Proxy Session traffic"
    from_port   = 9202
    to_port     = 9202
    protocol    = "tcp"
    cidr_blocks = [var.authorized_client_cidr]
  }

  ingress {
    description     = "Boundary ops listener (metrics) from Prometheus"
    from_port       = 9203
    to_port         = 9203
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_client.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-ingress-worker-sg"
  }
}

# 3. Boundary Egress Worker Security Group (Private Subnet)
resource "aws_security_group" "egress_worker" {
  name        = "${var.environment}-boundary-egress-worker-sg"
  description = "Security group for Boundary Egress Worker"
  vpc_id      = aws_vpc.main.id

  # Worker-to-worker multi-hop proxy channel
  ingress {
    description     = "Worker-to-worker multi-hop traffic from Ingress Worker"
    from_port       = 9202
    to_port         = 9202
    protocol        = "tcp"
    security_groups = [aws_security_group.ingress_worker.id]
  }

  ingress {
    description     = "Boundary ops listener (metrics) from Prometheus"
    from_port       = 9203
    to_port         = 9203
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_client.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-egress-worker-sg"
  }
}

# 4. Target Instances Security Group (Private Subnet)
# Completely isolated: ONLY Boundary Egress Worker can reach target ports!
resource "aws_security_group" "targets" {
  name        = "${var.environment}-boundary-targets-sg"
  description = "Zero-trust target security group - allows access ONLY from Boundary Egress Worker"
  vpc_id      = aws_vpc.main.id

  # SSH for Linux Target
  ingress {
    description     = "SSH Target access from Boundary Egress Worker"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  # RDP for Windows Target
  ingress {
    description     = "RDP Target access from Boundary Egress Worker"
    from_port       = 3389
    to_port         = 3389
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  # HTTP Web Application Target
  ingress {
    description     = "HTTP Web Target access from Boundary Egress Worker"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  egress {
    description = "Allow outbound for OS updates via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-targets-sg"
  }
}

# 5. RDS PostgreSQL Security Group (Private Subnet)
resource "aws_security_group" "rds" {
  name        = "${var.environment}-boundary-rds-sg"
  description = "Security group for PostgreSQL RDS (Controller database + Demo target database)"
  vpc_id      = aws_vpc.main.id

  # Controller backend database storage
  ingress {
    description     = "PostgreSQL from Boundary Controller"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.controller.id]
  }

  # Target database access via Egress Worker
  ingress {
    description     = "PostgreSQL RDS Target from Boundary Egress Worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.egress_worker.id]
  }

  # Grafana reads the Boundary data warehouse (read-only role)
  ingress {
    description     = "PostgreSQL warehouse reads from Grafana"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_client.id]
  }

  egress {
    description = "Allow outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-boundary-rds-sg"
  }
}

# Former standalone rules, now inline above. Forget them without revoking
# (the inline definitions adopt or replace the live rules).
removed {
  from = aws_security_group_rule.controller_cluster_from_ingress
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.controller_cluster_from_egress
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.metrics_from_ops
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.rds_from_ops
  lifecycle {
    destroy = false
  }
}
