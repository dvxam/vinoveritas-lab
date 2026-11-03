# CLIENT01: Windows 11 Enterprise workstation, POSTES zone (VLAN 30), imposed by the brief.
#   - address from pfSense's DHCP, reserved for this MAC (10.50.30.10, ansible/host_vars/pfsense.yml);
#   - UEFI and TPM 2.0, required by Windows 11 (edition "client" of modules/windows_vm);
#   - the inside (domain join, local administrators, Wazuh agent) by Ansible: ansible/client01.yml.

module "client01" {
  source = "./modules/windows_vm"

  name     = "client01"
  hostname = "CLIENT01"
  edition  = "client"
  vcpu     = 2
  ram      = 4096      # Windows 11 minimum
  disk     = 64        # Windows 11 minimum
  network  = "seg-cli" # access port VLAN 30 on OVS
  mac      = "02:50:00:00:30:10"

  iso_path       = module.windows_11_iso.path
  admin_password = local.windows_admin_password
  admin_network  = local.admin_network
  pool           = libvirt_pool.lab.name
  pool_path      = libvirt_pool.lab.target.path
  server         = local.server

  depends_on = [libvirt_network.segment]
}
