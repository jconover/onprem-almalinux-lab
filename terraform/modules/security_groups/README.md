# AWS Security Groups Module

Terraform module for creating a comprehensive, multi-tier security group architecture on AWS. This module implements defense-in-depth network security by creating isolated security groups for bastion, application, database, and admin server tiers with carefully scoped ingress and egress rules.

## Overview

This module provisions four distinct security groups designed to mirror on-premises firewall rules in a cloud-native implementation. Each security group enforces the principle of least privilege, allowing only the necessary traffic between tiers.

### Architecture

```
                    Internet
                        |
                        v
              +-------------------+
              |    Bastion SG     |  <-- SSH (22), HTTP (80), HAProxy Stats (8404)
              +-------------------+
                   |         |
          +--------+         +--------+
          v                           v
+-------------------+       +-------------------+
|      App SG       |       |     Admin SG      |
| HTTP/HTTPS from   |       | DNS (53) from VPC |
| bastion, SSH from |       | SSH from bastion  |
| bastion           |       +-------------------+
+-------------------+
          |
          v
+-------------------+
|       DB SG       |
| MySQL (3306) from |
| app tier only     |
+-------------------+
```

## Features

- **Multi-Tier Architecture**: Separate security groups for bastion, application, database, and admin servers
- **Bastion Host Security**: Configurable SSH access with optional CIDR restrictions
- **Load Balancer Ready**: HTTP/HTTPS ingress on bastion for HAProxy integration
- **Database Isolation**: MySQL access restricted to application tier only
- **DNS Services Support**: TCP and UDP port 53 access for admin servers within VPC
- **Monitoring Integration**: Node exporter (port 9100) access for Prometheus metrics collection
- **Zero-Downtime Updates**: `create_before_destroy` lifecycle policy on all security groups
- **Flexible Tagging**: Support for custom tags with automatic Name tag generation
- **Environment Namespacing**: All resources prefixed with environment name for multi-environment deployments

## Usage

```hcl
module "security_groups" {
  source = "./modules/security_groups"

  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = "10.0.0.0/16"
  environment = "production"

  allowed_ssh_cidrs = ["10.0.0.0/8", "192.168.1.0/24"]

  tags = {
    Project     = "my-project"
    ManagedBy   = "terraform"
    Environment = "production"
  }
}

# Reference outputs in other modules
resource "aws_instance" "app" {
  # ...
  vpc_security_group_ids = [module.security_groups.app_sg_id]
}

resource "aws_instance" "bastion" {
  # ...
  vpc_security_group_ids = [module.security_groups.bastion_sg_id]
}
```

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.0 |
| AWS Provider | >= 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_id` | ID of the VPC where security groups will be created | `string` | n/a | yes |
| `vpc_cidr` | CIDR block of the VPC (used for internal DNS access rules) | `string` | n/a | yes |
| `environment` | Environment name used as prefix for all resource names | `string` | n/a | yes |
| `allowed_ssh_cidrs` | List of CIDR blocks allowed to SSH to bastion hosts | `list(string)` | `["0.0.0.0/0"]` | no |
| `tags` | Map of common tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bastion_sg_id` | Security group ID for bastion hosts |
| `app_sg_id` | Security group ID for application servers |
| `db_sg_id` | Security group ID for database servers |
| `admin_sg_id` | Security group ID for admin servers |

## Security Group Rules

### Bastion Security Group

| Direction | Port | Protocol | Source/Destination | Description |
|-----------|------|----------|-------------------|-------------|
| Ingress | 22 | TCP | `allowed_ssh_cidrs` | SSH access |
| Ingress | 80 | TCP | 0.0.0.0/0 | HTTP for HAProxy |
| Ingress | 8404 | TCP | `allowed_ssh_cidrs` | HAProxy statistics |
| Egress | All | All | 0.0.0.0/0 | All outbound traffic |

### Application Security Group

| Direction | Port | Protocol | Source/Destination | Description |
|-----------|------|----------|-------------------|-------------|
| Ingress | 80 | TCP | Bastion SG | HTTP from bastion/LB |
| Ingress | 443 | TCP | Bastion SG | HTTPS from bastion/LB |
| Ingress | 22 | TCP | Bastion SG | SSH from bastion |
| Ingress | 9100 | TCP | Self | Node exporter metrics |
| Egress | All | All | 0.0.0.0/0 | All outbound traffic |

### Database Security Group

| Direction | Port | Protocol | Source/Destination | Description |
|-----------|------|----------|-------------------|-------------|
| Ingress | 3306 | TCP | App SG | MySQL from app tier |
| Ingress | 22 | TCP | Bastion SG | SSH from bastion |
| Egress | All | All | 0.0.0.0/0 | All outbound traffic |

### Admin Security Group

| Direction | Port | Protocol | Source/Destination | Description |
|-----------|------|----------|-------------------|-------------|
| Ingress | 53 | TCP | VPC CIDR | DNS queries (TCP) |
| Ingress | 53 | UDP | VPC CIDR | DNS queries (UDP) |
| Ingress | 22 | TCP | Bastion SG | SSH from bastion |
| Ingress | 9100 | TCP | Self | Node exporter metrics |
| Egress | All | All | 0.0.0.0/0 | All outbound traffic |

## Best Practices

1. **Restrict SSH Access**: Always specify `allowed_ssh_cidrs` in production to limit SSH access to known IP ranges
2. **Use with VPC Module**: Pair this module with a VPC module that provides the `vpc_id` and `vpc_cidr` values
3. **Tag Resources**: Use the `tags` variable to maintain consistent tagging across your infrastructure
4. **Environment Isolation**: Use different `environment` values for dev, staging, and production deployments

## License

This module is part of the on-premises to AWS migration lab environment.
