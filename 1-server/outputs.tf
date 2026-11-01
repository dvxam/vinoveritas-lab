output "ip" {
  description = "Public address of the server"
  value       = data.ovh_dedicated_server.lab.ip
}

output "reinstall_status" {
  description = "Status of the reinstall started by install_debian"
  value       = var.install_debian ? ovh_dedicated_server_reinstall_task.debian[0].status : "disabled (install_debian = false)"
}

output "wireguard_endpoint" {
  description = "Endpoint for the Mac's WireGuard tunnels"
  value       = "${data.ovh_dedicated_server.lab.ip}:${var.wg_port}"
}

output "wireguard_server_key_command" {
  description = "Command that prints the server's public key, for the Mac's tunnels"
  value       = "ssh ${var.ssh_user}@${data.ovh_dedicated_server.lab.ip} sudo cat /etc/wireguard/server.pub"
}
