// The default AWS provider (eu-central-1) and the terraform block are both defined
// in versions.tf — kept together so version pins and provider config are in one file.
//
// A second provider alias is declared here for the billing CloudWatch namespace,
// which AWS only publishes to us-east-1 regardless of where resources live.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.tags
  }
}
