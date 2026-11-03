# OVS: Open vSwitch, the switch of the lab, Debian 13 (Mission 2). One card per segment, as the
# ports of a real switch: seg-trunk towards pfSense (802.1Q), access ports for the others.
# DHCP on nat only (temporary, for the first ovs.yml run); the segment cards are OVS ports.

locals {
  ovs_segment_macs = {
    "seg-trunk"  = "02:50:00:00:01:01"
    "seg-admin"  = "02:50:00:00:01:10"
    "seg-dc"     = "02:50:00:00:01:20"
    "seg-fs"     = "02:50:00:00:01:21"
    "seg-siem"   = "02:50:00:00:01:22"
    "seg-cli"    = "02:50:00:00:01:30"
    "seg-backup" = "02:50:00:00:01:40"
  }
}

module "ovs" {
  source = "./modules/debian_vm"

  name = "ovs"
  vcpu = 1
  ram  = 1024
  disk = 8
  cards = concat(
    [{ network = "nat", mac = "02:50:00:00:01:00", dhcp = true }],
    [for segment, mac in local.ovs_segment_macs : { network = segment, mac = mac }],
  )

  pool       = libvirt_pool.lab.name
  base_image = libvirt_volume.debian13.path
  admin_user = var.admin_user
  ssh_keys   = local.ssh_keys

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}
