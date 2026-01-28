# AWS VPC Terraform Module

A production-ready Terraform module for deploying a fully-featured Virtual Private Cloud (VPC) on AWS with public and private subnets across multiple Availability Zones.

## Description

This module creates a complete VPC infrastructure following AWS best practices for network isolation and high availability. It provisions a VPC with both public and private subnet tiers, enabling secure deployment of internet-facing and internal resources. The module handles all routing configuration, including NAT Gateway setup for private subnet internet access.

## Features

- **Multi-AZ Deployment**: Automatically creates subnets across specified Availability Zones for high availability
- **Public/Private Subnet Architecture**: Implements a two-tier network design with proper isolation
- **NAT Gateway**: Enables outbound internet access for private subnet resources
- **Internet Gateway**: Provides internet connectivity for public subnets
- **Automatic Route Tables**: Configures routing for both public and private subnets
- **DNS Support**: Enables DNS resolution and DNS hostnames within the VPC
- **Flexible CIDR Configuration**: Customizable IP address ranges for VPC and subnets
- **Consistent Tagging**: Supports custom tags with automatic environment-based naming

## Architecture

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                         VPC                             │
                    │  ┌─────────────────┐       ┌─────────────────┐          │
    Internet ───────┼──│  Internet GW    │       │    NAT GW       │          │
                    │  └────────┬────────┘       └────────┬────────┘          │
                    │           │                         │                   │
                    │  ┌────────┴────────┐       ┌────────┴────────┐          │
                    │  │  Public Subnet  │       │  Public Subnet  │          │
                    │  │     (AZ-1)      │───────│     (AZ-2)      │          │
                    │  └─────────────────┘       └─────────────────┘          │
                    │                                                          │
                    │  ┌─────────────────┐       ┌─────────────────┐          │
                    │  │ Private Subnet  │       │ Private Subnet  │          │
                    │  │     (AZ-1)      │       │     (AZ-2)      │          │
                    │  └─────────────────┘       └─────────────────┘          │
                    └─────────────────────────────────────────────────────────┘
```

## Usage

### Basic Example

```hcl
module "vpc" {
  source = "./modules/vpc"

  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  tags = {
    Project   = "my-application"
    ManagedBy = "terraform"
  }
}
```

### Three-AZ Deployment

```hcl
module "vpc" {
  source = "./modules/vpc"

  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

  tags = {
    Project     = "my-application"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### Using Outputs

```hcl
# Reference VPC outputs in other modules
module "ec2" {
  source = "./modules/ec2"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
}

# Output the NAT Gateway IP for whitelisting
output "nat_ip" {
  value = module.vpc.nat_gateway_ip
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_cidr` | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| `public_subnet_cidrs` | CIDR blocks for public subnets | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | no |
| `private_subnet_cidrs` | CIDR blocks for private subnets | `list(string)` | `["10.0.10.0/24", "10.0.11.0/24"]` | no |
| `availability_zones` | Availability zones to use | `list(string)` | `["us-east-1a", "us-east-1b"]` | no |
| `environment` | Environment name (used for resource naming) | `string` | n/a | **yes** |
| `tags` | Common tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `public_subnet_ids` | IDs of public subnets |
| `private_subnet_ids` | IDs of private subnets |
| `nat_gateway_ip` | Public IP of the NAT Gateway |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.0.0 |
| AWS Provider | >= 4.0.0 |

## Resources Created

This module creates the following AWS resources:

- `aws_vpc` - The main VPC
- `aws_internet_gateway` - Internet Gateway for public subnet access
- `aws_subnet` (public) - Public subnets (one per AZ)
- `aws_subnet` (private) - Private subnets (one per AZ)
- `aws_eip` - Elastic IP for NAT Gateway
- `aws_nat_gateway` - NAT Gateway for private subnet internet access
- `aws_route_table` (public) - Route table for public subnets
- `aws_route_table` (private) - Route table for private subnets
- `aws_route_table_association` - Associations for all subnets

## Notes

- The NAT Gateway is deployed in the first public subnet for cost optimization. For production workloads requiring high availability, consider deploying NAT Gateways in each AZ.
- Ensure the number of elements in `public_subnet_cidrs` and `private_subnet_cidrs` matches the number of `availability_zones`.
- All resources are tagged with the environment name and any custom tags provided.

## License

This module is part of the onprem-almalinux-lab project.
