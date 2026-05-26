output "inventory_path" {
  description = "Path to the rendered Ansible inventory file."
  value       = local_file.inventory.filename
}

output "credentials_path" {
  description = "Path to the credentials JSON sidecar."
  value       = local_sensitive_file.credentials.filename
}

output "credentials" {
  description = "Credentials map. Marked sensitive so it doesn't appear in plan output."
  value       = local.credentials
  sensitive   = true
}
