# OVH server, already rented. This file only does two things:
#   - read the server (IP, service name);
#   - reinstall it with Debian 13, only when install_debian = true.
#
# WARNING: reinstalling wipes ALL the server's disks.
# Set install_debian back to false as soon as the install is done,
# otherwise a later apply could run it again.

data "ovh_dedicated_server" "lab" {
  service_name = var.service_name
}

# OVH installation template (the plan checks that the name exists at OVH)
data "ovh_dedicated_installation_template" "debian" {
  template_name = var.debian_template
}

resource "ovh_dedicated_server_reinstall_task" "debian" {
  count = var.install_debian ? 1 : 0

  service_name = var.service_name
  os           = data.ovh_dedicated_installation_template.debian.template_name

  customizations {
    hostname = var.server_hostname
    ssh_key  = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  # Two disks in software RAID 1: 1 GiB /boot, the rest for /
  storage {
    partitioning {
      disks = 2

      layout {
        file_system = "ext4"
        mount_point = "/boot"
        raid_level  = 1
        size        = 1024
      }

      layout {
        file_system = "ext4"
        mount_point = "/"
        raid_level  = 1
        size        = 0 # 0 = all remaining space
      }
    }
  }
}
