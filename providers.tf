// The main aws provider (eu-central-1) actually lives in versions.tf, right next
// to the version pins — felt cleaner to keep those two together.
//
// This file just adds the second alias we need for billing metrics, since AWS
// only ever publishes those to us-east-1, no matter where our stack runs.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.tags
  }
}
