resource "google_logging_metric" "agent_errors" {
  name   = "firework_agent_errors"
  filter = "resource.type=\"gce_instance\" AND severity>=ERROR AND labels.\"compute.googleapis.com/resource_name\":\"firework-node\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_storage_bucket" "log_archive" {
  name                        = "firework-node-logs-${var.gcp_project}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_logging_project_sink" "node_archive" {
  name                   = "firework-node-archive"
  destination            = "storage.googleapis.com/${google_storage_bucket.log_archive.name}"
  filter                 = "resource.type=\"gce_instance\" AND labels.\"compute.googleapis.com/resource_name\":\"firework-node\""
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.log_archive.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.node_archive.writer_identity
}
