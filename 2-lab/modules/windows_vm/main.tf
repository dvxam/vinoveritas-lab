# Windows VM, installed without intervention: Setup finds autounattend.xml on a small ISO of its
# own, which sets the disk, computer name, network, Administrator password and WinRM over HTTPS.
# The inside (AD DS, domain join...) is then configured by Ansible from ADMIN01 (flow F11).
#   - edition "server": Windows Server 2022, BIOS, fixed IP;
#   - edition "client": Windows 11, UEFI and TPM 2.0 (required), address from pfSense's DHCP.
# SATA disk and e1000e card: Windows has drivers for both, so no VirtIO driver ISO is needed.

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

locals {
  uefi = var.edition == "client"

  unattend = {
    "autounattend.xml" = templatefile("${path.module}/templates/autounattend-${var.edition}.xml.tftpl", {
      hostname       = var.hostname
      mac            = upper(replace(var.mac, ":", "-")) # Windows writes MACs as 02-50-00-...
      ip             = var.ip
      gateway        = var.gateway
      dns            = var.dns
      admin_password = var.admin_password
      image_index    = 2                             # Standard (Desktop Experience), server edition only
      timezone       = "Romance Standard Time"       # Paris
      input_locale   = "040c:0000040c;0409:00000409" # French keyboard first, US second
    })
    "setup-winrm.ps1" = templatefile("${path.module}/templates/setup-winrm.ps1.tftpl", {
      admin_network = var.admin_network
    })
  }

  unattend_iso = "${var.pool_path}/${var.name}-unattend.iso"
}

# Small ISO with autounattend.xml and setup-winrm.ps1, built on the server (xorriso, see 1-server/)
resource "terraform_data" "unattend" {
  triggers_replace = [sha256(jsonencode(local.unattend))]

  connection {
    type        = "ssh"
    host        = var.server.host
    user        = var.server.user
    private_key = file(pathexpand(var.server.private_key_path))
  }

  provisioner "remote-exec" {
    inline = ["rm -rf /tmp/${var.name}-unattend", "mkdir -p /tmp/${var.name}-unattend"]
  }

  provisioner "file" {
    content     = local.unattend["autounattend.xml"]
    destination = "/tmp/${var.name}-unattend/autounattend.xml"
  }

  provisioner "file" {
    content     = local.unattend["setup-winrm.ps1"]
    destination = "/tmp/${var.name}-unattend/setup-winrm.ps1"
  }

  # The file holds the Administrator password: readable by root and libvirt only, sources removed
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo xorriso -as mkisofs -quiet -J -r -V UNATTEND -o '${local.unattend_iso}' /tmp/${var.name}-unattend",
      "sudo chmod 600 '${local.unattend_iso}'",
      "rm -rf /tmp/${var.name}-unattend",
    ]
  }
}

resource "libvirt_volume" "system" {
  name          = "${var.name}.qcow2"
  pool          = var.pool
  capacity      = var.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

# Data disk, for the VMs that have one (FS01: the shares)
resource "libvirt_volume" "data" {
  count = var.data_disk > 0 ? 1 : 0

  name          = "${var.name}-data.qcow2"
  pool          = var.pool
  capacity      = var.data_disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  vcpu        = var.vcpu
  memory      = var.ram
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  # UEFI (OVMF, chosen by libvirt), required by Windows 11
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = local.uefi ? "efi" : null
  }

  # ACPI and APIC: not added by the provider, Windows needs them (see pfsense.tf).
  # SMM: needed by the Secure Boot firmware.
  features = {
    acpi = true
    apic = {}
    smm  = local.uefi ? { state = "on" } : null
  }

  devices = {
    # Disk first: empty, so the VM starts on the Windows ISO; installed, it boots on the disk.
    # By path, not as pool volumes (AppArmor, see modules/debian_vm).
    disks = concat([
      {
        source = { file = { file = libvirt_volume.system.path } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = var.iso_path } }
        target = { bus = "sata", dev = "sdb" }
        boot   = { order = 2 }
      },
      {
        device = "cdrom"
        source = { file = { file = local.unattend_iso } }
        target = { bus = "sata", dev = "sdc" }
      },
      ], var.data_disk > 0 ? [{
        source = { file = { file = one(libvirt_volume.data[*].path) } }
        target = { bus = "sata", dev = "sdd" }
        driver = { name = "qemu", type = "qcow2" }
    }] : [])

    interfaces = [{
      model  = { type = "e1000e" }
      mac    = { address = var.mac }
      source = { network = { network = var.network } }
    }]

    # TPM 2.0 emulated by swtpm (installed by 1-server/): required by Windows 11, used by BitLocker
    tpms = local.uefi ? [{
      model   = "tpm-crb"
      backend = { emulator = { version = "2.0" } }
    }] : null

    # Graphical console: Cockpit (Machines page)
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  lifecycle {
    replace_triggered_by = [libvirt_volume.system]
  }

  depends_on = [terraform_data.unattend]
}

# In UEFI mode, the Windows ISO asks "Press any key to boot from CD or DVD" for a few seconds,
# otherwise the firmware moves on and the install never starts. Press a key during the first
# 30 seconds after the VM is created (harmless once Setup runs).
resource "terraform_data" "boot_key" {
  count = local.uefi ? 1 : 0

  triggers_replace = [libvirt_domain.vm.id]

  connection {
    type        = "ssh"
    host        = var.server.host
    user        = var.server.user
    private_key = file(pathexpand(var.server.private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 30); do virsh -c qemu:///system send-key ${var.name} KEY_SPACE > /dev/null 2>&1; sleep 1; done",
    ]
  }
}
