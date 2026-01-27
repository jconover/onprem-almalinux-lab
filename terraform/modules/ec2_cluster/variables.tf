variable "environment" {
  description = "Environment name"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for bastion"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for internal servers"
  type        = list(string)
}

variable "bastion_sg_id" {
  description = "Security group ID for bastion"
  type        = string
}

variable "app_sg_id" {
  description = "Security group ID for app servers"
  type        = string
}

variable "admin_sg_id" {
  description = "Security group ID for admin server"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 key pair"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "t3.micro"
}

variable "admin_instance_type" {
  description = "Instance type for admin server"
  type        = string
  default     = "t3.small"
}

variable "app_instance_type" {
  description = "Instance type for app servers"
  type        = string
  default     = "t3.small"
}

variable "app_count" {
  description = "Number of application servers"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
