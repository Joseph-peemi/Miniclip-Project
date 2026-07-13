// Everything derived/computed lives here. If we ever need to re-CIDR the
// network or rename the whole stack, this is the only file that should change.

locals {
  // Feeds into every resource name — keep it in sync with the bucket name in s3.tf
  name_prefix = var.tags.product

  // Only using 2 of eu-central-1's 3 AZs, since we're capping each cluster at
  // 2 instances anyway to stay inside the free tier
  azs = ["eu-central-1a", "eu-central-1b"]

  // App VPC — /24 subnets carved out of 10.40.0.0/16
  app_vpc_cidr        = "10.40.0.0/16"
  app_public_subnets  = ["10.40.0.0/24", "10.40.1.0/24"]
  app_private_subnets = ["10.40.10.0/24", "10.40.11.0/24"]

  // Jenkins VPC — same layout, just shifted into 10.41.0.0/16
  jenkins_vpc_cidr        = "10.41.0.0/16"
  jenkins_public_subnets  = ["10.41.0.0/24", "10.41.1.0/24"]
  jenkins_private_subnets = ["10.41.10.0/24", "10.41.11.0/24"]
}
