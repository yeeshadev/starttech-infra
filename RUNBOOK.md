# Operations Runbook

## Deployment Process

### Automatic (recommended)
Push to `main` branch in the application repo. GitHub Actions will:
1. Run tests and build Docker image
2. Push to ECR
3. Update EC2 instances via SSM Rolling deployment
4. Verify `/health` endpoint

### Manual
```bash
# Backend
export IMAGE_TAG=<git-sha>
export ECR_REPOSITORY=muchtodo-backend
export ASG_NAME=muchtodo-production-asg
export ALB_DNS_NAME=<alb-dns-from-tf-output>
./scripts/deploy-backend.sh

# Frontend
export S3_BUCKET_NAME=muchtodo-production-frontend
export CLOUDFRONT_DISTRIBUTION_ID=<id-from-tf-output>
./scripts/deploy-frontend.sh
```

---

## How to Roll Back

### Backend rollback to a previous image
```bash
# 1. Find previous image tags in ECR
aws ecr list-images --repository-name muchtodo-backend \
  --query 'imageIds[*].imageTag' --output table

# 2. Roll back to a specific tag
export ROLLBACK_TAG=<previous-sha>
./scripts/rollback.sh "$ROLLBACK_TAG"
```

### Frontend rollback via S3 versioning
```bash
# List previous versions
aws s3api list-object-versions --bucket muchtodo-production-frontend \
  --prefix index.html --query 'Versions[*].[VersionId,LastModified]' --output table

# Restore a specific version
aws s3api copy-object \
  --copy-source "muchtodo-production-frontend/index.html?versionId=<VERSION_ID>" \
  --bucket muchtodo-production-frontend --key index.html

# Invalidate CloudFront
aws cloudfront create-invalidation \
  --distribution-id <DIST_ID> --paths "/*"
```

---

## Scaling Manually

### Scale up (emergency capacity)
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name muchtodo-production-asg \
  --desired-capacity 3
```

### Scale down
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name muchtodo-production-asg \
  --desired-capacity 1
```

### Trigger ASG instance refresh (redeploy all instances)
```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name muchtodo-production-asg \
  --preferences '{"MinHealthyPercentage":50}'
```

---

## Common Troubleshooting

### EC2 instances not healthy in target group

1. Check instance health in ASG:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names muchtodo-production-asg \
     --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
     --output table
   ```
2. SSH to an instance (or use SSM Session Manager):
   ```bash
   aws ssm start-session --target <instance-id>
   ```
3. Check Docker container status:
   ```bash
   docker ps
   docker logs muchtodo-backend --tail 100
   ```
4. Check application health directly:
   ```bash
   curl localhost:8080/health
   ```

### Redis connection refused

1. Verify Redis security group allows traffic from backend SG on port 6379
2. Check the Redis endpoint in `/etc/muchtodo.env` on the EC2 instance
3. Test connectivity:
   ```bash
   redis-cli -h <elasticache-endpoint> -p 6379 ping
   ```
4. If `ENABLE_CACHE=false` is acceptable as a temporary workaround, update the env file and restart:
   ```bash
   sudo sed -i 's/ENABLE_CACHE=true/ENABLE_CACHE=false/' /etc/muchtodo.env
   docker restart muchtodo-backend
   ```

### S3 frontend deploy failed / CloudFront serving stale content

1. Check S3 sync completed:
   ```bash
   aws s3 ls s3://muchtodo-production-frontend --recursive | head -20
   ```
2. Force invalidation:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id <DIST_ID> --paths "/*"
   ```
3. Check invalidation status:
   ```bash
   aws cloudfront list-invalidations --distribution-id <DIST_ID>
   ```

### Backend returns 502 Bad Gateway from ALB

1. Target group has no healthy targets — check EC2 health (above)
2. App is starting up — wait 120s (health_check_grace_period)
3. App crashed immediately — check CloudWatch Logs:
   ```bash
   aws logs tail /muchtodo/backend --follow
   ```

### GitHub Actions deploy fails at SSM step

1. Verify EC2 instances have the SSM Agent running and IAM role has `AmazonSSMManagedInstanceCore`
2. Check SSM command status:
   ```bash
   aws ssm list-command-invocations \
     --command-id <command-id-from-ci-output> --details
   ```

---

## Monitoring and Alerting

### View live logs
```bash
aws logs tail /muchtodo/backend --follow --format short
```

### Run a Logs Insights query
```bash
aws logs start-query \
  --log-group-name /muchtodo/backend \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 20'
```

Then retrieve results:
```bash
aws logs get-query-results --query-id <query-id>
```

### CloudWatch Dashboard
Open the dashboard URL from `terraform output dashboard_url`.

---

## Rotating Secrets

### JWT Secret Key
1. Generate a new secret: `openssl rand -base64 48`
2. Update GitHub Secret `TF_VAR_JWT_SECRET_KEY`
3. Update Terraform variable and re-apply (this triggers a new launch template version)
4. Trigger an instance refresh to roll new env to all instances
5. Note: existing JWT tokens will be invalidated immediately — users will need to log in again

### MongoDB URI (password rotation)
1. Rotate the password in MongoDB Atlas
2. Update `TF_VAR_MONGO_URI` GitHub Secret
3. Apply Terraform and trigger instance refresh

### AWS Access Keys (CI/CD)
1. Create new IAM access keys for the CI/CD user
2. Update `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub Secrets (for both repos)
3. Verify a pipeline run succeeds
4. Deactivate and delete the old access keys in IAM
