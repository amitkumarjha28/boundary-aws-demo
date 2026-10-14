# RDS DB Subnet Group spanning two Availability Zones in private subnets
resource "aws_db_subnet_group" "boundary" {
  name       = "${var.environment}-boundary-db-subnet-group"
  subnet_ids = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]

  tags = {
    Name = "${var.environment}-boundary-db-subnet-group"
  }
}

# RDS PostgreSQL Instance
# Hosts both the 'boundary' database (controller state) and 'appdb' database (demo target)
resource "aws_db_instance" "postgres" {
  identifier             = "${var.environment}-boundary-postgres"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_allocated_storage
  storage_type           = "gp3"
  db_name                = "boundary"
  username               = var.rds_username
  password               = local.rds_password
  db_subnet_group_name   = aws_db_subnet_group.boundary.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  deletion_protection    = false

  tags = {
    Name = "${var.environment}-boundary-postgres-rds"
  }
}
