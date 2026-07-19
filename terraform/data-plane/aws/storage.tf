# Persistent storage is opt-in. Firework consumes mounted pools and never calls
# AWS provisioning APIs at runtime.

resource "aws_efs_file_system" "shared" {
  count = var.enable_shared_storage ? 1 : 0

  creation_token   = "${var.project_name}-firework-shared"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name      = "${var.project_name}-firework-shared"
    Retention = "manual"
  }

  # Workload removal and ordinary stack changes must not silently delete data.
  # Deliberate teardown is documented in the data-plane README.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_security_group" "efs" {
  count = var.enable_shared_storage ? 1 : 0

  name_prefix = "${var.project_name}-efs-"
  vpc_id      = aws_vpc.main.id
  description = "Allow NFSv4.1 from Firework nodes only"

  ingress {
    description     = "NFS from Firework nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-efs-sg" }
}

resource "aws_efs_mount_target" "shared" {
  count = var.enable_shared_storage ? length(aws_subnet.private) : 0

  file_system_id  = aws_efs_file_system.shared[0].id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_efs_access_point" "shared" {
  count = var.enable_shared_storage && var.shared_storage_use_access_point ? 1 : 0

  file_system_id = aws_efs_file_system.shared[0].id

  root_directory {
    path = "/firework"
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "0750"
    }
  }

  tags = { Name = "${var.project_name}-firework" }
}
