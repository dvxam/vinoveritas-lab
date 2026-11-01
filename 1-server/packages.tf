# Convenience tools on the server. Re-run when the list changes or when the server is reinstalled.
# Removing a package from the list does not uninstall it.

resource "terraform_data" "packages" {
  triggers_replace = {
    packages    = var.packages
    collections = "openvswitch.openvswitch==2.2.2"
    install     = ovh_dedicated_server_reinstall_task.debian[*].id
  }

  connection {
    type        = "ssh"
    host        = coalesce(var.ssh_host, data.ovh_dedicated_server.lab.ip)
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${join(" ", var.packages)}",
      # Ansible collection used by ansible/roles/ovs (not shipped by Debian)
      "ansible-galaxy collection install openvswitch.openvswitch==2.2.2",
    ]
  }

  depends_on = [ovh_dedicated_server_reinstall_task.debian]
}

# Renamed from French
moved {
  from = terraform_data.paquets
  to   = terraform_data.packages
}
