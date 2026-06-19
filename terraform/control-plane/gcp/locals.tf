locals {
  name_prefix             = "firework-cp"
  state_prefix_with_slash = "${trim(var.state_prefix, "/")}/"
  common_labels = {
    application = "firework"
    plane       = "control"
    managed_by  = "terraform"
  }
}
