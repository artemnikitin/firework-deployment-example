# -----------------------------------------------------------------------------
# Authenticated read-only deployment API and same-origin web UI
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}/controlplane-api"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-controlplane-api-logs" }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project_name}-api"
  port        = var.api_task_port
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = aws_vpc.controlplane.id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = "/healthz"
    matcher             = "200"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = { Name = "${var.project_name}-api-tg" }
}

locals {
  api_bootstrap_script = <<EOT
    set -eu
    mkdir -p /tmp/firework/tls /tmp/firework/secrets
    printf '%s' "$API_TLS_CERT_PEM" > /tmp/firework/tls/controlplane.crt
    printf '%s' "$API_TLS_KEY_PEM" > /tmp/firework/tls/controlplane.key
    printf '%s' "$OPERATOR_TOKEN" > /tmp/firework/secrets/operator-token
    chmod 0600 /tmp/firework/tls/controlplane.key /tmp/firework/secrets/operator-token
    {
      printf '%s\n' \
        'role: "api"' \
        'api_listen_addr: "${var.api_listen_addr}"' \
        'operator_token_file: "/tmp/firework/secrets/operator-token"' \
        'state:' \
        '  backend: "s3"' \
        '  prefix: "${local.state_prefix_clean}"' \
        '  s3:' \
        '    bucket: "${aws_s3_bucket.configs.id}"' \
        '    region: "${var.aws_region}"' \
        '    endpoint_url: "${var.state_s3_endpoint_url}"' \
        '    force_path_style: ${var.state_s3_force_path_style}' \
        'node_stale_ttl: "${var.node_stale_ttl}"' \
        'tls:' \
        '  cert_file: "/tmp/firework/tls/controlplane.crt"' \
        '  key_file: "/tmp/firework/tls/controlplane.key"'
    } > /tmp/firework/controlplane.yaml
    chmod 0600 /tmp/firework/controlplane.yaml
    exec ${var.controlplane_binary_path} --config /tmp/firework/controlplane.yaml
  EOT

  api_secret_entries = [
    { name = "API_TLS_CERT_PEM", valueFrom = local.effective_events_tls_cert_secret_arn },
    { name = "API_TLS_KEY_PEM", valueFrom = local.effective_events_tls_key_secret_arn },
    { name = "OPERATOR_TOKEN", valueFrom = local.effective_operator_token_secret_arn },
  ]

  api_container_definition = merge(
    {
      name       = local.api_container_name
      image      = var.controlplane_image
      essential  = true
      entryPoint = ["/bin/sh", "-lc"]
      command    = [local.api_bootstrap_script]
      portMappings = [{
        containerPort = var.api_task_port
        hostPort      = var.api_task_port
        protocol      = "tcp"
      }]
      secrets = local.api_secret_entries
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    var.controlplane_image_pull_secret_arn != "" ? {
      repositoryCredentials = {
        credentialsParameter = var.controlplane_image_pull_secret_arn
      }
    } : {},
  )
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-controlplane-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.api_task_cpu)
  memory                   = tostring(var.api_task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.api_task.arn
  container_definitions    = jsonencode([local.api_container_definition])

  lifecycle {
    precondition {
      condition     = local.effective_events_tls_cert_secret_arn != "" && local.effective_events_tls_key_secret_arn != ""
      error_message = "API TLS uses the events-origin certificate/key secrets, which must be configured."
    }
    precondition {
      condition     = local.effective_operator_token_secret_arn != ""
      error_message = "operator token secret is required (set operator_token_secret_arn or enable auto_create_demo_secrets)."
    }
  }

  tags = { Name = "${var.project_name}-controlplane-api-taskdef" }
}

resource "aws_ecs_service" "api" {
  name                 = "${var.project_name}-controlplane-api"
  cluster              = aws_ecs_cluster.controlplane.id
  task_definition      = aws_ecs_task_definition.api.arn
  desired_count        = var.api_desired_count
  launch_type          = "FARGATE"
  force_new_deployment = true

  triggers = {
    controlplane_deployment_revision = var.controlplane_deployment_revision
  }

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.api_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.api_container_name
    container_port   = var.api_task_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.status]

  tags = { Name = "${var.project_name}-controlplane-api-svc" }
}
