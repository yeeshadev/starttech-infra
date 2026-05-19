variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ASG instances"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "backend_sg_id" {
  description = "Security group ID for backend EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the backend Docker image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "mongo_uri" {
  description = "MongoDB Atlas connection string"
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "JWT signing secret"
  type        = string
  sensitive   = true
}

variable "redis_addr" {
  description = "Redis endpoint address (host:port)"
  type        = string
  default     = ""
}

variable "redis_password" {
  description = "Redis auth password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_cache" {
  description = "Whether to enable Redis caching in the app"
  type        = bool
  default     = true
}

variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 3
}

variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "log_group_name" {
  description = "CloudWatch log group name for application logs"
  type        = string
  default     = "/muchtodo/backend"
}
