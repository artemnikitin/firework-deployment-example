# -----------------------------------------------------------------------------
# Optional step-ca PKI service (ECS/Fargate)
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  name              = "/ecs/${var.project_name}/step-ca"
  retention_in_days = var.observability_log_retention_days

  tags = { Name = "${var.project_name}-step-ca-logs" }
}

resource "aws_security_group" "step_ca_tasks" {
  count = var.enable_step_ca ? 1 : 0

  name_prefix = "${var.project_name}-step-ca-tasks-"
  description = "step-ca ECS tasks"
  vpc_id      = aws_vpc.controlplane.id

  ingress {
    description = "step-ca TLS from allowed clients"
    from_port   = var.step_ca_task_port
    to_port     = var.step_ca_task_port
    protocol    = "tcp"
    cidr_blocks = var.step_ca_allowed_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-step-ca-tasks-sg" }
}

resource "aws_security_group" "step_ca_efs" {
  count = var.enable_step_ca ? 1 : 0

  name_prefix = "${var.project_name}-step-ca-efs-"
  description = "EFS mount access for step-ca tasks"
  vpc_id      = aws_vpc.controlplane.id

  ingress {
    description     = "NFS from step-ca tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.step_ca_tasks[0].id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-step-ca-efs-sg" }
}

resource "aws_efs_file_system" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  encrypted = true

  tags = { Name = "${var.project_name}-step-ca-efs" }
}

resource "aws_efs_mount_target" "step_ca" {
  for_each = var.enable_step_ca ? aws_subnet.public : {}

  file_system_id  = aws_efs_file_system.step_ca[0].id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.step_ca_efs[0].id]
}

resource "aws_efs_access_point" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  file_system_id = aws_efs_file_system.step_ca[0].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/step-ca"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0750"
    }
  }

  tags = { Name = "${var.project_name}-step-ca-ap" }
}

resource "aws_lb" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  name               = substr("${var.project_name}-step-ca", 0, 32)
  internal           = var.step_ca_internal
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = { Name = "${var.project_name}-step-ca-nlb" }
}

resource "aws_lb_target_group" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  name        = substr("${var.project_name}-step-ca", 0, 32)
  port        = var.step_ca_task_port
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

  tags = { Name = "${var.project_name}-step-ca-tg" }
}

resource "aws_lb_listener" "step_ca_tcp" {
  count = var.enable_step_ca ? 1 : 0

  load_balancer_arn = aws_lb.step_ca[0].arn
  port              = var.step_ca_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.step_ca[0].arn
  }
}

locals {
  step_ca_bootstrap_script = <<EOT
    set -eu
    mkdir -p /home/step/secrets /home/step/config /home/step/certs /home/step/db
    printf '%s' "$STEP_CA_PASSWORD" > /home/step/secrets/password
    chmod 0600 /home/step/secrets/password

    if [ ! -s /home/step/config/ca.json ]; then
      step ca init \
        --deployment-type standalone \
        --name "$STEP_CA_NAME" \
        ${local.step_ca_dns_flags} \
        --address "${var.step_ca_listen_addr}" \
        --with-ca-url "${local.step_ca_url}" \
        --provisioner "$STEP_CA_BOOTSTRAP_PROVISIONER_NAME" \
        --password-file /home/step/secrets/password \
        --provisioner-password-file /home/step/secrets/password
    fi

    provisioners_json="$(step ca provisioner list --ca-config /home/step/config/ca.json)"
    if ! printf '%s' "$provisioners_json" | grep -Fq "\"name\": \"$STEP_CA_AWS_PROVISIONER_NAME\"" && \
       ! printf '%s' "$provisioners_json" | grep -Fq "\"name\":\"$STEP_CA_AWS_PROVISIONER_NAME\""; then
      step ca provisioner add "$STEP_CA_AWS_PROVISIONER_NAME" \
        --type AWS \
        ${local.step_ca_aws_account_flags} \
        --x509-default-dur "${var.step_ca_cert_ttl}" \
        --x509-max-dur "${var.step_ca_cert_ttl}" \
        ${local.step_ca_disable_custom_sans_flag} \
        ${local.step_ca_disable_tofu_flag} \
        --ca-config /home/step/config/ca.json
    fi

    exec step-ca /home/step/config/ca.json
  EOT

  step_ca_container_definition = var.enable_step_ca ? merge(
    {
      name      = "${var.project_name}-step-ca"
      image     = var.step_ca_image
      essential = true
      command   = ["/bin/sh", "-lc", local.step_ca_bootstrap_script]
      portMappings = [
        {
          containerPort = var.step_ca_task_port
          hostPort      = var.step_ca_task_port
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "step-ca-data"
          containerPath = "/home/step"
          readOnly      = false
        }
      ]
      environment = [
        { name = "STEP_CA_NAME", value = var.step_ca_name },
        { name = "STEP_CA_BOOTSTRAP_PROVISIONER_NAME", value = var.step_ca_bootstrap_provisioner_name },
        { name = "STEP_CA_AWS_PROVISIONER_NAME", value = var.step_ca_aws_provisioner_name },
      ]
      secrets = [
        { name = "STEP_CA_PASSWORD", valueFrom = local.effective_step_ca_password_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.step_ca[0].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    var.step_ca_image_pull_secret_arn != "" ? {
      repositoryCredentials = {
        credentialsParameter = var.step_ca_image_pull_secret_arn
      }
    } : {},
  ) : null
}

resource "aws_ecs_task_definition" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  family                   = "${var.project_name}-step-ca"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.step_ca_task_cpu)
  memory                   = tostring(var.step_ca_task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.step_ca_container_definition])

  volume {
    name = "step-ca-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.step_ca[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.step_ca[0].id
        iam             = "DISABLED"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.effective_step_ca_password_secret_arn != ""
      error_message = "step-ca password secret is required when enable_step_ca is true (set step_ca_password_secret_arn or enable auto_create_demo_secrets)."
    }
  }

  tags = { Name = "${var.project_name}-step-ca-taskdef" }
}

resource "aws_ecs_service" "step_ca" {
  count = var.enable_step_ca ? 1 : 0

  name            = "${var.project_name}-step-ca"
  cluster         = aws_ecs_cluster.controlplane.id
  task_definition = aws_ecs_task_definition.step_ca[0].arn
  desired_count   = var.step_ca_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.step_ca_tasks[0].id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.step_ca[0].arn
    container_name   = "${var.project_name}-step-ca"
    container_port   = var.step_ca_task_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.step_ca_tcp,
    aws_efs_mount_target.step_ca,
  ]

  tags = { Name = "${var.project_name}-step-ca-svc" }
}
