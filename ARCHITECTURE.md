# Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud (us-east-1)                │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    VPC 10.0.0.0/16                   │  │
│  │                                                      │  │
│  │  Public Subnets (10.0.1.0/24, 10.0.2.0/24)          │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │  Application Load Balancer  :80/:443            │  │  │
│  │  └─────────────────┬──────────────────────────────┘  │  │
│  │                    │ port 8080                        │  │
│  │  Private Subnets (10.0.10.0/24, 10.0.11.0/24)        │  │
│  │  ┌─────────────────▼──────────────────────────────┐  │  │
│  │  │  Auto Scaling Group (min 1 / max 3)             │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  EC2 t3.micro (Amazon Linux 2023)          │  │  │  │
│  │  │  │  Docker: muchtodo-backend:sha              │  │  │  │
│  │  │  │  CloudWatch Agent → /muchtodo/backend      │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │                                                      │  │
│  │  ┌─────────────────────────────────────────────────┐ │  │
│  │  │  ElastiCache Redis (cache.t3.micro)              │ │  │
│  │  │  Port 6379 — accessible only from backend SG    │ │  │
│  │  └─────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ECR Repository (muchtodo-backend)                          │
│  CloudWatch (Logs + Dashboard + Alarms)                     │
│  SNS Topic (muchtodo-production-alerts)                     │
└─────────────────────────────────────────────────────────────┘

                    ↑ pulls images
     ┌──────────────┘
     │
  GitHub Actions CI/CD
     │
     ├── frontend-ci-cd.yml → S3 + CloudFront invalidation
     ├── backend-ci-cd.yml  → ECR push + SSM rolling update
     └── infrastructure-deploy.yml → Terraform apply

     ↑ connects to
     │
  MongoDB Atlas (external, cloud DB)

S3 Bucket (muchtodo-production-frontend)
     ↑ origin
CloudFront Distribution
     ↑ serves
Browser (HTTPS)
```

## Data Flow

### Frontend Request
1. User browser → HTTPS → CloudFront edge node
2. CloudFront checks cache; on miss → S3 origin (private, OAC)
3. React SPA handles routing client-side
4. React app calls backend API via `VITE_API_BASE_URL` (ALB DNS or custom domain)

### Backend Request
1. Browser → HTTP → ALB listener (:80)
2. ALB → target group → EC2 instance port 8080
3. Go/Gin handler → MongoDB Atlas (external) for persistence
4. Go/Gin handler → ElastiCache Redis (internal VPC) for session cache
5. Structured JSON logs → CloudWatch Logs via Docker `awslogs` driver

### Deployment Flow
1. Developer pushes to `main` branch
2. GitHub Actions detects change in `Server/**` or `Client/**`
3. **Frontend**: build → S3 sync → CloudFront invalidation
4. **Backend**: test → Docker build → ECR push → SSM Run Command → rolling restart → health check

## Security Model

| Layer | Control |
|-------|---------|
| Network | EC2 in private subnets, only ALB is internet-facing |
| Security Groups | Least-privilege: backend only reachable from ALB, Redis only from backend |
| IAM | EC2 instance profile: ECR read, CloudWatch write, SSM (no broad permissions) |
| Secrets | `TF_VAR_*` via GitHub Secrets; env file `/etc/muchtodo.env` (chmod 600) on EC2 |
| Images | ECR scan-on-push; Trivy scan in CI pipeline |
| TLS | CloudFront enforces HTTPS redirect; ALB can be upgraded to HTTPS with ACM cert |

## Scaling Strategy

- **Horizontal**: ASG target-tracking scales out at 70% CPU, scales in when load drops
- **Stateless backend**: no local state means any instance can handle any request
- **Cache**: Redis reduces MongoDB load for hot data (username checks, sessions)
- **CDN**: CloudFront absorbs frontend traffic — backend sees only API calls

## Cost Estimate (us-east-1, production defaults)

| Component | Monthly est. |
|-----------|-------------|
| EC2 t3.micro × 1 | ~$8 |
| ALB | ~$20 |
| ElastiCache cache.t3.micro | ~$12 |
| NAT Gateway | ~$33 (depends on traffic) |
| CloudFront | ~$1–5 (depends on traffic) |
| CloudWatch Logs | ~$0.50/GB ingested |
| ECR | ~$0.10/GB stored |
| **Total** | **~$75–80/month** |

To reduce costs for dev/staging: set `asg_desired_capacity = 0` when not in use, or use `t3.nano`.
