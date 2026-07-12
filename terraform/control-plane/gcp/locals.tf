locals {
  name_prefix             = "${var.deployment_name}-cp"
  state_prefix_with_slash = "${trim(var.state_prefix, "/")}/"
  common_labels = {
    application = "firework"
    plane       = "control"
    managed_by  = "terraform"
  }
}
