variable "uri_libvirt" {
  description = "Connexion à libvirt : par le tunnel WireGuard, avec le compte debian"
  type        = string
  default     = "qemu+sshcmd://debian@10.99.0.1/system"
}

variable "compte_admin" {
  description = "Compte créé par cloud-init sur les VM Debian"
  type        = string
}

variable "cle_ssh_publique" {
  description = "Clé SSH publique posée par cloud-init sur les VM Debian"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "iso_windows" {
  description = "Liens de l'Evaluation Center de Microsoft, version française"
  type        = map(string) # { ws2022 = "...", win11 = "..." }
}

variable "creer_windows" {
  description = "Passer à true pour créer DC01, FS01 et CLIENT01"
  type        = bool
  default     = false
}
