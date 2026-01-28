# Terraform AWS Infrastructure

## 1. Overview

This lab includes a complete Terraform configuration that mirrors the on-prem
AlmaLinux cluster in AWS. The goal is to demonstrate that the same multi-tier
architecture (bastion, admin, app, db) can be expressed as infrastructure-as-code
for cloud deployment, giving practical demonstration of both on-prem and cloud skills.

Terraform uses **declarative HCL** to define infrastructure, maintains a **state
file** tracking what exists, and uses a **plan/apply cycle** to converge
infrastructure to the desired state safely and predictably.

### Why Terraform for This Lab

Senior Linux Admin roles increasingly require cloud skills alongside on-prem
expertise. This Terraform configuration demonstrates:

- VPC networking (subnets, routing, NAT) -- analogous to on-prem VLANs
- Security groups -- analogous to on-prem firewalld rules
- EC2 instances with user_data bootstrap -- analogous to Vagrant provisioning
- RDS managed database -- the "cloud-native" replacement for self-hosted MariaDB
- Module-based composition -- the same DRY principles as Puppet role/profile

---

## 2. Architecture

### On-Prem to AWS Mapping

```
On-Prem (KVM/libvirt)               AWS (Terraform)
========================             ===========================
192.168.60.0/24 network      --->    VPC 10.0.0.0/16
  bastion (192.168.60.10)    --->    EC2 in public subnet (EIP)
  admin   (192.168.60.11)    --->    EC2 in private subnet
  app     (192.168.60.12)    --->    EC2 in private subnet (x2, multi-AZ)
  db      (192.168.60.13)    --->    RDS MariaDB (private subnet)
firewalld per-node rules     --->    Security groups per tier
Vagrant provisioning         --->    user_data bootstrap scripts
```

### AWS Network Topology

```
                 Internet
                    |
             [Internet Gateway]
                    |
  +-----------------------------------+
  |          VPC 10.0.0.0/16          |
  |                                   |
  |  Public Subnets (10.0.1.0/24,     |
  |                  10.0.2.0/24)     |
  |    [bastion]                      |
  |        |                          |
  |  [NAT Gateway]                    |
  |        |                          |
  |  Private Subnets (10.0.10.0/24,   |
  |                   10.0.11.0/24)   |
  |    [admin]  [app-1]  [app-2]      |
  |                                   |
  |    [RDS MariaDB - Multi-AZ]       |
  +-----------------------------------+
```

### Module Layout

```
terraform/
  README.md
  .gitignore              # Ignores .terraform/, *.tfstate, *.tfvars
  modules/
    vpc/                  # VPC, subnets, IGW, NAT GW, route tables
      main.tf
      variables.tf
      outputs.tf
    security_groups/      # Per-tier SGs (bastion, app, db, admin)
      main.tf
      variables.tf
      outputs.tf
    ec2_cluster/          # EC2 instances (bastion, admin, app)
      main.tf
      variables.tf
      outputs.tf
    rds/                  # Managed MariaDB
      main.tf
      variables.tf
      outputs.tf
  environments/
    dev/                  # Dev composition (small instances, no HA)
      main.tf
      variables.tf
```

---

## 3. Prerequisites

- Terraform >= 1.5.0 installed
- AWS CLI configured with credentials (`aws configure` or environment variables)
- An SSH key pair for EC2 access
- IAM permissions for VPC, EC2, RDS, and related resources

```bash
# Install Terraform (AlmaLinux/RHEL)
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform

# Verify
terraform version
```

---

## 4. Step-by-Step Setup / Deep Dive

### 4.1 Terraform Fundamentals

#### Core Concepts

| Concept         | Description |
|-----------------|-------------|
| **Provider**    | Plugin that talks to an API (AWS, Azure, GCP, etc.) |
| **Resource**    | A single infrastructure object (EC2 instance, VPC, etc.) |
| **Data Source** | Read-only query to existing infrastructure |
| **Module**      | Reusable group of resources |
| **State**       | JSON file tracking real infrastructure IDs and attributes |
| **Plan**        | Preview of changes before applying |
| **Apply**       | Execute changes to reach desired state |

#### The Plan/Apply Cycle

```bash
# 1. Initialize -- download providers, configure backend
terraform init

# 2. Plan -- show what will change (creates nothing)
terraform plan -out=tfplan

# 3. Apply -- execute the plan
terraform apply tfplan

# 4. Destroy -- tear down everything (use with caution)
terraform destroy
```

### 4.2 VPC Module Deep Dive

The VPC module (`terraform/modules/vpc/main.tf`) creates the network foundation.

**What it creates**:

```
aws_vpc.main                    # 10.0.0.0/16 with DNS support
aws_internet_gateway.main       # Attach to VPC for public internet
aws_subnet.public[0,1]          # 10.0.1.0/24, 10.0.2.0/24 (one per AZ)
aws_subnet.private[0,1]         # 10.0.10.0/24, 10.0.11.0/24 (one per AZ)
aws_eip.nat                     # Elastic IP for NAT gateway
aws_nat_gateway.main            # In first public subnet
aws_route_table.public          # 0.0.0.0/0 -> IGW
aws_route_table.private         # 0.0.0.0/0 -> NAT GW
aws_route_table_association.*   # Bind subnets to route tables
```

**Key design decisions**:

- **Two AZs** for high availability (us-east-1a, us-east-1b)
- **Public subnets** get `map_public_ip_on_launch = true` for bastion access
- **Private subnets** route outbound traffic through NAT gateway (packages, updates)
- **Single NAT gateway** in dev (cost savings); prod would have one per AZ

**Actual lab code** (excerpt):

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.environment}-nat-gw"
  })

  depends_on = [aws_internet_gateway.main]
}
```

### 4.3 Security Groups Module

Maps directly to the on-prem firewalld rules defined in Puppet/Ansible.

| Security Group | Inbound Rules | On-Prem Equivalent |
|---------------|---------------|-------------------|
| **bastion**   | SSH (22) from allowed CIDRs, HTTP (80), HAProxy stats (8404) | `firewall-cmd --add-service=ssh/http` |
| **app**       | HTTP/HTTPS from bastion SG, SSH from bastion SG, node_exporter self | `--add-service=http,https` |
| **db**        | MySQL (3306) from app SG, SSH from bastion SG | `--add-service=mysql` |
| **admin**     | DNS (53 TCP+UDP) from VPC CIDR, SSH from bastion SG, node_exporter self | `--add-service=dns` |

**Key pattern** -- referencing security groups instead of CIDRs for internal traffic:

```hcl
ingress {
  description     = "MySQL from app tier"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  security_groups = [aws_security_group.app.id]  # SG reference, not CIDR
}
```

This ensures only app-tier instances can reach the database, regardless of IP.

### 4.4 EC2 Cluster Module

**AMI Data Source** -- dynamically finds the latest AlmaLinux 9 AMI:

```hcl
data "aws_ami" "almalinux" {
  most_recent = true
  owners      = ["764336703387"]  # AlmaLinux official AWS account

  filter {
    name   = "name"
    values = ["AlmaLinux OS 9*x86_64*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

**User Data Bootstrap** -- equivalent to Vagrant provisioning:

```bash
#!/bin/bash
set -euxo pipefail
dnf -y update
dnf -y install vim firewalld chrony policycoreutils-python-utils \
  setools-console bind-utils iproute procps-ng net-tools tcpdump \
  traceroute nmap-ncat lvm2
systemctl enable --now firewalld chronyd
setenforce 1 || true
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
```

**App servers use `count`** for horizontal scaling:

```hcl
resource "aws_instance" "app" {
  count         = var.app_count  # 2 in dev
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  # Spreads instances across AZs via modulo
}
```

### 4.5 RDS Module

Replaces the self-hosted MariaDB with AWS managed service:

```hcl
resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-mariadb"
  engine         = "mariadb"
  instance_class = var.instance_class       # db.t3.micro for dev
  multi_az       = var.multi_az             # false for dev, true for prod

  storage_encrypted     = true              # Always encrypt at rest
  publicly_accessible   = false             # Private subnet only

  backup_retention_period = var.backup_retention_period  # 1 day for dev
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
}
```

**What RDS gives you over self-hosted MariaDB**:
- Automated backups and point-in-time recovery
- Multi-AZ failover (prod)
- Automated patching
- CloudWatch metrics built-in
- No OS-level management

### 4.6 Environment Composition

The `environments/dev/main.tf` file composes all modules:

```hcl
module "vpc" {
  source               = "../../modules/vpc"
  vpc_cidr             = var.vpc_cidr                # 10.0.0.0/16
  public_subnet_cidrs  = var.public_subnet_cidrs     # [10.0.1.0/24, 10.0.2.0/24]
  private_subnet_cidrs = var.private_subnet_cidrs    # [10.0.10.0/24, 10.0.11.0/24]
  availability_zones   = var.availability_zones      # [us-east-1a, us-east-1b]
  environment          = var.environment             # "dev"
  tags                 = local.common_tags
}

module "security_groups" {
  source            = "../../modules/security_groups"
  vpc_id            = module.vpc.vpc_id              # Output from VPC module
  vpc_cidr          = var.vpc_cidr
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  environment       = var.environment
  tags              = local.common_tags
}
```

**Module output chaining**: The VPC module exports `vpc_id` and `public_subnet_ids`,
which security_groups and ec2_cluster consume. This creates an implicit dependency
graph.

### 4.7 Directory-Based Environments vs Workspaces

This lab uses **directory-based environments** (`environments/dev/`, and a future
`environments/prod/`).

| Approach    | Directory-Based                     | Workspaces                         |
|-------------|-------------------------------------|------------------------------------|
| State       | Separate state file per directory   | Separate state per workspace       |
| Variables   | Different `.tfvars` per environment | Same variables, different values   |
| Modules     | Can use different module versions   | Same module versions               |
| Visibility  | Clear in file system                | Hidden behind CLI commands          |
| Best for    | Different infra per env             | Identical infra, different scale    |

**Why directories**: Dev uses `t3.micro`, single NAT GW, no multi-AZ. Prod would
use `t3.large`, multi-AZ, multiple NAT GWs. These are structural differences
best expressed as separate compositions, not just variable overrides.

### 4.8 State Management

#### S3 + DynamoDB Backend (Production Pattern)

```hcl
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "onprem-lab/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**State locking**: DynamoDB prevents two people from running `terraform apply`
simultaneously, avoiding state corruption.

**Remote state data source** -- reading another environment's outputs:

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "shared/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# Use: data.terraform_remote_state.vpc.outputs.vpc_id
```

### 4.9 GitOps Integration

#### PR-Based Plan/Apply Workflow

```
Feature branch --> PR --> terraform plan (CI) --> Review --> Merge --> terraform apply
```

**GitHub Actions example** (see docs/gitops.md for full pipeline):

```yaml
on:
  pull_request:
    paths: ['terraform/**']

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
        working-directory: terraform/environments/dev
      - run: terraform plan -no-color
        working-directory: terraform/environments/dev
```

### 4.10 Importing Existing Infrastructure

```bash
# Import an existing VPC into Terraform state
terraform import module.vpc.aws_vpc.main vpc-0123456789abcdef0

# Import an existing EC2 instance
terraform import module.ec2_cluster.aws_instance.bastion i-0123456789abcdef0

# After import, run plan to see drift between real state and code
terraform plan
```

### 4.11 Cost Management

| Strategy               | Dev                          | Prod                          |
|------------------------|------------------------------|-------------------------------|
| Instance sizing        | t3.micro/small               | t3.large or m5.large          |
| NAT Gateway            | Single (one AZ)              | One per AZ                    |
| RDS                    | db.t3.micro, single-AZ       | db.r5.large, multi-AZ         |
| Reserved Instances     | No                           | 1-year RI for steady-state    |
| Savings Plans          | No                           | Compute Savings Plan           |
| Auto-shutdown          | Lambda + EventBridge to stop | 24/7                           |
| Storage                | gp3 (20 GB)                  | gp3 (100 GB) + provisioned IOPS |

---

## 5. Verification / Testing

```bash
# Initialize and validate
cd terraform/environments/dev
make tf-init-dev
make tf-validate

# Or directly:
terraform init
terraform validate     # Syntax + type checking
terraform fmt -check   # Style checking
terraform plan         # Full plan without applying

# After apply, verify outputs
terraform output
terraform show

# Check specific resource state
terraform state list
terraform state show module.vpc.aws_vpc.main
```

### Smoke Tests After Apply

```bash
# SSH to bastion
ssh -i ~/.ssh/lab-key ec2-user@$(terraform output -raw bastion_public_ip)

# From bastion, verify app servers
curl http://<app-private-ip>/

# Verify RDS connectivity from app tier
mysql -h $(terraform output -raw rds_endpoint) -u admin -p appdb
```

---

## 6. Troubleshooting

| Issue | Diagnostic | Fix |
|-------|-----------|-----|
| `Error: No valid credential sources` | Missing AWS credentials | `aws configure` or set `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` |
| `Error: creating VPC: VpcLimitExceeded` | AWS account VPC limit (5 per region) | Delete unused VPCs or request limit increase |
| `Error: Error locking state` | Stale DynamoDB lock | `terraform force-unlock <LOCK_ID>` |
| State drift after manual console change | `terraform plan` shows unexpected changes | `terraform apply` to reconcile or `terraform import` |
| `Error: Cycle` in dependency graph | Circular module references | Check `depends_on` and module output chains |
| Timeout creating NAT Gateway | Slow AWS region | Increase timeout or retry |
| `Error: Unsupported attribute` in module output | Output not declared | Add missing `output` block in child module |

### State Recovery

```bash
# List all resources in state
terraform state list

# Move a resource (rename without destroy/recreate)
terraform state mv aws_instance.old aws_instance.new

# Remove from state (does NOT destroy the real resource)
terraform state rm aws_instance.orphan

# Pull current state for inspection
terraform state pull > state-backup.json
```

---

## 7. Architecture Decision Rationale

### Why AWS Provider (Not Azure or GCP)

**Decision**: Target AWS as the cloud platform.

**Rationale**:
- AWS is the most requested cloud platform in Linux Admin job postings
- AlmaLinux has official AWS AMIs maintained by the AlmaLinux Foundation
- The on-prem lab's architecture (bastion + private tiers) maps cleanly to VPC
- RDS MariaDB is a natural cloud counterpart to self-hosted MariaDB
- EC2 user_data parallels Vagrant provisioning, showing the migration path

### Why Modules Instead of a Single main.tf

**Decision**: Split infrastructure into VPC, security_groups, ec2_cluster, and rds modules.

**Rationale**:
- Each module has a single responsibility (network, security, compute, data)
- Modules can be versioned and reused across environments
- Team members can work on different modules without merge conflicts
- Blast radius is limited -- changing security groups does not risk VPC changes
- Mirrors Puppet's role/profile separation of concerns

### Why Directory-Based Environments

**Decision**: Use `environments/dev/` and `environments/prod/` directories, not workspaces.

**Rationale**:
- Dev and prod have fundamentally different architectures (single vs multi-AZ)
- Separate state files mean a dev mistake cannot corrupt prod state
- Easier to review in PRs -- "this PR only touches dev"
- Workspaces are better for identical infrastructure at different scales (staging = smaller prod)

### Why RDS Instead of EC2-Based MariaDB

**Decision**: Use RDS for database in AWS, not EC2 with self-managed MariaDB.

**Rationale**:
- Demonstrates understanding of managed services vs self-managed
- Automated backups, patching, failover
- Frees the team from OS-level DB maintenance
- On-prem lab still teaches self-hosted MariaDB skills
- Senior engineers expect you to understand how to choose the right approach for each context

---

## 8. Key Concepts to Master

### Handling Terraform State in a Team

Store state in S3 with server-side encryption and use DynamoDB for state
locking. Each environment has its own state file keyed by path --
`environments/dev/terraform.tfstate`. Never commit state to Git. Access
to the S3 bucket is restricted by IAM policy. For debugging, use
`terraform state pull` to inspect state locally, and `terraform state mv`
for refactoring without destroying resources.

### Terraform Module Design Approach

Follow single-responsibility modules. In this project, the VPC module only
handles networking, security_groups handles firewall rules, ec2_cluster handles
compute, and rds handles the database. Each module takes inputs via variables,
produces outputs for other modules to consume, and uses `merge(var.tags, {...})`
for consistent tagging. Environments compose modules with different parameters --
dev uses `t3.micro` and single-AZ, prod uses larger instances with multi-AZ.
Module interfaces are documented with `description` on every variable.

### Managing Secrets in Terraform

Sensitive variables are marked with `sensitive = true` so Terraform redacts
them from plan output. Values are injected via environment variables
(`TF_VAR_db_password`), CI/CD secrets, or a secrets manager. Never store
secrets in `.tfvars` files committed to Git. For dynamic secrets, use the
AWS Secrets Manager data source or Vault provider to read secrets at plan time.
The RDS password in this lab uses `sensitive = true` on the variable declaration.

### CI/CD Pipeline for Terraform

On every PR that touches `terraform/`, CI runs `terraform fmt -check`,
`terraform validate`, and `terraform plan`. The plan output is posted as a PR
comment so reviewers can see exactly what will change. On merge to main,
CD runs `terraform apply` with the saved plan. Use Atlantis or GitHub
Actions. The key principle is that `terraform apply` only runs from CI,
never from developer laptops -- this ensures the state file is always
consistent with the reviewed code.

### Handling Infrastructure Drift

Scheduled CI jobs run `terraform plan` nightly and alert on any drift.
Common drift sources: console changes, auto-scaling events, AWS-initiated
changes (security patches). For console changes, either apply to
reconcile or `terraform import` to adopt the change. Have a policy that
all infrastructure changes go through code -- manual console changes are
treated as incidents and remediated via PR.

### Migrating On-Prem Infrastructure to AWS

The Terraform modules already mirror the on-prem architecture. Migration
steps: First, provision the VPC and security groups. Second, launch EC2
instances with the same user_data bootstrap. Third, migrate MariaDB data
to RDS using mysqldump or AWS DMS. Fourth, update DNS (Route 53) to point
to the new infrastructure. Fifth, configure the same Puppet/Ansible automation
to target the EC2 instances. The key challenge is data migration and
cutover timing -- use a blue/green approach with DNS failover.
