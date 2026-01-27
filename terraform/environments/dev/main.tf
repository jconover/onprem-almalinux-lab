# Development Environment
# Composes all modules into a complete infrastructure stack

terraform {
  required_version = ">= 1.5.0"

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
      Environment = "dev"
      Project     = "onprem-almalinux-lab"
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = var.environment

  tags = local.common_tags
}

module "security_groups" {
  source = "../../modules/security_groups"

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  allowed_ssh_cidrs  = var.allowed_ssh_cidrs
  environment        = var.environment

  tags = local.common_tags
}

module "ec2_cluster" {
  source = "../../modules/ec2_cluster"

  environment        = var.environment
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  bastion_sg_id      = module.security_groups.bastion_sg_id
  app_sg_id          = module.security_groups.app_sg_id
  admin_sg_id        = module.security_groups.admin_sg_id
  ssh_public_key     = var.ssh_public_key

  bastion_instance_type = "t3.micro"
  admin_instance_type   = "t3.small"
  app_instance_type     = "t3.small"
  app_count             = 2

  tags = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids
  db_sg_id           = module.security_groups.db_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password

  instance_class          = "db.t3.micro"
  multi_az                = false
  backup_retention_period = 1
  skip_final_snapshot     = true

  tags = local.common_tags
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = "onprem-almalinux-lab"
  }
}
