// Alarms land here and get forwarded to email. Heads up: the subscription
// starts in "pending confirmation" — whoever owns var.alert_email has to
// click the link AWS sends before any alerts actually arrive.

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
