variable "libvirt_uri" {
  description = "libvirt connection: through the WireGuard tunnel, with the debian account"
  type        = string
  default     = "qemu+sshcmd://debian@10.99.0.1/system"
}

variable "admin_user" {
  description = "Account created by cloud-init on the VM"
  type        = string
  default     = "root"
}

variable "ssh_public_key_path" {
  description = "SSH public key installed by cloud-init on the VM"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
