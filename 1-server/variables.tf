# Values specific to the rented server. No secrets here: OVH credentials go in .env, local values in terraform.tfvars.

variable "service_name" {
  description = "OVH service name of the server (e.g. nsXXXXXXX.ip-X-X-X-X.net), shown in the OVH control panel"
  type        = string
}

# --- SSH access -------------------------------------------------------------------

variable "ssh_user" {
  description = "SSH account on the server: OVH's Debian image refuses root and gives sudo to debian"
  type        = string
  default     = "debian"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed on the server"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key used to run the setup scripts"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_host" {
  description = "SSH address when it is not the public IP: 10.99.0.1 once SSH is only reachable through the tunnel"
  type        = string
  default     = null
}

# --- Debian 13 reinstall ----------------------------------------------------------

variable "install_debian" {
  description = "Switch: true starts the reinstall (wipes the disks). Set back to false afterwards."
  type        = bool
  default     = false
}

variable "debian_template" {
  description = "OVH installation template for Debian 13 (checked by the plan)"
  type        = string
  default     = "debian13_64"
}

variable "server_hostname" {
  description = "Server hostname after install"
  type        = string
  default     = "pve"
}

# --- Packages ---------------------------------------------------------------------

variable "packages" {
  description = "Debian packages installed on the server (convenience tools, Ansible for tests)"
  type        = list(string)
  default     = ["tree", "neovim", "ansible", "git"]
}

# --- WireGuard --------------------------------------------------------------------

variable "wg_mac_public_key" {
  description = "WireGuard public key of the Mac (shown by the WireGuard app)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.wg_mac_public_key))
    error_message = "A WireGuard key is 44 base64 characters ending with \"=\"."
  }
}

variable "wg_port" {
  description = "WireGuard UDP listen port"
  type        = number
  default     = 51820
}

variable "wg_server_address" {
  description = "Server address in the tunnel, in CIDR notation"
  type        = string
  default     = "10.99.0.1/24"
}

variable "wg_network" {
  description = "Tunnel network, source of the outgoing NAT"
  type        = string
  default     = "10.99.0.0/24"
}

variable "wg_mac_address" {
  description = "Mac address in the tunnel"
  type        = string
  default     = "10.99.0.2/32"
}

variable "public_interface" {
  description = "Interface carrying the public address"
  type        = string
  default     = "enp1s0f0"
}

# --- libvirt ----------------------------------------------------------------------

variable "lab_network" {
  description = "Lab NAT network (like VMnet8), created by 2-lab/: goes out to the Internet through the public address"
  type        = string
  default     = "192.168.206.0/24"
}
