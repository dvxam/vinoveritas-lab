# Réseau NAT du labo (WAN de pfSense, lien temporaire d'installation), comme VMnet8.
# Mode « open » : libvirt ne pose aucune règle de pare-feu. Le NAT vers Internet est posé
# par 1-serveur/ (service labo-nat), et le Mac joint les VM par le tunnel WireGuard.
resource "libvirt_network" "nat" {
  name      = "nat"
  autostart = true

  bridge = {
    name = "labo-nat"
  }

  forward = {
    mode = "open"
  }

  ips = [{
    address = "192.168.206.1" # le serveur
    prefix  = 24

    dhcp = {
      ranges = [{
        start = "192.168.206.100"
        end   = "192.168.206.199"
      }]
    }
  }]
}

# Un réseau isolé par segment, sans adresse ni sortie : l'équivalent des LAN Segments.
# Le pont ne filtre pas les VLAN : le trunk pfSense ↔ OVS laisse passer les trames étiquetées.
resource "libvirt_network" "segment" {
  for_each = toset(["seg-trunk", "seg-admin", "seg-dc", "seg-fs", "seg-cli", "seg-backup", "seg-siem"])

  name      = each.key
  autostart = true

  bridge = {
    name = each.key
  }
}
