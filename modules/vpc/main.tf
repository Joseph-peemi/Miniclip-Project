// Thin wrapper around terraform-aws-modules/vpc/aws — doesn't own any resources
// itself, just gives the root module a small, identical interface for calling
// vpc_app and vpc_jenkins without repeating all the upstream module's inputs.
module "this" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  // One NAT gateway shared across AZs instead of one each — cheaper, and fine for this scale
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  // Only the ALB lives in the public subnets — no instance gets a public IP directly
  map_public_ip_on_launch = false

  public_subnet_tags = {
    Tier = "public"
  }

  private_subnet_tags = {
    Tier = "private"
  }

  tags = var.tags
}
