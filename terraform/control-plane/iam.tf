# -----------------------------------------------------------------------------
# Enricher Lambda IAM role and policies
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enricher" {
  name_prefix        = "${var.project_name}-enricher-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = { Name = "${var.project_name}-enricher-role" }
}

# Allow enricher to write configs to S3
data "aws_iam_policy_document" "enricher_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.configs.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["nodes/*"]
    }
  }
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.configs.arn}/nodes/*"]
  }

}

resource "aws_iam_role_policy" "enricher_s3" {
  name_prefix = "s3-write-configs-"
  role        = aws_iam_role.enricher.id
  policy      = data.aws_iam_policy_document.enricher_s3.json
}

# CloudWatch Logs for Lambda
resource "aws_iam_role_policy_attachment" "enricher_logs" {
  role       = aws_iam_role.enricher.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow enricher to resolve EC2 instance private IPs for cross-node links.
data "aws_iam_policy_document" "enricher_ec2" {
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "enricher_ec2" {
  name_prefix = "ec2-describe-instances-"
  role        = aws_iam_role.enricher.id
  policy      = data.aws_iam_policy_document.enricher_ec2.json
}

# Allow enricher to invoke the scheduler Lambda.
data "aws_iam_policy_document" "enricher_invoke_scheduler" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.scheduler.arn]
  }
}

resource "aws_iam_role_policy" "enricher_invoke_scheduler" {
  name_prefix = "invoke-scheduler-"
  role        = aws_iam_role.enricher.id
  policy      = data.aws_iam_policy_document.enricher_invoke_scheduler.json
}

# Optional X-Ray segment publishing from Lambda.
resource "aws_iam_role_policy_attachment" "enricher_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.enricher.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# =============================================================================
# Scheduler Lambda IAM role and policies
# =============================================================================

resource "aws_iam_role" "scheduler" {
  name_prefix        = "${var.project_name}-scheduler-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = { Name = "${var.project_name}-scheduler-role" }
}

# CloudWatch Logs for Lambda execution
resource "aws_iam_role_policy_attachment" "scheduler_logs" {
  role       = aws_iam_role.scheduler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow scheduler to read node capacity metrics from CloudWatch.
data "aws_iam_policy_document" "scheduler_cloudwatch" {
  statement {
    actions = [
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "scheduler_cloudwatch" {
  name_prefix = "cloudwatch-read-"
  role        = aws_iam_role.scheduler.id
  policy      = data.aws_iam_policy_document.scheduler_cloudwatch.json
}

# Allow scheduler to read existing placement from S3 (for stability).
data "aws_iam_policy_document" "scheduler_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.configs.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["nodes/*"]
    }
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.configs.arn}/nodes/*"]
  }
}

resource "aws_iam_role_policy" "scheduler_s3" {
  name_prefix = "s3-read-placement-"
  role        = aws_iam_role.scheduler.id
  policy      = data.aws_iam_policy_document.scheduler_s3.json
}

# Optional X-Ray tracing for scheduler.
resource "aws_iam_role_policy_attachment" "scheduler_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.scheduler.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
