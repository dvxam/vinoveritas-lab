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

variable "extra_ssh_public_keys" {
  description = "Other SSH public keys installed by cloud-init: the server account, so Ansible can run from the server"
  type        = list(string)
  default = [
    # debian@pve (~/.ssh/id_ed25519.pub on the server); changes if the server is reinstalled
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN3st8rUdJhCJnsXZQY24uf2dP6Hyrm7bBVU552/UE34 debian@pve",
  ]
}
