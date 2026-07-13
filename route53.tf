// Passive HTTPS health checks against both ALBs. These don't create any DNS
// records on their own — wire them into a weighted or failover routing policy
// if you want Route 53 to actually cut traffic away from an unhealthy ALB.

resource "aws_route53_health_check" "app" {
  fqdn              = aws_lb.app.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, { Name = "${local.name_prefix}-app-hc" })
}

resource "aws_route53_health_check" "jenkins" {
  fqdn              = aws_lb.jenkins.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/login"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, { Name = "${local.name_prefix}-jenkins-hc" })
}
