output "path" {
  description = "Path of the ISO on the server, known once downloaded"
  value       = var.path
  depends_on  = [terraform_data.download]
}
