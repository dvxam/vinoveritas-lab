# ADMIN01: administration workstation of the IT team, Debian 13, VLAN 10 (Mission 2).
# Ansible runs from here towards the Windows machines (flow F11).

module "admin01" {
  source = "./modules/debian_vm"

  name = "admin01"
  vcpu = 2
  ram  = 2048
  disk = 16
  cards = [
    { network = "seg-admin", mac = "02:50:00:00:10:10", ip = "10.50.10.10/24" },
    # Temporary link until pfSense routes VLAN 10: the default route goes through the server for now
    { network = "nat", mac = "02:50:00:00:10:11", ip = "192.168.206.10/24", gateway = "192.168.206.1" },
  ]

  pool       = libvirt_pool.lab.name
  base_image = libvirt_volume.debian13.path
  admin_user = var.admin_user
  ssh_keys   = local.ssh_keys

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}
