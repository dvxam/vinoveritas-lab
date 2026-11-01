# Windows Server 2022 VMs (DC01 for now; FS01 will go in the same map).
# Unattended install: Setup finds autounattend.xml on a small ISO of its own, which sets the
# disk, computer name, fixed IP, Administrator password and WinRM over HTTPS.
# The inside (AD DS, DNS...) is then configured by Ansible from ADMIN01 (flow F11).
#
# SATA disk and e1000e card: Windows has drivers for both, so no VirtIO driver ISO is needed.

locals {
  windows = {
    dc01 = {
      hostname = "DC01"
      vcpu     = 2
      ram      = 4096
      disk     = 40
      network  = "seg-dc" # access port VLAN 20 on OVS
      mac      = "02:50:00:00:20:10"
      ip       = "10.50.20.10/24"
      gateway  = "10.50.20.1" # pfSense
      dns      = "10.50.20.1" # pfSense's resolver (F9) until DC01 is its own DNS server
    }
  }

  # Evaluation (180 days), English, from Microsoft's Evaluation Center
  windows_iso_url  = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
  windows_iso_path = "${libvirt_pool.lab.target.path}/windows-server-2022-eval-en-us.iso"

  # Same password as Ansible uses afterwards: one source, ansible/secrets/windows.yml (not versioned)
  windows_admin_password = yamldecode(file("${path.module}/../ansible/secrets/windows.yml")).windows_admin_password

  windows_unattend = {
    for name, vm in local.windows : name => {
      "autounattend.xml" = templatefile("${path.module}/windows/autounattend.xml.tftpl", {
        hostname       = vm.hostname
        mac            = upper(replace(vm.mac, ":", "-")) # Windows writes MACs as 02-50-00-...
        ip             = vm.ip
        gateway        = vm.gateway
        dns            = vm.dns
        admin_password = local.windows_admin_password
        image_index    = 2
        timezone       = "Romance Standard Time"       # Paris
        input_locale   = "040c:0000040c;0409:00000409" # French keyboard first, US second
      })
      "setup-winrm.ps1" = templatefile("${path.module}/windows/setup-winrm.ps1.tftpl", {
        admin_network = "10.50.10.0/24"
      })
    }
  }
}

# 5 GB ISO, downloaded once on the server. Microsoft publishes no checksum next to this link.
resource "terraform_data" "windows_iso" {
  triggers_replace = [local.windows_iso_path]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if sudo test -f '${local.windows_iso_path}'; then echo 'ISO already there'; exit 0; fi",
      "curl -fsSL '${local.windows_iso_url}' | sudo tee '${local.windows_iso_path}.part' > /dev/null",
      "sudo mv '${local.windows_iso_path}.part' '${local.windows_iso_path}'",
      "sha256sum '${local.windows_iso_path}' 2>/dev/null || sudo sha256sum '${local.windows_iso_path}'",
    ]
  }
}

# Small ISO with autounattend.xml and setup-winrm.ps1, built on the server (xorriso, see 1-server/)
resource "terraform_data" "windows_unattend" {
  for_each = local.windows_unattend

  triggers_replace = [sha256(jsonencode(each.value))]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = ["rm -rf /tmp/${each.key}-unattend", "mkdir -p /tmp/${each.key}-unattend"]
  }

  provisioner "file" {
    content     = each.value["autounattend.xml"]
    destination = "/tmp/${each.key}-unattend/autounattend.xml"
  }

  provisioner "file" {
    content     = each.value["setup-winrm.ps1"]
    destination = "/tmp/${each.key}-unattend/setup-winrm.ps1"
  }

  # The file holds the Administrator password: readable by root and libvirt only, sources removed
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo xorriso -as mkisofs -quiet -J -r -V UNATTEND -o '${libvirt_pool.lab.target.path}/${each.key}-unattend.iso' /tmp/${each.key}-unattend",
      "sudo chmod 600 '${libvirt_pool.lab.target.path}/${each.key}-unattend.iso'",
      "rm -rf /tmp/${each.key}-unattend",
    ]
  }
}

resource "libvirt_volume" "windows" {
  for_each = local.windows

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = each.value.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_domain" "windows" {
  for_each = local.windows

  name        = each.key
  type        = "kvm"
  vcpu        = each.value.vcpu
  memory      = each.value.ram
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  # Not added by the provider; Windows needs them (see pfsense.tf)
  features = {
    acpi = true
    apic = {}
  }

  devices = {
    # Disk first: empty, so the VM starts on the Windows ISO; installed, it boots on the disk.
    # By path, not as pool volumes (AppArmor, see vms.tf).
    disks = [
      {
        source = { file = { file = libvirt_volume.windows[each.key].path } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = local.windows_iso_path } }
        target = { bus = "sata", dev = "sdb" }
        boot   = { order = 2 }
      },
      {
        device = "cdrom"
        source = { file = { file = "${libvirt_pool.lab.target.path}/${each.key}-unattend.iso" } }
        target = { bus = "sata", dev = "sdc" }
      },
    ]

    interfaces = [{
      model  = { type = "e1000e" }
      mac    = { address = each.value.mac }
      source = { network = { network = each.value.network } }
    }]

    # Graphical console: Cockpit (Machines page)
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  lifecycle {
    replace_triggered_by = [libvirt_volume.windows[each.key]]
  }

  depends_on = [libvirt_network.segment, terraform_data.windows_iso, terraform_data.windows_unattend]
}
