# Employee Directory App — Project Documentation

## 1. Application & Functionality

**Employee Directory App** — a full-stack web application for managing employee records.

### Backend (Python Flask API)

- CRUD operations for employees (name, email, role, department, DOB, photo)
- Photo upload to S3 with UUID-based filenames to prevent collisions
- `/api/stats` endpoint — aggregated metrics (total count, department breakdown, latest hire)
- `/api/health` — liveness/readiness probe that verifies DB connectivity
- `/metrics` — Prometheus metrics endpoint (request rate, duration histograms, error counts)
- Structured JSON logging to both stdout (for container log collection) and CloudWatch via watchtower
- Connection pooling (pool_size=10, pool_recycle=300s, pool_pre_ping=True) for database resilience
- Duplicate email validation, proper HTTP status codes (201, 400, 404, 409, 503)

### Frontend (Nginx + HTML/JS)

- Single-page app with modern UI (Inter font, colored avatar initials)
- Dropdowns for department (10 options) and role (8 levels)
- Search bar, date picker for DOB, stats banner, toast notifications
- Communicates with backend via `/api` path prefix (routed by ALB)

---

## 2. Testing Strategy

### Unit/Integration Tests (`test_app.py` — 11 test cases)

- Uses pytest with SQLite in-memory DB (no external dependencies needed)
- Mocks S3 with `unittest.mock` for photo upload tests
- Test classes organized by feature: Health, GetEmployees, CreateEmployee, UpdateEmployee, DeleteEmployee
- Covers: happy paths, missing fields (400), duplicate email (409), not found (404), photo upload with mocked S3
- Runs in CI pipeline **before** build — if tests fail, nothing gets deployed

**Test isolation**: Each test gets a fresh database (`db.create_all()` / `db.drop_all()`), test.db file cleaned up after.

---

## 3. Infrastructure Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Account                              │
│                                                                  │
│  ┌─────────────── VPC (10.0.0.0/16) ──────────────────────┐    │
│  │                                                          │    │
│  │  Public Subnets (2 AZs)          Private Subnets (2 AZs)│    │
│  │  ┌──────────┐ ┌──────────┐      ┌──────────┐ ┌────────┐│    │
│  │  │ ALB      │ │ NAT GW   │      │ EKS Nodes│ │  RDS   ││    │
│  │  │(internet)│ │          │      │ (t3.med) │ │(pg 15) ││    │
│  │  └──────────┘ └──────────┘      └──────────┘ └────────┘│    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─── EKS Cluster (landmark-cluster-dev) ───────────────────┐   │
│  │  Pods: backend(2) + frontend(2) + prometheus + grafana    │   │
│  │  + node-exporter(2) + kube-state-metrics + operator       │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
│  S3 (photos) │ ECR (images) │ Secrets Manager │ CloudWatch       │
└─────────────────────────────────────────────────────────────────┘
```

### Terraform Modules

- `terraform-aws-modules/vpc/aws` — VPC with public/private subnets, NAT gateway, proper tagging for LB discovery
- `terraform-aws-modules/eks/aws` — EKS cluster with managed node groups, OIDC provider, KMS encryption
- `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks` — IRSA roles (app, LB controller, EBS CSI)

### State Management

S3 backend (`landmark-terraform-state-file`) with versioning enabled for state recovery.

### Environment Separation

`env/dev/terraform.tfvars`, `env/stg/`, `env/prod/` — same code, different parameters.

---

## 4. Security

| Layer | Implementation |
|-------|---------------|
| **Network isolation** | RDS + EKS nodes in private subnets, no public access to DB |
| **RDS security group** | Only allows port 5432 from EKS node SG, cluster SG, and VPC CIDR |
| **Secrets management** | DB credentials in AWS Secrets Manager, synced to K8s via External Secrets Operator — never in code or env vars |
| **IRSA (IAM Roles for Service Accounts)** | Pods assume IAM roles via OIDC — no static AWS credentials in pods |
| **Least privilege IAM** | Each policy scoped to specific resources (only the app bucket, only the app secret, only the app ECR repos) |
| **S3 hardening** | Public access fully blocked (block_public_acls, block_public_policy, ignore_public_acls, restrict_public_buckets) |
| **Storage encryption** | RDS `storage_encrypted = true`, EKS secrets encrypted with KMS |
| **ECR image scanning** | Private repos, auth token required to pull |
| **EKS API auth** | Dual mode (API + ConfigMap), cluster creator gets admin, OIDC for service accounts |
| **Control plane logging** | All 5 log types enabled (api, audit, authenticator, controllerManager, scheduler) |
| **No hardcoded secrets in CI** | GitHub Secrets for AWS credentials, GitHub Environment Variables for non-sensitive config |

---

## 5. Availability & Resilience

| Aspect | Implementation |
|--------|---------------|
| **Multi-AZ** | VPC spans 2 AZs, EKS nodes spread across both, RDS multi-AZ in prod |
| **Pod replicas** | Backend: 2 replicas, Frontend: 2 replicas — survives single node failure |
| **Auto-scaling** | Node group: min=1, max=3 (ASG-backed), scales with demand |
| **Health checks** | `/api/health` verifies DB connectivity, ALB routes only to healthy targets |
| **DB connection pooling** | `pool_pre_ping=True` detects stale connections, `pool_recycle=300s` prevents timeouts |
| **RDS auto-scaling storage** | `max_allocated_storage=100` — disk grows automatically |
| **RDS backups** | 7-day retention in prod, 1-day in dev, final snapshot in prod on deletion |
| **S3 versioning** | Enabled on app bucket — accidental photo deletions recoverable |
| **Prometheus persistent storage** | 10Gi EBS volume with gp2 StorageClass — metrics survive pod restarts |
| **Graceful degradation** | CloudWatch logging wrapped in try/except — app continues if CW is unavailable |

---

## 6. Monitoring & Observability

Three pillars covered:

### Metrics (Prometheus + Grafana)

- Platform dashboard: node CPU/memory, pod counts, restarts, per-pod resources
- Application dashboard: HTTP request rate, 5xx errors, p95 latency, network I/O
- kube-state-metrics: deployment replicas, pod status
- node-exporter: host-level CPU, memory, disk, network

### Logs (CloudWatch + Grafana)

- Structured JSON logs from backend → CloudWatch log group `/landmark/employee-app`
- Grafana CloudWatch datasource with Logs Insights queries
- Dashboard panels: request rate from logs, avg response time, error rate, slowest requests, endpoint breakdown

### EKS Control Plane Logs

API server, audit, authenticator, controller manager, scheduler → CloudWatch

---

## 7. Deployment Strategy

### CI/CD Pipeline (GitHub Actions)

```
Push to main
    │
    ▼
┌─────────┐     ┌──────────────┐     ┌─────────┐
│  TEST   │────▶│ BUILD & PUSH │────▶│ DEPLOY  │
│ pytest  │     │  Docker→ECR  │     │ Helm    │
└─────────┘     └──────────────┘     └─────────┘
```

**Stage 1 — Test**: Install deps from requirements.txt, run pytest against SQLite. Gate: if tests fail, pipeline stops.

**Stage 2 — Build & Push**:
- Timestamp-based image tags (`be-dev-20260710-010534`) — every build is unique, easy to trace
- Builds both backend and frontend Docker images
- Pushes to ECR private repos

**Stage 3 — Deploy**:
- Updates `helm/values.yaml` with new image tags
- Commits tags back to repo (GitOps traceability — you can always see which tag is deployed)
- `helm upgrade --install` with `--wait` — waits for pods to be Ready before marking success
- Verifies with `kubectl get pods` and `kubectl get ingress`

### Deployment Model

Rolling update (Kubernetes default) — new pods come up, old pods terminate only after new ones are healthy. Zero downtime.

### Environment Promotion

GitHub environments (development → staging → production) with separate secrets/variables per environment. Manual `workflow_dispatch` allows choosing target environment.

### Infrastructure Changes

Terraform applied manually (or could be added as a separate workflow). App deployments are fully automated.

---

## Summary

This is a production-grade setup for a relatively simple app, demonstrating:

- Infrastructure as Code (Terraform) with remote state
- Container orchestration (EKS) with proper networking
- Secret management without credentials in code
- Full observability stack (metrics + logs + dashboards)
- Automated CI/CD with testing gates
- Security at every layer (network, IAM, encryption, access control)
- Environment separation for dev/stg/prod promotion
