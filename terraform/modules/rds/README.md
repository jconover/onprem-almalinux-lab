# AWS RDS MariaDB Module

A Terraform module for deploying a production-ready Amazon RDS MariaDB instance with security best practices, automated backups, and optional high availability.

## Description

This module provisions a fully managed AWS RDS MariaDB database instance, designed to replace on-premises MariaDB deployments with a cloud-native solution. It implements AWS security best practices including encryption at rest, private subnet placement, and configurable backup retention.

## Features

- **Managed MariaDB Database** - Fully managed AWS RDS instance with MariaDB engine
- **Encryption at Rest** - Storage encryption enabled by default using AWS-managed keys
- **Storage Autoscaling** - Automatic storage expansion with configurable limits
- **GP3 Storage** - Modern, cost-effective SSD storage with baseline performance
- **Automated Backups** - Configurable backup retention with defined backup windows
- **Multi-AZ Support** - Optional high availability with automatic failover
- **Private Network Placement** - Database deployed in private subnets with no public access
- **Flexible Tagging** - Support for custom resource tagging
- **Maintenance Windows** - Scheduled maintenance windows for updates

## Usage

```hcl
module "rds" {
  source = "./modules/rds"

  environment        = "production"
  private_subnet_ids = ["subnet-abc123", "subnet-def456"]
  db_sg_id           = "sg-12345678"

  db_name     = "myapp"
  db_username = "admin"
  db_password = var.db_password  # Use sensitive variable or secrets manager

  instance_class        = "db.t3.small"
  engine_version        = "10.11"
  allocated_storage     = 50
  max_allocated_storage = 200

  multi_az                = true
  backup_retention_period = 14
  skip_final_snapshot     = false

  tags = {
    Project     = "MyApplication"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `environment` | Environment name (used for resource naming) | `string` | n/a | yes |
| `private_subnet_ids` | Private subnet IDs for DB subnet group | `list(string)` | n/a | yes |
| `db_sg_id` | Security group ID for database access | `string` | n/a | yes |
| `db_password` | Master password (sensitive) | `string` | n/a | yes |
| `db_name` | Name of the database to create | `string` | `"appdb"` | no |
| `db_username` | Master username for the database | `string` | `"admin"` | no |
| `instance_class` | RDS instance class | `string` | `"db.t3.micro"` | no |
| `engine_version` | MariaDB engine version | `string` | `"10.11"` | no |
| `allocated_storage` | Allocated storage in GB | `number` | `20` | no |
| `max_allocated_storage` | Maximum allocated storage for autoscaling in GB | `number` | `100` | no |
| `multi_az` | Enable Multi-AZ deployment for high availability | `bool` | `false` | no |
| `backup_retention_period` | Backup retention period in days | `number` | `7` | no |
| `skip_final_snapshot` | Skip final snapshot on deletion | `bool` | `true` | no |
| `tags` | Common tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint` | RDS endpoint address (hostname:port format) |
| `port` | RDS port number |
| `db_name` | Name of the created database |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.0 |
| AWS Provider | >= 4.0 |

## Resources Created

This module creates the following AWS resources:

- `aws_db_subnet_group` - DB subnet group for private network placement
- `aws_db_instance` - RDS MariaDB database instance

## Security Considerations

- **No Public Access** - The database is configured with `publicly_accessible = false`
- **Encryption** - Storage encryption is enabled by default
- **Network Isolation** - Database is deployed within private subnets
- **Security Groups** - Access controlled via provided security group
- **Sensitive Variables** - Password variable is marked as sensitive in Terraform

## Backup and Maintenance

- **Backup Window**: 03:00-04:00 UTC daily
- **Maintenance Window**: Sunday 04:00-05:00 UTC
- **Final Snapshot**: Configurable via `skip_final_snapshot` variable

## License

This module is part of the on-premises to cloud migration lab environment.
