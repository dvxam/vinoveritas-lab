# Disks and images, in /var/lib/libvirt/images/lab on the server
resource "libvirt_pool" "lab" {
  name = "lab"
  type = "dir"

  target = {
    path = "/var/lib/libvirt/images/lab"
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

resource "libvirt_volume" "debian13" {
  name = "debian-13-genericcloud-amd64.qcow2"
  pool = libvirt_pool.lab.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    }
  }
}
