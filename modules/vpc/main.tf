// This module owns no resources directly — it wraps terraform-aws-modules/vpc/aws
// (req. 2) so root main.tf can call vpc_app and vpc_jenkins with identical, minimal inputs.
module "this" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  // Single shared NAT gateway instead of one per AZ — cost minimization (req. 13.5)
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  // Public subnets host the ALB only; instances never get a public IP directly
  map_public_ip_on_launch = false

  public_subnet_tags = {
    Tier = "public"
  }

  private_subnet_tags = {
    Tier = "private"
  }

  tags = var.tags
}
