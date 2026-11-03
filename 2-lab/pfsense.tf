# pfSense: firewall and router of the lab (Mission 2).
#   - WAN (em0) on nat, by DHCP: plays the school network;
#   - LAN (em1) on seg-trunk, 802.1Q trunk towards OVS: VLAN 10, 20, 30, 40, gateway .1 in each.
# Terraform only creates the VM; the ISO is downloaded by images.tf. pfSense itself is installed and set up
# by hand at the console (Cockpit, Machines page), then config.xml is exported to the repository.

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
    # By path, not as pool volumes (AppArmor, see modules/debian_vm).
    disks = [
      {
        source = { file = { file = libvirt_volume.pfsense.path } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = module.pfsense_iso.path } }
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

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}
