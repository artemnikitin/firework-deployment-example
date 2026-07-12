# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "events_lb" {
  name_prefix = "${var.project_name}-events-lb-"
  description = "Ingress for public events HTTPS endpoint"
  vpc_id      = aws_vpc.controlplane.id

  ingress {
    description = "HTTPS from internet"
    from_port   = var.events_listener_port
    to_port     = var.events_listener_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-events-lb-sg" }
}

resource "aws_security_group" "events_tasks" {
  name_prefix = "${var.project_name}-events-tasks-"
  description = "Events ECS tasks"
  vpc_id      = aws_vpc.controlplane.id

  ingress {
    description     = "HTTPS from events ALB"
    from_port       = var.events_task_port
    to_port         = var.events_task_port
    protocol        = "tcp"
    security_groups = [aws_security_group.events_lb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-events-tasks-sg" }
}

resource "aws_security_group" "registry_tasks" {
  name_prefix = "${var.project_name}-registry-tasks-"
  description = "Registry ECS tasks"
  vpc_id      = aws_vpc.controlplane.id

  ingress {
    description = "Registry TLS from allowed clients"
    from_port   = var.registry_task_port
    to_port     = var.registry_task_port
    protocol    = "tcp"
    cidr_blocks = var.registry_allowed_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-registry-tasks-sg" }
}

resource "aws_security_group" "controller_tasks" {
  name_prefix = "${var.project_name}-controller-tasks-"
  description = "Controller ECS tasks"
  vpc_id      = aws_vpc.controlplane.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-controller-tasks-sg" }
}
