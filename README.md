# 8byte-devops-assignment

## Terraform infrastructure

The Terraform configuration for this assignment lives under the [terraform](terraform) folder. It provisions a VPC, public/private subnets, an application load balancer, an EC2 Auto Scaling group, an RDS PostgreSQL instance, IAM roles, and Secrets Manager-backed database credentials.

Security note: the EC2 instances use an IAM instance profile with SSM permissions, so the deployment avoids exposing SSH on port 22. Access is handled through AWS Systems Manager Session Manager instead of open inbound SSH.

Copy [terraform/terraform.tfvars.example](terraform/terraform.tfvars.example) to [terraform/terraform.tfvars](terraform/terraform.tfvars) for local values before running Terraform.