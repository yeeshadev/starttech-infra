# Redeploy Guide — Bringing MuchTodo Infrastructure Back Up

Use this guide after a `terraform destroy` to rebuild the full AWS stack from scratch.

---

## What gets rebuilt

| Layer | Resources |
|---|---|
| Networking | VPC, 2 public + 2 private subnets, IGW, route table, 3 security groups |
| Storage | ECR repo, S3 frontend bucket, CloudFront distribution, ElastiCache Redis |
| Compute | IAM role + instance profile, Launch Template, ALB, Target Group, ASG (1 instance) |
| Monitoring | CloudWatch log groups, SNS topic + email subscription, 4 CW alarms, CW dashboard |
| State backend | S3 bucket `muchtodo-terraform-state`, DynamoDB table `muchtodo-terraform-locks` (these survive destroy — do NOT delete them) |

Region: **eu-north-1**  
Naming prefix: **muchtodo-production**

---

## Prerequisites

- AWS CLI configured with the CI/CD IAM user credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
- Terraform >= 1.5.0 (CI uses 1.9.0)
- GitHub Secrets set in **both** repos (see list below)

### GitHub Secrets — StartTech-infra repo

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | `eu-north-1` |
| `TF_VAR_MONGO_URI` | MongoDB Atlas connection string |
| `TF_VAR_JWT_SECRET_KEY` | JWT signing secret (min 32 chars) |
| `TF_VAR_REDIS_PASSWORD` | Redis auth token (can be empty) |
| `ALERT_EMAIL` | Email for CloudWatch alarm notifications |

### GitHub Secrets — much-to-do (app) repo

These need updating **after** infra is back up (resource IDs change on each fresh deploy):

| Secret | Where to get the value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Same IAM user as above |
| `AWS_SECRET_ACCESS_KEY` | Same IAM user as above |
| `AWS_REGION` | `eu-north-1` |
| `ECR_REPOSITORY` | `muchtodo-backend` (stays the same) |
| `ASG_NAME` | `muchtodo-production-asg` (stays the same) |
| `ALB_DNS_NAME` | `terraform output alb_dns_name` after apply |
| `S3_BUCKET_NAME` | `muchtodo-production-frontend` (stays the same) |
| `CLOUDFRONT_DISTRIBUTION_ID` | `terraform output cloudfront_distribution_id` after apply |
| `VITE_API_BASE_URL` | `http://<ALB_DNS_NAME>` after apply |

---

## Step 1 — Verify state backend still exists

The S3 bucket and DynamoDB table are NOT destroyed by `terraform destroy` (they are created by the bootstrap step in the plan job, not managed as Terraform resources). Confirm they exist:

```bash
aws s3api head-bucket --bucket muchtodo-terraform-state --region eu-north-1
aws dynamodb describe-table --table-name muchtodo-terraform-locks --region eu-north-1
```

If either is missing, the next plan run will recreate them automatically via the bootstrap step in the CI workflow.

---

## Step 2 — Clear any stale DynamoDB state lock

A crashed previous run may leave a lock entry that blocks init/plan/apply.

```bash
aws dynamodb delete-item \
  --table-name muchtodo-terraform-locks \
  --region eu-north-1 \
  --key '{"LockID": {"S": "muchtodo-terraform-state/production/terraform.tfstate"}}'
```

This is safe to run even if no lock exists (the command is a no-op).

---

## Step 3 — Trigger the plan via CI

Push any trivial change to master in the **StartTech-infra** repo (e.g. add a blank line to `README.md`), or go to **Actions → Infrastructure Deploy → Run workflow → action: plan**.

The plan job will:
1. Bootstrap the state backend (idempotent)
2. Clear any stale DynamoDB lock
3. Run `terraform init`
4. Skip all imports (nothing in AWS yet, nothing to reconcile)
5. Run `terraform plan` — expect **~30+ resources to add, 0 to change, 0 to destroy**

Check the plan output in the job logs before applying.

---

## Step 4 — Trigger apply

Go to **Actions → Infrastructure Deploy → Run workflow → action: apply**.

Expected duration: **8–12 minutes** (ElastiCache Redis takes the longest, ~5–7 min).

Resources are created in dependency order:
1. Networking (VPC, subnets, security groups) — ~1 min
2. Storage (ECR, S3, CloudFront, Redis) — ~7 min
3. Compute (IAM, Launch Template, ALB, ASG) — ~2 min
4. Monitoring (CloudWatch, SNS) — ~1 min

---

## Step 5 — Retrieve outputs and update app repo secrets

After apply completes, get the new resource IDs:

```bash
cd terraform
terraform init
terraform output
```

Or read them directly from the workflow's step summary in the Actions run.

Key outputs to note:

```
alb_dns_name                = <new-alb-xxxx.eu-north-1.elb.amazonaws.com>
cloudfront_domain_name      = https://<xxxx.cloudfront.net>
cloudfront_distribution_id  = <E1XXXXXXXXX>
ecr_repository_url          = <account>.dkr.ecr.eu-north-1.amazonaws.com/muchtodo-backend
s3_bucket_name              = muchtodo-production-frontend
asg_name                    = muchtodo-production-asg
```

Update these secrets in the **much-to-do** repo:
- `ALB_DNS_NAME` → new ALB DNS name
- `CLOUDFRONT_DISTRIBUTION_ID` → new distribution ID
- `VITE_API_BASE_URL` → `http://<new-alb-dns-name>`

---

## Step 6 — Re-deploy the application

Once infra secrets are updated, trigger both CI/CD pipelines in the **much-to-do** repo:

```bash
# From the much-to-do repo — push an empty commit to trigger both pipelines
git commit --allow-empty -m "chore: redeploy after infra rebuild"
git push
```

This will:
1. Build and push the backend Docker image to ECR
2. Deploy it to the new EC2 instances via SSM
3. Build and sync the frontend to S3
4. Invalidate CloudFront

---

## Step 7 — Verify everything is live

```bash
# Backend health
curl http://<ALB_DNS_NAME>/health

# Frontend (may take a few minutes for CloudFront to propagate)
curl https://<cloudfront_domain_name>
```

Also check the first EC2 instance started cleanly:

```bash
# Find the instance ID
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names muchtodo-production-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
  --output table

# Check container logs via SSM (no SSH key needed)
aws ssm start-session --target <instance-id>
# then: docker logs muchtodo-backend --tail 50
```

---

## Known gotchas

### ElastiCache Redis takes ~7 minutes
This is normal. The plan job will wait. Do not cancel the apply run early.

### SNS email subscription needs manual confirmation
After apply, AWS sends a confirmation email to `ALERT_EMAIL`. The subscription stays `PendingConfirmation` until you click the link. CloudWatch alarms will still fire — they just won't deliver until confirmed.

### CloudFront deployment takes ~5 minutes to propagate globally
`curl` on the CloudFront URL may return a 307/403 for a few minutes while the distribution deploys. This is normal.

### EC2 instance needs ~2 minutes before it passes health checks
The ASG has `health_check_grace_period = 120`. The instance is pulling the Docker image and starting the app during this time. Wait 2–3 minutes after the ASG reports the instance as `InService` before testing the ALB.

### MongoDB Atlas IP allowlist
If MongoDB Atlas has IP allowlisting enabled, add the new EC2 instance's public IP (or the NAT gateway IP if you add one) to the Atlas allowlist. The EC2 instances are in public subnets and will have public IPs directly.

---

## Local apply (if CI is unavailable)

```bash
cd terraform

# Export credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=eu-north-1

# Export sensitive Terraform vars
export TF_VAR_mongo_uri="..."
export TF_VAR_jwt_secret_key="..."
export TF_VAR_redis_password=""
export TF_VAR_alert_email="aishaagunbiade05@gmail.com"

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
