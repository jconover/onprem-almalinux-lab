# EC2 Cluster Module

A Terraform module that provisions a complete EC2 cluster infrastructure on AWS, designed for multi-tier application deployments with secure bastion access.

## Overview

This module creates a production-ready EC2 cluster consisting of:

- **Bastion Host**: Public-facing jump server for secure SSH access to private instances
- **Admin Server**: Private instance for administrative tasks and configuration management
- **Application Servers**: Scalable private instances with Apache HTTP server pre-configured

All instances run AlmaLinux OS 9, providing enterprise-grade stability and RHEL compatibility.

## Features

- Automatic AMI discovery for the latest AlmaLinux OS 9 release
- Configurable instance types for each server role
- Horizontal scaling support for application servers
- Automatic distribution of app servers across availability zones
- Security-hardened bootstrap with SELinux, firewalld, and chronyd
- Pre-configured Apache web server on application instances
- GP3 EBS volumes for improved performance
- Flexible tagging support for resource organization

## Usage

```hcl
module "ec2_cluster" {
  source = "./modules/ec2_cluster"

  environment        = "production"
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  bastion_sg_id      = module.security_groups.bastion_sg_id
  admin_sg_id        = module.security_groups.admin_sg_id
  app_sg_id          = module.security_groups.app_sg_id
  ssh_public_key     = file("~/.ssh/id_rsa.pub")

  bastion_instance_type = "t3.micro"
  admin_instance_type   = "t3.small"
  app_instance_type     = "t3.small"
  app_count             = 3

  tags = {
    Project     = "my-application"
    Environment = "production"
    ManagedBy   = "terraform"
  }
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
| `environment` | Environment name (e.g., dev, staging, production) | `string` | n/a | yes |
| `public_subnet_ids` | List of public subnet IDs for bastion host placement | `list(string)` | n/a | yes |
| `private_subnet_ids` | List of private subnet IDs for internal servers | `list(string)` | n/a | yes |
| `bastion_sg_id` | Security group ID to attach to the bastion host | `string` | n/a | yes |
| `admin_sg_id` | Security group ID to attach to the admin server | `string` | n/a | yes |
| `app_sg_id` | Security group ID to attach to application servers | `string` | n/a | yes |
| `ssh_public_key` | SSH public key content for EC2 key pair creation | `string` | n/a | yes |
| `bastion_instance_type` | EC2 instance type for the bastion host | `string` | `"t3.micro"` | no |
| `admin_instance_type` | EC2 instance type for the admin server | `string` | `"t3.small"` | no |
| `app_instance_type` | EC2 instance type for application servers | `string` | `"t3.small"` | no |
| `app_count` | Number of application server instances to create | `number` | `2` | no |
| `tags` | Map of tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bastion_public_ip` | Public IP address of the bastion host for SSH access |
| `bastion_private_ip` | Private IP address of the bastion host within the VPC |
| `admin_private_ip` | Private IP address of the admin server |
| `app_private_ips` | List of private IP addresses for all application servers |

## Architecture

```
                    Internet
                        |
                   [ Bastion ]  (Public Subnet)
                        |
        +---------------+---------------+
        |               |               |
    [ Admin ]       [ App 1 ]       [ App 2 ]
                   (Private Subnets)
```

## Security Considerations

- The bastion host is the only instance with a public IP address
- All internal servers are deployed in private subnets
- SELinux is enabled and enforcing on all instances
- Firewalld is configured with minimal required services
- SSH access to private instances requires bastion host tunneling

## License

This module is provided under the MIT License.
