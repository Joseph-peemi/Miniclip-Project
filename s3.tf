// S3 bucket for ALB access logs, ECS container logs, and Jenkins pipeline logs (req. 6)
// Note: this same bucket could have hosted the Terraform state backend — see the
// FLAW comment in versions.tf for why that was deliberately left unconfigured.
resource "aws_s3_bucket" "logs" {
  bucket = "${var.tags.product}-logs-eu-central-1-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

data "aws_caller_identity" "current" {}

// Blocks all public access — these logs are internal only
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// Server-side encryption at rest for all objects
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// Bucket policy allowing log writers (req. 6: "attach a bucket policy allowing log writes")
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

data "aws_iam_policy_document" "logs" {
  // ALB access logging requires the regional ELB log-delivery account to PutObject
  statement {
    sid    = "AllowALBLogDelivery"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::054676820928:root"] // eu-central-1 ELB log delivery account
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/alb/*"]
  }

  // ECS tasks write container logs via the task execution role
  statement {
    sid    = "AllowECSLogWrites"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecs_task_execution.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/ecs/*"]
  }

  // Jenkins pipeline writes build/push/deploy logs via the EC2 host role (bridge-mode container
  // inherits the host instance profile, not the task execution role)
  statement {
    sid    = "AllowPipelineLogWrites"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecs_host.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/pipeline/*"]
  }
}
