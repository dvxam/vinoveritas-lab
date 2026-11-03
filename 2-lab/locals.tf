# Values shared by the machine files (one file per machine: admin01.tf, dc01.tf...)

locals {
  # SSH access to the server, for what libvirt cannot do (downloads, unattend ISOs, keys)
  server = {
    host             = var.server_host
    user             = var.server_user
    private_key_path = var.ssh_private_key_path
  }

  # Keys installed by cloud-init on the Debian VMs
  ssh_keys = concat([trimspace(file(pathexpand(var.ssh_public_key_path)))], var.extra_ssh_public_keys)

  # Same password as Ansible uses afterwards: one source, ansible/secrets/windows.yml (not versioned)
  windows_admin_password = yamldecode(file("${path.module}/../ansible/secrets/windows.yml")).windows_admin_password

  # Only zone allowed to reach WinRM on the Windows machines (flow F11)
  admin_network = "10.50.10.0/24"
}
