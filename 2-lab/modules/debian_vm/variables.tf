variable "name" {
  description = "Name of the VM in libvirt, also its hostname"
  type        = string
}

variable "vcpu" {
  type = number
}

variable "ram" {
  description = "Memory, in MiB"
  type        = number
}

variable "disk" {
  description = "System disk, in GiB: cloud-init grows the partition to it"
  type        = number
}

variable "cards" {
  description = <<-EOT
    Network cards, in order. Without ip nor dhcp the card is left unconfigured (OVS ports).
    With a gateway, the card carries the default route and the DNS server (nat network).
    name: key of the card in the netplan file, card<index> by default.
  EOT
  type = list(object({
    network = string
    mac     = string
    ip      = optional(string)
    gateway = optional(string)
    dhcp    = optional(bool, false)
    name    = optional(string)
  }))
}

variable "pool" {
  description = "libvirt pool of the disks"
  type        = string
}

variable "base_image" {
  description = "Path of the Debian cloud image, backing file of the system disk"
  type        = string
}

variable "admin_user" {
  description = "Account created by cloud-init"
  type        = string
}

variable "ssh_keys" {
  description = "SSH public keys installed by cloud-init for admin_user"
  type        = list(string)
}
