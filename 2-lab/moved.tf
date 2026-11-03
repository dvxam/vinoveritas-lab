# Resources moved when vms.tf and windows.tf were split into one file per machine and modules.
# They tell OpenTofu nothing is to be rebuilt. Can be removed once applied everywhere the state lives.

# --- Debian VMs ---------------------------------------------------------------
moved {
  from = libvirt_volume.system["admin01"]
  to   = module.admin01.libvirt_volume.system
}
moved {
  from = libvirt_cloudinit_disk.init["admin01"]
  to   = module.admin01.libvirt_cloudinit_disk.init
}
moved {
  from = libvirt_volume.cloudinit["admin01"]
  to   = module.admin01.libvirt_volume.cloudinit
}
moved {
  from = libvirt_domain.vm["admin01"]
  to   = module.admin01.libvirt_domain.vm
}

moved {
  from = libvirt_volume.system["ovs"]
  to   = module.ovs.libvirt_volume.system
}
moved {
  from = libvirt_cloudinit_disk.init["ovs"]
  to   = module.ovs.libvirt_cloudinit_disk.init
}
moved {
  from = libvirt_volume.cloudinit["ovs"]
  to   = module.ovs.libvirt_volume.cloudinit
}
moved {
  from = libvirt_domain.vm["ovs"]
  to   = module.ovs.libvirt_domain.vm
}

moved {
  from = libvirt_volume.siem01
  to   = module.siem01.libvirt_volume.system
}
moved {
  from = libvirt_cloudinit_disk.siem01
  to   = module.siem01.libvirt_cloudinit_disk.init
}
moved {
  from = libvirt_volume.siem01_cloudinit
  to   = module.siem01.libvirt_volume.cloudinit
}
moved {
  from = libvirt_domain.siem01
  to   = module.siem01.libvirt_domain.vm
}

# --- Windows VMs --------------------------------------------------------------
moved {
  from = terraform_data.windows_unattend["dc01"]
  to   = module.dc01.terraform_data.unattend
}
moved {
  from = libvirt_volume.windows["dc01"]
  to   = module.dc01.libvirt_volume.system
}
moved {
  from = libvirt_domain.windows["dc01"]
  to   = module.dc01.libvirt_domain.vm
}

moved {
  from = terraform_data.windows_unattend["fs01"]
  to   = module.fs01.terraform_data.unattend
}
moved {
  from = libvirt_volume.windows["fs01"]
  to   = module.fs01.libvirt_volume.system
}
moved {
  from = libvirt_volume.windows_data["fs01"]
  to   = module.fs01.libvirt_volume.data[0]
}
moved {
  from = libvirt_domain.windows["fs01"]
  to   = module.fs01.libvirt_domain.vm
}

moved {
  from = terraform_data.client01_unattend
  to   = module.client01.terraform_data.unattend
}
moved {
  from = libvirt_volume.client01
  to   = module.client01.libvirt_volume.system
}
moved {
  from = libvirt_domain.client01
  to   = module.client01.libvirt_domain.vm
}
moved {
  from = terraform_data.client01_boot_key
  to   = module.client01.terraform_data.boot_key[0]
}

# --- Installation ISOs --------------------------------------------------------
moved {
  from = terraform_data.windows_iso
  to   = module.windows_server_iso.terraform_data.download
}
moved {
  from = terraform_data.client01_iso
  to   = module.windows_11_iso.terraform_data.download
}
moved {
  from = terraform_data.pfsense_iso
  to   = module.pfsense_iso.terraform_data.download
}
