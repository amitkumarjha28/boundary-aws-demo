terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "Amit_TFC"

    workspaces {
      name = "boundary-demo-config"
    }
  }

  required_providers {
    boundary = {
      source  = "hashicorp/boundary"
      version = "~> 1.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Controller address, recovery key, target IPs and target credentials come
# from the boundary-demo-infra workspace. That workspace must share its state
# with this one (Settings > General > Remote state sharing).
data "terraform_remote_state" "infra" {
  backend = "remote"

  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.infra_workspace_name
    }
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs
}

provider "boundary" {
  addr             = local.infra.boundary_controller_url
  recovery_kms_hcl = <<-EOT
    kms "aead" {
      purpose   = "recovery"
      aead_type = "aes-gcm"
      key       = "${local.infra.boundary_recovery_key}"
      key_id    = "global_recovery"
    }
  EOT
}
