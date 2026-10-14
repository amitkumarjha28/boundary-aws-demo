variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag name"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the Public Subnet (Hosts Controller, Ingress Worker, NAT)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the Primary Private Subnet (Hosts Egress Worker, Linux, Windows, RDS)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_secondary_cidr" {
  description = "CIDR block for the Secondary Private Subnet (Required for AWS RDS DB Subnet Group)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "boundary_version" {
  description = "HashiCorp Boundary Enterprise version to install (without the +ent suffix)"
  type        = string
  default     = "0.19.5"
}

variable "authorized_client_cidr" {
  description = "CIDR block authorized to access Boundary Controller UI (port 9200) and Ingress Worker (port 9202). HCP Terraform runners must reach port 9200 for the boundary-config workspace, so restricting this requires an HCP Terraform agent."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_nat_gateway" {
  description = "If true, provisions AWS Managed NAT Gateway (~$32/mo). If false, provisions a cost-effective t3.micro NAT instance (~$8/mo)."
  type        = bool
  default     = false
}

variable "instance_type_controller" {
  description = "EC2 instance size for Boundary Controller"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_ingress_worker" {
  description = "EC2 instance size for Boundary Ingress Worker"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_egress_worker" {
  description = "EC2 instance size for Boundary Egress Worker"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_linux_target" {
  description = "EC2 instance size for Linux Target (SSH + Web Demo)"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_windows_target" {
  description = "EC2 instance size for Windows Target (RDP). Windows requires minimum 2GB RAM (t3.small)."
  type        = string
  default     = "t3.small"
}

variable "instance_type_nat" {
  description = "EC2 instance size for NAT Instance if enable_nat_gateway is false. Minimum t3.micro: t3.nano (512 MB) is OOM-killed by dnf during setup."
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class for PostgreSQL backend and demo target database"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Storage allocated for RDS in GB"
  type        = number
  default     = 20
}

variable "rds_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "rds_password" {
  description = "Master password for RDS PostgreSQL. If null, a random password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "windows_admin_password" {
  description = "Administrator password for Windows Target. If null, a random password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "linux_ssh_password" {
  description = "Password for the boundary-user account on the Linux Target. If null, a random password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "demo_db_password" {
  description = "Password for the demouser role in the appdb demo database. If null, a random password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "instance_type_ops" {
  description = "EC2 instance size for the private ops instance (OpenLDAP, Prometheus, Grafana)"
  type        = string
  default     = "t3.small"
}

variable "ldap_users" {
  description = "Demo LDAP users mapped to their group. boundary-admins get full org admin in Boundary; boundary-users can connect to the demo targets."
  type        = map(string)
  default = {
    alice = "boundary-admins"
    bob   = "boundary-admins"
    carol = "boundary-users"
    dave  = "boundary-users"
    erin  = "boundary-users"
  }

  validation {
    condition     = alltrue([for g in values(var.ldap_users) : contains(["boundary-admins", "boundary-users"], g)])
    error_message = "Each LDAP user's group must be \"boundary-admins\" or \"boundary-users\"."
  }
}

variable "boundary_license" {
  description = "Boundary Enterprise license (contents of the .hclic file). Set as a sensitive workspace variable; never commit it."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.boundary_license)) > 0
    error_message = "boundary_license must contain the Boundary Enterprise license."
  }
}
