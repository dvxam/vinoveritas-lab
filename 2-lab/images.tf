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

# Base of every Debian VM (modules/debian_vm)
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

# Windows Server 2022, DC01 and FS01: evaluation (180 days), English, from Microsoft's
# Evaluation Center. 5 GB; Microsoft publishes no checksum next to this link.
module "windows_server_iso" {
  source = "./modules/server_iso"

  url    = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
  path   = "${libvirt_pool.lab.target.path}/windows-server-2022-eval-en-us.iso"
  server = local.server
}

# Windows 11 Enterprise, CLIENT01: evaluation (90 days), English, 24H2 (build 26100). 5.4 GB, no checksum.
module "windows_11_iso" {
  source = "./modules/server_iso"

  url    = "https://go.microsoft.com/fwlink/?linkid=2289031&clcid=0x409&culture=en-us&country=us"
  path   = "${libvirt_pool.lab.target.path}/windows-11-enterprise-eval-en-us.iso"
  server = local.server
}

# pfSense: last CE release published as an ISO; 2.8 only comes through Netgate's online installer.
# Upgrade from the web interface once installed. Gzipped: libvirt cannot unpack it.
module "pfsense_iso" {
  source = "./modules/server_iso"

  url    = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
  sha256 = "883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4" # of the .gz, from the mirror's .sha256
  gzip   = true
  path   = "${libvirt_pool.lab.target.path}/pfSense-CE-2.7.2-RELEASE-amd64.iso"
  server = local.server
}
