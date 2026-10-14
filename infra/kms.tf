# Cryptographic AEAD keys for Boundary encryption
# AEAD avoids AWS KMS monthly charges ($1/key/month) and IAM complexity
# while delivering full 256-bit AES-GCM envelope encryption.

resource "random_id" "root_kms_key" {
  byte_length = 32
}

resource "random_id" "worker_auth_kms_key" {
  byte_length = 32
}

resource "random_id" "recovery_kms_key" {
  byte_length = 32
}

resource "random_id" "bsrm_kms_key" {
  byte_length = 32
}

# Key values available as base64
locals {
  boundary_root_key        = random_id.root_kms_key.b64_std
  boundary_worker_auth_key = random_id.worker_auth_kms_key.b64_std
  boundary_recovery_key    = random_id.recovery_kms_key.b64_std
  boundary_bsrm_key        = random_id.bsrm_kms_key.b64_std
}
