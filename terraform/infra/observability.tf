# -----------------------------------------------------------------------------
# Observability (logs + dashboard)
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  node_agent_log_group_name       = "/firework/${var.project_name}/node/firework-agent"
  node_firecracker_log_group_name = "/firework/${var.project_name}/node/firecracker"
  agent_metric_namespace          = "Firework/${var.project_name}"
  alb_access_logs_prefix          = "alb"
  enricher_function_name          = "${var.project_name}-enricher"
  scheduler_function_name         = "${var.project_name}-scheduler"
  # Scheduler log group is created by the control-plane stack; derived here by name convention.
  scheduler_log_group_name = "/aws/lambda/${var.project_name}-scheduler"
}

resource "aws_cloudwatch_log_group" "node_agent" {
  name              = local.node_agent_log_group_name
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-node-agent-logs" }
}

resource "aws_cloudwatch_log_group" "node_firecracker" {
  name              = local.node_firecracker_log_group_name
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-node-firecracker-logs" }
}

resource "aws_cloudwatch_log_group" "node_prometheus" {
  name              = "/firework/${var.project_name}/node/prometheus"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-node-prometheus-logs" }
}

resource "aws_cloudwatch_log_metric_filter" "all_config_fetches_failed" {
  name           = "${var.project_name}-all-config-fetches-failed"
  log_group_name = aws_cloudwatch_log_group.node_agent.name
  pattern        = "\"all config fetches failed\""

  metric_transformation {
    name      = "AllConfigFetchesFailed"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "failed_to_create_service" {
  name           = "${var.project_name}-failed-to-create-service"
  log_group_name = aws_cloudwatch_log_group.node_agent.name
  pattern        = "\"failed to create service\""

  metric_transformation {
    name      = "FailedToCreateService"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "health_check_failed" {
  name           = "${var.project_name}-health-check-failed"
  log_group_name = aws_cloudwatch_log_group.node_agent.name
  pattern        = "\"health check failed\""

  metric_transformation {
    name      = "HealthCheckFailed"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_no_nodes_discovered" {
  name           = "${var.project_name}-scheduler-no-nodes-discovered"
  log_group_name = local.scheduler_log_group_name
  pattern        = "\"no active nodes discovered\""

  metric_transformation {
    name      = "SchedulerNoNodesDiscovered"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_insufficient_capacity" {
  name           = "${var.project_name}-scheduler-insufficient-capacity"
  log_group_name = local.scheduler_log_group_name
  pattern        = "\"no node has sufficient capacity\""

  metric_transformation {
    name      = "SchedulerInsufficientCapacity"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_placement_read_failed" {
  name           = "${var.project_name}-scheduler-placement-read-failed"
  log_group_name = local.scheduler_log_group_name
  pattern        = "\"failed to read existing placement\""

  metric_transformation {
    name      = "SchedulerPlacementReadFailed"
    namespace = local.agent_metric_namespace
    value     = "1"
  }
}

resource "aws_s3_bucket" "alb_access_logs" {
  bucket_prefix = "${var.project_name}-alb-logs-"
  force_destroy = true

  tags = { Name = "${var.project_name}-alb-access-logs" }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    id     = "expire-old-alb-access-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.alb_access_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "alb_access_logs" {
  statement {
    sid = "AWSLogDeliveryAclCheck"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.alb_access_logs.arn]
  }

  statement {
    sid = "AWSLogDeliveryWrite"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.alb_access_logs.arn}/${local.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = data.aws_iam_policy_document.alb_access_logs.json
}

resource "aws_cloudwatch_dashboard" "observability" {
  dashboard_name = "${var.project_name}-observability"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title   = "ALB Target Health (Traefik)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.main.arn_suffix, "TargetGroup", aws_lb_target_group.traefik.arn_suffix, { label = "traefik healthy nodes" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.main.arn_suffix, "TargetGroup", aws_lb_target_group.traefik.arn_suffix, { label = "traefik unhealthy nodes" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB 5xx"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { label = "ELB 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { label = "Target 5xx" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "firework-agent Error Signals (Log-Derived)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          metrics = [
            [local.agent_metric_namespace, "AllConfigFetchesFailed", { label = "all config fetches failed" }],
            [local.agent_metric_namespace, "FailedToCreateService", { label = "failed to create service" }],
            [local.agent_metric_namespace, "HealthCheckFailed", { label = "health check failed" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Node Capacity (all nodes)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            [local.agent_metric_namespace, "firework_node_capacity_vcpus", { label = "capacity vCPUs", stat = "Sum" }],
            [local.agent_metric_namespace, "firework_node_used_vcpus", { label = "used vCPUs", stat = "Sum" }],
            [local.agent_metric_namespace, "firework_node_capacity_memory_mb", { label = "capacity memory MB", stat = "Sum" }],
            [local.agent_metric_namespace, "firework_node_used_memory_mb", { label = "used memory MB", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Enricher Lambda"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", local.enricher_function_name, { stat = "Sum", label = "errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", local.enricher_function_name, { stat = "Sum", label = "throttles" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.enricher_function_name, { stat = "Average", label = "duration avg" }],
            ["AWS/Lambda", "Invocations", "FunctionName", local.enricher_function_name, { stat = "Sum", label = "invocations" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Scheduler Lambda"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", local.scheduler_function_name, { stat = "Sum", label = "errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", local.scheduler_function_name, { stat = "Sum", label = "throttles" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.scheduler_function_name, { stat = "Average", label = "duration avg" }],
            ["AWS/Lambda", "Invocations", "FunctionName", local.scheduler_function_name, { stat = "Sum", label = "invocations" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "Scheduler Error Signals (Log-Derived)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          metrics = [
            [local.agent_metric_namespace, "SchedulerNoNodesDiscovered", { label = "no nodes discovered" }],
            [local.agent_metric_namespace, "SchedulerInsufficientCapacity", { label = "insufficient capacity" }],
            [local.agent_metric_namespace, "SchedulerPlacementReadFailed", { label = "placement read failed" }]
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "Scheduler — Recent Invocations"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${local.scheduler_log_group_name}' | fields @timestamp, services, nodes, node_configs | filter msg = \"scheduling complete\" | sort @timestamp desc | limit 20"
        }
      }
    ]
  })
}
