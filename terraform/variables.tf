# ── Input Variables ──────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project identifier used in resource names and tags"
  type        = string
  default     = "muchtodo"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for backend servers"
  type        = string
  default     = "t3.micro"
}

variable "ecr_repository_name" {
  description = "Name for the ECR repository storing backend Docker images"
  type        = string
  default     = "muchtodo-backend"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "admin@example.com"
}

variable "mongo_uri" {
  description = "MongoDB Atlas connection string"
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "JWT signing secret (minimum 32 characters)"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis auth token (leave empty to disable auth)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the ASG"
  type        = number
  default     = 1
}
