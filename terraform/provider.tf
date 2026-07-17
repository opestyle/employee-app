# Terraform configuration with S3 backend
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "landmark-terraform-state-063718566254"
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
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
