output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (for ElastiCache)"
  value       = aws_subnet.private[*].id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "backend_sg_id" {
  description = "ID of the backend EC2 security group"
  value       = aws_security_group.backend.id
}

output "redis_sg_id" {
  description = "ID of the Redis/ElastiCache security group"
  value       = aws_security_group.redis.id
}
