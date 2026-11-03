variable "name" {
  description = "Name of the VM in libvirt (lower case)"
  type        = string
}

variable "hostname" {
  description = "Windows computer name"
  type        = string
}

variable "edition" {
  description = "server (Windows Server 2022) or client (Windows 11)"
  type        = string

  validation {
    condition     = contains(["server", "client"], var.edition)
    error_message = "edition is server or client."
  }
}

variable "vcpu" {
  type = number
}

variable "ram" {
  description = "Memory, in MiB"
  type        = number
}

variable "disk" {
  description = "System disk, in GiB"
  type        = number
}

variable "data_disk" {
  description = "Second disk (D:), in GiB; 0 = none"
  type        = number
  default     = 0
}

variable "network" {
  description = "libvirt network of the card (access port on OVS)"
  type        = string
}

variable "mac" {
  type = string
}

# Fixed address, server edition only: the client edition gets its address from DHCP
variable "ip" {
  description = "Address with its prefix, e.g. 10.50.20.10/24"
  type        = string
  default     = null
}

variable "gateway" {
  type    = string
  default = null
}

variable "dns" {
  type    = string
  default = null
}

variable "iso_path" {
  description = "Windows installation ISO, on the server"
  type        = string
}

variable "admin_password" {
  description = "Password of the built-in Administrator, used by Ansible afterwards"
  type        = string
}

variable "admin_network" {
  description = "Only network allowed to reach WinRM through the Windows firewall"
  type        = string
}

variable "pool" {
  description = "libvirt pool of the disks"
  type        = string
}

variable "pool_path" {
  description = "Folder of the pool on the server, where the unattend ISO is written"
  type        = string
}

variable "server" {
  description = "SSH access to the server (sudo), to build the unattend ISO"
  type = object({
    host             = string
    user             = string
    private_key_path = string
  })
}
