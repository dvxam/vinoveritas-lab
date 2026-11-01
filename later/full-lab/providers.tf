# libvirt du serveur, par SSH (la commande ssh du Mac : ~/.ssh/config et clés habituelles)
provider "libvirt" {
  uri = var.uri_libvirt
}
