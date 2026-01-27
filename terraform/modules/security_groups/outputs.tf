output "bastion_sg_id" {
  description = "Security group ID for bastion hosts"
  value       = aws_security_group.bastion.id
}

output "app_sg_id" {
  description = "Security group ID for application servers"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group ID for database servers"
  value       = aws_security_group.db.id
}

output "admin_sg_id" {
  description = "Security group ID for admin servers"
  value       = aws_security_group.admin.id
}
