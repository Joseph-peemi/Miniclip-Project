// Route 53 health checks for both ALBs (req. 11)
// These are passive HTTPS probes — they do not create DNS records.
// Attach them to Route 53 DNS records (e.g. weighted/failover policies) to
// automate traffic cutover when an ALB goes unhealthy.

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
