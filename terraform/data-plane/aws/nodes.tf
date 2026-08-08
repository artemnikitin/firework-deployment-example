# -----------------------------------------------------------------------------
# EC2 node — Firecracker hosts running microVMs
# -----------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix   = "${var.project_name}-node-"
  image_id      = local.effective_node_ami_id
  instance_type = var.node_instance_type
  key_name      = var.node_key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.node.arn
  }

  # Virtual instance types need the nested virtualization CPU option to expose
  # /dev/kvm to Firecracker. Bare-metal types expose it natively and reject the
  # option, so it is opt-out via node_nested_virtualization.
  dynamic "cpu_options" {
    for_each = var.node_nested_virtualization ? [1] : []

    content {
      nested_virtualization = "enabled"
    }
  }

  # source_dest_check is NOT supported in aws_launch_template.network_interfaces
  # (the Terraform provider omits this attribute). It is disabled at instance
  # launch time via user-data (aws ec2 modify-instance-attribute). This is
  # required for VPC routing of east-west VM traffic between nodes.
  #
  # Note that in public placement this means a node can emit packets with
  # arbitrary source addresses straight to the internet gateway. See the
  # data-plane README.
  network_interfaces {
    associate_public_ip_address = local.node_subnets_are_public
    security_groups             = [aws_security_group.nodes.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.enable_local_storage ? [1] : []
    content {
      device_name = "/dev/sdf"
      ebs {
        volume_size           = var.local_storage_size_gib
        volume_type           = "gp3"
        delete_on_termination = false
        encrypted             = true
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # EC2 limits the raw user-data payload to 16 KiB. The bootstrap script is
  # intentionally larger because it retries transient network/bootstrap work.
  # Amazon Linux cloud-init transparently expands gzip-compressed user data.
  user_data = base64gzip(templatefile("${path.module}/templates/user-data.sh.tpl", {
    s3_configs_bucket                   = local.effective_s3_configs_bucket_id
    s3_configs_prefix                   = local.effective_s3_configs_prefix
    s3_images_bucket                    = var.s3_images_bucket_id
    s3_region                           = var.aws_region
    registry_url                        = local.effective_registry_url
    registry_server_name                = local.effective_registry_server_name
    step_ca_url                         = local.effective_step_ca_url
    step_ca_root_ca_secret_arn          = local.effective_step_ca_root_ca_secret_arn
    step_ca_provisioner                 = local.effective_step_ca_provisioner
    step_ca_subject_suffix              = var.step_ca_subject_suffix
    step_ca_renew_expires_in            = var.step_ca_renew_expires_in
    registry_client_ca_secret_arn       = local.effective_registry_client_ca_secret_arn
    registry_bootstrap_token_secret_arn = local.effective_registry_bootstrap_token_secret_arn
    vm_subnet                           = var.vm_subnet
    vm_gateway                          = var.vm_gateway
    cw_agent_log_group_name             = aws_cloudwatch_log_group.node_agent.name
    cw_firecracker_log_group            = aws_cloudwatch_log_group.node_firecracker.name
    cw_metric_namespace                 = local.agent_metric_namespace
    cw_prometheus_log_group             = aws_cloudwatch_log_group.node_prometheus.name
    traefik_config_dir                  = "/etc/traefik/dynamic"
    ingress_domain                      = trimsuffix(var.domain_name, ".")
    enable_local_storage                = var.enable_local_storage
    local_storage_capacity              = var.local_storage_capacity
    enable_shared_storage               = var.enable_shared_storage
    shared_storage_backend_id           = var.shared_storage_backend_id
    shared_storage_capacity             = var.shared_storage_capacity
    efs_file_system_id                  = var.enable_shared_storage ? aws_efs_file_system.shared[0].id : ""
    efs_access_point_id                 = var.enable_shared_storage && var.shared_storage_use_access_point ? aws_efs_access_point.shared[0].id : ""
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name      = "${var.project_name}-node-volume"
      Retention = "manual"
    }
  }

  tags = { Name = "${var.project_name}-node-lt" }
}

resource "aws_autoscaling_group" "nodes" {
  name_prefix         = "${var.project_name}-node-"
  desired_capacity    = var.node_count
  min_size            = var.node_count
  max_size            = var.node_count
  vpc_zone_identifier = local.node_subnet_ids
  target_group_arns   = [aws_lb_target_group.traefik.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 600

  # Skip the graceful drain (desired→0 then wait). The ASG and its
  # instances are deleted in one API call. Terraform still waits for
  # the ASG to disappear, which requires all instances to terminate.
  # Virtual instances terminate in 1-2 min, but bare-metal types such as
  # c6g.metal can take 15-20 min, so the delete timeout stays generous.
  force_delete = true

  timeouts {
    delete = "30m"
  }

  # Pinned to the concrete latest version rather than "$Latest": an instance
  # refresh does not start when the ASG references "$Latest", so launch-template
  # changes would silently never reach running instances.
  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  # Without this, changing node_network_placement, node_instance_type, or the
  # AMI updates the launch template but leaves running instances untouched.
  # That is dangerous for the private -> public migration in particular: the
  # NAT gateways and private default routes are removed in the same apply, so
  # un-refreshed instances would keep their private subnet and lose egress.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      # node_count defaults to 1, so a rolling refresh has to be allowed to
      # take the only instance out of service.
      min_healthy_percentage = 0
      instance_warmup        = 600
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-node"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  # Do not launch instances until their egress route tables are associated and
  # the S3 gateway endpoint exists. User-data still retries because route/NAT
  # readiness can be transient, but this prevents the normal apply path from
  # racing egress provisioning entirely. Both associations are listed because
  # either one can carry node egress depending on node_network_placement.
  depends_on = [
    aws_efs_mount_target.shared,
    aws_route_table_association.private,
    aws_route_table_association.public,
    aws_vpc_endpoint.s3,
  ]

}
