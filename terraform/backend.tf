terraform {
  backend "s3" {
    bucket         = "8byte-devops-assignment-tfstate-600929978273"
    key            = "8byte-devops-assignment/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "8byte-devops-assignment-tf-lock"
    encrypt        = true
  }
}

# The S3 bucket and DynamoDB table above are created by terraform/bootstrap.
