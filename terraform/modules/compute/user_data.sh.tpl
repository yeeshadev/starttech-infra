#!/bin/bash
set -euo pipefail

# ── System update & Docker ────────────────────────────────────────────────────
yum update -y
yum install -y docker amazon-cloudwatch-agent aws-cli

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
ENABLE_CACHE=${enable_cache}
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
  --log-driver=awslogs \
  --log-opt awslogs-region="${aws_region}" \
  --log-opt awslogs-group="${log_group_name}" \
  --log-opt awslogs-create-group=true \
  "$IMAGE"

# ── CloudWatch agent config ───────────────────────────────────────────────────
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/system",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
