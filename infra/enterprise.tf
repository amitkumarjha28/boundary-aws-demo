# -------------------------------------------------------------------------
# Boundary Enterprise: license delivery, node IAM, and session recording
# -------------------------------------------------------------------------

# License: kept out of git and user-data. Set var.boundary_license as a
# sensitive workspace variable; the controller reads it from SSM at boot.
locals {
  diag_parameter_path = "/${var.environment}/boundary/diag"
  diag_parameter_name = "${local.diag_parameter_path}/controller"
}

resource "aws_ssm_parameter" "boundary_license" {
  name        = "/${var.environment}/boundary/license"
  description = "Boundary Enterprise license"
  type        = "SecureString"
  value       = var.boundary_license
}

# -------------------------------------------------------------------------
# Session recording storage (S3)
# -------------------------------------------------------------------------

resource "random_id" "recordings_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "session_recordings" {
  bucket        = "${var.environment}-boundary-recordings-${random_id.recordings_bucket_suffix.hex}"
  force_destroy = true # demo: allow destroy even when recordings exist
}

resource "aws_s3_bucket_public_access_block" "session_recordings" {
  bucket                  = aws_s3_bucket.session_recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "session_recordings" {
  bucket = aws_s3_bucket.session_recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Private-subnet workers reach S3 without going through the NAT instance
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.environment}-boundary-s3-endpoint"
  }
}

# -------------------------------------------------------------------------
# IAM
# The Boundary AWS storage plugin uses dynamic credentials: the controller
# and workers assume the session-recording role from their instance profiles.
# -------------------------------------------------------------------------

locals {
  ec2_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

data "aws_caller_identity" "current" {}

# Controller
resource "aws_iam_role" "controller" {
  name               = "${var.environment}-boundary-controller-role"
  assume_role_policy = local.ec2_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "controller_ssm_core" {
  role       = aws_iam_role.controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "controller" {
  name = "boundary-controller"
  role = aws_iam_role.controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadLicense"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.boundary_license.arn
      },
      {
        Sid      = "AssumeSessionRecordingRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.session_recording.arn
      },
      {
        Sid      = "PublishBootDiagnostics"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.diag_parameter_name}"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "controller" {
  name = "${var.environment}-boundary-controller-profile"
  role = aws_iam_role.controller.name
}

# Workers
resource "aws_iam_role" "worker" {
  name               = "${var.environment}-boundary-worker-role"
  assume_role_policy = local.ec2_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "worker" {
  name = "boundary-worker"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeSessionRecordingRole"
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = aws_iam_role.session_recording.arn
    }]
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.environment}-boundary-worker-profile"
  role = aws_iam_role.worker.name
}

# Session recording role: S3 access, assumable only by the controller and workers
resource "aws_iam_role" "session_recording" {
  name = "${var.environment}-boundary-session-recording"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Condition = {
        ArnEquals = {
          "aws:PrincipalArn" = [aws_iam_role.controller.arn, aws_iam_role.worker.arn]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "session_recording" {
  name = "boundary-session-recording-s3"
  role = aws_iam_role.session_recording.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectAttributes",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.session_recordings.arn,
        "${aws_s3_bucket.session_recordings.arn}/*",
      ]
    }]
  })
}

# -------------------------------------------------------------------------
# Controller boot diagnostics (written by the controller's user-data)
# Read at plan time, so a run after a failed boot shows the previous boot.
# -------------------------------------------------------------------------

data "aws_ssm_parameters_by_path" "diag" {
  path            = local.diag_parameter_path
  with_decryption = true
}
