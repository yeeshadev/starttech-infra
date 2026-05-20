#!/bin/bash
set -euo pipefail

# ── System update & Docker ────────────────────────────────────────────────────
yum update -y
yum install -y docker aws-cli

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# ── App environment file ──────────────────────────────────────────────────────
cat > /etc/muchtodo.env << 'ENVEOF'
PORT=8080
MONGO_URI=${mongo_uri}
DB_NAME=much_todo_db
JWT_SECRET_KEY=${jwt_secret_key}
JWT_EXPIRATION_HOURS=72
ENABLE_CACHE=false
REDIS_ADDR=${redis_addr}
REDIS_PASSWORD=${redis_password}
LOG_LEVEL=INFO
LOG_FORMAT=json
SECURE_COOKIE=true
ENVEOF
chmod 600 /etc/muchtodo.env

# ── ECR login & pull ──────────────────────────────────────────────────────────
AWS_REGION="${aws_region}"
ECR_REGISTRY=$(echo "${ecr_repository_url}" | cut -d'/' -f1)
IMAGE="${ecr_repository_url}:${image_tag}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker pull "$IMAGE"

# ── Start application container ───────────────────────────────────────────────
docker run -d \
  --name muchtodo-backend \
  --restart unless-stopped \
  -p 8080:8080 \
  --env-file /etc/muchtodo.env \
  "$IMAGE"

# Docker's awslogs driver streams container logs directly to CloudWatch
# without needing the CloudWatch agent installed
