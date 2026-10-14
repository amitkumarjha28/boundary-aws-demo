# -------------------------------------------------------------------------
# Session Recording (Boundary Enterprise)
# Recordings are staged on the workers and uploaded to S3. The AWS storage
# plugin uses the worker instance-profile role (dynamic credentials).
# -------------------------------------------------------------------------

# The Admin UI lists session recordings from the global scope, so admins need
# grants there (their org-admin role only covers Demo-Org).
resource "boundary_role" "session_recording_viewers" {
  name            = "session-recording-viewers"
  description     = "Admins can list, play back and download session recordings"
  scope_id        = "global"
  grant_scope_ids = ["this", "descendants"]
  principal_ids   = [boundary_user.admin.id, boundary_managed_group_ldap.admins.id]
  grant_strings = [
    "ids=*;type=session-recording;actions=list,read,download",
    "ids=*;type=storage-bucket;actions=list,read",
    "ids=*;type=scope;actions=list,read",
  ]
}

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
