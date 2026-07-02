// Security groups and WAF rules (req. 10)
// Layout:
//   alb_app      — HTTPS open to the internet (all app traffic)
//   alb_jenkins  — HTTPS open, WAF enforces PT geo-restriction below
//   ecs_app      — dynamic ports reachable only from alb_app
//   ecs_jenkins  — dynamic ports from alb_jenkins + Jenkins agent port from app VPC

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
# Security groups cannot filter by geography — port 443 is open here so health
# checks and Route 53 can reach the ALB. The WAF Web ACL below blocks all
# non-Portuguese traffic at the L7 edge before requests hit the listener.

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

  // ALB uses the dynamic/ephemeral port range when task port mappings use hostPort = 0
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

  // Jenkins agent JNLP port — ECS tasks in the app VPC connect back via peering
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
# Enforce HTTPS-only inbound at the subnet boundary (req. 4).
# NACLs are stateless — ephemeral/return-traffic ports (1024-65535) must be
# explicitly permitted inbound so established TCP sessions can complete.
# Private subnet NACLs allow only VPC-internal and peered-VPC CIDR traffic.

# App VPC — public subnets (ALB layer)
resource "aws_network_acl" "app_public" {
  vpc_id     = module.vpc_app.vpc_id
  subnet_ids = module.vpc_app.public_subnet_ids

  // Inbound: HTTPS from the internet
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  // Inbound: ephemeral ports — return traffic for ALB-initiated connections to ECS targets
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  // Outbound: allow all (ALB → ECS targets, health checks, NAT)
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

  // Inbound: all TCP from the app VPC itself (ALB health checks, dynamic port range)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  // Inbound: traffic from Jenkins VPC via peering (pipeline deploy calls)
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.jenkins_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  // Inbound: return traffic from internet (ECR pulls, CW logs via NAT)
  ingress {
    rule_no    = 300
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  // Outbound: allow all (ECR image pulls, CloudWatch logs, NAT gateway)
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

  // Inbound: app VPC via peering — Jenkins agent JNLP connections originate here
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
