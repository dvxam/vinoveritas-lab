# SIEM01: Wazuh all-in-one (manager, indexer, dashboard), Debian 13, VLAN 20 (Mission 7).
#   - seg-siem: 10.50.20.30/24, access port VLAN 20 on OVS; gateway 10.50.20.1 once pfSense routes it;
#   - nat: 192.168.206.30/24, temporary link with the default route, for the Wazuh packages
#     and for Ansible until pfSense is in place (same as ADMIN01).
# Kept apart from vms.tf: same building blocks (cloud image, cloud-init), bigger VM.
# The inside is installed by Ansible: ansible/siem01.yml, role wazuh.

locals {
  siem01 = {
    vcpu = 4 # Wazuh sizing for 1 to 25 agents: 4 vCPU, 8 GiB, 50 GB (90 days of alerts)
    ram  = 8192
    disk = 50
    cards = [
      { network = "seg-siem", mac = "02:50:00:00:20:30", ip = "10.50.20.30/24" },
      { network = "nat", mac = "02:50:00:00:20:31", ip = "192.168.206.30/24" },
    ]
  }
}

# VM disk: the Debian image is the backing file; cloud-init grows the partition to 50 GiB
resource "libvirt_volume" "siem01" {
  name          = "siem01.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = local.siem01.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.debian13.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "siem01" {
  name = "siem01-cloudinit"

  meta_data = yamlencode({
    instance-id    = "siem01"
    local-hostname = "siem01"
  })

  user_data = join("\n", ["#cloud-config", yamlencode({
    users = [{
      name                = var.admin_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = concat([trimspace(file(pathexpand(var.ssh_public_key_path)))], var.extra_ssh_public_keys)
    }]
  })])

  network_config = yamlencode({
    version = 2
    ethernets = {
      seg-siem = {
        match     = { macaddress = local.siem01.cards[0].mac }
        addresses = [local.siem01.cards[0].ip]
      }
      # Temporary: removed once pfSense routes VLAN 20
      nat = {
        match       = { macaddress = local.siem01.cards[1].mac }
        addresses   = [local.siem01.cards[1].ip]
        routes      = [{ to = "default", via = "192.168.206.1" }]
        nameservers = { addresses = ["192.168.206.1"] } # libvirt's dnsmasq on the nat network
      }
    }
  })
}

# The provider detects the ISO and records "iso": any other value fails after apply
resource "libvirt_volume" "siem01_cloudinit" {
  name = "siem01-cloudinit.iso"
  pool = libvirt_pool.lab.name

  target = {
    format = { type = "iso" }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.siem01.path
    }
  }
}

resource "libvirt_domain" "siem01" {
  name        = "siem01"
  type        = "kvm"
  vcpu        = local.siem01.vcpu
  memory      = local.siem01.ram
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    # By path, not as pool volumes (AppArmor, see vms.tf)
    disks = [
      {
        source = { file = { file = libvirt_volume.siem01.path } }
        target = { bus = "virtio", dev = "vda" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        device = "cdrom"
        source = { file = { file = libvirt_volume.siem01_cloudinit.path } }
        target = { bus = "sata", dev = "sda" }
      },
    ]

    interfaces = [for card in local.siem01.cards : {
      model  = { type = "virtio" }
      mac    = { address = card.mac }
      source = { network = { network = card.network } }
    }]

    # Graphical console: Cockpit (Machines page), or ssh -L 5900:127.0.0.1:59xx debian@10.99.0.1
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  # A new disk is only read by a new VM (see vms.tf)
  lifecycle {
    replace_triggered_by = [
      libvirt_volume.siem01,
      libvirt_volume.siem01_cloudinit,
    ]
  }

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}

output "ssh_siem01" {
  description = "Command to connect to SIEM01 (Mac with 192.168.206.0/24 in the tunnel's AllowedIPs)"
  value       = "ssh ${var.admin_user}@192.168.206.30"
}
