terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "Amit_TFC"

    workspaces {
      name = "boundary-demo-infra"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "HashiCorp-Boundary-Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
