// Two roles ECS actually uses:
//   ecs_task_execution — lets the ECS agent pull images from ECR and ship logs to CloudWatch
//   ecs_host           — lets the EC2 hosts register with the cluster and pull down tasks

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

// The standard AWS-managed policy: ECR pull, CloudWatch Logs write, SSM param read
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// The managed policy above doesn't cover S3, so this bolts on write access
// for container logs and pipeline logs specifically
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

// Lets the ECS agent on each host register, drain, and manage its own tasks
resource "aws_iam_role_policy_attachment" "ecs_host" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

// So we can reach these hosts through SSM Session Manager instead of SSH keys
resource "aws_iam_role_policy_attachment" "ecs_host_ssm" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

// Gives the Jenkins host a way to publish its own build notifications to SNS
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

// The Jenkins container runs bridge-mode and inherits this host role, so this
// is what actually lets the pipeline push images to ECR and kick off ECS deploys
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