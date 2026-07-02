// CloudWatch log groups, a HTTP 5xx alarm, and a daily cost alarm (req. 9)
// Log group names must match the awslogs-group values in ecs-service/main.tf.

resource "aws_cloudwatch_log_group" "ecs_app" {
  name              = "/ecs/${local.name_prefix}-app"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "ecs_jenkins" {
  name              = "/ecs/${local.name_prefix}-jenkins"
  retention_in_days = 7
  tags              = var.tags
}

// Fires on any HTTP 5xx response from the app ALB targets (req. 9: "errors > 0")
resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  alarm_name          = "${local.name_prefix}-app-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "App ALB target returned at least one 5xx error in the last 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

// AWS billing metrics are only published to us-east-1 — provider alias from providers.tf
resource "aws_cloudwatch_metric_alarm" "cost" {
  provider = aws.us_east_1

  alarm_name          = "${local.name_prefix}-daily-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Daily AWS estimated charges exceeded $1 — investigate unexpected spend"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  tags = var.tags
}
