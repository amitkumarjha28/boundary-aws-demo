# TEMPORARY troubleshooting aid: collect boot/service logs from the live
# workers with SSM Run Command (read-only on the instances), upload them as
# text to the recordings bucket under diag/, and expose them as an output.
# Remove this file once the workers are healthy.

resource "aws_ssm_association" "worker_diag" {
  name             = "AWS-RunShellScript"
  association_name = "${var.environment}-boundary-worker-diag"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ingress_worker.id, aws_instance.egress_worker.id]
  }

  parameters = {
    commands = join("\n", [
      "ID=$(curl -s -H \"X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')\" http://169.254.169.254/latest/meta-data/instance-id)",
      "{",
      "  echo \"== $ID $(hostname) $(date -u +%FT%TZ)\"",
      "  echo \"--- boundary-worker: $(systemctl is-active boundary-worker 2>&1)\"",
      "  journalctl -u boundary-worker -n 120 --no-pager -o cat 2>&1 | grep -vE '^[{]' | tail -25",
      "  echo '--- worker errors (json events)'",
      "  journalctl -u boundary-worker -n 300 --no-pager -o cat 2>&1 | grep -E '\"error\"' | tail -8 | cut -c1-400",
      "  echo '--- put-parameter test'",
      "  aws ssm put-parameter --region ${var.aws_region} --name ${local.diag_parameter_path}/probe-worker --type SecureString --overwrite --value probe 2>&1 | tail -3",
      "  echo '--- cloud-init tail'",
      "  tail -n 70 /var/log/cloud-init-output.log 2>&1",
      "} 2>&1 | grep -viE 'password|secret|key +=|token: ' | cut -c1-400 > /tmp/worker-diag.txt",
      "aws s3 cp /tmp/worker-diag.txt s3://${aws_s3_bucket.session_recordings.bucket}/diag/$ID.txt --content-type text/plain",
    ])
  }
}

data "aws_s3_objects" "worker_diag" {
  bucket = aws_s3_bucket.session_recordings.bucket
  prefix = "diag/"
}

data "aws_s3_object" "worker_diag" {
  for_each = toset(data.aws_s3_objects.worker_diag.keys)
  bucket   = aws_s3_bucket.session_recordings.bucket
  key      = each.value
}

data "aws_ssm_instances" "managed" {}

data "aws_iam_instance_profile" "worker" {
  name = aws_iam_instance_profile.worker.name
}

output "diag_identity" {
  description = "TEMPORARY: SSM registration and worker instance profile role"
  value = {
    ssm_managed_instances = join(",", data.aws_ssm_instances.managed.ids)
    controller_id         = aws_instance.controller.id
    ingress_worker_id     = aws_instance.ingress_worker.id
    egress_worker_id      = aws_instance.egress_worker.id
    worker_profile_role   = data.aws_iam_instance_profile.worker.role_name
    ingress_profile       = aws_instance.ingress_worker.iam_instance_profile
  }
}

output "worker_diagnostics" {
  description = "TEMPORARY: scrubbed worker logs collected via SSM Run Command"
  value       = { for k, o in data.aws_s3_object.worker_diag : k => o.body }
}
