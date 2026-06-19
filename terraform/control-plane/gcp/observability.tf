resource "google_logging_metric" "control_plane_errors" {
  name   = "firework_control_plane_errors"
  filter = "resource.type=\"gce_instance\" AND severity>=ERROR AND labels.\"compute.googleapis.com/resource_name\":\"${local.name_prefix}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
