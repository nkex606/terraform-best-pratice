provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

module "network" {
  source  = "terraform-google-modules/network/google"
  version = "9.0.0"

  project_id   = var.project
  network_name = var.vpc
  subnets = [
    for s in var.subnets : {
      subnet_name   = s.name
      subnet_ip     = s.cidr
      subnet_region = var.region
    }
  ]
  ingress_rules = [
    for rule in var.ingress_rules : {
      name          = "${var.vpc}-${rule.name}"
      source_ranges = rule.source_ranges
      target_tags   = rule.target_tags
      allow         = lookup(rule, "allow", [])
      deny          = lookup(rule, "deny", [])
    }
  ]
}

resource "google_compute_disk" "vm_disk" {
  for_each   = var.attached_disks
  name       = "${var.vpc}-${each.key}-data"
  type       = each.value.type
  size       = each.value.size
  depends_on = [module.network]
}

resource "google_compute_instance" "vm" {
  for_each     = var.instances
  name         = "${var.vpc}-${each.key}"
  machine_type = each.value.machine_type
  zone         = var.zone

  tags                      = each.value.tags
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = each.value.image
      size  = each.value.boot_disk_size
    }
  }

  network_interface {
    subnetwork = each.value.subnet
    dynamic "access_config" {
      for_each = each.value.static_ip == true ? [1] : []
      content {
        nat_ip = google_compute_address.default[each.key].address
      }
    }
  }

  service_account {
    email  = var.default_sa
    scopes = ["cloud-platform"]
  }

  lifecycle {
    ignore_changes = [attached_disk]
  }

  depends_on = [
    module.network,
    google_compute_disk.vm_disk
  ]
}

resource "google_compute_attached_disk" "vm_attached_disks" {
  for_each = var.attached_disks
  disk     = google_compute_disk.vm_disk[each.key].id
  instance = google_compute_instance.vm[each.value.instance].id
  depends_on = [
    google_compute_disk.vm_disk,
    google_compute_instance.vm
  ]
}