output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of bastion host"
  value       = aws_instance.bastion.private_ip
}

output "admin_private_ip" {
  description = "Private IP of admin server"
  value       = aws_instance.admin.private_ip
}

output "app_private_ips" {
  description = "Private IPs of application servers"
  value       = aws_instance.app[*].private_ip
}
