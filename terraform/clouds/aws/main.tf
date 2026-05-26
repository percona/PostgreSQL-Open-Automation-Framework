provider "aws" {
  region = var.aws_region
}

# ── etcd resolution + validation locals ──────────────────────────────────────

locals {
  vm_names = [for v in var.vms : v.name]

  resolved_etcd_hosts = (
    length(var.etcd_hosts) > 0 ? var.etcd_hosts : var.database_hosts
  )

  unknown_database_hosts = [
    for n in var.database_hosts : n if !contains(local.vm_names, n)
  ]

  unknown_etcd_hosts = (
    length(var.etcd_hosts) > 0
    ? [for n in var.etcd_hosts : n if !contains(local.vm_names, n) && trimspace(n) == ""]
    : []
  )

  etcd_hosts_external = [
    for n in local.resolved_etcd_hosts : n if !contains(local.vm_names, n)
  ]

  etcd_quorum_ok = !(var.enable_ha && length(local.resolved_etcd_hosts) < 3)
}

data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

# ── Pre-flight ───────────────────────────────────────────────────────────────

resource "terraform_data" "preflight" {
  input = {
    vm_count       = length(var.vms)
    resolved_etcd  = local.resolved_etcd_hosts
    database_hosts = var.database_hosts
    enable_ha      = var.enable_ha
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_database_hosts) == 0
      error_message = "database_hosts contains unknown vm name: ${join(", ", local.unknown_database_hosts)}"
    }

    precondition {
      condition     = length(local.unknown_etcd_hosts) == 0
      error_message = "etcd_hosts contains unknown vm name: ${join(", ", local.unknown_etcd_hosts)}"
    }

    precondition {
      condition     = local.etcd_quorum_ok
      error_message = "HA requires at least 3 etcd nodes; only ${length(local.resolved_etcd_hosts)} resolved"
    }
  }
}

# ── Cloud module + shared inventory rendering ────────────────────────────────

module "vms" {
  source = "../../modules/aws"

  vms            = var.vms
  region         = var.aws_region
  ami            = var.aws_ami
  vpc_id         = var.aws_vpc_id
  subnet_id      = var.aws_subnet_id
  ssh_user       = var.ssh_user
  ssh_public_key = data.local_file.ssh_public_key.content

  depends_on = [terraform_data.preflight]
}

module "inventory" {
  source = "../../modules/inventory"

  provider_name           = "aws"
  vm_facts                = module.vms.vm_facts
  database_hosts          = var.database_hosts
  resolved_etcd_hosts     = local.resolved_etcd_hosts
  etcd_hosts_external     = local.etcd_hosts_external
  ssh_user                = var.ssh_user
  ssh_private_key_path    = var.ssh_private_key_path
  ssh_public_key_path     = var.ssh_public_key_path
  inventory_output_path   = var.inventory_output_path
  credentials_output_path = var.credentials_output_path
}
