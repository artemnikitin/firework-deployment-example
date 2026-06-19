data "google_compute_image" "firework_node" {
  family  = var.node_image_family
  project = local.node_image_project
}

resource "google_compute_instance_template" "node" {
  name_prefix    = "${local.name_prefix}-"
  machine_type   = var.node_machine_type
  can_ip_forward = true
  tags           = ["firework-node"]
  labels         = local.common_labels

  disk {
    source_image = data.google_compute_image.firework_node.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-ssd"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.nodes.id
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
    gcs_configs_bucket        = var.config_bucket_name
    gcs_configs_prefix        = var.config_prefix
    gcs_images_bucket         = google_storage_bucket.images.name
    vm_subnet                 = var.vm_subnet
    vm_gateway                = var.vm_gateway
    registry_url              = var.registry_url
    registry_server_name      = var.registry_server_name
    registry_ca_secret        = data.google_secret_manager_secret.registry_ca.secret_id
    registry_bootstrap_secret = data.google_secret_manager_secret.bootstrap_token.secret_id
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
  name = "firework-node-health"

  http_health_check {
    port         = 8080
    request_path = "/ping"
  }
}

resource "google_compute_instance_group_manager" "nodes" {
  name               = "firework-nodes"
  zone               = var.gcp_zone
  base_instance_name = "firework-node"
  target_size        = var.node_count

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

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 1
    max_unavailable_fixed = 0
  }
}
