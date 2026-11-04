# Cockpit: web interface to look at the server and the lab VMs (cockpit-machines),
# with a graphical console in the browser. Optional, self-contained add-on:
# its variables, resource and output are all in this file, its script in scripts/cockpit.sh.tftpl.
#
# Listens only on the server's tunnel address (https://10.99.0.1:9090), never on the public IP.
# Login uses the debian account's password (Cockpit has no SSH key login): set it once with
#   ssh debian@10.99.0.1 sudo passwd debian
# SSH stays key-only (PasswordAuthentication no), so this password does not open SSH.
#
# Use it to look, open consoles, start and stop VMs. Do not create or change VMs in it:
# 2-lab/ manages them, and a later tofu apply would undo or clash with manual changes.
#
# To remove Cockpit:
#   1. set cockpit_enabled = false in terraform.tfvars, then tofu apply (uninstalls it from the server);
#   2. delete this file and scripts/cockpit.sh.tftpl.
# Deleting the files first would only forget Cockpit, without uninstalling it.

variable "cockpit_enabled" {
  description = "Switch: true installs Cockpit, false uninstalls it from the server"
  type        = bool
  default     = true
}

variable "cockpit_port" {
  description = "Cockpit HTTPS port, on the tunnel address only"
  type        = number
  default     = 9090
}

locals {
  # Tunnel address without the prefix length (10.99.0.1/24 -> 10.99.0.1)
  cockpit_address = split("/", var.wg_server_address)[0]

  cockpit_script = templatefile("${path.module}/scripts/cockpit.sh.tftpl", {
    address = local.cockpit_address
    port    = var.cockpit_port
  })
}

# Re-run when the script changes or when the server is reinstalled.
# A re-run uninstalls then reinstalls Cockpit (the destroy step below runs first).
resource "terraform_data" "cockpit" {
  count = var.cockpit_enabled ? 1 : 0

  triggers_replace = {
    script  = sha256(local.cockpit_script)
    install = ovh_dedicated_server_reinstall_task.debian[*].id
  }

  # Kept for the destroy step, which can only read self
  input = {
    host             = coalesce(var.ssh_host, data.ovh_dedicated_server.lab.ip)
    user             = var.ssh_user
    private_key_path = var.ssh_private_key_path
  }

  connection {
    type        = "ssh"
    host        = self.input.host
    user        = self.input.user
    private_key = file(pathexpand(self.input.private_key_path))
  }

  provisioner "file" {
    content     = local.cockpit_script
    destination = "/tmp/cockpit.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/cockpit.sh",
      "rm /tmp/cockpit.sh",
    ]
  }

  # Uninstall when cockpit_enabled goes to false. Does not block the apply if the server is unreachable.
  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "sudo systemctl disable --now cockpit.socket || true",
      "sudo rm -rf /etc/systemd/system/cockpit.socket.d",
      "sudo systemctl daemon-reload",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y cockpit-ws cockpit-bridge cockpit-system cockpit-machines libvirt-dbus pcp python3-pcp",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y",
    ]
  }

  depends_on = [ovh_dedicated_server_reinstall_task.debian, terraform_data.wireguard, terraform_data.libvirt]
}

output "cockpit_url" {
  description = "Cockpit address, through the WireGuard tunnel"
  value       = var.cockpit_enabled ? "https://${local.cockpit_address}:${var.cockpit_port}" : "disabled (cockpit_enabled = false)"
}
