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

  # source_dest_check is NOT supported in aws_launch_template.network_interfaces
  # (the Terraform provider omits this attribute). It is disabled at instance
  # launch time via user-data (aws ec2 modify-instance-attribute). This is
  # required for VPC routing of east-west VM traffic between nodes.
  network_interfaces {
    associate_public_ip_address = false
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

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tpl", {
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
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-node"
    }
  }

  tags = { Name = "${var.project_name}-node-lt" }
}

resource "aws_autoscaling_group" "nodes" {
  name_prefix         = "${var.project_name}-node-"
  desired_capacity    = var.node_count
  min_size            = var.node_count
  max_size            = var.node_count
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.traefik.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 600

  # Skip the graceful drain (desired→0 then wait). The ASG and its
  # instances are deleted in one API call. Terraform still waits for
  # the ASG to disappear, which requires all instances to terminate.
  # c6g.metal can take 15-20 min, so raise the delete timeout below.
  force_delete = true

  timeouts {
    delete = "30m"
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-node"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

}
