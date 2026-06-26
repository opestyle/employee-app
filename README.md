# Employee App

A web application for managing employee records. The backend is a Python Flask API that stores employee data in RDS PostgreSQL and profile photos in S3. The frontend is a simple HTML/JS UI served by Nginx. The app runs on EKS with secrets pulled from AWS Secrets Manager via External Secrets Operator, and is exposed through an ALB Ingress with HTTPS.

## Deployment Steps

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply -var-file=env/dev/terraform.tfvars
```

### 2. Get Terraform Outputs

```bash
terraform output s3_access_role_arn
terraform output acm_certificate_arn
terraform output app_bucket_name
terraform output secrets_manager_secret_arn
```

Or use AWS CLI:

```bash
# serviceAccount.roleArn
aws iam get-role --role-name landmark-cluster-dev-app-sa --query "Role.Arn" --output text --profile terraform

# ingress.certificateArn
aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='employees.landmark.dev'].CertificateArn" --output text --profile terraform

# s3.bucket
aws s3api list-buckets --query "Buckets[?starts_with(Name,'landmark-app-bucket')].Name" --output text --profile terraform

# externalSecrets.secretName
aws secretsmanager list-secrets --region us-east-1 --query "SecretList[?starts_with(Name,'landmark-cluster')].Name" --output text --profile terraform
```

Copy the values and update `helm/values.yaml`:
- `s3_access_role_arn` → `serviceAccount.roleArn`
- `acm_certificate_arn` → `ingress.certificateArn`
- `app_bucket_name` → `s3.bucket`
- `secrets_manager_secret_arn` → verify `externalSecrets.secretName` matches

### 3. Build and Push Docker Images

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 075120018043.dkr.ecr.us-east-1.amazonaws.com

cd employee-app/backend
docker build -t 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-backend:latest .
docker push 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-backend:latest

cd ../frontend
docker build -t 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-frontend:latest .
docker push 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-frontend:latest
```

### 4. Connect to EKS

```bash
aws eks update-kubeconfig --name landmark-cluster-dev --region us-east-1 --profile terraform
```

### 5. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

### 6. Deploy the App

```bash
helm install employee-app helm/ --namespace employee-app --create-namespace
```

### 7. Verify

```bash
kubectl get pods -n employee-app
kubectl get ingress -n employee-app
```

## Run Tests

```bash
cd employee-app/backend
pip install -r requirements.txt
pytest
```
