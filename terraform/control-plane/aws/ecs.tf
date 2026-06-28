# -----------------------------------------------------------------------------
# ECS/Fargate control-plane (role-separated services)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "events" {
  name              = "/ecs/${var.project_name}/controlplane-events"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-controlplane-events-logs" }
}

resource "aws_cloudwatch_log_group" "registry" {
  name              = "/ecs/${var.project_name}/controlplane-registry"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-controlplane-registry-logs" }
}

resource "aws_cloudwatch_log_group" "controller" {
  name              = "/ecs/${var.project_name}/controlplane-controller"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-controlplane-controller-logs" }
}

resource "aws_ecs_cluster" "controlplane" {
  name = "${var.project_name}-controlplane"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-controlplane-cluster" }
}

resource "aws_lb" "events" {
  name                       = "${var.project_name}-events"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.events_lb.id]
  subnets                    = [for subnet in aws_subnet.public : subnet.id]
  drop_invalid_header_fields = true

  tags = { Name = "${var.project_name}-events-alb" }
}

resource "aws_lb_target_group" "events" {
  name        = "${var.project_name}-events"
  port        = var.events_task_port
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = aws_vpc.controlplane.id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = var.events_health_check_path
    matcher             = var.events_health_check_matcher
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = { Name = "${var.project_name}-events-tg" }
}

resource "aws_lb_listener" "events_https" {
  load_balancer_arn = aws_lb.events.arn
  port              = var.events_listener_port
  protocol          = "HTTPS"
  certificate_arn   = local.effective_events_acm_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.events.arn
  }

  lifecycle {
    precondition {
      condition     = local.effective_events_acm_certificate_arn != ""
      error_message = "Events HTTPS listener requires an ACM cert. Set events_acm_certificate_arn or set events_domain_name for auto-generated ACM."
    }
  }

  depends_on = [terraform_data.validate_events_tls]
}

resource "aws_lb" "registry" {
  name               = "${var.project_name}-registry"
  internal           = var.registry_internal
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = { Name = "${var.project_name}-registry-nlb" }
}

resource "aws_lb_target_group" "registry" {
  name        = "${var.project_name}-registry"
  port        = var.registry_task_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.controlplane.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 6
    interval            = 15
  }

  tags = { Name = "${var.project_name}-registry-tg" }
}

resource "aws_lb_listener" "registry_tcp" {
  load_balancer_arn = aws_lb.registry.arn
  port              = var.registry_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.registry.arn
  }
}

locals {
  events_bootstrap_script = <<EOT
    set -eu
    mkdir -p /tmp/firework/tls
    printf '%s' "$EVENTS_TLS_CERT_PEM" > /tmp/firework/tls/controlplane.crt
    printf '%s' "$EVENTS_TLS_KEY_PEM" > /tmp/firework/tls/controlplane.key
    chmod 0600 /tmp/firework/tls/controlplane.key
    {
      printf '%s\n' \
        'role: "events"' \
        'registry_listen_addr: "${var.registry_listen_addr}"' \
        'events_listen_addr: "${var.events_listen_addr}"' \
        'state:' \
        '  backend: "s3"' \
        '  prefix: "${local.state_prefix_clean}"' \
        '  s3:' \
        '    bucket: "${aws_s3_bucket.configs.id}"' \
        '    region: "${var.aws_region}"' \
        '    endpoint_url: "${var.state_s3_endpoint_url}"' \
        '    force_path_style: ${var.state_s3_force_path_style}' \
        'leader_lease_ttl: "${var.leader_lease_ttl}"' \
        'leader_renew_interval: "${var.leader_renew_interval}"' \
        'controller_tick: "${var.controller_tick}"' \
        'target_branch: "${var.target_branch}"' \
        'config_dir: "${var.config_dir}"' \
        'git_repo_url: "${var.git_repo_url}"' \
        'reconcile_on_start: ${var.reconcile_on_start}' \
        "github_webhook_secret: \"$GITHUB_WEBHOOK_SECRET\"" \
        'tls:' \
        '  cert_file: "/tmp/firework/tls/controlplane.crt"' \
        '  key_file: "/tmp/firework/tls/controlplane.key"'
    } > /tmp/firework/controlplane.yaml
    chmod 0600 /tmp/firework/controlplane.yaml
    exec ${var.controlplane_binary_path} --config /tmp/firework/controlplane.yaml
  EOT

  registry_bootstrap_script = <<EOT
    set -eu
    mkdir -p /tmp/firework/tls /tmp/firework/pki
    printf '%s' "$REGISTRY_TLS_CERT_PEM" > /tmp/firework/tls/controlplane.crt
    printf '%s' "$REGISTRY_TLS_KEY_PEM" > /tmp/firework/tls/controlplane.key
    printf '%s' "$REGISTRY_CLIENT_CA_PEM" > /tmp/firework/pki/node-ca.crt
%{if local.registry_enrollment_enabled}
    printf '%s' "$REGISTRY_ENROLLMENT_CA_PEM" > /tmp/firework/pki/enrollment-ca.crt
    printf '%s' "$REGISTRY_ENROLLMENT_CA_KEY_PEM" > /tmp/firework/pki/enrollment-ca.key
%{endif}
    chmod 0600 /tmp/firework/tls/controlplane.key
%{if local.registry_enrollment_enabled}
    chmod 0600 /tmp/firework/pki/enrollment-ca.key
%{endif}
    {
      printf '%s\n' \
        'role: "registry"' \
        'registry_listen_addr: "${var.registry_listen_addr}"' \
        'events_listen_addr: "${var.events_listen_addr}"' \
        'state:' \
        '  backend: "s3"' \
        '  prefix: "${local.state_prefix_clean}"' \
        '  s3:' \
        '    bucket: "${aws_s3_bucket.configs.id}"' \
        '    region: "${var.aws_region}"' \
        '    endpoint_url: "${var.state_s3_endpoint_url}"' \
        '    force_path_style: ${var.state_s3_force_path_style}' \
        'leader_lease_ttl: "${var.leader_lease_ttl}"' \
        'leader_renew_interval: "${var.leader_renew_interval}"' \
        'controller_tick: "${var.controller_tick}"' \
        'target_branch: "${var.target_branch}"' \
        'config_dir: "${var.config_dir}"' \
        'git_repo_url: "${var.git_repo_url}"' \
        'reconcile_on_start: ${var.reconcile_on_start}' \
        'tls:' \
        '  cert_file: "/tmp/firework/tls/controlplane.crt"' \
        '  key_file: "/tmp/firework/tls/controlplane.key"' \
        '  client_ca_file: "/tmp/firework/pki/node-ca.crt"'
%{if local.registry_enrollment_enabled}
      printf '%s\n' \
        'enrollment:' \
        '  ca_file: "/tmp/firework/pki/enrollment-ca.crt"' \
        '  ca_key_file: "/tmp/firework/pki/enrollment-ca.key"' \
        '  node_cert_ttl: "${var.registry_node_cert_ttl}"'
%{if local.registry_bootstrap_token_enabled}
      printf '%s\n' \
        '  bootstrap_tokens:' \
        "    - token: \"$REGISTRY_BOOTSTRAP_TOKEN\""
%{if var.registry_bootstrap_node_id != ""}
      printf '%s\n' \
        '      node_id: "${var.registry_bootstrap_node_id}"'
%{endif}
%{endif}
%{endif}
    } > /tmp/firework/controlplane.yaml
    chmod 0600 /tmp/firework/controlplane.yaml
    exec ${var.controlplane_binary_path} --config /tmp/firework/controlplane.yaml
  EOT

  controller_bootstrap_script = <<EOT
    set -eu
    mkdir -p /tmp/firework
    {
      printf '%s\n' \
        'role: "controller"' \
        'registry_listen_addr: "${var.registry_listen_addr}"' \
        'events_listen_addr: "${var.events_listen_addr}"' \
        'state:' \
        '  backend: "s3"' \
        '  prefix: "${local.state_prefix_clean}"' \
        '  s3:' \
        '    bucket: "${aws_s3_bucket.configs.id}"' \
        '    region: "${var.aws_region}"' \
        '    endpoint_url: "${var.state_s3_endpoint_url}"' \
        '    force_path_style: ${var.state_s3_force_path_style}' \
        'leader_lease_ttl: "${var.leader_lease_ttl}"' \
        'leader_renew_interval: "${var.leader_renew_interval}"' \
        'controller_tick: "${var.controller_tick}"' \
        'target_branch: "${var.target_branch}"' \
        'config_dir: "${var.config_dir}"' \
        'git_repo_url: "${var.git_repo_url}"' \
        'reconcile_on_start: ${var.reconcile_on_start}'
    } > /tmp/firework/controlplane.yaml
    chmod 0600 /tmp/firework/controlplane.yaml
    exec ${var.controlplane_binary_path} --config /tmp/firework/controlplane.yaml
  EOT

  events_secret_entries = concat(
    [
      { name = "EVENTS_TLS_CERT_PEM", valueFrom = local.effective_events_tls_cert_secret_arn },
      { name = "EVENTS_TLS_KEY_PEM", valueFrom = local.effective_events_tls_key_secret_arn },
      { name = "GITHUB_WEBHOOK_SECRET", valueFrom = local.effective_github_webhook_secret_arn },
    ],
    var.github_token_secret_arn != "" ? [{ name = "GITHUB_TOKEN", valueFrom = var.github_token_secret_arn }] : [],
  )

  registry_secret_entries = concat(
    [
      { name = "REGISTRY_TLS_CERT_PEM", valueFrom = local.effective_registry_tls_cert_secret_arn },
      { name = "REGISTRY_TLS_KEY_PEM", valueFrom = local.effective_registry_tls_key_secret_arn },
      { name = "REGISTRY_CLIENT_CA_PEM", valueFrom = local.effective_registry_client_ca_secret_arn },
    ],
    local.registry_enrollment_enabled ? [
      { name = "REGISTRY_ENROLLMENT_CA_PEM", valueFrom = local.effective_registry_enrollment_ca_secret_arn },
      { name = "REGISTRY_ENROLLMENT_CA_KEY_PEM", valueFrom = local.effective_registry_enrollment_ca_key_secret_arn },
    ] : [],
    local.registry_bootstrap_token_enabled ? [
      { name = "REGISTRY_BOOTSTRAP_TOKEN", valueFrom = local.effective_registry_bootstrap_token_secret_arn },
    ] : [],
  )

  events_container_definition = merge(
    {
      name       = local.events_container_name
      image      = var.controlplane_image
      essential  = true
      entryPoint = ["/bin/sh", "-lc"]
      command    = [local.events_bootstrap_script]
      portMappings = [
        {
          containerPort = var.events_task_port
          hostPort      = var.events_task_port
          protocol      = "tcp"
        }
      ]
      secrets = local.events_secret_entries
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.events.name
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

  registry_container_definition = merge(
    {
      name       = local.registry_container_name
      image      = var.controlplane_image
      essential  = true
      entryPoint = ["/bin/sh", "-lc"]
      command    = [local.registry_bootstrap_script]
      portMappings = [
        {
          containerPort = var.registry_task_port
          hostPort      = var.registry_task_port
          protocol      = "tcp"
        }
      ]
      secrets = local.registry_secret_entries
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.registry.name
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

  controller_container_definition = merge(
    {
      name       = local.controller_container_name
      image      = var.controlplane_image
      essential  = true
      entryPoint = ["/bin/sh", "-lc"]
      command    = [local.controller_bootstrap_script]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.controller.name
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

resource "aws_ecs_task_definition" "events" {
  family                   = "${var.project_name}-controlplane-events"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.events_task_cpu)
  memory                   = tostring(var.events_task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.events_container_definition])

  lifecycle {
    precondition {
      condition     = local.effective_events_tls_cert_secret_arn != ""
      error_message = "events TLS certificate secret is required (set events_tls_cert_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = local.effective_events_tls_key_secret_arn != ""
      error_message = "events TLS key secret is required (set events_tls_key_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = local.effective_github_webhook_secret_arn != ""
      error_message = "GitHub webhook secret is required (set github_webhook_secret_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = !var.reconcile_on_start || var.git_repo_url != ""
      error_message = "git_repo_url is required when reconcile_on_start is true."
    }
  }

  tags = { Name = "${var.project_name}-controlplane-events-taskdef" }
}

resource "aws_ecs_task_definition" "registry" {
  family                   = "${var.project_name}-controlplane-registry"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.registry_task_cpu)
  memory                   = tostring(var.registry_task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.registry_container_definition])

  lifecycle {
    precondition {
      condition     = local.effective_registry_tls_cert_secret_arn != ""
      error_message = "registry TLS certificate secret is required (set registry_tls_cert_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = local.effective_registry_tls_key_secret_arn != ""
      error_message = "registry TLS key secret is required (set registry_tls_key_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = local.effective_registry_client_ca_secret_arn != ""
      error_message = "registry client CA secret is required (set registry_client_ca_secret_arn or enable auto_create_demo_secrets)."
    }

    precondition {
      condition     = (local.effective_registry_enrollment_ca_secret_arn == "") == (local.effective_registry_enrollment_ca_key_secret_arn == "")
      error_message = "registry enrollment CA cert/key secrets must both be set or both be empty."
    }

    precondition {
      condition     = var.enable_step_ca || (local.registry_enrollment_enabled && local.registry_bootstrap_token_enabled)
      error_message = "When enable_step_ca is false, legacy enrollment CA cert/key and bootstrap token secrets must all be set (or auto-generated)."
    }

    precondition {
      condition     = !local.registry_bootstrap_token_enabled || local.registry_enrollment_enabled
      error_message = "Registry bootstrap token requires registry enrollment CA cert/key."
    }

    precondition {
      condition     = var.registry_bootstrap_node_id == "" || local.registry_bootstrap_token_enabled
      error_message = "registry_bootstrap_node_id requires registry_bootstrap_token_secret_arn."
    }
  }

  tags = { Name = "${var.project_name}-controlplane-registry-taskdef" }
}

resource "aws_ecs_task_definition" "controller" {
  family                   = "${var.project_name}-controlplane-controller"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.controller_task_cpu)
  memory                   = tostring(var.controller_task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.controller_container_definition])

  tags = { Name = "${var.project_name}-controlplane-controller-taskdef" }
}

resource "aws_ecs_service" "events" {
  name            = "${var.project_name}-controlplane-events"
  cluster         = aws_ecs_cluster.controlplane.id
  task_definition = aws_ecs_task_definition.events.arn
  desired_count   = var.events_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.events_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.events.arn
    container_name   = local.events_container_name
    container_port   = var.events_task_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.events_https]

  tags = { Name = "${var.project_name}-controlplane-events-svc" }
}

resource "aws_ecs_service" "registry" {
  name            = "${var.project_name}-controlplane-registry"
  cluster         = aws_ecs_cluster.controlplane.id
  task_definition = aws_ecs_task_definition.registry.arn
  desired_count   = var.registry_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.registry_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.registry.arn
    container_name   = local.registry_container_name
    container_port   = var.registry_task_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.registry_tcp]

  tags = { Name = "${var.project_name}-controlplane-registry-svc" }
}

resource "aws_ecs_service" "controller" {
  name            = "${var.project_name}-controlplane-controller"
  cluster         = aws_ecs_cluster.controlplane.id
  task_definition = aws_ecs_task_definition.controller.arn
  desired_count   = var.controller_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.controller_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = { Name = "${var.project_name}-controlplane-controller-svc" }
}

resource "aws_cloudwatch_dashboard" "controlplane" {
  dashboard_name = "${var.project_name}-controlplane-observability"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title  = "ECS Service Health"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ClusterName", aws_ecs_cluster.controlplane.name, "ServiceName", aws_ecs_service.events.name, { stat = "Average", label = "events running" }],
            ["AWS/ECS", "RunningTaskCount", "ClusterName", aws_ecs_cluster.controlplane.name, "ServiceName", aws_ecs_service.registry.name, { stat = "Average", label = "registry running" }],
            ["AWS/ECS", "RunningTaskCount", "ClusterName", aws_ecs_cluster.controlplane.name, "ServiceName", aws_ecs_service.controller.name, { stat = "Average", label = "controller running" }]
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
          title  = "Events ALB Requests"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.events.arn_suffix, { stat = "Sum", label = "requests" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.events.arn_suffix, { stat = "Sum", label = "elb 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.events.arn_suffix, { stat = "Sum", label = "target 5xx" }]
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
          title  = "Registry NLB Health"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/NetworkELB", "HealthyHostCount", "LoadBalancer", aws_lb.registry.arn_suffix, "TargetGroup", aws_lb_target_group.registry.arn_suffix, { stat = "Average", label = "healthy targets" }],
            ["AWS/NetworkELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.registry.arn_suffix, "TargetGroup", aws_lb_target_group.registry.arn_suffix, { stat = "Average", label = "unhealthy targets" }]
          ]
        }
      }
    ]
  })
}
