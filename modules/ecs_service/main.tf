// Reusable ECS-on-EC2 module (req. 3) — root main.tf calls this once for the
// application (infrastructureascode/hello-world, 2 tasks) and once for Jenkins
// (jenkins/jenkins:lts, 1 task), each pointed at its own VPC's private subnets.

// Resolves the latest ECS-optimized AMI instead of hardcoding one
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

// ECS cluster for this service (app cluster or Jenkins cluster)
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = var.tags
}

// Launch template for the 2 free-tier EC2 hosts backing this cluster
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  // Registers the instance with the correct ECS cluster on boot
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

// Auto Scaling group — fixed at instance_count (2) free-tier instances per cluster
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

// Ties the ASG to the ECS cluster so tasks can actually be placed on it
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

// Task definition sized via var.task_size. See root main.tf for the FLAW comment
// explaining why the app task is deliberately over-allocated at 1024 CPU / 512 MiB.
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

// Keeps desired_count tasks running and registered with the ALB target group
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
