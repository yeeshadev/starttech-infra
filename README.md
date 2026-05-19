# StartTech Infrastructure

Terraform-managed AWS infrastructure for the MuchToDo full-stack application.

## Architecture Overview

```
Internet
   │
   ▼
CloudFront ──── S3 (React static files)
   │
   ▼
Application Load Balancer (public subnets)
   │
   ▼
Auto Scaling Group ─── EC2 instances (private subnets)
   │                      │
   │                   Docker: muchtodo-backend
   │                      │
   │              ┌───────┴────────┐
   │              ▼                ▼
   │         MongoDB Atlas    ElastiCache Redis
   │                               (private subnets)
   │
   └── CloudWatch Logs / Alarms ── SNS ── Email
```

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| Terraform | 1.5.0 |
| AWS CLI | 2.x |
| aws credentials | Configured via `aws configure` or environment |

## Quick Start

### 1. Clone and configure
```bash
git clone <this-repo>
cd starttech-infra

cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars — do NOT commit sensitive values
```

### 2. Set sensitive variables via environment (never commit these)
```bash
export TF_VAR_mongo_uri="mongodb+srv://user:pass@cluster.mongodb.net/much_todo_db"
export TF_VAR_jwt_secret_key="your-secret-at-least-32-chars"
export TF_VAR_redis_password=""         # leave empty to disable Redis auth
```

### 3. (Optional) Set up remote state first
Before deploying, create a state bucket and lock table:
```bash
aws s3 mb s3://muchtodo-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket muchtodo-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name muchtodo-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```
Then uncomment the `backend "s3"` block in `terraform/main.tf` and run `terraform init -migrate-state`.

### 4. Deploy
```bash
# Plan only (safe, read-only)
./scripts/deploy-infrastructure.sh plan

# Apply changes
./scripts/deploy-infrastructure.sh apply

# Nuclear option — destroy everything
./scripts/deploy-infrastructure.sh destroy
```

## GitHub Actions CI/CD

The `.github/workflows/infrastructure-deploy.yml` workflow runs automatically.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user with sufficient permissions |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret |
| `AWS_REGION` | Target region (e.g. `us-east-1`) |
| `TF_VAR_MONGO_URI` | MongoDB Atlas connection string |
| `TF_VAR_JWT_SECRET_KEY` | JWT signing secret |
| `TF_VAR_REDIS_PASSWORD` | Redis auth token (can be empty) |
| `ALERT_EMAIL` | Email for CloudWatch alarm notifications |

### Pipeline Flow

```
PR opened       →  validate + plan  →  plan posted as PR comment
Push to main    →  validate + plan  →  apply (with environment approval gate)
Manual dispatch →  choose action    →  plan / apply / destroy
```

## Module Descriptions

| Module | Resources |
|--------|-----------|
| `networking` | VPC, subnets, IGW, NAT, route tables, security groups |
| `compute` | EC2 Launch Template, ASG, ALB, Target Group, IAM roles |
| `storage` | S3, CloudFront, ECR, ElastiCache Redis |
| `monitoring` | CloudWatch Log Groups, Dashboard, Alarms, SNS |

## Key Outputs After Deploy

```bash
cd terraform
terraform output          # show all outputs
terraform output -json    # machine-readable
```

Important outputs:
- `alb_dns_name` → set as `ALB_DNS_NAME` secret in the application repo
- `cloudfront_domain_name` → public URL for the frontend
- `s3_bucket_name` → set as `S3_BUCKET_NAME` secret
- `cloudfront_distribution_id` → set as `CLOUDFRONT_DISTRIBUTION_ID` secret
- `ecr_repository_url` → set as `ECR_REPOSITORY` secret (just the name part)
- `asg_name` → set as `ASG_NAME` secret

## IAM Permissions Required

The deploying IAM user/role needs at minimum:
- `AmazonVPCFullAccess`
- `AmazonEC2FullAccess`
- `AmazonS3FullAccess`
- `CloudFrontFullAccess`
- `AmazonElastiCacheFullAccess`
- `AmazonECR_FullAccess`
- `CloudWatchFullAccess`
- `IAMFullAccess`
- `AmazonSNSFullAccess`
- `AmazonDynamoDBFullAccess` (for state lock table)
