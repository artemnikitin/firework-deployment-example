# -----------------------------------------------------------------------------
# S3 bucket — configs (enricher writes enriched node YAML, agent reads)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "configs" {
  bucket_prefix = "${var.project_name}-configs-"
  force_destroy = true

  tags = { Name = "${var.project_name}-configs" }
}

resource "aws_s3_bucket_versioning" "configs" {
  bucket = aws_s3_bucket.configs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "configs" {
  bucket = aws_s3_bucket.configs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "configs" {
  bucket = aws_s3_bucket.configs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
