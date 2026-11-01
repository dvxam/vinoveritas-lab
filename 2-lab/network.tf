# NAT network, like VMnet8. "open" mode: libvirt adds no firewall rules.
# NAT to the Internet is set up by 1-server/ (lab-nat service), and the Mac reaches the VMs through the tunnel.
resource "libvirt_network" "nat" {
  name      = "nat"
  autostart = true

  bridge = {
    name = "lab-nat"
  }

  forward = {
    mode = "open"
  }

  ips = [{
    address = "192.168.206.1" # the server
    prefix  = 24

    dhcp = {
      ranges = [{
        start = "192.168.206.100"
        end   = "192.168.206.199"
      }]
    }
  }]
}

# One isolated network per segment, no address and no way out: the equivalent of VMware LAN Segments.
# The bridge does not filter VLANs: the pfSense <-> OVS trunk carries tagged frames.
resource "libvirt_network" "segment" {
  for_each = toset(local.segments)

  name      = each.key
  autostart = true

  bridge = {
    name = each.key
  }
}

locals {
  segments = ["seg-trunk", "seg-admin", "seg-dc", "seg-fs", "seg-cli", "seg-backup", "seg-siem"]
}
