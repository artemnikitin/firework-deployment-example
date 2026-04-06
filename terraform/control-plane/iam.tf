# -----------------------------------------------------------------------------
# ECS IAM roles and policies
# -----------------------------------------------------------------------------

locals {
  iam_state_prefix_pattern = local.state_prefix_clean == "" ? "*" : "${local.state_prefix_clean}/*"
  iam_state_object_arn     = local.state_prefix_clean == "" ? "${aws_s3_bucket.configs.arn}/*" : "${aws_s3_bucket.configs.arn}/${local.state_prefix_clean}/*"
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name_prefix        = "${var.project_name}-cp-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = { Name = "${var.project_name}-cp-task-execution-role" }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  name_prefix = "secrets-read-"
  role        = aws_iam_role.task_execution.id
  policy      = data.aws_iam_policy_document.task_execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name_prefix        = "${var.project_name}-cp-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = { Name = "${var.project_name}-cp-task-role" }
}

data "aws_iam_policy_document" "task_s3_state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.configs.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.iam_state_prefix_pattern]
    }
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [local.iam_state_object_arn]
  }
}

resource "aws_iam_role_policy" "task_s3_state" {
  name_prefix = "s3-state-"
  role        = aws_iam_role.task.id
  policy      = data.aws_iam_policy_document.task_s3_state.json
}
