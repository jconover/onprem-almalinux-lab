variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-2)."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All public subnet CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "At least one public subnet CIDR must be specified."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All private subnet CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) > 0
    error_message = "At least one private subnet CIDR must be specified."
  }
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "At least one availability zone must be specified."
  }

  validation {
    condition     = alltrue([for az in var.availability_zones : can(regex("^[a-z]{2}-[a-z]+-[0-9]+[a-z]$", az))])
    error_message = "All availability zones must be valid format (e.g., us-east-1a, eu-west-2b)."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All allowed SSH CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 instances"
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\\s+", var.ssh_public_key))
    error_message = "SSH public key must be a valid OpenSSH public key format (ssh-rsa, ssh-ed25519, or ecdsa)."
  }
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "Database name must start with a letter, contain only alphanumeric characters and underscores, and be 1-63 characters long."
  }
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_username))
    error_message = "Database username must start with a letter, contain only alphanumeric characters and underscores, and be 1-63 characters long."
  }

  validation {
    condition     = !contains(["admin", "administrator", "root", "master", "postgres", "mysql"], lower(var.db_username))
    error_message = "Database username cannot be a reserved name (admin, administrator, root, master, postgres, mysql)."
  }
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 12
    error_message = "Database password must be at least 12 characters long."
  }

  validation {
    condition     = can(regex("[A-Z]", var.db_password)) && can(regex("[a-z]", var.db_password)) && can(regex("[0-9]", var.db_password))
    error_message = "Database password must contain at least one uppercase letter, one lowercase letter, and one number."
  }

  validation {
    condition     = !can(regex("[\"@/\\\\]", var.db_password))
    error_message = "Database password cannot contain quotes, @, /, or backslash characters."
  }
}
