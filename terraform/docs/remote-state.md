# Terraform Remote State Backend Setup

## Table of Contents

- [Overview](#overview)
- [S3 + DynamoDB Backend Setup](#s3--dynamodb-backend-setup)
- [Alternative Backends](#alternative-backends)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Why Remote State Matters

Terraform state is the source of truth for your infrastructure. By default, Terraform stores state locally in a `terraform.tfstate` file. While this works for individual learning, production environments require remote state for several critical reasons:

#### Team Collaboration

- **Shared Access**: Multiple team members can access the same state file
- **Consistent View**: Everyone sees the same infrastructure state
- **No Manual Syncing**: Eliminates passing state files via email, Slack, or Git

#### State Locking

- **Prevents Corruption**: Only one operation can modify state at a time
- **Avoids Race Conditions**: Two `terraform apply` commands cannot run simultaneously
- **Automatic Lock Management**: Locks are acquired and released automatically

#### Security

- **Encryption at Rest**: State files often contain sensitive data (passwords, keys)
- **Access Control**: IAM policies restrict who can read/write state
- **Audit Trail**: Versioning provides history of all state changes

#### Disaster Recovery

- **Automatic Backups**: Versioning preserves previous state versions
- **Recovery Options**: Roll back to previous state if corruption occurs
- **Durability**: Cloud storage provides 99.999999999% durability

---

## S3 + DynamoDB Backend Setup

The S3 backend with DynamoDB locking is the most common pattern for AWS-based infrastructure.

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0.0 installed

#### Required IAM Permissions

Create an IAM policy with these minimum permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::your-terraform-state-bucket"
    },
    {
      "Sid": "S3StateObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::your-terraform-state-bucket/*"
    },
    {
      "Sid": "DynamoDBLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    }
  ]
}
```

### Step 1: Create the S3 Bucket

Create a file named `state-backend/main.tf`:

```hcl
# state-backend/main.tf
# Bootstrap infrastructure for Terraform remote state
# Run this ONCE to create the backend resources

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Purpose     = "terraform-state"
      Environment = "shared"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region for state resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "myproject"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "shared"
}

# Random suffix for globally unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-terraform-state-${random_id.bucket_suffix.hex}"
  table_name  = "${var.project_name}-terraform-lock"
}

# S3 Bucket for State Storage
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.bucket_name
  }
}

# Enable versioning for state history and recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

# KMS key for encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-terraform-state-key"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "state-lifecycle"
    status = "Enabled"

    # Move non-current versions to cheaper storage after 30 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    # Move to Glacier after 90 days
    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    # Delete very old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy to enforce SSL
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

### Step 2: Create the DynamoDB Table

Add to the same `state-backend/main.tf`:

```hcl
# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"  # Cost-effective for sporadic access
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable point-in-time recovery for disaster recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  tags = {
    Name = local.table_name
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

### Step 3: Outputs

Add outputs to `state-backend/main.tf`:

```hcl
# Outputs - Save these for backend configuration
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  value       = aws_kms_key.terraform_state.arn
}

output "backend_config" {
  description = "Backend configuration to use in other projects"
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "path/to/terraform.tfstate"
        region         = "${var.aws_region}"
        encrypt        = true
        kms_key_id     = "${aws_kms_key.terraform_state.arn}"
        dynamodb_table = "${aws_dynamodb_table.terraform_lock.name}"
      }
    }
  EOT
}
```

### Step 4: Deploy the Backend Infrastructure

```bash
# Initialize and apply the state backend configuration
cd state-backend
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Save the outputs
terraform output -json > backend-config.json
```

### Step 5: Configure Backend in Your Project

Create `backend.tf` in your project:

```hcl
# backend.tf
terraform {
  backend "s3" {
    # Replace with your actual values from Step 4
    bucket         = "myproject-terraform-state-a1b2c3d4"
    key            = "environments/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:123456789012:key/xxx"
    dynamodb_table = "myproject-terraform-lock"

    # Optional: Use a specific profile
    # profile        = "terraform-admin"

    # Optional: Assume a role for cross-account access
    # role_arn       = "arn:aws:iam::123456789012:role/TerraformStateAccess"
  }
}
```

### State Migration: Local to Remote

If you have existing local state, migrate it to the remote backend:

```bash
# Step 1: Backup your current state
cp terraform.tfstate terraform.tfstate.backup

# Step 2: Add the backend configuration to backend.tf (as shown above)

# Step 3: Initialize with migration
terraform init -migrate-state

# Terraform will prompt:
# Do you want to copy existing state to the new backend?
# Enter "yes"

# Step 4: Verify the state was migrated
terraform state list

# Step 5: Remove local state file (optional, keep backup)
rm terraform.tfstate
rm terraform.tfstate.backup  # Only after verifying migration
```

---

## Alternative Backends

### Terraform Cloud

Terraform Cloud provides a managed backend with additional features like remote execution and policy enforcement.

```hcl
# backend.tf
terraform {
  cloud {
    organization = "your-organization"

    workspaces {
      name = "my-workspace"
      # Or use tags to match multiple workspaces:
      # tags = ["app:myapp", "env:production"]
    }
  }
}
```

**Setup Steps:**

1. Create account at [app.terraform.io](https://app.terraform.io)
2. Create an organization and workspace
3. Generate a user API token
4. Run `terraform login` or set `TF_TOKEN_app_terraform_io` environment variable
5. Add the backend configuration above
6. Run `terraform init`

### Azure Blob Storage

```hcl
# backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateaccount"
    container_name       = "tfstate"
    key                  = "production/terraform.tfstate"

    # Optional: Use Azure AD authentication instead of access keys
    use_azuread_auth     = true
  }
}
```

**Prerequisites:**

```bash
# Create storage account
az group create --name terraform-state-rg --location eastus

az storage account create \
  --name tfstateaccount \
  --resource-group terraform-state-rg \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name tfstate \
  --account-name tfstateaccount
```

### Google Cloud Storage (GCS)

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "my-terraform-state-bucket"
    prefix = "terraform/state/production"
  }
}
```

**Prerequisites:**

```bash
# Create bucket with versioning
gsutil mb -l us-central1 gs://my-terraform-state-bucket
gsutil versioning set on gs://my-terraform-state-bucket

# Enable uniform bucket-level access
gsutil uniformbucketlevelaccess set on gs://my-terraform-state-bucket
```

---

## Best Practices

### One State File Per Environment

Separate state files prevent accidental changes across environments:

```
terraform-state-bucket/
├── environments/
│   ├── development/
│   │   └── terraform.tfstate
│   ├── staging/
│   │   └── terraform.tfstate
│   └── production/
│   │   └── terraform.tfstate
├── shared/
│   ├── networking/
│   │   └── terraform.tfstate
│   └── dns/
│       └── terraform.tfstate
```

**Implementation:**

```hcl
# environments/production/backend.tf
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "environments/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}
```

### Bucket Naming Conventions

Follow a consistent naming pattern:

```
{company}-{project}-terraform-state-{region}
{company}-terraform-state-{account-id}
```

**Examples:**

- `acme-webapp-terraform-state-us-east-1`
- `acme-terraform-state-123456789012`

**Naming Rules:**

- Use lowercase only
- Use hyphens (not underscores)
- Include region or account ID for uniqueness
- Keep it under 63 characters

### Access Control and IAM Policies

**Principle of Least Privilege:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOnlyForDevelopers",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::mycompany-terraform-state",
        "arn:aws:s3:::mycompany-terraform-state/environments/development/*"
      ]
    }
  ]
}
```

**Production Write Access (CI/CD only):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ProductionStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::mycompany-terraform-state",
        "arn:aws:s3:::mycompany-terraform-state/environments/production/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalArn": "arn:aws:iam::123456789012:role/CI-CD-Role"
        }
      }
    }
  ]
}
```

### Backup and Disaster Recovery

#### Enable Cross-Region Replication

```hcl
# Destination bucket in another region
resource "aws_s3_bucket" "terraform_state_replica" {
  provider = aws.dr_region
  bucket   = "${local.bucket_name}-replica"
}

resource "aws_s3_bucket_versioning" "terraform_state_replica" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.terraform_state_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Replication configuration on source bucket
resource "aws_s3_bucket_replication_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-state"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.terraform_state_replica.arn
      storage_class = "STANDARD_IA"
    }
  }
}
```

#### Manual Backup Script

```bash
#!/bin/bash
# backup-terraform-state.sh

BUCKET="mycompany-terraform-state"
BACKUP_DIR="/backups/terraform-state"
DATE=$(date +%Y%m%d-%H%M%S)

# Create backup directory
mkdir -p "${BACKUP_DIR}/${DATE}"

# Sync all state files
aws s3 sync "s3://${BUCKET}" "${BACKUP_DIR}/${DATE}/"

# Keep only last 30 days of backups
find "${BACKUP_DIR}" -type d -mtime +30 -exec rm -rf {} \;

echo "Backup completed: ${BACKUP_DIR}/${DATE}"
```

---

## Troubleshooting

### State Lock Stuck

**Symptoms:**

```
Error: Error acquiring the state lock
Lock Info:
  ID:        a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Path:      mycompany-terraform-state/env/prod/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
  Version:   1.5.0
  Created:   2024-01-15 10:30:00.000000000 +0000 UTC
```

**Solutions:**

1. **Wait for the other operation to complete** (preferred)

2. **Force unlock (use with caution):**

   ```bash
   # Only use if you're certain no operation is running
   terraform force-unlock a1b2c3d4-e5f6-7890-abcd-ef1234567890
   ```

3. **Manually remove from DynamoDB:**

   ```bash
   aws dynamodb delete-item \
     --table-name terraform-lock \
     --key '{"LockID": {"S": "mycompany-terraform-state/env/prod/terraform.tfstate"}}'
   ```

**Prevention:**

- Use CI/CD pipelines that handle interruptions gracefully
- Set appropriate timeouts
- Never interrupt `terraform apply` mid-run

### State File Corruption

**Symptoms:**

- `Error: Error loading state: ...`
- Terraform plan shows resources to create that already exist
- Inconsistent state between plan and actual infrastructure

**Recovery Steps:**

1. **Restore from version history:**

   ```bash
   # List versions
   aws s3api list-object-versions \
     --bucket mycompany-terraform-state \
     --prefix "environments/production/terraform.tfstate"

   # Download a specific version
   aws s3api get-object \
     --bucket mycompany-terraform-state \
     --key "environments/production/terraform.tfstate" \
     --version-id "abc123def456" \
     terraform.tfstate.restored

   # Verify the restored state
   cat terraform.tfstate.restored | jq '.resources | length'

   # Upload restored version as current
   aws s3 cp terraform.tfstate.restored \
     s3://mycompany-terraform-state/environments/production/terraform.tfstate
   ```

2. **Import resources manually:**

   ```bash
   # If state is lost, import existing resources
   terraform import aws_instance.web i-1234567890abcdef0
   terraform import aws_s3_bucket.data my-bucket-name
   ```

3. **Refresh state from infrastructure:**

   ```bash
   # Update state to match actual infrastructure
   terraform refresh
   ```

### Permission Denied Errors

**Symptoms:**

```
Error: Error loading state: AccessDenied: Access Denied
        status code: 403
```

**Diagnosis:**

```bash
# Check your current identity
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://mycompany-terraform-state/

# Test DynamoDB access
aws dynamodb describe-table --table-name terraform-lock
```

**Common Causes and Fixes:**

1. **Wrong AWS profile:**

   ```bash
   export AWS_PROFILE=terraform-admin
   # Or in backend configuration:
   # profile = "terraform-admin"
   ```

2. **Missing IAM permissions:**

   Ensure your user/role has the IAM policy from the [Prerequisites](#required-iam-permissions) section.

3. **KMS key access denied:**

   ```json
   {
     "Sid": "AllowKMSAccess",
     "Effect": "Allow",
     "Action": [
       "kms:Encrypt",
       "kms:Decrypt",
       "kms:GenerateDataKey"
     ],
     "Resource": "arn:aws:kms:us-east-1:123456789012:key/xxx"
   }
   ```

4. **Bucket policy blocking access:**

   Check the bucket policy doesn't have an explicit deny for your principal.

5. **VPC endpoint policy:**

   If using S3 VPC endpoints, ensure the endpoint policy allows access.

### State Drift Detection

Detect when infrastructure changes outside of Terraform:

```bash
# Check for drift
terraform plan -refresh-only

# Output example:
# Note: Objects have changed outside of Terraform
#
# Terraform detected the following changes made outside of Terraform:
#   # aws_instance.web has been changed
#   ~ resource "aws_instance" "web" {
#       ~ instance_type = "t3.micro" -> "t3.small"
#     }
```

**Resolution Options:**

1. **Accept the drift:**

   ```bash
   terraform apply -refresh-only
   ```

2. **Revert to desired state:**

   ```bash
   terraform apply  # This will change infrastructure back to match config
   ```

---

## Quick Reference

### Common Commands

```bash
# Initialize with backend
terraform init

# Migrate state to new backend
terraform init -migrate-state

# Reconfigure backend (e.g., change bucket)
terraform init -reconfigure

# Force unlock state
terraform force-unlock LOCK_ID

# Pull remote state locally
terraform state pull > terraform.tfstate.backup

# Push local state to remote
terraform state push terraform.tfstate

# List resources in state
terraform state list

# Show specific resource
terraform state show aws_instance.web
```

### Environment Variables

```bash
# AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_PROFILE="terraform-admin"

# Backend configuration (partial)
export TF_CLI_ARGS_init="-backend-config=bucket=mycompany-terraform-state"

# Terraform Cloud token
export TF_TOKEN_app_terraform_io="your-token"
```

---

## Summary

Remote state is essential for production Terraform deployments. Key takeaways:

1. **Always use remote state** for team environments
2. **Enable state locking** to prevent corruption
3. **Encrypt state at rest** (it contains sensitive data)
4. **Enable versioning** for disaster recovery
5. **Separate state by environment** to reduce blast radius
6. **Use IAM policies** to control access
7. **Automate backups** for additional protection

Start with the S3 + DynamoDB setup for AWS environments, or Terraform Cloud for a fully managed solution.
