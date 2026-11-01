# KVM and libvirt: the lab VMs run directly on Debian.
# Re-run when the script changes or when the server is reinstalled.

locals {
  libvirt_script = templatefile("${path.module}/scripts/libvirt.sh.tftpl", {
    user             = var.ssh_user
    lab_network      = var.lab_network
    public_interface = var.public_interface
  })
}

resource "terraform_data" "libvirt" {
  triggers_replace = {
    script  = sha256(local.libvirt_script)
    install = ovh_dedicated_server_reinstall_task.debian[*].id
  }

  connection {
    type        = "ssh"
    host        = coalesce(var.ssh_host, data.ovh_dedicated_server.lab.ip)
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.libvirt_script
    destination = "/tmp/libvirt.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/libvirt.sh",
      "rm /tmp/libvirt.sh",
    ]
  }

  depends_on = [ovh_dedicated_server_reinstall_task.debian]
}
