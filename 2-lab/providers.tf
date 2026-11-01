# The server's libvirt, over SSH (the Mac's ssh command: ~/.ssh/config and usual keys)
provider "libvirt" {
  uri = var.libvirt_uri
}
