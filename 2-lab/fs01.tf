# FS01: file server (shares of the departments), Windows Server 2022, VLAN 20 (Mission 5).
# The inside (domain join, shares) by Ansible from ADMIN01: ansible/fs01.yml, file_shares.yml.

module "fs01" {
  source = "./modules/windows_vm"

  name      = "fs01"
  hostname  = "FS01"
  edition   = "server"
  vcpu      = 2
  ram       = 4096
  disk      = 40
  data_disk = 40       # the shares (D:)
  network   = "seg-fs" # access port VLAN 20 on OVS
  mac       = "02:50:00:00:20:20"
  ip        = "10.50.20.20/24"
  gateway   = "10.50.20.1"
  dns       = "10.50.20.10" # DC01, to join the domain

  iso_path       = module.windows_server_iso.path
  admin_password = local.windows_admin_password
  admin_network  = local.admin_network
  pool           = libvirt_pool.lab.name
  pool_path      = libvirt_pool.lab.target.path
  server         = local.server

  depends_on = [libvirt_network.segment]
}
