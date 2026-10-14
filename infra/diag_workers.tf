# TEMPORARY troubleshooting aid: collect live state from SSM-managed nodes
# with SSM Run Command (read-only on the instances) and publish it to each
# node's diagnostics parameter (output boot_diagnostics). Remove this file
# once the deployment is healthy.

locals {
  diag_collect = <<-EOT
    ID=$(cat /var/lib/cloud/data/instance-id)
    case "$ID" in
      ${aws_instance.controller.id})     NAME=controller;     SVC=boundary-controller ;;
      ${aws_instance.ingress_worker.id}) NAME=ingress-worker; SVC=boundary-worker ;;
      ${aws_instance.egress_worker.id})  NAME=egress-worker;  SVC=boundary-worker ;;
      *)                                 NAME=nat;            SVC=nftables ;;
    esac
    {
      echo "== LIVE $NAME $ID $(date -u +%FT%TZ) up: $(uptime)"
      free -m | head -3
      echo "--- $SVC: $(systemctl is-active $SVC 2>&1) restarts=$(systemctl show $SVC -p NRestarts --value 2>/dev/null)"
      if [ "$NAME" = nat ]; then
        sysctl net.ipv4.ip_forward; ip -br addr; ip route; nft list ruleset 2>&1
        tail -n 25 /var/log/cloud-init-output.log
      else
        journalctl -u $SVC --since -30min --no-pager -o cat 2>&1 | grep -E '^[^{]|"error"' | tail -12 | cut -c1-350
        dmesg 2>/dev/null | grep -iE 'oom|killed process' | tail -5
        ps -eo rss,comm --sort=-rss | head -6
      fi
    } 2>&1 | grep -viE 'password|secret|key +=|token' | tail -c 3800 > /tmp/live-diag.txt
    aws ssm put-parameter --region ${var.aws_region} --name ${local.diag_parameter_path}/$NAME --type SecureString --overwrite --value file:///tmp/live-diag.txt
  EOT
}

resource "aws_ssm_association" "worker_diag" {
  name             = "AWS-RunShellScript"
  association_name = "${var.environment}-boundary-live-diag"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.controller.id, aws_instance.ingress_worker.id, aws_instance.egress_worker.id, aws_instance.nat[0].id]
  }

  parameters = {
    commands = local.diag_collect
  }
}

# The NAT/targets/ops role may publish the NAT's diagnostics parameter
resource "aws_iam_role_policy" "ec2_diag" {
  name = "boundary-nat-diag"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.diag_parameter_path}/nat"
    }]
  })
}

data "aws_ssm_instances" "managed" {}

output "diag_identity" {
  description = "TEMPORARY: SSM registration of nodes"
  value = {
    ssm_managed_instances = join(",", data.aws_ssm_instances.managed.ids)
    controller_id         = aws_instance.controller.id
    ingress_worker_id     = aws_instance.ingress_worker.id
    egress_worker_id      = aws_instance.egress_worker.id
    nat_id                = aws_instance.nat[0].id
  }
}
