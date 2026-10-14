# -------------------------------------------------------------------------
# Session Recording (Boundary Enterprise)
# Recordings are staged on the workers and uploaded to S3. The AWS storage
# plugin assumes the session-recording IAM role (dynamic credentials).
# -------------------------------------------------------------------------

resource "boundary_storage_bucket" "session_recordings" {
  name        = "aws-session-recordings"
  description = "S3 bucket for Boundary session recordings"
  scope_id    = boundary_scope.org.id
  plugin_name = "aws"
  bucket_name = local.infra.session_recording_bucket

  attributes_json = jsonencode({
    region                      = local.infra.aws_region
    role_arn                    = local.infra.session_recording_role_arn
    disable_credential_rotation = true
  })

  # Workers tagged storage=s3 (both ingress and egress) can write recordings
  worker_filter = "\"s3\" in \"/tags/storage\""
}
