# Debian 13 VMs built from the cloud image: cloud-init sets the hostname, addresses, account and SSH key.
# MAC addresses are fixed: cloud-init uses them to recognise each card, and they survive a rebuild.

locals {
  # Every card has the same attributes; null = not set
  vms = {
    admin01 = {
      vcpu = 2
      ram  = 2048
      disk = 16
      cards = [
        { network = "seg-admin", mac = "02:50:00:00:10:10", ip = "10.50.10.10/24", gateway = null, dhcp = false },
        # Temporary link until pfSense routes VLAN 10: the default route goes through the server for now
        { network = "nat", mac = "02:50:00:00:10:11", ip = "192.168.206.10/24", gateway = "192.168.206.1", dhcp = false },
      ]
    }

    # Open vSwitch: DHCP on nat only (temporary, for the first ovs.yml run); the segment cards are OVS ports
    ovs = {
      vcpu = 1
      ram  = 1024
      disk = 8
      cards = concat(
        [{ network = "nat", mac = "02:50:00:00:01:00", ip = null, gateway = null, dhcp = true }],
        [for segment, mac in local.ovs_segment_macs : { network = segment, mac = mac, ip = null, gateway = null, dhcp = false }],
      )
    }
  }

  ovs_segment_macs = {
    "seg-trunk"  = "02:50:00:00:01:01"
    "seg-admin"  = "02:50:00:00:01:10"
    "seg-dc"     = "02:50:00:00:01:20"
    "seg-fs"     = "02:50:00:00:01:21"
    "seg-siem"   = "02:50:00:00:01:22"
    "seg-cli"    = "02:50:00:00:01:30"
    "seg-backup" = "02:50:00:00:01:40"
  }
}

# VM disk: the Debian image is the backing file, only the VM's writes are stored
resource "libvirt_volume" "system" {
  for_each = local.vms

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = each.value.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.debian13.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = local.vms

  name = "${each.key}-cloudinit"

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  user_data = join("\n", ["#cloud-config", yamlencode({
    users = [{
      name                = var.admin_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }]
  })])

  # Only cards with an address or DHCP are configured; the others stay untouched (OVS ports).
  # One map per kind of card, because each kind has different keys.
  network_config = yamlencode({
    version = 2
    ethernets = merge(
      {
        for i, card in each.value.cards : "card${i}" => {
          match = { macaddress = card.mac }
          dhcp4 = true
        } if card.dhcp
      },
      {
        for i, card in each.value.cards : "card${i}" => {
          match     = { macaddress = card.mac }
          addresses = [card.ip]
        } if card.ip != null && card.gateway == null
      },
      {
        for i, card in each.value.cards : "card${i}" => {
          match       = { macaddress = card.mac }
          addresses   = [card.ip]
          routes      = [{ to = "default", via = card.gateway }]
          nameservers = { addresses = [card.gateway] } # libvirt's dnsmasq on the nat network
        } if card.ip != null && card.gateway != null
      },
    )
  })
}

resource "libvirt_volume" "cloudinit" {
  for_each = local.vms

  name = "${each.key}-cloudinit.iso"
  pool = libvirt_pool.lab.name

  # The provider detects the ISO and records "iso": any other value fails after apply
  target = {
    format = { type = "iso" }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

resource "libvirt_domain" "vm" {
  for_each = local.vms

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

  devices = {
    # Disks by path, not as pool volumes: libvirt leaves pool volumes out of the AppArmor
    # profile it writes for the VM, and QEMU then gets "Permission denied"
    disks = [
      {
        source = { file = { file = libvirt_volume.system[each.key].path } }
        target = { bus = "virtio", dev = "vda" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        device = "cdrom"
        source = { file = { file = libvirt_volume.cloudinit[each.key].path } }
        target = { bus = "sata", dev = "sda" }
      },
    ]

    interfaces = [for card in each.value.cards : {
      model  = { type = "virtio" }
      mac    = { address = card.mac }
      source = { network = { network = card.network } }

      # The apply waits for the DHCP lease, on DHCP cards only
      wait_for_ip = card.dhcp ? { timeout = 300, source = "lease" } : null
    }]

    # Graphical console, only reachable from the server: ssh -L 5900:127.0.0.1:5900 debian@10.99.0.1
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}
