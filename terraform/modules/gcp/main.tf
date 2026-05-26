locals {
  vms_by_name = { for v in var.vms : v.name => v }
}

resource "google_compute_disk" "data" {
  for_each = local.vms_by_name

  name = "${each.value.name}-data"
  type = "pd-balanced"
  zone = var.zone
  size = each.value.storage_gb
}

resource "google_compute_instance" "vm" {
  for_each = local.vms_by_name

  name         = each.value.name
  machine_type = each.value.instance_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  attached_disk {
    source      = google_compute_disk.data[each.key].self_link
    device_name = "${each.value.name}-data"
  }

  network_interface {
    network = "default"
    access_config {} # ephemeral public IP
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }

  tags = ["poaf"]
}
