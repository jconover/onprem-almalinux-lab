# S3 backend for state management
# Uncomment after creating the S3 bucket and DynamoDB table
#
# terraform {
#   backend "s3" {
#     bucket         = "onprem-lab-terraform-state"
#     key            = "dev/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }
