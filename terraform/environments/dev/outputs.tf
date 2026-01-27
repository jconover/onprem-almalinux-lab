output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "bastion_public_ip" {
  description = "Bastion public IP"
  value       = module.ec2_cluster.bastion_public_ip
}

output "admin_private_ip" {
  description = "Admin server private IP"
  value       = module.ec2_cluster.admin_private_ip
}

output "app_private_ips" {
  description = "Application server private IPs"
  value       = module.ec2_cluster.app_private_ips
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}
