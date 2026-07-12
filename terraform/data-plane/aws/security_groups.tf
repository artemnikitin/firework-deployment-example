# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------

# --- ALB security group ---

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Allow inbound HTTP/HTTPS to ALB"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }

  lifecycle { create_before_destroy = true }
}

# --- Node security group ---

resource "aws_security_group" "nodes" {
  name_prefix = "${var.project_name}-nodes-"
  vpc_id      = aws_vpc.main.id
  description = "Allow Traefik traffic from ALB; intra-VPC for east-west VM routing"

  # ALB forwards all tenant traffic to Traefik on each node.
  ingress {
    description     = "Traefik from ALB"
    from_port       = var.traefik_port
    to_port         = var.traefik_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Node-to-node communication within the VPC (east-west VM-to-VM traffic
  # routed through VPC when services span multiple nodes).
  ingress {
    description = "Intra-VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nodes-sg" }

  lifecycle { create_before_destroy = true }
}
