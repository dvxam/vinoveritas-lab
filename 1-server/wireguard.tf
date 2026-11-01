# WireGuard on the server: admin access to the lab.
# The script is uploaded and run over SSH. It is re-run when its content changes
# or when the server is reinstalled (reinstalling wipes its configuration).

locals {
  wireguard_script = templatefile("${path.module}/scripts/wireguard.sh.tftpl", {
    mac_public_key   = var.wg_mac_public_key
    port             = var.wg_port
    server_address   = var.wg_server_address
    network          = var.wg_network
    mac_address      = var.wg_mac_address
    public_interface = var.public_interface
  })
}

resource "terraform_data" "wireguard" {
  triggers_replace = {
    script  = sha256(local.wireguard_script)
    install = ovh_dedicated_server_reinstall_task.debian[*].id
  }

  connection {
    type        = "ssh"
    host        = coalesce(var.ssh_host, data.ovh_dedicated_server.lab.ip)
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.wireguard_script
    destination = "/tmp/wireguard.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/wireguard.sh",
      "rm /tmp/wireguard.sh",
    ]
  }

  depends_on = [ovh_dedicated_server_reinstall_task.debian]
}
