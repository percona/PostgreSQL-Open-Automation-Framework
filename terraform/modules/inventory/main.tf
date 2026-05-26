locals {
  # External (already-existing) etcd members have no Terraform-managed facts;
  # they appear in the inventory with their name echoed as ansible_host and no
  # data_disk_* vars. Operators can override via host_vars / group_vars.
  database_inventory = [
    for n in var.database_hosts : {
      name              = n
      ip                = try(var.vm_facts[n].public_ip, n)
      data_disk_size_gb = try(var.vm_facts[n].data_disk_size_gb, 0)
      data_disk_device  = try(var.vm_facts[n].data_disk_device, "")
    }
  ]

  etcd_inventory = [
    for n in var.resolved_etcd_hosts : {
      name              = n
      ip                = try(var.vm_facts[n].public_ip, n)
      data_disk_size_gb = try(var.vm_facts[n].data_disk_size_gb, 0)
      data_disk_device  = try(var.vm_facts[n].data_disk_device, "")
    }
  ]

  credentials = {
    provider             = var.provider_name
    ssh_user             = var.ssh_user
    ssh_private_key_file = pathexpand(var.ssh_private_key_path)
    ssh_public_key_file  = pathexpand(var.ssh_public_key_path)
    generated_at         = timestamp()
  }
}

resource "local_file" "inventory" {
  filename        = var.inventory_output_path
  file_permission = "0644"

  content = templatefile("${path.module}/templates/ansible_inventory.tmpl", {
    provider             = var.provider_name
    generated_at         = timestamp()
    ssh_user             = var.ssh_user
    ssh_private_key_file = pathexpand(var.ssh_private_key_path)
    database_hosts       = local.database_inventory
    etcd_hosts           = local.etcd_inventory
  })
}

resource "local_sensitive_file" "credentials" {
  filename        = var.credentials_output_path
  file_permission = "0600"
  content         = jsonencode(local.credentials)
}
