// IAM roles consumed by ECS (req. 5):
//   ecs_task_execution — ECS agent pulls images from ECR and writes CloudWatch logs
//   ecs_host           — EC2 container hosts register with the cluster and pull tasks

# ── ECS task execution role ───────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json
  tags               = var.tags
}

// Grants ECR pull, CloudWatch Logs write, and SSM parameter read (standard set)
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// Additional S3 write permission for ECS container logs and pipeline logs (req. 6)
data "aws_iam_policy_document" "ecs_s3_logs" {
  statement {
    sid = "WriteECSAndPipelineLogs"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.logs.arn}/ecs/*",
      "${aws_s3_bucket.logs.arn}/pipeline/*",
    ]
  }
}

resource "aws_iam_policy" "ecs_s3_logs" {
  name   = "${local.name_prefix}-ecs-s3-logs"
  policy = data.aws_iam_policy_document.ecs_s3_logs.json
}

resource "aws_iam_role_policy_attachment" "ecs_s3_logs" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_s3_logs.arn
}

# ── EC2 instance role for ECS container hosts ─────────────────────────────────

data "aws_iam_policy_document" "ecs_host_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_host" {
  name               = "${local.name_prefix}-ecs-host"
  assume_role_policy = data.aws_iam_policy_document.ecs_host_assume.json
  tags               = var.tags
}

// Allows the ECS agent on the EC2 host to register, drain, and manage tasks
resource "aws_iam_role_policy_attachment" "ecs_host" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

// Allows the EC2 host to be managed through AWS Systems Manager
resource "aws_iam_role_policy_attachment" "ecs_host_ssm" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

// Allows the EC2 host (Jenkins) to publish build notifications to SNS
data "aws_iam_policy_document" "ecs_host_sns" {
  statement {
    sid = "PublishPipelineNotifications"

    actions = [
      "sns:Publish"
    ]

    resources = [
      aws_sns_topic.alerts.arn
    ]
  }
}

resource "aws_iam_policy" "ecs_host_sns" {
  name   = "${local.name_prefix}-ecs-host-sns"
  policy = data.aws_iam_policy_document.ecs_host_sns.json
}

resource "aws_iam_role_policy_attachment" "ecs_host_sns" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = aws_iam_policy.ecs_host_sns.arn
}

// Allows Jenkins container (running via EC2 host role) to push images and trigger ECS deploys
data "aws_iam_policy_document" "ecs_host_pipeline" {
  statement {
    sid = "ECRAuth"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid = "ECSUpdateService"
    actions = ["ecs:UpdateService"]
    resources = ["*"]
  }

  statement {
    sid = "S3PipelineLogs"
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/pipeline/*"]
  }
}

resource "aws_iam_policy" "ecs_host_pipeline" {
  name   = "${local.name_prefix}-ecs-host-pipeline"
  policy = data.aws_iam_policy_document.ecs_host_pipeline.json
}

resource "aws_iam_role_policy_attachment" "ecs_host_pipeline" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = aws_iam_policy.ecs_host_pipeline.arn
}

resource "aws_iam_instance_profile" "ecs_host" {
  name = "${local.name_prefix}-ecs-host"
  role = aws_iam_role.ecs_host.name
}