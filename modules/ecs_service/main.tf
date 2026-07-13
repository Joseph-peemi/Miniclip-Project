// Generic ECS-on-EC2 setup, called twice from root main.tf: once for the app
// (infrastructureascode/hello-world, 2 tasks) and once for Jenkins
// (jenkins/jenkins:lts, 1 task) — each landing in its own VPC's private subnets.

// Grabs whatever the current ECS-optimized AMI is instead of pinning an ID that'll go stale
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

// One cluster per call — this becomes either the app cluster or the Jenkins cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = var.tags
}

// Template for the free-tier EC2 hosts that back this cluster
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  // Tells the instance which ECS cluster to join as soon as it boots
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-ecs-host" })
  }
}

// Pinned at instance_count on both ends (default 2) — no scaling surprises
resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = var.instance_count
  max_size            = var.instance_count
  desired_capacity    = var.instance_count

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

// Without this, the ASG and the cluster don't know about each other and no task ever gets placed
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.this.arn

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}

// CPU/memory come from var.task_size — root main.tf has the full story on why
// the app task ends up over-allocated at 1024 CPU / 512 MiB (FLAW 1).
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name}-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = var.task_size.cpu
  memory                   = var.task_size.memory
  execution_role_arn       = var.task_execution_role_arn

  dynamic "volume" {
    for_each = var.mount_docker_socket ? [1] : []
    content {
      name      = "docker-socket"
      host_path = "/var/run/docker.sock"
    }
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      mountPoints = var.mount_docker_socket ? [
        {
          sourceVolume  = "docker-socket"
          containerPath = "/var/run/docker.sock"
          readOnly      = false
        }
      ] : []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.name}"
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = var.name
        }
      }
    }
  ])

  tags = var.tags
}

// Keeps desired_count tasks alive and registered with whichever target group we pass in
resource "aws_ecs_service" "this" {
  name            = "${var.name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name    = var.name
    container_port    = var.container_port
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}
