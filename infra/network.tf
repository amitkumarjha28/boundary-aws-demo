# Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-boundary-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-boundary-igw"
  }
}

# Public Subnet (Controller, Ingress Worker, NAT)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-boundary-public-subnet"
    Tier = "Public"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.environment}-boundary-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Primary Private Subnet (Egress Worker, Linux Target, Windows Target, RDS)
resource "aws_subnet" "private_primary" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.environment}-boundary-private-primary-subnet"
    Tier = "Private"
  }
}

# Secondary Private Subnet (Required for AWS RDS DB Subnet Group across multiple AZs)
resource "aws_subnet" "private_secondary" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_secondary_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.environment}-boundary-private-secondary-subnet"
    Tier = "Private"
  }
}

# -------------------------------------------------------------------------
# Low-Cost NAT: Choose between t3.nano NAT Instance or AWS Managed NAT Gateway
# -------------------------------------------------------------------------

# Option A: AWS Managed NAT Gateway
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.environment}-boundary-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.environment}-boundary-nat-gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Option B: Ultra Low-Cost NAT Instance (Default: saves ~$32/month)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "nat_instance" {
  count       = var.enable_nat_gateway ? 0 : 1
  name        = "${var.environment}-nat-instance-sg"
  description = "Security Group for low-cost NAT Instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow inbound traffic from private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr, var.private_subnet_secondary_cidr]
  }

  egress {
    description = "Allow all outbound traffic to internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-nat-instance-sg"
  }
}

resource "aws_instance" "nat" {
  count                       = var.enable_nat_gateway ? 0 : 1
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_nat
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat_instance[0].id]
  source_dest_check           = false # Critical for NAT functionality
  associate_public_ip_address = true

  user_data = file("${path.module}/templates/nat-instance-init.sh.tftpl")

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.environment}-low-cost-nat-instance"
  }
}

# Route Table for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-boundary-private-rt"
  }
}

# Default route for Private Subnet (pointing to NAT Gateway or NAT Instance)
resource "aws_route" "private_nat_gateway" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}

resource "aws_route" "private_nat_instance" {
  count                  = var.enable_nat_gateway ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "private_primary" {
  subnet_id      = aws_subnet.private_primary.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_secondary" {
  subnet_id      = aws_subnet.private_secondary.id
  route_table_id = aws_route_table.private.id
}
