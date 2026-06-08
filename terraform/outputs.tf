output "alb_dns_name" {
  description = "ALB DNS name — use this as the backend API base URL"
  value       = module.compute.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name — the public URL for the frontend"
  value       = "https://${module.storage.cloudfront_domain_name}"
}

output "s3_bucket_name" {
  description = "S3 bucket name for frontend deployments"
  value       = module.storage.s3_bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for cache invalidations"
  value       = module.storage.cloudfront_distribution_id
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker image pushes"
  value       = module.storage.ecr_repository_url
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = "${module.storage.redis_endpoint}:${module.storage.redis_port}"
}

output "asg_name" {
  description = "Auto Scaling Group name — used by CI/CD for rolling deploys"
  value       = module.compute.asg_name
}

output "backend_log_group" {
  description = "CloudWatch log group for backend application logs"
  value       = module.monitoring.log_group_backend
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = module.monitoring.sns_topic_arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.dashboard_name}"
}

output "region" {
  description = "AWS region where infrastructure is deployed"
  value       = var.aws_region
}
