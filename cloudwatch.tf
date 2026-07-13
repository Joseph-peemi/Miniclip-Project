// Log groups for both clusters, an alarm for 5xx errors, and a daily cost
// tripwire. Keep the log group names in sync with the awslogs-group values
// set in modules/ecs_service/main.tf, or logging silently breaks.

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

// Any 5xx from an app ALB target trips this — threshold is intentionally 0,
// we want to know the moment something breaks, not after a batch of them
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

// Billing metrics only ever show up in us-east-1, no matter where the rest of
// the stack lives, so this alarm has to use the aliased provider from providers.tf
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
