# SIEM01: Wazuh all-in-one (manager, indexer, dashboard), Debian 13, VLAN 20 (Mission 7).
#   - seg-siem: 10.50.20.30/24, access port VLAN 20 on OVS; gateway 10.50.20.1 once pfSense routes it;
#   - nat: 192.168.206.30/24, temporary link with the default route, for the Wazuh packages
#     and for Ansible until pfSense is in place (same as ADMIN01).
# The inside is installed by Ansible: ansible/siem01.yml, role wazuh.

module "siem01" {
  source = "./modules/debian_vm"

  name = "siem01"
  vcpu = 4 # Wazuh sizing for 1 to 25 agents: 4 vCPU, 8 GiB, 50 GB (90 days of alerts)
  ram  = 8192
  disk = 50
  # Named cards: the netplan keys of the first install, kept so cloud-init is not rebuilt
  cards = [
    { name = "seg-siem", network = "seg-siem", mac = "02:50:00:00:20:30", ip = "10.50.20.30/24" },
    # Temporary: removed once pfSense routes VLAN 20
    { name = "nat", network = "nat", mac = "02:50:00:00:20:31", ip = "192.168.206.30/24", gateway = "192.168.206.1" },
  ]

  pool       = libvirt_pool.lab.name
  base_image = libvirt_volume.debian13.path
  admin_user = var.admin_user
  ssh_keys   = local.ssh_keys

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}

output "ssh_siem01" {
  description = "Command to connect to SIEM01 (Mac with 192.168.206.0/24 in the tunnel's AllowedIPs)"
  value       = "ssh ${var.admin_user}@192.168.206.30"
}
