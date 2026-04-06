# -----------------------------------------------------------------------------
# Application Load Balancer — routes all tenant traffic through per-node Traefik
# -----------------------------------------------------------------------------

resource "aws_lb" "main" {
  name_prefix        = "fw-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.alb_access_logs.id
    prefix  = local.alb_access_logs_prefix
  }

  depends_on = [aws_s3_bucket_policy.alb_access_logs]

  tags = { Name = "${var.project_name}-alb" }
}

# --- Single target group for Traefik (port 8080 on each node) ---
#
# NOTE — multi-node routing limitation:
# This target group includes ALL nodes. ALB picks a node round-robin, but each
# node's Traefik only knows routes for services scheduled there.
#
# The full fix requires one target group per node and ALB listener rules mapping each tenant
# hostname to the node where that tenant's services are scheduled. That in turn
# requires the control-plane controller to manage ALB rules dynamically after scheduling — a
# larger architectural change tracked separately.

resource "aws_lb_target_group" "traefik" {
  name_prefix = "trafk-"
  port        = var.traefik_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # Traefik exposes /ping on the same entrypoint when ping is enabled.
  health_check {
    enabled             = true
    path                = "/ping"
    port                = tostring(var.traefik_port)
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-traefik-tg" }
}

# --- Listeners ---

# HTTP: redirect everything to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = { Name = "${var.project_name}-http-listener" }
}

# HTTPS: forward all traffic to Traefik. Traefik uses the Host header to
# route to the correct tenant service.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }

  tags = { Name = "${var.project_name}-https-listener" }
}
