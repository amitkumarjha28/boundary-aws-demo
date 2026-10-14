# -------------------------------------------------------------------------
# Boundary Infrastructure: Controller, Ingress Worker & Egress Worker
# -------------------------------------------------------------------------

# 1. Boundary Controller (Public Subnet)
resource "aws_instance" "controller" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_controller
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.controller.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/controller-init.sh.tftpl", {
    boundary_version    = var.boundary_version
    db_username         = var.rds_username
    db_password         = local.rds_password
    demo_db_password    = local.demo_db_password
    grafana_db_password = random_password.grafana_db.result
    db_endpoint         = aws_db_instance.postgres.endpoint
    root_kms_key        = local.boundary_root_key
    worker_auth_kms_key = local.boundary_worker_auth_key
    recovery_kms_key    = local.boundary_recovery_key
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-boundary-controller"
    Role = "Controller"
  }

  depends_on = [aws_db_instance.postgres]
}

# 2. Boundary Ingress Worker (Public Subnet)
resource "aws_instance" "ingress_worker" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_ingress_worker
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ingress_worker.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/ingress-worker-init.sh.tftpl", {
    boundary_version      = var.boundary_version
    controller_private_ip = aws_instance.controller.private_ip
    worker_auth_kms_key   = local.boundary_worker_auth_key
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-boundary-ingress-worker"
    Role = "IngressWorker"
  }

  depends_on = [aws_instance.controller]
}

# 3. Boundary Egress Worker (Private Subnet)
resource "aws_instance" "egress_worker" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_egress_worker
  subnet_id                   = aws_subnet.private_primary.id
  vpc_security_group_ids      = [aws_security_group.egress_worker.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/egress-worker-init.sh.tftpl", {
    boundary_version          = var.boundary_version
    controller_private_ip     = aws_instance.controller.private_ip
    ingress_worker_private_ip = aws_instance.ingress_worker.private_ip
    worker_auth_kms_key       = local.boundary_worker_auth_key
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-boundary-egress-worker"
    Role = "EgressWorker"
  }

  depends_on = [
    aws_instance.ingress_worker,
    aws_route.private_nat_instance,
    aws_route.private_nat_gateway
  ]
}
