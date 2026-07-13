terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  // No remote backend yet — state is just local for now. That's fine while it's
  // one person applying, but there's no locking or versioning, so two people
  // running apply at the same time could corrupt it. The block below is a ready
  // S3 + DynamoDB setup that reuses the logs bucket from s3.tf; it's commented
  // out only because that bucket doesn't exist until the first apply runs.
  // Flip it on once the bucket's there and more than one person touches this.
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
