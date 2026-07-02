// Central place for computed / derived values.
// Changing these is the only thing needed to re-CIDR or rename the whole stack.

locals {
  // Short prefix used in all resource names — keeps naming consistent with s3.tf
  name_prefix = var.tags.product

  // eu-central-1 has three AZs; we use two to keep the free-tier instance count at 2 per cluster
  azs = ["eu-central-1a", "eu-central-1b"]

  // App VPC — 10.40.0.0/16, subnets carved into /24 blocks
  app_vpc_cidr        = "10.40.0.0/16"
  app_public_subnets  = ["10.40.0.0/24", "10.40.1.0/24"]
  app_private_subnets = ["10.40.10.0/24", "10.40.11.0/24"]

  // Jenkins VPC — 10.41.0.0/16, mirrors the app VPC layout
  jenkins_vpc_cidr        = "10.41.0.0/16"
  jenkins_public_subnets  = ["10.41.0.0/24", "10.41.1.0/24"]
  jenkins_private_subnets = ["10.41.10.0/24", "10.41.11.0/24"]
}
