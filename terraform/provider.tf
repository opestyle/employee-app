# Terraform configuration with S3 backend
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "landmark-terraform-state-file"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "landmark-terraform-locks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS provider
provider "aws" {
  region = var.region
}
