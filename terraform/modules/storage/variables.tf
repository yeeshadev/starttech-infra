variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for backend images"
  type        = string
  default     = "muchtodo-backend"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ElastiCache subnet group"
  type        = list(string)
}

variable "redis_sg_id" {
  description = "Security group ID for the Redis cluster"
  type        = string
}

variable "redis_password" {
  description = "Redis auth token (empty string disables auth)"
  type        = string
  sensitive   = true
  default     = ""
}
