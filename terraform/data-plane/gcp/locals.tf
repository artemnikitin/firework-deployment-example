locals {
  name_prefix        = "${var.deployment_name}-node"
  node_image_project = var.node_image_project != "" ? var.node_image_project : var.gcp_project
  common_labels = {
    application = "firework"
    plane       = "data"
    managed_by  = "terraform"
  }
}
