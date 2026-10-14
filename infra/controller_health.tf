# Block the apply until the Controller API accepts connections, so the
# run-triggered boundary-demo-config workspace only starts once Boundary is
# reachable. Runs only when the controller is (re)created, so ordinary plans
# are never blocked by a down controller (~10 minute budget for user-data to
# install Boundary and initialize/migrate the database).
resource "terraform_data" "controller_ready" {
  triggers_replace = aws_instance.controller.id

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 60); do
        if timeout 5 bash -c '</dev/tcp/${aws_instance.controller.public_ip}/9200' 2>/dev/null; then
          echo "Controller API is reachable"; exit 0
        fi
        echo "Waiting for controller API ($i/60)..."; sleep 10
      done
      echo "Controller API did not come up. See output boot_diagnostics."
      exit 1
    EOT
  }
}
