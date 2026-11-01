# CLIENT01: Windows 11 Enterprise workstation, POSTES zone (VLAN 30), imposed by the brief.
# Kept apart from windows.tf: Windows 11 needs UEFI and a TPM 2.0, and changing the firmware
# of the shared Windows table would rebuild DC01 and FS01.
#   - address from pfSense's DHCP, reserved for this MAC (10.50.30.10, ansible/host_vars/pfsense.yml);
#   - unattended install (windows/autounattend-client.xml.tftpl), then WinRM over HTTPS from the
#     ADMIN zone (same setup-winrm.ps1 as the servers);
#   - the inside (domain join, local administrators, Wazuh agent) by Ansible: ansible/client01.yml.

locals {
  client01 = {
    hostname = "CLIENT01"
    vcpu     = 2
    ram      = 4096      # Windows 11 minimum
    disk     = 64        # Windows 11 minimum
    network  = "seg-cli" # access port VLAN 30 on OVS
    mac      = "02:50:00:00:30:10"
  }

  # Evaluation (90 days), English, from Microsoft's Evaluation Center (24H2, build 26100)
  client01_iso_url  = "https://go.microsoft.com/fwlink/?linkid=2289031&clcid=0x409&culture=en-us&country=us"
  client01_iso_path = "${libvirt_pool.lab.target.path}/windows-11-enterprise-eval-en-us.iso"

  client01_unattend = {
    "autounattend.xml" = templatefile("${path.module}/windows/autounattend-client.xml.tftpl", {
      hostname       = local.client01.hostname
      admin_password = local.windows_admin_password  # same source as the servers (windows.tf)
      timezone       = "Romance Standard Time"       # Paris
      input_locale   = "040c:0000040c;0409:00000409" # French keyboard first, US second
    })
    "setup-winrm.ps1" = templatefile("${path.module}/windows/setup-winrm.ps1.tftpl", {
      admin_network = "10.50.10.0/24"
    })
  }
}

# 5.4 GB ISO, downloaded once on the server. Microsoft publishes no checksum next to this link.
resource "terraform_data" "client01_iso" {
  triggers_replace = [local.client01_iso_path]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if sudo test -f '${local.client01_iso_path}'; then echo 'ISO already there'; exit 0; fi",
      "curl -fsSL '${local.client01_iso_url}' | sudo tee '${local.client01_iso_path}.part' > /dev/null",
      "sudo mv '${local.client01_iso_path}.part' '${local.client01_iso_path}'",
      "sudo sha256sum '${local.client01_iso_path}'",
    ]
  }
}

# Small ISO with autounattend.xml and setup-winrm.ps1, as for the servers (windows.tf)
resource "terraform_data" "client01_unattend" {
  triggers_replace = [sha256(jsonencode(local.client01_unattend))]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = ["rm -rf /tmp/client01-unattend", "mkdir -p /tmp/client01-unattend"]
  }

  provisioner "file" {
    content     = local.client01_unattend["autounattend.xml"]
    destination = "/tmp/client01-unattend/autounattend.xml"
  }

  provisioner "file" {
    content     = local.client01_unattend["setup-winrm.ps1"]
    destination = "/tmp/client01-unattend/setup-winrm.ps1"
  }

  # The file holds the Administrator password: readable by root and libvirt only, sources removed
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo xorriso -as mkisofs -quiet -J -r -V UNATTEND -o '${libvirt_pool.lab.target.path}/client01-unattend.iso' /tmp/client01-unattend",
      "sudo chmod 600 '${libvirt_pool.lab.target.path}/client01-unattend.iso'",
      "rm -rf /tmp/client01-unattend",
    ]
  }
}

resource "libvirt_volume" "client01" {
  name          = "client01.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = local.client01.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_domain" "client01" {
  name        = "client01"
  type        = "kvm"
  vcpu        = local.client01.vcpu
  memory      = local.client01.ram
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  # UEFI (OVMF, chosen by libvirt), required by Windows 11
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }

  # ACPI and APIC: not added by the provider (see pfsense.tf). SMM: needed by Secure Boot firmware.
  features = {
    acpi = true
    apic = {}
    smm  = { state = "on" }
  }

  devices = {
    # By path, not as pool volumes (AppArmor, see vms.tf)
    disks = [
      {
        source = { file = { file = libvirt_volume.client01.path } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = local.client01_iso_path } }
        target = { bus = "sata", dev = "sdb" }
        boot   = { order = 2 }
      },
      {
        device = "cdrom"
        source = { file = { file = "${libvirt_pool.lab.target.path}/client01-unattend.iso" } }
        target = { bus = "sata", dev = "sdc" }
      },
    ]

    interfaces = [{
      model  = { type = "e1000e" }
      mac    = { address = local.client01.mac }
      source = { network = { network = local.client01.network } }
    }]

    # TPM 2.0 emulated by swtpm (installed by 1-server/): required by Windows 11, used by BitLocker
    tpms = [{
      model   = "tpm-crb"
      backend = { emulator = { version = "2.0" } }
    }]

    # Graphical console: Cockpit (Machines page)
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  lifecycle {
    replace_triggered_by = [libvirt_volume.client01]
  }

  depends_on = [libvirt_network.segment, terraform_data.client01_iso, terraform_data.client01_unattend]
}

# In UEFI mode, the Windows ISO asks "Press any key to boot from CD or DVD" for a few seconds,
# otherwise the firmware moves on and the install never starts. Press a key during the first
# 30 seconds after the VM is created (harmless once Setup runs).
resource "terraform_data" "client01_boot_key" {
  triggers_replace = [libvirt_domain.client01.id]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 30); do virsh -c qemu:///system send-key client01 KEY_SPACE > /dev/null 2>&1; sleep 1; done",
    ]
  }
}
