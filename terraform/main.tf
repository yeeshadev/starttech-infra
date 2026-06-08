terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "muchtodo-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "muchtodo-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Networking

module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment  = var.environment
}

# Storage (S3, CloudFront, ECR, ElastiCache) 

module "storage" {
  source = "./modules/storage"

  project_name        = var.project_name
  environment         = var.environment
  ecr_repository_name = var.ecr_repository_name
  private_subnet_ids  = module.networking.private_subnet_ids
  redis_sg_id         = module.networking.redis_sg_id
  redis_password      = var.redis_password
}

# Compute (EC2 ASG, ALB) 

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  private_subnet_ids   = module.networking.private_subnet_ids
  alb_sg_id            = module.networking.alb_sg_id
  backend_sg_id        = module.networking.backend_sg_id
  instance_type        = var.ec2_instance_type
  ecr_repository_url   = module.storage.ecr_repository_url
  mongo_uri            = var.mongo_uri
  jwt_secret_key       = var.jwt_secret_key
  redis_addr           = "${module.storage.redis_endpoint}:${module.storage.redis_port}"
  redis_password       = var.redis_password
  enable_cache         = true
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  log_group_name       = "/muchtodo/backend"
}

# Monitoring

module "monitoring" {
  source = "./modules/monitoring"

  project_name            = var.project_name
  environment             = var.environment
  aws_region              = var.aws_region
  alert_email             = var.alert_email
  asg_name                = module.compute.asg_name
  alb_arn_suffix          = module.compute.alb_arn
  target_group_arn_suffix = module.compute.target_group_arn
  elasticache_cluster_id  = "${var.project_name}-${var.environment}-redis"
  log_retention_days      = 30

  depends_on = [module.compute, module.storage]
}
