// Security groups plus the WAF rule that restricts Jenkins by country. Rough layout:
//   alb_app      — HTTPS wide open to the internet, this is public app traffic
//   alb_jenkins  — HTTPS open at the SG level, but WAF below blocks anything not from PT
//   ecs_app      — only reachable from alb_app, on the dynamic port range
//   ecs_jenkins  — reachable from alb_jenkins, plus the Jenkins agent port from the app VPC

# ── App ALB ──────────────────────────────────────────────────────────────────

resource "aws_security_group" "alb_app" {
  name        = "${local.name_prefix}-alb-app"
  description = "Allow HTTPS inbound from the internet to the app ALB"
  vpc_id      = module.vpc_app.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# ── Jenkins ALB ───────────────────────────────────────────────────────────────
# Security groups have no concept of "country," so 443 has to stay open here
# just so health checks and Route 53 can reach the ALB at all. The actual
# geo-blocking happens one layer up, in the WAF Web ACL below.

resource "aws_security_group" "alb_jenkins" {
  name        = "${local.name_prefix}-alb-jenkins"
  description = "Allow HTTPS inbound - WAF Web ACL restricts origin country to PT"
  vpc_id      = module.vpc_jenkins.vpc_id

  ingress {
    description = "HTTPS (WAF enforces PT geo-restriction)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# ── ECS hosts (app VPC) ───────────────────────────────────────────────────────

resource "aws_security_group" "ecs_app" {
  name        = "${local.name_prefix}-ecs-app"
  description = "Allow inbound from the app ALB only (dynamic port range)"
  vpc_id      = module.vpc_app.vpc_id

  // hostPort = 0 in the task definition means Docker picks a random host port,
  // so the SG has to allow the whole ephemeral range, not one fixed port
  ingress {
    description     = "Dynamic ports from app ALB"
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# ── ECS hosts (Jenkins VPC) ───────────────────────────────────────────────────

resource "aws_security_group" "ecs_jenkins" {
  name        = "${local.name_prefix}-ecs-jenkins"
  description = "Allow inbound from the Jenkins ALB and Jenkins agent connections from the app VPC"
  vpc_id      = module.vpc_jenkins.vpc_id

  ingress {
    description     = "Dynamic ports from Jenkins ALB"
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_jenkins.id]
  }

  // Port 50000 is the Jenkins agent JNLP port — app-side ECS tasks reach it over the peering link
  ingress {
    description = "Jenkins agent connections from app VPC"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [local.app_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# ── WAF — Portugal geo-restriction for Jenkins ALB ────────────────────────────

resource "aws_wafv2_web_acl" "jenkins" {
  name        = "${local.name_prefix}-jenkins-pt-only"
  description = "Block all non-PT traffic to the Jenkins ALB"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "AllowPortugal"
    priority = 1

    action {
      allow {}
    }

    statement {
      geo_match_statement {
        country_codes = ["PT"]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-jenkins-pt-allow"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-jenkins-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "jenkins" {
  resource_arn = aws_lb.jenkins.arn
  web_acl_arn  = aws_wafv2_web_acl.jenkins.arn
}

# ── Network ACLs ──────────────────────────────────────────────────────────────
# Locks inbound traffic down to HTTPS-only at the subnet boundary. Worth
# remembering NACLs are stateless — unlike security groups, they don't track
# connection state, so return traffic on ephemeral ports (1024-65535) needs its
# own explicit allow rule or established connections just never complete.
# Private subnets only trust traffic from inside the VPC or the peered one.

# App VPC — public subnets (ALB layer)
resource "aws_network_acl" "app_public" {
  vpc_id     = module.vpc_app.vpc_id
  subnet_ids = module.vpc_app.public_subnet_ids

  // HTTPS in from anywhere — this is the public-facing side
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  // Needed so return traffic from the ALB's own connections to ECS targets can get back in
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  // Wide open outbound — ALB talks to ECS targets, runs health checks, goes through NAT
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-app-public-nacl" })
}

# App VPC — private subnets (ECS host layer)
resource "aws_network_acl" "app_private" {
  vpc_id     = module.vpc_app.vpc_id
  subnet_ids = module.vpc_app.private_subnet_ids

  // All TCP from within the app VPC itself — covers ALB health checks and the dynamic port range
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  // Lets pipeline deploy calls in from the Jenkins VPC over the peering connection
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.jenkins_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  // Return traffic from the internet via NAT — this is what ECR pulls and CW log shipping need
  ingress {
    rule_no    = 300
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  // Outbound wide open — ECR pulls, CloudWatch logs, NAT gateway traffic
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-app-private-nacl" })
}

# Jenkins VPC — public subnets (ALB layer)
resource "aws_network_acl" "jenkins_public" {
  vpc_id     = module.vpc_jenkins.vpc_id
  subnet_ids = module.vpc_jenkins.public_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-jenkins-public-nacl" })
}

# Jenkins VPC — private subnets (ECS host layer)
resource "aws_network_acl" "jenkins_private" {
  vpc_id     = module.vpc_jenkins.vpc_id
  subnet_ids = module.vpc_jenkins.private_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.jenkins_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  // App VPC over peering — this is where Jenkins agent JNLP connections come from
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  ingress {
    rule_no    = 300
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-jenkins-private-nacl" })
}
