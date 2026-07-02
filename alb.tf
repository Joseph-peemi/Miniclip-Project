// Both Application Load Balancers, their target groups, and HTTPS listeners (req. 4)
// Access logs land in the shared S3 bucket (s3.tf) under alb/app and alb/jenkins prefixes.

# ── App ALB ──────────────────────────────────────────────────────────────────

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_app.id]
  subnets            = module.vpc_app.public_subnet_ids

  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb/app"
    enabled = true
  }

  tags = var.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc_app.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "app_https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Jenkins ALB ───────────────────────────────────────────────────────────────

resource "aws_lb" "jenkins" {
  name               = "${local.name_prefix}-jenkins"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_jenkins.id]
  subnets            = module.vpc_jenkins.public_subnet_ids

  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb/jenkins"
    enabled = true
  }

  tags = var.tags
}

resource "aws_lb_target_group" "jenkins" {
  name        = "${local.name_prefix}-jenkins"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc_jenkins.vpc_id
  target_type = "instance"

  health_check {
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    interval            = 30
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "jenkins_https" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}
