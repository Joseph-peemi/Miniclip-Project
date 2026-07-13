// The handful of values you actually want printed after `terraform apply`

output "app_alb_dns_name" {
  description = "DNS name of the application ALB — point your app CNAME here"
  value       = aws_lb.app.dns_name
}

output "jenkins_alb_dns_name" {
  description = "DNS name of the Jenkins ALB — point your Jenkins CNAME here"
  value       = aws_lb.jenkins.dns_name
}

output "app_ecr_repository_url" {
  description = "ECR repository URL for the app image (docker push target)"
  value       = aws_ecr_repository.app.repository_url
}

output "jenkins_ecr_repository_url" {
  description = "ECR repository URL for the Jenkins image (docker push target)"
  value       = aws_ecr_repository.jenkins.repository_url
}

output "app_ecs_cluster_id" {
  description = "ECS cluster ID for the application workload"
  value       = module.ecs_app.cluster_id
}

output "jenkins_ecs_cluster_id" {
  description = "ECS cluster ID for Jenkins"
  value       = module.ecs_jenkins.cluster_id
}

output "logs_bucket_name" {
  description = "S3 bucket receiving ALB access logs, ECS logs, and pipeline logs"
  value       = aws_s3_bucket.logs.bucket
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN used by CloudWatch alarms"
  value       = aws_sns_topic.alerts.arn
}
