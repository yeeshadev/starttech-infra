output "log_group_backend" {
  description = "CloudWatch log group name for backend application"
  value       = aws_cloudwatch_log_group.backend.name
}

output "log_group_frontend" {
  description = "CloudWatch log group name for frontend access logs"
  value       = aws_cloudwatch_log_group.frontend.name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
