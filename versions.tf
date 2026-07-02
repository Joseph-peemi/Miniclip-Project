terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  // Design note: no remote backend is configured. State is stored locally, which works
  // for a single operator but risks corruption under concurrent applies (no locking, no
  // versioning). The commented block below shows a correct S3 + DynamoDB setup reusing
  // the bucket already provisioned in s3.tf. Left disabled to keep the initial apply
  // self-contained — enable it once the bucket exists and team size grows beyond one.
  #
  # backend "s3" {
  #   bucket         = "broken-pipeline-tfstate-eu-central-1"
  #   key            = "broken-cloud-pipeline/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "broken-pipeline-tf-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = var.tags
  }
}
