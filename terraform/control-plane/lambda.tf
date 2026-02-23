# -----------------------------------------------------------------------------
# Enricher Lambda + API Gateway (GitHub webhook endpoint)
# -----------------------------------------------------------------------------

locals {
  use_local_zip              = var.enricher_zip_path != ""
  use_local_scheduler_zip    = var.scheduler_zip_path != ""
  cache_dir                  = abspath("${path.module}/.cache")
  cached_zip_path            = abspath("${path.module}/.cache/enricher.zip")
  cached_scheduler_zip_path  = abspath("${path.module}/.cache/scheduler.zip")
  effective_zip_path         = local.use_local_zip ? abspath(var.enricher_zip_path) : local.cached_zip_path
  effective_scheduler_zip    = local.use_local_scheduler_zip ? abspath(var.scheduler_zip_path) : local.cached_scheduler_zip_path
  enricher_metric_namespace  = "Firework/${var.project_name}/Enricher"
  scheduler_metric_namespace = "Firework/${var.project_name}/Scheduler"
}

# Download enricher.zip from GitHub releases when no local path is provided.
resource "null_resource" "download_enricher" {
  count = local.use_local_zip ? 0 : 1

  triggers = {
    version = var.enricher_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p "${local.cache_dir}"
      if [ "${var.enricher_version}" = "latest" ]; then
        DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/artemnikitin/firework/releases/latest \
          | jq -r '(.assets // [])[] | select(.name == "enricher.zip") | .browser_download_url' || true)
      else
        DOWNLOAD_URL="https://github.com/artemnikitin/firework/releases/download/v${var.enricher_version}/enricher.zip"
      fi
      if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "No GitHub release found — creating stub Lambda ZIP as placeholder"
        TMPDIR=$(mktemp -d)
        printf '#!/bin/sh\necho "{\"statusCode\":503,\"body\":\"enricher not yet deployed\"}"\n' > "$TMPDIR/bootstrap"
        chmod +x "$TMPDIR/bootstrap"
        (cd "$TMPDIR" && zip "${local.cached_zip_path}" bootstrap)
        rm -rf "$TMPDIR"
      else
        curl -fsSL "$DOWNLOAD_URL" -o "${local.cached_zip_path}"
      fi
    EOT
  }
}

# --- Lambda function ---

resource "aws_lambda_function" "enricher" {
  function_name = "${var.project_name}-enricher"
  role          = aws_iam_role.enricher.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  timeout       = 60
  memory_size   = 256

  depends_on = [null_resource.download_enricher]

  filename         = local.effective_zip_path
  source_code_hash = local.use_local_zip ? filebase64sha256(local.effective_zip_path) : base64sha256(var.enricher_version)

  environment {
    variables = {
      S3_BUCKET             = aws_s3_bucket.configs.id
      S3_REGION             = var.aws_region
      TARGET_BRANCH         = var.config_repo_branch
      CONFIG_REPO_URL       = var.config_repo_url
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      GITHUB_TOKEN          = var.github_token
      SCHEDULER_LAMBDA_ARN  = aws_lambda_function.scheduler.arn
      SCHEDULER_REGION      = var.aws_region
      EC2_REGION            = var.aws_region
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = { Name = "${var.project_name}-enricher" }
}

resource "aws_cloudwatch_log_group" "enricher" {
  name              = "/aws/lambda/${aws_lambda_function.enricher.function_name}"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-enricher-logs" }
}

resource "aws_cloudwatch_log_group" "webhook_access" {
  name              = "/aws/apigateway/${var.project_name}-webhook-access"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-webhook-access-logs" }
}

# --- API Gateway (HTTP API) for GitHub webhook ---

resource "aws_apigatewayv2_api" "webhook" {
  name          = "${var.project_name}-webhook"
  protocol_type = "HTTP"
  description   = "GitHub webhook endpoint for the firework enricher"

  tags = { Name = "${var.project_name}-webhook-api" }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = true
    # Explicitly set non-zero throttling. Leaving these unset can produce
    # zero values via API update and throttle all webhook traffic (HTTP 429).
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.webhook_access.arn
    format = jsonencode({
      request_id        = "$context.requestId"
      source_ip         = "$context.identity.sourceIp"
      request_time      = "$context.requestTime"
      route_key         = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      response_length   = "$context.responseLength"
      integration_error = "$context.integrationErrorMessage"
    })
  }

  tags = { Name = "${var.project_name}-webhook-stage" }
}

resource "aws_apigatewayv2_integration" "enricher" {
  api_id                 = aws_apigatewayv2_api.webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.enricher.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.enricher.id}"
}

resource "aws_cloudwatch_log_metric_filter" "enrichment_failed" {
  name           = "${var.project_name}-enrichment-failed"
  log_group_name = aws_cloudwatch_log_group.enricher.name
  pattern        = "\"enrichment failed\""

  metric_transformation {
    name      = "EnrichmentFailed"
    namespace = local.enricher_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "webhook_signature_missing" {
  name           = "${var.project_name}-webhook-signature-missing"
  log_group_name = aws_cloudwatch_log_group.enricher.name
  pattern        = "\"missing X-Hub-Signature-256 header\""

  metric_transformation {
    name      = "WebhookSignatureMissing"
    namespace = local.enricher_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "webhook_signature_invalid" {
  name           = "${var.project_name}-webhook-signature-invalid"
  log_group_name = aws_cloudwatch_log_group.enricher.name
  pattern        = "\"invalid X-Hub-Signature-256 header\""

  metric_transformation {
    name      = "WebhookSignatureInvalid"
    namespace = local.enricher_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_no_nodes_discovered" {
  name           = "${var.project_name}-scheduler-no-nodes"
  log_group_name = aws_cloudwatch_log_group.scheduler.name
  pattern        = "\"no active nodes discovered\""

  metric_transformation {
    name      = "SchedulerNoNodesDiscovered"
    namespace = local.scheduler_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_insufficient_capacity" {
  name           = "${var.project_name}-scheduler-no-capacity"
  log_group_name = aws_cloudwatch_log_group.scheduler.name
  pattern        = "\"no node has sufficient capacity\""

  metric_transformation {
    name      = "SchedulerInsufficientCapacity"
    namespace = local.scheduler_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "scheduler_placement_read_failed" {
  name           = "${var.project_name}-scheduler-placement-read-failed"
  log_group_name = aws_cloudwatch_log_group.scheduler.name
  pattern        = "\"failed to read existing placement\""

  metric_transformation {
    name      = "SchedulerPlacementReadFailed"
    namespace = local.scheduler_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_dashboard" "observability" {
  dashboard_name = "${var.project_name}-enricher-observability"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "Enricher Lambda Health"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.enricher.function_name, { stat = "Sum", label = "invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.enricher.function_name, { stat = "Sum", label = "errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.enricher.function_name, { stat = "Sum", label = "throttles" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.enricher.function_name, { stat = "p95", label = "duration p95 ms" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "Webhook API (HTTP API)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.webhook.id, "Stage", aws_apigatewayv2_stage.default.name, { stat = "Sum", label = "request count" }],
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.webhook.id, "Stage", aws_apigatewayv2_stage.default.name, { stat = "Sum", label = "4xx" }],
            ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.webhook.id, "Stage", aws_apigatewayv2_stage.default.name, { stat = "Sum", label = "5xx" }],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.webhook.id, "Stage", aws_apigatewayv2_stage.default.name, { stat = "p95", label = "latency p95 ms" }]
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
          title  = "Enricher Log-Derived Signals"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          metrics = [
            [local.enricher_metric_namespace, "EnrichmentFailed", { label = "enrichment failed" }],
            [local.enricher_metric_namespace, "WebhookSignatureMissing", { label = "signature missing" }],
            [local.enricher_metric_namespace, "WebhookSignatureInvalid", { label = "signature invalid" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Scheduler Lambda Health"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.scheduler.function_name, { stat = "Sum", label = "invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.scheduler.function_name, { stat = "Sum", label = "errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.scheduler.function_name, { stat = "Sum", label = "throttles" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.scheduler.function_name, { stat = "p95", label = "duration p95 ms" }]
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
          title  = "Scheduler Log-Derived Signals"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          metrics = [
            [local.scheduler_metric_namespace, "SchedulerNoNodesDiscovered", { label = "no nodes discovered" }],
            [local.scheduler_metric_namespace, "SchedulerInsufficientCapacity", { label = "insufficient capacity" }],
            [local.scheduler_metric_namespace, "SchedulerPlacementReadFailed", { label = "placement read failed" }]
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
          query  = "SOURCE '${aws_cloudwatch_log_group.scheduler.name}' | fields @timestamp, services, nodes, node_configs | filter msg = \"scheduling complete\" | sort @timestamp desc | limit 20"
        }
      }
    ]
  })
}

# =============================================================================
# Scheduler Lambda
# =============================================================================

# Download scheduler.zip from GitHub releases when no local path is provided.
resource "null_resource" "download_scheduler" {
  count = local.use_local_scheduler_zip ? 0 : 1

  triggers = {
    version = var.scheduler_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p "${local.cache_dir}"
      if [ "${var.scheduler_version}" = "latest" ]; then
        DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/artemnikitin/firework/releases/latest \
          | jq -r '(.assets // [])[] | select(.name == "scheduler.zip") | .browser_download_url' || true)
      else
        DOWNLOAD_URL="https://github.com/artemnikitin/firework/releases/download/v${var.scheduler_version}/scheduler.zip"
      fi
      if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "No GitHub release found for scheduler — creating stub Lambda ZIP as placeholder"
        TMPDIR=$(mktemp -d)
        printf '#!/bin/sh\nprintf "scheduler stub: no binary deployed, refusing to run\n" >&2\nexit 1\n' > "$TMPDIR/bootstrap"
        chmod +x "$TMPDIR/bootstrap"
        (cd "$TMPDIR" && zip "${local.cached_scheduler_zip_path}" bootstrap)
        rm -rf "$TMPDIR"
      else
        curl -fsSL "$DOWNLOAD_URL" -o "${local.cached_scheduler_zip_path}"
      fi
    EOT
  }
}

resource "aws_lambda_function" "scheduler" {
  function_name = "${var.project_name}-scheduler"
  role          = aws_iam_role.scheduler.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  # Scheduler queries CloudWatch + S3 for node discovery and existing placement.
  # Timeout accommodates paginated ListMetrics + GetMetricData calls.
  timeout     = 60
  memory_size = 256

  depends_on = [null_resource.download_scheduler]

  filename         = local.effective_scheduler_zip
  source_code_hash = local.use_local_scheduler_zip ? filebase64sha256(local.effective_scheduler_zip) : base64sha256(var.scheduler_version)

  environment {
    variables = {
      CW_NAMESPACE = var.cw_namespace
      S3_BUCKET    = aws_s3_bucket.configs.id
      S3_PREFIX    = ""
      S3_REGION    = var.aws_region
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = { Name = "${var.project_name}-scheduler" }
}

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/aws/lambda/${aws_lambda_function.scheduler.function_name}"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-scheduler-logs" }
}

# Allow API Gateway to invoke the Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enricher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}

# =============================================================================
# EventBridge — periodic enricher re-sync
# =============================================================================
# Fires every minute so that nodes which come online after the last git push
# eventually receive their correct config (fixes the timing race where the
# scheduler sees no CloudWatch metrics because the node just launched).

resource "aws_cloudwatch_event_rule" "enricher_periodic" {
  name                = "${var.project_name}-enricher-periodic"
  description         = "Trigger enricher every minute for periodic config re-sync"
  schedule_expression = "rate(1 minute)"

  tags = { Name = "${var.project_name}-enricher-periodic" }
}

resource "aws_cloudwatch_event_target" "enricher_periodic" {
  rule      = aws_cloudwatch_event_rule.enricher_periodic.name
  target_id = "enricher"
  arn       = aws_lambda_function.enricher.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enricher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.enricher_periodic.arn
}
