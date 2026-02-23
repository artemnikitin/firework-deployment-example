# -----------------------------------------------------------------------------
# IAM roles and instance profiles for EC2 nodes
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${var.project_name}-node-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.project_name}-node-role" }
}

# Allow nodes to read configs from S3
data "aws_iam_policy_document" "node_s3_configs" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:HeadObject",
    ]
    resources = ["${var.s3_configs_bucket_arn}/nodes/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.s3_configs_bucket_arn]
  }
}

resource "aws_iam_role_policy" "node_s3_configs" {
  name_prefix = "s3-read-configs-"
  role        = aws_iam_role.node.id
  policy      = data.aws_iam_policy_document.node_s3_configs.json
}

# Allow nodes to read images (ext4 rootfs) from S3
data "aws_iam_policy_document" "node_s3_images" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:HeadObject",
    ]
    resources = ["${var.s3_images_bucket_arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.s3_images_bucket_arn]
  }
}

resource "aws_iam_role_policy" "node_s3_images" {
  name_prefix = "s3-read-images-"
  role        = aws_iam_role.node.id
  policy      = data.aws_iam_policy_document.node_s3_images.json
}

# Allow nodes to ship logs via CloudWatch Agent.
data "aws_iam_policy_document" "node_cloudwatch_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "${aws_cloudwatch_log_group.node_agent.arn}:*",
      "${aws_cloudwatch_log_group.node_firecracker.arn}:*",
      "${aws_cloudwatch_log_group.node_prometheus.arn}:*",
    ]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "node_cloudwatch_logs" {
  name_prefix = "cloudwatch-logs-"
  role        = aws_iam_role.node.id
  policy      = data.aws_iam_policy_document.node_cloudwatch_logs.json
}

# Allow nodes to publish capacity metrics to CloudWatch.
# The firework-agent emits firework_node_* metrics scraped by the CW agent,
# which then calls PutMetricData on the node's behalf.
data "aws_iam_policy_document" "node_cloudwatch_metrics" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.agent_metric_namespace]
    }
  }
}

resource "aws_iam_role_policy" "node_cloudwatch_metrics" {
  name_prefix = "cloudwatch-metrics-"
  role        = aws_iam_role.node.id
  policy      = data.aws_iam_policy_document.node_cloudwatch_metrics.json
}

# Allow nodes to disable their own source/dest check at startup and to let
# the CloudWatch agent resolve EC2 instance tags (required by amazon-cloudwatch-agent
# fetch-config validation even when no tag-based substitutions are used).
data "aws_iam_policy_document" "node_ec2_self" {
  statement {
    actions = [
      "ec2:ModifyInstanceAttribute",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "node_ec2_self" {
  name_prefix = "ec2-modify-self-"
  role        = aws_iam_role.node.id
  policy      = data.aws_iam_policy_document.node_ec2_self.json
}

# Allow nodes to use SSM Session Manager (optional, for debugging)
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "${var.project_name}-node-"
  role        = aws_iam_role.node.name
}
