locals {
  cle_ssh = trimspace(file(pathexpand(var.cle_ssh_publique)))

  # VM Debian créées depuis l'image cloud : cloud-init pose le nom, l'IP, le compte et la clé SSH.
  # Les MAC sont fixes : cloud-init s'en sert pour reconnaître chaque carte.
  debian = {
    admin01 = {
      ram     = 2048
      disque  = 16
      donnees = 0
      reseau = [
        { reseau = "seg-admin", mac = "02:50:00:00:10:10", ip = "10.50.10.10/24", passerelle = "10.50.10.1" },
        { reseau = "nat", mac = "02:50:00:00:10:11", ip = "192.168.206.10/24", passerelle = null }, # lien temporaire, sans passerelle
      ]
    }
    siem01 = {
      ram     = 8192
      disque  = 40
      donnees = 0
      reseau  = [{ reseau = "seg-siem", mac = "02:50:00:00:20:30", ip = "10.50.20.30/24", passerelle = "10.50.20.1" }]
    }
    backup01 = {
      ram     = 2048
      disque  = 16
      donnees = 80 # dépôt des sauvegardes
      reseau  = [{ reseau = "seg-backup", mac = "02:50:00:00:40:10", ip = "10.50.40.10/24", passerelle = "10.50.40.1" }]
    }
  }

  # Cartes de la VM OVS, avec des MAC fixes : elles ne changent plus à la reconstruction
  ovs_cartes = [
    { reseau = "nat", mac = "02:50:00:00:01:00" }, # temporaire, pour le premier passage d'ovs.yml
    { reseau = "seg-trunk", mac = "02:50:00:00:01:01" },
    { reseau = "seg-admin", mac = "02:50:00:00:01:10" },
    { reseau = "seg-dc", mac = "02:50:00:00:01:20" },
    { reseau = "seg-fs", mac = "02:50:00:00:01:21" },
    { reseau = "seg-siem", mac = "02:50:00:00:01:22" },
    { reseau = "seg-cli", mac = "02:50:00:00:01:30" },
    { reseau = "seg-backup", mac = "02:50:00:00:01:40" },
  ]

  # Installation à la console (VNC) depuis l'ISO ; nom et IP posés à la première ouverture
  windows = {
    dc01     = { iso = "ws2022", ram = 4096, disque = 40, donnees = 0, reseau = "seg-dc" }
    fs01     = { iso = "ws2022", ram = 4096, disque = 40, donnees = 40, reseau = "seg-fs" } # D:\Partages
    client01 = { iso = "win11", ram = 6144, disque = 64, donnees = 0, reseau = "seg-cli" }
  }

  # Données des VM (disques de 2e niveau), à plat pour for_each
  disques_donnees = merge(
    { for nom, vm in local.debian : nom => vm.donnees if vm.donnees > 0 },
    { for nom, vm in local.windows : nom => vm.donnees if vm.donnees > 0 && var.creer_windows },
  )

  # Console graphique joignable seulement depuis le serveur : ssh -L 5900:127.0.0.1:5900 …
  vnc = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
}

# --- Disques -------------------------------------------------------------------------

resource "libvirt_volume" "systeme_debian" {
  for_each = merge(local.debian, { ovs = { disque = 8 } })

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.labo.name
  capacity      = each.value.disque
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.debian13.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "systeme_vide" {
  for_each = merge(
    { pfsense = 16 },
    var.creer_windows ? { for nom, vm in local.windows : nom => vm.disque } : {},
  )

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.labo.name
  capacity      = each.value
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "donnees" {
  for_each = local.disques_donnees

  name          = "${each.key}-donnees.qcow2"
  pool          = libvirt_pool.labo.name
  capacity      = each.value
  capacity_unit = "GiB"

  target = {
    format = { type = "qcow2" }
  }
}

# --- cloud-init ----------------------------------------------------------------------

resource "libvirt_cloudinit_disk" "debian" {
  for_each = merge(local.debian, { ovs = { reseau = [] } })

  name = "${each.key}-cloudinit"

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  user_data = join("\n", ["#cloud-config", yamlencode({
    users = [{
      name                = var.compte_admin
      groups              = ["sudo"]
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = [local.cle_ssh]
    }]
  })])

  # OVS : DHCP sur la carte nat seulement ; ovs.yml crée le reste
  network_config = yamlencode({
    version = 2
    ethernets = each.key == "ovs" ? {
      nat = { match = { macaddress = local.ovs_cartes[0].mac }, dhcp4 = true }
      } : {
      for i, carte in each.value.reseau : "carte${i}" => merge(
        {
          match       = { macaddress = carte.mac }
          addresses   = [carte.ip]
          nameservers = { addresses = [each.value.reseau[0].passerelle] } # pfSense, dans le VLAN de la machine
        },
        carte.passerelle == null ? {} : { routes = [{ to = "default", via = carte.passerelle }] },
      )
    }
  })
}

resource "libvirt_volume" "cloudinit" {
  for_each = libvirt_cloudinit_disk.debian

  name = "${each.key}-cloudinit.iso"
  pool = libvirt_pool.labo.name

  target = {
    format = { type = "raw" }
  }

  create = {
    content = {
      url = each.value.path
    }
  }
}

# --- VM Debian (ADMIN01, SIEM01, BACKUP01) et OVS ------------------------------------

resource "libvirt_domain" "debian" {
  for_each = merge(
    { for nom, vm in local.debian : nom => { ram = vm.ram, cartes = vm.reseau } },
    { ovs = { ram = 1024, cartes = local.ovs_cartes } },
  )

  name        = each.key
  type        = "kvm"
  vcpu        = each.key == "ovs" ? 1 : 2
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
    disks = concat(
      [{
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.systeme_debian[each.key].name } }
        target = { bus = "virtio", dev = "vda" }
        driver = { name = "qemu", type = "qcow2" }
      }],
      contains(keys(local.disques_donnees), each.key) ? [{
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.donnees[each.key].name } }
        target = { bus = "virtio", dev = "vdb" }
        driver = { name = "qemu", type = "qcow2" }
      }] : [],
      [{
        device = "cdrom"
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.cloudinit[each.key].name } }
        target = { bus = "sata", dev = "sda" }
      }],
    )

    interfaces = [for carte in each.value.cartes : {
      model  = { type = "virtio" }
      mac    = { address = carte.mac }
      source = { network = { network = carte.reseau } }
    }]

    graphics = local.vnc
  }

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}

# --- pfSense -------------------------------------------------------------------------

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

  devices = {
    # Disque vide en premier : tant qu'il n'est pas installé, la VM démarre sur l'ISO
    disks = [
      {
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.systeme_vide["pfsense"].name } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      },
      {
        device = "cdrom"
        source = { file = { file = "${libvirt_pool.labo.target.path}/pfsense.iso" }, startup_policy = "optional" }
        target = { bus = "sata", dev = "sdb" }
        boot   = { order = 2 }
      },
    ]

    # Cartes e1000 : pfSense les nomme em0 et em1, comme sur VMware, donc config.xml se restaure tel quel
    interfaces = [
      {
        model  = { type = "e1000" }
        source = { network = { network = "nat" } }
      },
      {
        model  = { type = "e1000" }
        source = { network = { network = "seg-trunk" } }
      },
    ]

    graphics = local.vnc
  }

  depends_on = [libvirt_network.nat, libvirt_network.segment]
}

# --- Windows (DC01, FS01, CLIENT01) --------------------------------------------------

resource "libvirt_domain" "windows" {
  for_each = var.creer_windows ? local.windows : {}

  name        = each.key
  type        = "kvm"
  vcpu        = 2
  memory      = each.value.ram
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = { mode = "host-passthrough" }

  # UEFI avec Secure Boot et puce TPM 2.0 : exigés par Windows 11
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }

  features = {
    acpi = true
    smm  = { state = "on" }
  }

  devices = {
    # Disques SATA et carte e1000e : l'installeur Windows les reconnaît sans pilote VirtIO
    disks = concat(
      [{
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.systeme_vide[each.key].name } }
        target = { bus = "sata", dev = "sda" }
        driver = { name = "qemu", type = "qcow2" }
        boot   = { order = 1 }
      }],
      each.value.donnees > 0 ? [{
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.donnees[each.key].name } }
        target = { bus = "sata", dev = "sdb" }
        driver = { name = "qemu", type = "qcow2" }
      }] : [],
      [{
        device = "cdrom"
        source = { volume = { pool = libvirt_pool.labo.name, volume = libvirt_volume.windows[each.value.iso].name } }
        target = { bus = "sata", dev = "sdc" }
        boot   = { order = 2 }
      }],
    )

    interfaces = [{
      model  = { type = "e1000e" }
      source = { network = { network = each.value.reseau } }
    }]

    tpms = [{
      model   = "tpm-crb"
      backend = { emulator = { version = "2.0" } }
    }]

    graphics = local.vnc
  }

  depends_on = [libvirt_network.segment]
}
