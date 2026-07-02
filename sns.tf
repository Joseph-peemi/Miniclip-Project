// SNS topic that receives alarm notifications and forwards them by email (req. 9)
// The subscription creates a pending confirmation — the email address in var.alert_email
// must click the AWS confirmation link before any alarm emails are delivered.

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
