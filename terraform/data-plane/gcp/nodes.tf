data "google_compute_image" "firework_node" {
  family  = var.node_image_family
  project = local.node_image_project
}

locals {
  node_machine_series = split("-", var.node_machine_type)[0]
  node_uses_hyperdisk = contains(["c4", "n4"], local.node_machine_series)
  node_requires_gvnic = contains(["c3", "c4", "n4"], local.node_machine_series)
  effective_node_zones = var.node_zones == null ? [
    "${var.gcp_region}-a",
    "${var.gcp_region}-b",
    "${var.gcp_region}-c",
  ] : var.node_zones
}

resource "google_compute_instance_template" "node" {
  name_prefix    = "${local.name_prefix}-"
  machine_type   = var.node_machine_type
  can_ip_forward = true
  tags           = [local.node_network_tag]
  labels         = local.common_labels

  disk {
    source_image = data.google_compute_image.firework_node.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    # N4/C4 only support Hyperdisk. Compute Engine selects the appropriate
    # NVMe interface from the machine type; explicitly setting NVME is rejected
    # for this boot-disk configuration. Keep pd-ssd for an N2 fallback.
    disk_type = local.node_uses_hyperdisk ? "hyperdisk-balanced" : "pd-ssd"
  }

  dynamic "disk" {
    for_each = var.enable_local_storage ? [1] : []
    content {
      auto_delete  = false
      boot         = false
      device_name  = "firework-volumes"
      disk_size_gb = var.local_storage_size_gib
      disk_type    = local.node_uses_hyperdisk ? "hyperdisk-balanced" : "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.nodes.id
    nic_type   = local.node_requires_gvnic ? "GVNIC" : "VIRTIO_NET"
  }

  advanced_machine_features {
    enable_nested_virtualization = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "TERMINATE"
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup-script.sh.tpl", {
    gcp_project               = var.gcp_project
    gcs_configs_bucket        = local.effective_config_bucket_name
    gcs_configs_prefix        = local.effective_config_prefix
    gcs_images_bucket         = var.images_bucket_name
    ingress_domain            = trimsuffix(var.base_domain, ".")
    vm_subnet                 = var.vm_subnet
    vm_gateway                = var.vm_gateway
    registry_url              = local.effective_registry_url
    registry_server_name      = local.effective_registry_server_name
    registry_ca_secret        = data.google_secret_manager_secret.registry_ca.secret_id
    registry_bootstrap_secret = data.google_secret_manager_secret.bootstrap_token.secret_id
    enable_local_storage      = var.enable_local_storage
    local_storage_capacity    = var.local_storage_capacity
    enable_shared_storage     = var.enable_shared_storage
    shared_storage_backend_id = var.shared_storage_backend_id
    shared_storage_capacity   = var.shared_storage_capacity
    filestore_ip              = var.enable_shared_storage ? google_filestore_instance.shared[0].networks[0].ip_addresses[0] : ""
    filestore_share           = var.enable_shared_storage ? google_filestore_instance.shared[0].file_shares[0].name : ""
  })

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_secret_manager_secret_iam_member.registry_ca,
    google_secret_manager_secret_iam_member.bootstrap_token,
    google_storage_bucket_iam_member.configs_reader,
    google_storage_bucket_iam_member.images_reader,
  ]
}

resource "google_compute_health_check" "node" {
  name = "${local.name_prefix}-health"

  http_health_check {
    port         = 8080
    request_path = "/ping"
  }
}

resource "google_compute_region_instance_group_manager" "nodes" {
  name               = "${local.name_prefix}-nodes"
  region             = var.gcp_region
  base_instance_name = "${local.name_prefix}-node"
  target_size        = var.node_count

  # Do not report a successful apply while quota or capacity errors leave the
  # manager with fewer running instances than its target size.
  wait_for_instances        = true
  wait_for_instances_status = "STABLE"

  distribution_policy_zones = local.effective_node_zones

  version {
    instance_template = google_compute_instance_template.node.id
  }

  named_port {
    name = "traefik"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.node.id
    initial_delay_sec = 300
  }

  dynamic "stateful_disk" {
    for_each = var.enable_local_storage ? [1] : []
    content {
      device_name = "firework-volumes"
      delete_rule = "NEVER"
    }
  }

  # A region migration creates a new MIG before the global backend service is
  # switched away from the old one. Without this ordering, Compute Engine
  # rejects deletion because the old MIG is still attached to that backend.
  lifecycle {
    create_before_destroy = true
  }

  update_policy {
    type           = "PROACTIVE"
    minimal_action = "REPLACE"
    # A regional MIG updates proportionally across all selected zones. Fixed
    # values must therefore be zero or at least the three-zone distribution.
    # Keep all current nodes available while one replacement is created per
    # zone.
    max_surge_fixed              = var.enable_local_storage ? 0 : 3
    max_unavailable_fixed        = var.enable_local_storage ? 3 : 0
    replacement_method           = var.enable_local_storage ? "RECREATE" : "SUBSTITUTE"
    instance_redistribution_type = var.enable_local_storage ? "NONE" : "PROACTIVE"
  }
}
