# pfSense: firewall and router of the lab (Mission 2).
#   - WAN (em0) on nat, by DHCP: plays the school network;
#   - LAN (em1) on seg-trunk, 802.1Q trunk towards OVS: VLAN 10, 20, 30, 40, gateway .1 in each.
# Terraform only creates the VM and downloads the ISO. pfSense itself is installed and set up
# by hand at the console (Cockpit, Machines page), then config.xml is exported to the repository.

locals {
  pfsense_iso_name = "pfSense-CE-2.7.2-RELEASE-amd64.iso"
  # Last CE release published as an ISO; 2.8 only comes through Netgate's online installer.
  # Upgrade from the web interface once installed.
  pfsense_iso_url    = "https://atxfiles.netgate.com/mirror/downloads/${local.pfsense_iso_name}.gz"
  pfsense_iso_sha256 = "883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4" # of the .gz, from the mirror's .sha256
  pfsense_iso_path   = "${libvirt_pool.lab.target.path}/${local.pfsense_iso_name}"
}

# The ISO is gzipped: libvirt cannot unpack it, so it is downloaded and unpacked on the server
# over SSH. Skipped if the file is already there.
resource "terraform_data" "pfsense_iso" {
  triggers_replace = [local.pfsense_iso_path, local.pfsense_iso_sha256]

  connection {
    type        = "ssh"
    host        = var.server_host
    user        = var.server_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if sudo test -f '${local.pfsense_iso_path}'; then echo 'ISO already there'; exit 0; fi",
      "tmp=$(mktemp -d)",
      "curl -fsSL -o \"$tmp/pfsense.iso.gz\" '${local.pfsense_iso_url}'",
      "echo '${local.pfsense_iso_sha256}  '\"$tmp/pfsense.iso.gz\" | sha256sum -c",
      "gunzip -c \"$tmp/pfsense.iso.gz\" | sudo tee '${local.pfsense_iso_path}.part' > /dev/null",
      "sudo mv '${local.pfsense_iso_path}.part' '${local.pfsense_iso_path}'",
      "rm -r \"$tmp\"",
    ]
  }
}

# Empty disk: pfSense's installer partitions it
resource "libvirt_volume" "pfsense" {
  name          = "pfsense.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = 16
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_domain" "pfsense" {
  name        = "pfsense"
  type        = "kvm"
  vcpu        = 2
  memory      = 2048
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  # The provider adds neither by default. Linux copes, FreeBSD does not: without ACPI,
  # pfSense finds no network card at all (and panics on an i440fx machine).
  features = {
    acpi = true
    apic = {}
  }

  devices = {
    # Disk first: as long as it is empty, the VM falls back to the ISO; once installed, it boots on the disk.
    # By path, not as pool volumes (AppArmor, see vms.tf).
    disks = [
      {
        source = { file = { file = libvirt_volume.pfsense.path } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = local.pfsense_iso_path } }
        target = { bus = "sata", dev = "sdb" }
        boot   = { order = 2 }
      },
    ]

    # e1000 cards: pfSense names them em0 and em1, as in the report (Mission 2, section 3)
    interfaces = [
      {
        model  = { type = "e1000" }
        mac    = { address = "02:50:00:00:00:01" }
        source = { network = { network = "nat" } }
      },
      {
        model  = { type = "e1000" }
        mac    = { address = "02:50:00:00:00:02" }
        source = { network = { network = "seg-trunk" } }
      },
    ]

    # Graphical console: Cockpit (Machines page), or ssh -L 5900:127.0.0.1:59xx debian@10.99.0.1
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  lifecycle {
    replace_triggered_by = [libvirt_volume.pfsense]
  }

  depends_on = [libvirt_network.nat, libvirt_network.segment, terraform_data.pfsense_iso]
}
