output "uuid" {
  description = "UUID of the domain (its id is the runtime number)"
  value       = libvirt_domain.vm.uuid
}
