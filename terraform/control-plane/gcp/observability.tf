locals {
  cp_log_filter = "resource.type=\"k8s_container\" AND labels.\"k8s-pod/application\":\"firework\" AND labels.\"k8s-pod/plane\":\"control\""
}

# Per-role error counts
resource "google_logging_metric" "control_plane_errors" {
  name   = "${local.name_prefix}-errors"
  filter = local.cp_log_filter

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
  name   = "${local.name_prefix}-events-errors"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"events\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# registry role errors
resource "google_logging_metric" "registry_errors" {
  name   = "${local.name_prefix}-registry-errors"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"registry\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# controller role errors
resource "google_logging_metric" "controller_errors" {
  name   = "${local.name_prefix}-controller-errors"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"controller\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Container restart counts (OOMKill or crash)
resource "google_logging_metric" "container_restarts" {
  name   = "${local.name_prefix}-restarts"
  filter = "resource.type=\"k8s_pod\" AND labels.\"k8s-pod/application\":\"firework\" AND labels.\"k8s-pod/plane\":\"control\" AND jsonPayload.reason:\"BackOff\""

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

resource "google_logging_metric" "controller_no_nodes_discovered" {
  name   = "${local.name_prefix}-controller-no-nodes-discovered"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"controller\" AND textPayload:\"no active nodes available for scheduling\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "controller_insufficient_capacity" {
  name   = "${local.name_prefix}-controller-insufficient-capacity"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"controller\" AND textPayload:\"insufficient capacity\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "controller_placement_read_failed" {
  name   = "${local.name_prefix}-controller-placement-read-failed"
  filter = "${local.cp_log_filter} AND labels.\"k8s-pod/role\":\"controller\" AND textPayload:\"placement read failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
