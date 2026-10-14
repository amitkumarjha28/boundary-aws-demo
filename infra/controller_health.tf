# Block the apply until the Controller API answers, so the run-triggered
# boundary-demo-config workspace only starts once Boundary is reachable.
# Any HTTP response counts as healthy; connection errors are retried
# (~10 minutes) while user-data installs Boundary and initializes the DB.
data "http" "controller_health" {
  url = "http://${aws_instance.controller.public_ip}:9200/"

  retry {
    attempts     = 60
    min_delay_ms = 10000
    max_delay_ms = 10000
  }
}
