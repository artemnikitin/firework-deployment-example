locals {
  cp_log_filter = "resource.type=\"k8s_container\" AND labels.\"k8s-pod/app\":\"%s\""
}

# Per-role error counts
resource "google_logging_metric" "control_plane_errors" {
  name   = "firework_control_plane_errors"
  filter = format(local.cp_log_filter, local.name_prefix)

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = "role"
      value_type = "STRING"
    }
  }

  label_extractors = {
    role = "EXTRACT(labels.\"k8s-pod/role\")"
  }
}

# events role errors
resource "google_logging_metric" "events_errors" {
  name   = "firework_events_errors"
  filter = "resource.type=\"k8s_container\" AND labels.\"k8s-pod/app\":\"${local.name_prefix}-events\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# registry role errors
resource "google_logging_metric" "registry_errors" {
  name   = "firework_registry_errors"
  filter = "resource.type=\"k8s_container\" AND labels.\"k8s-pod/app\":\"${local.name_prefix}-registry\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# controller role errors
resource "google_logging_metric" "controller_errors" {
  name   = "firework_controller_errors"
  filter = "resource.type=\"k8s_container\" AND labels.\"k8s-pod/app\":\"${local.name_prefix}-controller\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Container restart counts (OOMKill or crash)
resource "google_logging_metric" "container_restarts" {
  name   = "firework_controlplane_restarts"
  filter = "resource.type=\"k8s_pod\" AND labels.\"k8s-pod/app\":\"${local.name_prefix}\" AND jsonPayload.reason:\"BackOff\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = "role"
      value_type = "STRING"
    }
  }

  label_extractors = {
    role = "EXTRACT(labels.\"k8s-pod/role\")"
  }
}
