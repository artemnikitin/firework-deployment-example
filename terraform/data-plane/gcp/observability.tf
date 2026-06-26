locals {
  agent_log_filter = "resource.type=\"gce_instance\" AND labels.\"compute.googleapis.com/resource_name\":\"${local.name_prefix}\""
}

# --- Agent log metric filters (mirrors AWS CloudWatch metric filters) ---

resource "google_logging_metric" "all_config_fetches_failed" {
  name   = "${local.name_prefix}-all-config-fetches-failed"
  filter = "${local.agent_log_filter} AND textPayload:\"all config fetches failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "failed_to_create_service" {
  name   = "${local.name_prefix}-failed-to-create-service"
  filter = "${local.agent_log_filter} AND textPayload:\"failed to create service\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "health_check_failed" {
  name   = "${local.name_prefix}-health-check-failed"
  filter = "${local.agent_log_filter} AND textPayload:\"health check failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "controller_no_nodes_discovered" {
  name   = "${local.name_prefix}-controller-no-nodes-discovered"
  filter = "${local.agent_log_filter} AND textPayload:\"no active nodes available for scheduling\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "controller_insufficient_capacity" {
  name   = "${local.name_prefix}-controller-insufficient-capacity"
  filter = "${local.agent_log_filter} AND textPayload:\"insufficient capacity\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "controller_placement_read_failed" {
  name   = "${local.name_prefix}-controller-placement-read-failed"
  filter = "${local.agent_log_filter} AND textPayload:\"placement read failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Legacy generic error metric (kept for backward compat with existing alerts)
resource "google_logging_metric" "agent_errors" {
  name   = "${local.name_prefix}-agent-errors"
  filter = "${local.agent_log_filter} AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# --- LB access log sink ---

resource "google_storage_bucket" "lb_access_logs" {
  name                        = "${local.name_prefix}-lb-access-logs-${var.gcp_project}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = var.observability_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

resource "google_logging_project_sink" "lb_access" {
  name                   = "${local.name_prefix}-lb-access"
  destination            = "storage.googleapis.com/${google_storage_bucket.lb_access_logs.name}"
  filter                 = "resource.type=\"http_load_balancer\" AND resource.labels.forwarding_rule_name:(\"firework-tenant-https\" OR \"firework-tenant-http\")"
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "lb_sink_writer" {
  bucket = google_storage_bucket.lb_access_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.lb_access.writer_identity
}

# --- Node log archive (retain for operational debugging) ---

resource "google_storage_bucket" "log_archive" {
  name                        = "${local.name_prefix}-node-logs-${var.gcp_project}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = var.observability_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

resource "google_logging_project_sink" "node_archive" {
  name                   = "${local.name_prefix}-node-archive"
  destination            = "storage.googleapis.com/${google_storage_bucket.log_archive.name}"
  filter                 = local.agent_log_filter
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.log_archive.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.node_archive.writer_identity
}

# --- Monitoring dashboard ---

resource "google_monitoring_dashboard" "firework" {
  dashboard_json = jsonencode({
    displayName = "Firework Data-Plane — ${var.gcp_project}"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "LB Request Count (5m)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_RATE" }
                }
              }
            }]
          }
        },
        {
          title = "All Config Fetches Failed"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-all-config-fetches-failed\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "Failed To Create Service"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-failed-to-create-service\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "Health Check Failed"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-health-check-failed\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "No Nodes Discovered"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-controller-no-nodes-discovered\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "Insufficient Capacity"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-controller-insufficient-capacity\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "Placement Read Failed"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-controller-placement-read-failed\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
        {
          title = "Agent Errors"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${local.name_prefix}-agent-errors\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" }
                }
              }
            }]
          }
        },
      ]
    }
  })
}
