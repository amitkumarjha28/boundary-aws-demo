# -------------------------------------------------------------------------
# Demo Targets (Private Subnet - Zero Public Exposure)
# -------------------------------------------------------------------------

# 1. Linux Target (Hosts SSH on port 22 & Internal Web Portal on port 8080)
resource "aws_instance" "linux_target" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_linux_target
  subnet_id                   = aws_subnet.private_primary.id
  vpc_security_group_ids      = [aws_security_group.targets.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/linux-target-init.sh.tftpl", {
    linux_ssh_password = local.linux_ssh_password
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-linux-ssh-and-web-target"
    Role = "DemoTargetLinux"
  }

  depends_on = [
    aws_route.private_nat_instance,
    aws_route.private_nat_gateway
  ]
}

# 2. Windows Target (Hosts Remote Desktop RDP on port 3389)
data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "windows_target" {
  ami                         = data.aws_ami.windows_server.id
  instance_type               = var.instance_type_windows_target
  subnet_id                   = aws_subnet.private_primary.id
  vpc_security_group_ids      = [aws_security_group.targets.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/windows-target-init.ps1.tftpl", {
    windows_admin_password = local.windows_admin_password
  })

  root_block_device {
    volume_size           = 30 # Windows Server requires at least 30 GB
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-windows-rdp-target"
    Role = "DemoTargetWindows"
  }

  depends_on = [
    aws_route.private_nat_instance,
    aws_route.private_nat_gateway
  ]
}
