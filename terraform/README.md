# Terraform AWS Infrastructure

AWS IaC mirroring the on-prem AlmaLinux lab architecture.

## Architecture

This Terraform configuration creates:
- **VPC** with public and private subnets across 2 AZs
- **Bastion host** in public subnet (SSH jump box)
- **Admin server** in private subnet (DNS/management)
- **Application servers** (x2) in private subnets behind an ALB
- **RDS MariaDB** instance in private subnets (multi-AZ for prod)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- S3 bucket and DynamoDB table for state locking (see backend.tf)

## Usage

### Development Environment
```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### Production Environment
```bash
cd environments/prod
terraform init
terraform plan
terraform apply
```

## Module Structure

| Module | Purpose |
|--------|---------|
| `modules/vpc` | VPC, subnets, IGW, NAT GW, route tables |
| `modules/security_groups` | Security groups for each tier |
| `modules/ec2_cluster` | EC2 instances (bastion, admin, app, db) |
| `modules/rds` | RDS MariaDB instance |

## Local Validation (no AWS credentials needed)

```bash
terraform init
terraform validate
terraform fmt -check
```

## Architecture Decision Rationale

- **Multi-AZ**: Production spans 2 AZs for high availability
- **NAT Gateway**: Private subnets use NAT GW for outbound internet (package updates)
- **RDS over EC2 MariaDB**: Managed service reduces operational burden (backups, patching, failover)
- **S3+DynamoDB backend**: State locking prevents concurrent modifications in team environments
