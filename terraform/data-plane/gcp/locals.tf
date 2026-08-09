locals {
  name_prefix              = "${var.deployment_name}-node"
  controlplane_name_prefix = "${var.deployment_name}-cp"
  peering_name_suffix      = substr(md5(google_compute_network.data_plane.self_link), 0, 8)
  node_network_tag         = "${var.deployment_name}-node"
  node_image_project       = var.node_image_project != "" ? var.node_image_project : var.gcp_project
  common_labels = {
    application = "firework"
    plane       = "data"
    managed_by  = "terraform"
  }
}
