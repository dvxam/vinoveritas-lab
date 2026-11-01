# Disques et images du labo, dans /var/lib/libvirt/images/labo sur le serveur
resource "libvirt_pool" "labo" {
  name = "labo"
  type = "dir"

  target = {
    path = "/var/lib/libvirt/images/labo"
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

# Image cloud Debian 13 : base commune des disques des VM Debian
resource "libvirt_volume" "debian13" {
  name = "debian-13-genericcloud-amd64.qcow2"
  pool = libvirt_pool.labo.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    }
  }
}

resource "libvirt_volume" "windows" {
  for_each = var.iso_windows

  name = "${each.key}.iso"
  pool = libvirt_pool.labo.name

  target = {
    format = { type = "raw" }
  }

  create = {
    content = {
      url = each.value
    }
  }
}

# L'ISO pfSense se télécharge sur le site de Netgate, pas par un lien direct :
# la déposer à la main dans /var/lib/libvirt/images/labo/pfsense.iso
