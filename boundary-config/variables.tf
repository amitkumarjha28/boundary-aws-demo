variable "tfc_organization" {
  description = "HCP Terraform organization that owns the infra workspace"
  type        = string
  default     = "Amit_TFC"
}

variable "infra_workspace_name" {
  description = "Name of the HCP Terraform workspace that deploys the AWS infrastructure"
  type        = string
  default     = "boundary-demo-infra"
}
