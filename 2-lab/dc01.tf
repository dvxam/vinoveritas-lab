# DC01: domain controller and DNS of vinoveritas.local, Windows Server 2022, VLAN 20 (Mission 4).
# The inside (AD DS, DNS) by Ansible from ADMIN01: ansible/dc01.yml.

module "dc01" {
  source = "./modules/windows_vm"

  name     = "dc01"
  hostname = "DC01"
  edition  = "server"
  vcpu     = 2
  ram      = 4096
  disk     = 40
  network  = "seg-dc" # access port VLAN 20 on OVS
  mac      = "02:50:00:00:20:10"
  ip       = "10.50.20.10/24"
  gateway  = "10.50.20.1" # pfSense
  dns      = "10.50.20.1" # pfSense's resolver (F9) until DC01 is its own DNS server

  iso_path       = module.windows_server_iso.path
  admin_password = local.windows_admin_password
  admin_network  = local.admin_network
  pool           = libvirt_pool.lab.name
  pool_path      = libvirt_pool.lab.target.path
  server         = local.server

  depends_on = [libvirt_network.segment]
}
