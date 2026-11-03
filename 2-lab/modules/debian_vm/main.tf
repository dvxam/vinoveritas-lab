# Debian 13 VM built from the cloud image: cloud-init sets the hostname, addresses, account and SSH key.
# MAC addresses are fixed: cloud-init uses them to recognise each card, and they survive a rebuild.

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

# VM disk: the Debian image is the backing file, only the VM's writes are stored
resource "libvirt_volume" "system" {
  name          = "${var.name}.qcow2"
  pool          = var.pool
  capacity      = var.disk
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = var.base_image
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-cloudinit"

  meta_data = yamlencode({
    instance-id    = var.name
    local-hostname = var.name
  })

  user_data = join("\n", ["#cloud-config", yamlencode({
    users = [{
      name                = var.admin_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = var.ssh_keys
    }]
  })])

  # Only cards with an address or DHCP are configured; the others stay untouched (OVS ports).
  # One map per kind of card, because each kind has different keys.
  network_config = yamlencode({
    version = 2
    ethernets = merge(
      {
        for i, card in var.cards : coalesce(card.name, "card${i}") => {
          match = { macaddress = card.mac }
          dhcp4 = true
        } if card.dhcp
      },
      {
        for i, card in var.cards : coalesce(card.name, "card${i}") => {
          match     = { macaddress = card.mac }
          addresses = [card.ip]
        } if card.ip != null && card.gateway == null
      },
      {
        for i, card in var.cards : coalesce(card.name, "card${i}") => {
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
  name = "${var.name}-cloudinit.iso"
  pool = var.pool

  # The provider detects the ISO and records "iso": any other value fails after apply
  target = {
    format = { type = "iso" }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.init.path
    }
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
        source = { file = { file = libvirt_volume.system.path } }
        target = { bus = "virtio", dev = "vda" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        device = "cdrom"
        source = { file = { file = libvirt_volume.cloudinit.path } }
        target = { bus = "sata", dev = "sda" }
      },
    ]

    interfaces = [for card in var.cards : {
      model  = { type = "virtio" }
      mac    = { address = card.mac }
      source = { network = { network = card.network } }

      # The apply waits for the DHCP lease, on DHCP cards only
      wait_for_ip = card.dhcp ? { timeout = 300, source = "lease" } : null
    }]

    # Graphical console: Cockpit (Machines page), or ssh -L 5900:127.0.0.1:59xx debian@10.99.0.1
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }

  # A new disk is only read by a new VM: otherwise QEMU keeps running on the deleted old disk
  lifecycle {
    replace_triggered_by = [
      libvirt_volume.system,
      libvirt_volume.cloudinit,
    ]
  }
}
