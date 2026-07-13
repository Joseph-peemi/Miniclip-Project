// One bucket, three purposes: ALB access logs, ECS container logs, and Jenkins
// pipeline logs, split by prefix instead of spinning up three separate buckets.
// It could just as easily hold the Terraform state backend too — see the note
// in versions.tf on why that's left disabled for now.
resource "aws_s3_bucket" "logs" {
  bucket = "${var.tags.product}-logs-eu-central-1-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

data "aws_caller_identity" "current" {}

// Nobody outside the account needs to see these logs, so lock it down completely
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// Encrypt everything at rest — AES256 is enough here, no need for a KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// Grants write access to the three things that actually need to drop logs here
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

data "aws_iam_policy_document" "logs" {
  // AWS doesn't let your own account write ALB access logs — it has to come from
  // the regional ELB log-delivery service account instead
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

  // Container logs come from the ECS task execution role
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

  // Jenkins writes its build/push/deploy logs through the EC2 host role, not the
  // task execution role — bridge-mode containers inherit whatever profile is on
  // the host instance
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
