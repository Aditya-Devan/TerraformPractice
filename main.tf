
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "demo" {
  bucket = "terraform-aditya-devops-932632000024-demo-20261026"

  tags = {
    Name        = "terraform-s3-demo"
    Environment = "learning"
    ManagedBy   = "Terraform"
  }
}
