# OVS gets its nat address from DHCP: read it from the lease
data "libvirt_domain_interface_addresses" "ovs" {
  domain = module.ovs.uuid
  source = "lease"
}

output "ssh" {
  description = "Commands to connect to the VMs (Mac with 192.168.206.0/24 in the tunnel's AllowedIPs)"
  value = {
    admin01 = "ssh ${var.admin_user}@192.168.206.10"
    ovs     = "ssh ${var.admin_user}@${data.libvirt_domain_interface_addresses.ovs.interfaces[0].addrs[0].addr}"
  }
}
